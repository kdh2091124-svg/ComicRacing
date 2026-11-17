-- 모든 차(내 차 + 다른 사람 차)의 이펙트를 각자 화면에서 그린다.
--   드리프트: 스키드 마크, 빛나는 꼬리선, 반짝이는 불똥 + 날리는 불씨, 부드러운 타이어 연기
--   부스터: 2겹 불꽃(하얀 속불 + 주황 겉불), 차 옆 속도 줄기, 깜빡이는 불빛
--   충돌: 스파크
-- 상태는 모델 Attribute (FX_Drift, FX_Tier, FX_Boost) 를 읽음. 서버가 운전자 보고를 받아 설정.
-- 텍스처는 로블록스 내장 파티클만 사용 (EffectsConfig.Textures).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FX = require(Shared:WaitForChild("Config"):WaitForChild("EffectsConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local VehicleFX = Remotes:WaitForChild("VehicleFX") :: RemoteEvent
local ChaseCamera = require(script.Parent:WaitForChild("ChaseCamera"))

local VehicleEffects = {}

type WheelFX = {
	skid: Trail,
	glow: Trail,
	sparks: ParticleEmitter,
	embers: ParticleEmitter,
	smoke: ParticleEmitter,
}
type Rig = {
	model: Model,
	chassis: BasePart,
	wheels: { WheelFX },
	flameCore: ParticleEmitter,
	flameOuter: ParticleEmitter,
	flameLight: PointLight,
	streaks: { Trail },
	impactAtt: Attachment,
	impact: ParticleEmitter,
	lastTier: number,
	-- 벽 긁기
	grindAtt: Attachment,
	grindSparks: ParticleEmitter,
	grindSound: Sound?,
	lastMarkPos: Vector3?,
	lastScratchPos: Vector3?,
	scratches: number,
}

local rigs: { [Model]: Rig } = {}
local started = false

-- 속성 하나가 이 Studio 버전에 없어도 나머지는 정상 적용되게 (예: Brightness)
local function setProps(inst: Instance, props: { [string]: any })
	for k, v in props do
		pcall(function()
			(inst :: any)[k] = v
		end)
	end
end

local function newEmitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	setProps(e, props)
	e.Parent = parent
	return e
end

local function newAttachment(chassis: BasePart, name: string, pos: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = pos
	a.Parent = chassis
	return a
end

local function newTrail(parent: Instance, a0: Attachment, a1: Attachment, props: { [string]: any }): Trail
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Enabled = false
	setProps(t, props)
	t.Parent = parent
	return t
end

local function fade(startAlpha: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, startAlpha),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local function glowColor(c: Color3): ColorSequence
	-- 가운데는 하얗게 빛나고 끝으로 갈수록 색이 진해짐
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.35, c),
		ColorSequenceKeypoint.new(1, c),
	})
end

-- 뒷바퀴가 땅에 닿는 위치 (차체 기준)
local function rearContactPoints(model: Model, chassis: BasePart): { Vector3 }
	local rest = model:GetAttribute("Stat_suspensionRest") or 2.4
	local radius = model:GetAttribute("Stat_wheelRadius") or 1.2
	local stiffness = model:GetAttribute("Stat_suspensionStiffness") or 200
	local drop = rest + radius - workspace.Gravity / stiffness
	local points = {}
	for _, att in chassis:GetChildren() do
		if att:IsA("Attachment") and (att.Name == "Susp_RL" or att.Name == "Susp_RR") then
			table.insert(points, att.Position - Vector3.new(0, drop - 0.08, 0))
		end
	end
	if #points == 0 then
		local s = chassis.Size
		table.insert(points, Vector3.new(-s.X / 2, -s.Y / 2, s.Z / 2))
		table.insert(points, Vector3.new(s.X / 2, -s.Y / 2, s.Z / 2))
	end
	return points
end

local function buildRig(model: Model): Rig?
	local chassis = model.PrimaryPart or model:FindFirstChild("Chassis")
	if not chassis or not chassis:IsA("BasePart") then
		return nil
	end
	local T = FX.Textures
	local baseColor = FX.Sparks.tierColors[0]

	local wheels = {}
	for i, p in rearContactPoints(model, chassis) do
		-- 스키드 마크 (바닥에 남는 검은 자국)
		local half = FX.Skid.width / 2
		local s0 = newAttachment(chassis, "FX_Skid0_" .. i, p - Vector3.new(half, 0, 0))
		local s1 = newAttachment(chassis, "FX_Skid1_" .. i, p + Vector3.new(half, 0, 0))
		local skid = newTrail(chassis, s0, s1, {
			Lifetime = FX.Skid.lifetime,
			Color = ColorSequence.new(FX.Skid.color),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, FX.Skid.transparency),
				NumberSequenceKeypoint.new(0.7, FX.Skid.transparency + 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
			FaceCamera = false,
			LightInfluence = 1,
			MinLength = 0.05,
		})

		-- 빛나는 꼬리선 (뒷바퀴 뒤로 짧게 남는 네온 줄)
		local g0 = newAttachment(chassis, "FX_Glow0_" .. i, p + Vector3.new(0, 0.1, 0))
		local g1 = newAttachment(chassis, "FX_Glow1_" .. i, p + Vector3.new(0, FX.Glow.height, 0))
		local glow = newTrail(chassis, g0, g1, {
			Lifetime = FX.Glow.lifetime,
			Color = glowColor(baseColor),
			Transparency = fade(FX.Glow.transparency),
			LightEmission = 1,
			LightInfluence = 0,
			FaceCamera = true,
			MinLength = 0.05,
			Brightness = 2,
		})

		local center = newAttachment(chassis, "FX_Wheel_" .. i, p + Vector3.new(0, 0.2, 0))
		-- 반짝이는 불똥 (빠르게 튀고 금방 사라짐)
		local sparks = newEmitter(center, {
			Texture = T.spark,
			Lifetime = NumberRange.new(0.12, 0.3),
			Speed = NumberRange.new(22, 45),
			SpreadAngle = Vector2.new(28, 28),
			EmissionDirection = Enum.NormalId.Back,
			Acceleration = Vector3.new(0, -110, 0),
			Drag = 3,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Color = glowColor(baseColor),
			LightEmission = 1,
			LightInfluence = 0,
			Brightness = 3,
			Orientation = Enum.ParticleOrientation.VelocityParallel,
		})
		-- 날리는 불씨 (천천히 떠오르며 깜빡)
		local embers = newEmitter(center, {
			Texture = T.spark,
			Lifetime = NumberRange.new(0.4, 0.8),
			Speed = NumberRange.new(4, 10),
			SpreadAngle = Vector2.new(60, 60),
			EmissionDirection = Enum.NormalId.Back,
			Acceleration = Vector3.new(0, 6, 0),
			Drag = 2,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.25),
				NumberSequenceKeypoint.new(0.5, 0.18),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.6, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Color = ColorSequence.new(baseColor),
			LightEmission = 1,
			LightInfluence = 0,
			Brightness = 2,
		})
		-- 부드러운 타이어 연기 (뭉게뭉게 퍼짐)
		local smoke = newEmitter(center, {
			Texture = T.smoke,
			Lifetime = NumberRange.new(1.1, 1.9),
			Speed = NumberRange.new(3, 7),
			SpreadAngle = Vector2.new(50, 50),
			EmissionDirection = Enum.NormalId.Back,
			Acceleration = Vector3.new(0, 3, 0),
			Drag = 4,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1.2),
				NumberSequenceKeypoint.new(0.4, 3.5),
				NumberSequenceKeypoint.new(1, 6.5),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.55),
				NumberSequenceKeypoint.new(0.3, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Color = ColorSequence.new(FX.Smoke.color, FX.Smoke.endColor),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-40, 40),
			LightInfluence = 0.6,
		})
		table.insert(wheels, { skid = skid, glow = glow, sparks = sparks, embers = embers, smoke = smoke })
	end

	-- 부스터 불꽃 2겹 (차 뒤 가운데)
	local size = chassis.Size
	local flameAtt = newAttachment(chassis, "FX_Flame", Vector3.new(0, 0, size.Z / 2 + 0.3))
	local flameCore = newEmitter(flameAtt, {
		Texture = T.fire,
		Lifetime = NumberRange.new(0.07, 0.13),
		Speed = NumberRange.new(26, 36),
		SpreadAngle = Vector2.new(4, 4),
		EmissionDirection = Enum.NormalId.Back,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(1, 0.1),
		}),
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 230, 120)),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 4,
	})
	local flameOuter = newEmitter(flameAtt, {
		Texture = T.fire,
		Lifetime = NumberRange.new(0.16, 0.3),
		Speed = NumberRange.new(16, 26),
		SpreadAngle = Vector2.new(10, 10),
		EmissionDirection = Enum.NormalId.Back,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.6),
			NumberSequenceKeypoint.new(0.4, 2.3),
			NumberSequenceKeypoint.new(1, 0.4),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.6, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 80)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 110, 30)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 30, 60)),
		}),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-180, 180),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 2,
	})
	local flameLight = Instance.new("PointLight")
	flameLight.Color = Color3.fromRGB(255, 150, 60)
	flameLight.Range = 16
	flameLight.Brightness = FX.Flame.lightBrightness
	flameLight.Enabled = false
	flameLight.Parent = flameAtt

	-- 부스터 속도 줄기 (차 양옆 뒤로 흐르는 빛줄기)
	local streaks = {}
	for _, side in { -1, 1 } do
		local x = side * (size.X / 2 + 0.1)
		local a0 = newAttachment(chassis, "FX_Streak0_" .. side, Vector3.new(x, -size.Y / 4, size.Z / 2 - 0.5))
		local a1 = newAttachment(chassis, "FX_Streak1_" .. side, Vector3.new(x, size.Y / 4, size.Z / 2 - 0.5))
		table.insert(streaks, newTrail(chassis, a0, a1, {
			Lifetime = FX.Streak.lifetime,
			Color = ColorSequence.new(Color3.new(1, 1, 1), FX.Streak.color),
			Transparency = fade(FX.Streak.transparency),
			LightEmission = 1,
			LightInfluence = 0,
			FaceCamera = true,
			WidthScale = NumberSequence.new(1, 0.2),
			MinLength = 0.05,
		}))
	end

	-- 충돌 스파크 (위치는 박을 때마다 옮김)
	local impactAtt = newAttachment(chassis, "FX_Impact", Vector3.zero)
	local impact = newEmitter(impactAtt, {
		Texture = T.spark,
		Lifetime = NumberRange.new(0.2, 0.5),
		Speed = NumberRange.new(25, 60),
		SpreadAngle = Vector2.new(80, 80),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -120, 0),
		Drag = 1.5,
		Size = NumberSequence.new(0.5, 0),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 3,
		Color = glowColor(Color3.fromRGB(255, 200, 90)),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
	})

	-- 벽 긁기 불똥 (긁히는 지점으로 매 프레임 옮김, 뒤로 길게 흩날림)
	local grindAtt = newAttachment(chassis, "FX_Grind", Vector3.zero)
	local grindSparks = newEmitter(grindAtt, {
		Texture = T.spark,
		Lifetime = NumberRange.new(0.15, 0.45),
		Speed = NumberRange.new(18, 40),
		SpreadAngle = Vector2.new(35, 20),
		EmissionDirection = Enum.NormalId.Back,
		Acceleration = Vector3.new(0, -100, 0),
		Drag = 2,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 0),
		}),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 3,
		Color = glowColor(FX.Grind.sparkColor),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
	})
	local grindSound: Sound? = nil
	if FX.Sounds.scrape ~= "" then
		grindSound = Instance.new("Sound")
		grindSound.SoundId = FX.Sounds.scrape
		grindSound.Looped = true
		grindSound.Volume = 0
		grindSound.RollOffMaxDistance = 150
		grindSound.Parent = grindAtt
	end

	local rig: Rig = {
		model = model,
		chassis = chassis,
		wheels = wheels,
		flameCore = flameCore,
		flameOuter = flameOuter,
		flameLight = flameLight,
		streaks = streaks,
		impactAtt = impactAtt,
		impact = impact,
		lastTier = -1,
		grindAtt = grindAtt,
		grindSparks = grindSparks,
		grindSound = grindSound,
		lastMarkPos = nil,
		lastScratchPos = nil,
		scratches = 0,
	}
	rigs[model] = rig
	return rig
end

-- ===== 벽 긁기: 차 옆으로 짧게 레이를 쏴서 벽에 붙어 달리는지 봄 (모든 차, 각자 화면에서) =====
local grindParams = RaycastParams.new()
grindParams.FilterType = Enum.RaycastFilterType.Exclude
local grindParamsAge = 999

local fxFolder: Folder? = nil
local function getFxFolder(): Folder
	if not fxFolder or not fxFolder.Parent then
		local f = Instance.new("Folder")
		f.Name = "ClientFX"
		f.Parent = workspace
		fxFolder = f
	end
	return fxFolder :: Folder
end

local wallMarks: { BasePart } = {}

local function fadeAndRemove(p: BasePart, lifetime: number)
	TweenService:Create(p, TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	Debris:AddItem(p, lifetime + 0.1)
end

local function addWallMark(from: Vector3, to: Vector3, normal: Vector3)
	local len = (to - from).Magnitude
	if len < 0.2 then
		return
	end
	local G = FX.Grind
	local mid = (from + to) / 2 + normal * 0.05
	local p = Instance.new("Part")
	p.Name = "WallScratch"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = G.wallMarkColor
	p.Transparency = G.wallMarkTransparency
	p.Size = Vector3.new(0.05, G.wallMarkHeight, len + 0.1)
	p.CFrame = CFrame.lookAt(mid, to + normal * 0.05)
	p.Parent = getFxFolder()
	fadeAndRemove(p, G.wallMarkLifetime)
	table.insert(wallMarks, p)
	if #wallMarks > G.maxWallMarks then
		local old = table.remove(wallMarks, 1)
		if old then
			old:Destroy()
		end
	end
end

local function addCarScratch(rig: Rig, side: number, localZ: number)
	local G = FX.Grind
	if rig.scratches >= G.maxCarScratches then
		return
	end
	rig.scratches += 1
	local chassis = rig.chassis
	local half = chassis.Size / 2
	local y = (math.random() - 0.5) * half.Y * 1.2
	local z = math.clamp(localZ + (math.random() - 0.5) * 2, -half.Z + 0.5, half.Z - 0.5)
	local s = Instance.new("Part")
	s.Name = "CarScratch"
	s.Anchored = false
	s.Massless = true
	s.CanCollide = false
	s.CanQuery = false
	s.CanTouch = false
	s.CastShadow = false
	s.Material = Enum.Material.SmoothPlastic
	s.Color = G.carScratchColor
	s.Size = Vector3.new(0.04, 0.1 + math.random() * 0.12, 1 + math.random() * 2.5)
	s.CFrame = chassis.CFrame * CFrame.new(side * (half.X + 0.02), y, z) * CFrame.Angles(math.rad((math.random() - 0.5) * 20), 0, 0)
	local w = Instance.new("WeldConstraint")
	w.Part0 = chassis
	w.Part1 = s
	w.Parent = s
	s.Parent = rig.model
end

local function updateGrind(rig: Rig, dt: number)
	local G = FX.Grind
	local chassis = rig.chassis
	local v = chassis.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local hitPos, hitNormal, hitSide, hitZ = nil, nil, 0, 0
	if flat.Magnitude > G.minSpeed then
		local cf = chassis.CFrame
		local half = chassis.Size / 2
		for _, side in { -1, 1 } do
			for _, z in { -half.Z * 0.6, half.Z * 0.6 } do
				local origin = cf:PointToWorldSpace(Vector3.new(0, 0, z))
				local hit = workspace:Raycast(origin, cf.RightVector * side * (half.X + G.reach), grindParams)
				if hit and math.abs(hit.Normal.Y) < 0.5 then
					hitPos, hitNormal, hitSide, hitZ = hit.Position, hit.Normal, side, z
					break
				end
			end
			if hitPos then
				break
			end
		end
	end

	if hitPos and hitNormal then
		local dir = flat.Unit
		rig.grindAtt.WorldCFrame = CFrame.lookAt(hitPos + hitNormal * 0.2, hitPos + hitNormal * 0.2 + dir)
		local speedK = math.clamp(flat.Magnitude / 100, 0.4, 1.5)
		rig.grindSparks.Rate = G.sparkRate * speedK
		-- 벽에 긁힌 자국 (끊김 없이 이어서)
		if rig.lastMarkPos and (hitPos - rig.lastMarkPos).Magnitude < 12 then
			if (hitPos - rig.lastMarkPos).Magnitude >= G.markSpacing then
				addWallMark(rig.lastMarkPos, hitPos, hitNormal)
				rig.lastMarkPos = hitPos
			end
		else
			rig.lastMarkPos = hitPos
		end
		-- 차에도 긁힌 자국 (가끔)
		if not rig.lastScratchPos or (hitPos - rig.lastScratchPos).Magnitude >= G.carScratchSpacing then
			rig.lastScratchPos = hitPos
			addCarScratch(rig, hitSide, hitZ)
		end
		if rig.grindSound then
			if not rig.grindSound.IsPlaying then
				rig.grindSound:Play()
			end
			rig.grindSound.Volume = G.soundVolume * speedK
			rig.grindSound.PlaybackSpeed = 0.9 + speedK * 0.3
		end
	else
		rig.grindSparks.Rate = 0
		rig.lastMarkPos = nil
		if rig.grindSound and rig.grindSound.IsPlaying then
			rig.grindSound:Stop()
		end
	end
end

local function setOff(rig: Rig)
	for _, w in rig.wheels do
		w.skid.Enabled = false
		w.glow.Enabled = false
		w.sparks.Rate = 0
		w.embers.Rate = 0
		w.smoke.Rate = 0
	end
	rig.flameCore.Rate = 0
	rig.flameOuter.Rate = 0
	rig.flameLight.Enabled = false
	rig.grindSparks.Rate = 0
	rig.lastMarkPos = nil
	if rig.grindSound and rig.grindSound.IsPlaying then
		rig.grindSound:Stop()
	end
	for _, t in rig.streaks do
		t.Enabled = false
	end
end

local function update(dt: number)
	local camPos = workspace.CurrentCamera.CFrame.Position
	grindParamsAge += dt
	if grindParamsAge > 1 then
		grindParamsAge = 0
		local ignore: { Instance } = { getFxFolder() }
		local vehicles = workspace:FindFirstChild("Vehicles")
		if vehicles then
			table.insert(ignore, vehicles)
		end
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(ignore, p.Character)
			end
		end
		grindParams.FilterDescendantsInstances = ignore
	end
	for model, rig in rigs do
		if not model.Parent or not rig.chassis.Parent then
			rigs[model] = nil
			continue
		end
		if (rig.chassis.Position - camPos).Magnitude > FX.maxDistance then
			setOff(rig)
			continue
		end
		local drift = model:GetAttribute("FX_Drift") == true
		local tier = model:GetAttribute("FX_Tier") or 0
		local boost = model:GetAttribute("FX_Boost") == true

		if tier ~= rig.lastTier then
			rig.lastTier = tier
			local color = FX.Sparks.tierColors[tier] or FX.Sparks.tierColors[0]
			for _, w in rig.wheels do
				w.sparks.Color = glowColor(color)
				w.embers.Color = ColorSequence.new(color)
				w.glow.Color = glowColor(color)
			end
		end
		local sparkRate = drift and (FX.Sparks.baseRate + FX.Sparks.ratePerTier * tier) or 0
		for _, w in rig.wheels do
			w.skid.Enabled = drift
			w.glow.Enabled = drift and FX.Glow.enabled
			w.sparks.Rate = sparkRate
			w.embers.Rate = drift and FX.Sparks.emberRate or 0
			w.smoke.Rate = drift and FX.Smoke.rate or 0
		end

		rig.flameCore.Rate = boost and FX.Flame.coreRate or 0
		rig.flameOuter.Rate = boost and FX.Flame.outerRate or 0
		rig.flameLight.Enabled = boost
		if boost then
			-- 불빛 깜빡임
			rig.flameLight.Brightness = FX.Flame.lightBrightness * (0.75 + math.random() * 0.5)
		end
		for _, t in rig.streaks do
			t.Enabled = boost and FX.Streak.enabled
		end
		if not model:GetAttribute("Exploded") then
			updateGrind(rig, dt)
		end
	end
end

local function track(model: Instance)
	if model:IsA("Model") and not rigs[model] then
		-- 스트리밍으로 늦게 들어올 수 있으니 Chassis 를 잠깐 기다림
		task.spawn(function()
			local chassis = model.PrimaryPart or model:WaitForChild("Chassis", 5)
			if chassis and model.Parent and not rigs[model] then
				buildRig(model)
			end
		end)
	end
end

-- 충돌 스파크 터뜨리기 (내 차는 VehicleController 가 바로 호출, 다른 차는 서버 중계로)
function VehicleEffects.PlayImpact(model: Model, worldPos: Vector3, strength: number)
	local rig = rigs[model] or buildRig(model)
	if not rig then
		return
	end
	if (worldPos - workspace.CurrentCamera.CFrame.Position).Magnitude > FX.maxDistance then
		return
	end
	rig.impactAtt.WorldPosition = worldPos
	rig.impact:Emit(math.max(math.floor(FX.Impact.count * strength), 5))
end

-- 드리프트 들어가는 순간 연기/불똥 한 번에 펑 (내 화면)
function VehicleEffects.PlayDriftBurst(model: Model)
	local rig = rigs[model] or buildRig(model)
	if not rig then
		return
	end
	for _, w in rig.wheels do
		w.smoke:Emit(FX.Burst.smoke)
		w.sparks:Emit(FX.Burst.sparks)
		w.embers:Emit(FX.Burst.embers)
	end
end

-- 화면 전체 하얗게 번쩍 (내 화면)
local flashGui: ScreenGui? = nil
local function screenFlash(strength: number, duration: number)
	if not flashGui or not flashGui.Parent then
		local sg = Instance.new("ScreenGui")
		sg.Name = "ScreenFlash"
		sg.IgnoreGuiInset = true
		sg.ResetOnSpawn = false
		sg.DisplayOrder = 50
		local f = Instance.new("Frame")
		f.Name = "White"
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Parent = sg
		sg.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		flashGui = sg
	end
	local frame = (flashGui :: ScreenGui):FindFirstChild("White") :: Frame
	frame.BackgroundTransparency = 1 - strength
	TweenService:Create(frame, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

-- 내가 이 차에 타고 있거나 아주 가까운지
local function isNearMe(model: Model?, pos: Vector3, radius: number): boolean
	local char = Players.LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart and model and hum.SeatPart:IsDescendantOf(model) then
		return true
	end
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and (root.Position - pos).Magnitude < radius
end

-- 1단계 "틱": 차가 하얗게 번쩍 + (탄 사람/가까운 사람) 화면 살짝 하얗게
function VehicleEffects.PlayPreExplosion(model: Model, pos: Vector3)
	local E = FX.Explosion
	if model and model.Parent then
		local h = Instance.new("Highlight")
		h.FillColor = Color3.new(1, 1, 1)
		h.OutlineColor = Color3.new(1, 1, 1)
		h.FillTransparency = 0.1
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = model
		Debris:AddItem(h, E.tickFlashTime)
	end
	if isNearMe(model, pos, E.tickScreenRadius) then
		screenFlash(E.tickScreenFlash, E.tickFlashTime + 0.1)
	end
	if FX.Sounds.tick ~= "" then
		local s = Instance.new("Sound")
		s.SoundId = FX.Sounds.tick
		s.Parent = model and model.PrimaryPart or workspace
		s:Play()
		Debris:AddItem(s, 2)
	end
end

-- 날아가는 파편마다 불꼬리 (Trail)
local function addDebrisTrails(model: Model)
	local E = FX.Explosion
	local count = 0
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 and count < E.maxDebrisTrails then
			count += 1
			local half = math.max(p.Size.X, p.Size.Y, p.Size.Z) * 0.3
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, half, 0)
			a0.Parent = p
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -half, 0)
			a1.Parent = p
			local t = Instance.new("Trail")
			t.Attachment0 = a0
			t.Attachment1 = a1
			t.FaceCamera = true
			t.Lifetime = E.debrisTrailLifetime
			t.MinLength = 0.05
			t.LightEmission = 0.8
			t.LightInfluence = 0
			t.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 150)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 120, 30)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 60, 60)),
			})
			t.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.4),
				NumberSequenceKeypoint.new(1, 1),
			})
			t.WidthScale = NumberSequence.new(1, 0.3)
			t.Parent = p
			-- 꼬리는 1.5초 뒤 서서히 꺼짐
			task.delay(E.debrisTrailTime, function()
				if t.Parent then
					t.Enabled = false
				end
			end)
		end
	end
end

-- 대폭발: 큰 불덩이 + 검은 연기 + 불똥 + 번쩍 (모두 화면)
function VehicleEffects.PlayExplosion(pos: Vector3, model: Model?)
	if model and model.Parent then
		addDebrisTrails(model)
	end
	if isNearMe(model, pos, FX.Explosion.tickScreenRadius) then
		screenFlash(FX.Explosion.boomScreenFlash, 0.5)
	end
	local cam = workspace.CurrentCamera
	if (pos - cam.CFrame.Position).Magnitude > FX.maxDistance * 1.5 then
		return
	end
	local T, E = FX.Textures, FX.Explosion
	local p = Instance.new("Part")
	p.Name = "ExplosionFX"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.CFrame = CFrame.new(pos)
	p.Parent = getFxFolder()
	local fire = newEmitter(p, {
		Texture = T.fire,
		Lifetime = NumberRange.new(0.4, 0.9),
		Speed = NumberRange.new(20, 55),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Acceleration = Vector3.new(0, 25, 0),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 4),
			NumberSequenceKeypoint.new(0.3, 9),
			NumberSequenceKeypoint.new(1, 2),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 200)),
			ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 170, 40)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 40, 20)),
		}),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 3,
	})
	local smoke = newEmitter(p, {
		Texture = T.smoke,
		Lifetime = NumberRange.new(1.5, 2.8),
		Speed = NumberRange.new(10, 30),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 3,
		Acceleration = Vector3.new(0, 12, 0),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 5),
			NumberSequenceKeypoint.new(1, 16),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(Color3.fromRGB(60, 55, 55), Color3.fromRGB(120, 115, 110)),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-30, 30),
		LightInfluence = 0.7,
	})
	local sparks = newEmitter(p, {
		Texture = T.spark,
		Lifetime = NumberRange.new(0.5, 1.2),
		Speed = NumberRange.new(40, 90),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -120, 0),
		Drag = 1,
		Size = NumberSequence.new(0.6, 0),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 3,
		Color = glowColor(Color3.fromRGB(255, 190, 70)),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
	})
	fire:Emit(E.fire)
	smoke:Emit(E.smoke)
	sparks:Emit(E.sparks)
	-- 충격파: 순식간에 커지며 사라지는 빛나는 공 (파앙!)
	local ring = Instance.new("Part")
	ring.Name = "Shockwave"
	ring.Shape = Enum.PartType.Ball
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 200, 120)
	ring.Transparency = 0.25
	ring.Size = Vector3.one * 3
	ring.CFrame = CFrame.new(pos)
	ring.Parent = getFxFolder()
	TweenService:Create(ring, TweenInfo.new(E.shockwaveTime, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.one * E.shockwaveSize,
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, E.shockwaveTime + 0.1)
	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 180, 90)
	flash.Range = E.flashRange
	flash.Brightness = E.flashBrightness
	flash.Parent = p
	TweenService:Create(flash, TweenInfo.new(0.7), { Brightness = 0 }):Play()
	Debris:AddItem(p, 4)
	-- 가까우면 화면 흔들림
	local d = (pos - cam.CFrame.Position).Magnitude
	if d < E.shakeDistance then
		ChaseCamera.Punch(E.shake * (1 - d / E.shakeDistance))
	end
	if FX.Sounds.explosion ~= "" then
		local s = Instance.new("Sound")
		s.SoundId = FX.Sounds.explosion
		s.Volume = 1
		s.RollOffMaxDistance = 300
		s.Parent = p
		s:Play()
	end
end

function VehicleEffects.Start()
	if started then
		return
	end
	started = true
	task.spawn(function() -- Vehicles 폴더를 기다리는 동안 다른 스크립트를 막지 않게
		local folder = workspace:WaitForChild("Vehicles")
		folder.ChildAdded:Connect(track)
		folder.ChildRemoved:Connect(function(model)
			rigs[model :: Model] = nil
		end)
		for _, m in folder:GetChildren() do
			track(m)
		end
	end)
	VehicleFX.OnClientEvent:Connect(function(kind, model, pos, strength)
		if kind == "Impact" and typeof(model) == "Instance" and model:IsA("Model") and typeof(pos) == "Vector3" then
			VehicleEffects.PlayImpact(model, pos, type(strength) == "number" and strength or 1)
		elseif kind == "PreExplode" and typeof(pos) == "Vector3" then
			VehicleEffects.PlayPreExplosion(typeof(model) == "Instance" and model or nil, pos)
		elseif kind == "Explode" and typeof(pos) == "Vector3" then
			VehicleEffects.PlayExplosion(pos, typeof(model) == "Instance" and model or nil)
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return VehicleEffects
