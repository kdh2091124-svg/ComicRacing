-- 1인칭 내 무기 (내 화면 전용): 총 + "내 캐릭터의 진짜 팔"(옷/피부색 그대로)이 화면 오른쪽 아래에 보이고 움직임
-- 모션은 스프링(튕기며 제자리) + 짧은 동작 단계로 빠르고 간결하게
--   쏠 때: 뒤로 탁 밀리고 총구가 들렸다가 살짝 튕기며 복귀 (쫄깃)
--   볼트: 굴리기 → 당기기 → 밀기 → 복귀
--   장전: 기울이기 → 탄창 빼기(왼손 아래로) → 꽂기 → 탁 치기 → 복귀
--   스웨이(마우스 따라 늦게), 숨쉬기, 꺼내기(아래에서 올라옴), 우클릭 조준(가운데로)
-- 총 모델: ReplicatedStorage.WeaponModels.<id> (Tool/Model). 가장 긴 쪽 = 총열, "Muzzle" 쪽이 앞. 없으면 상자 총

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)

local ViewModel = {}

local VM = {
	hip = CFrame.new(0.95, -1.05, -2.2), -- 평소 위치 (카메라 기준 오른쪽, 아래, 앞)
	ads = CFrame.new(0, -0.55, -1.7), -- 우클릭 조준 위치 (가운데)
	maxLength = 3.6, -- 무기에 viewLength 가 없을 때 쓰는 길이
	grip = 0.32, -- 총 길이 중 오른손이 쥐는 곳 (0 = 개머리판 끝)
	foregrip = 0.68, -- 왼손이 받치는 곳
	-- 쏠 때 반동 스프링 (클수록 빨리, damping 낮을수록 더 튕김)
	kickBack = 0.35, -- 한 발당 뒤로 밀리는 속도
	kickUp = 0.22, -- 한 발당 총구 들림 (라디안 속도)
	kickRoll = 0.08,
	kickStiffness = 260,
	kickDamping = 0.42, -- 0.4~0.6 = 살짝 튕기며 복귀 (쫄깃)
	-- 스웨이: 손목이 아니라 "어깨"를 중심으로 팔째 살짝 늦게 따라옴 + 도는 쪽으로 살짝 기울임
	shoulderPivot = Vector3.new(0.75, -1.4, 0.7), -- 카메라 기준 오른쪽 어깨 (이 점을 중심으로 흔들림)
	swayAmount = 0.00006, -- 마우스 속도(픽셀/초) 1 당 흔들림 (라디안)
	swayMax = 0.07, -- 최대 흔들림 (라디안)
	swayRoll = 0.9, -- 좌우로 돌 때 기울기 비율
	swayStiffness = 230, -- 클수록 빨리 따라옴
	swayDamping = 0.85, -- 1 에 가까울수록 출렁임 없이 착 붙음
	adsSpeed = 16,
	adsDistance = 1.1, -- 총에 "Aim" 표시가 있으면 조준할 때 그 점이 눈앞 이 거리에 정확히 옴
	raiseTime = 0.25,
	-- 총 안의 움직이는 파트 (이름으로 찾음): "Mag" = 탄창, "Bolt" = 볼트 손잡이 (파트 또는 그 이름의 Model/Folder)
	boltTravel = 0.38, -- 볼트 당길 때 뒤로 가는 거리
	boltLift = 70, -- 볼트 손잡이 들어 올리는 각도 (도)
	shotSlide = 0.16, -- 연사 총: 쏠 때마다 볼트가 뒤로 철컥 하는 거리
	magDrop = 1.2, -- 장전 때 탄창이 빠지는 거리
	-- 리볼버: "Cylinder" = 실린더, "Hammer" = 공이치기
	cylinderStep = 60, -- 한 발마다 실린더 도는 각도 (6연발 = 60)
	cylinderSwing = 75, -- 장전 때 실린더가 왼쪽으로 열리는 각도
	hammerCock = 35, -- 공이치기 젖혀진 각도 (쏘면 앞으로 떨어졌다 다시 젖혀짐)
	boltAnimPortion = 0.75, -- boltTime 중 볼트 동작이 차지하는 비율 (나머지는 제자리)
	sleeveColor = Color3.fromRGB(60, 70, 90), -- 팔을 못 가져올 때 대신 쓰는 색
}
ViewModel.Settings = VM

-- 2차 스프링 (위치 x, 속도 v): 목표 0 으로 돌아감
type Spring = { x: number, v: number }
local function newSpring(): Spring
	return { x = 0, v = 0 }
end
local function stepSpring(s: Spring, k: number, zeta: number, dt: number, target: number?)
	local c = 2 * zeta * math.sqrt(k)
	local goal = target or 0
	-- 큰 dt 에서 튀지 않게 잘게 나눠 계산
	local steps = math.max(math.ceil(dt / (1 / 240)), 1)
	local h = dt / steps
	for _ = 1, steps do
		local a = k * (goal - s.x) - c * s.v
		s.v += a * h
		s.x += s.v * h
	end
end

-- 부드러운 최대치: 끝에서 딱 막히지 않고 점점 눌림
local function soft(x: number, limit: number): number
	return limit * math.tanh(x / limit)
end

local current: Model? = nil
local currentId: string? = nil
local gripOffset = CFrame.identity
local gunLength = 3
local muzzleLocal: Vector3? = nil
local foreLocal: Vector3? = nil
local ejectLocal: Vector3? = nil
local aimLocal: Vector3? = nil
local hasGrip = false
type ArmSet = { hand: BasePart?, fore: BasePart?, single: BasePart? }
local rightArm: ArmSet = {}
local leftArm: ArmSet = {}
local raiseStart = 0
local lastKick = 0
-- 움직이는 파트: 손잡이 기준 원래 위치 + 회전 중심
type Moving = { parts: { { part: BasePart, rel: CFrame } }, center: Vector3 }
local magSet: Moving? = nil
local boltSet: Moving? = nil
local cylSet: Moving? = nil
local hammerSet: Moving? = nil
local cylAngle, cylTarget = 0, 0
local kickZ, kickP, kickR = newSpring(), newSpring(), newSpring()
local swayX, swayY = newSpring(), newSpring()
local mouseVel = Vector2.zero
local adsBlend = 0

local function smooth(a: number, b: number, t: number): number
	local u = math.clamp((t - a) / (b - a), 0, 1)
	return u * u * (3 - 2 * u)
end

local function setupPart(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
end

local function placeholderGun(parent: Model)
	local function part(size: Vector3, cf: CFrame, color: Color3): Part
		local p = Instance.new("Part")
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = Enum.Material.Metal
		setupPart(p)
		p.Parent = parent
		return p
	end
	local body = part(Vector3.new(0.35, 0.5, 2.6), CFrame.identity, Color3.fromRGB(35, 35, 40))
	part(Vector3.new(0.25, 0.6, 0.35), CFrame.new(0, -0.5, -0.2), Color3.fromRGB(25, 25, 28)).Name = "Mag"
	part(Vector3.new(0.15, 0.2, 0.5), CFrame.new(0, 0.35, 0.3), Color3.fromRGB(25, 25, 28))
	part(Vector3.new(0.35, 0.12, 0.12), CFrame.new(0.3, 0.12, 0.45), Color3.fromRGB(120, 120, 130)).Name = "Bolt"
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.05, -1.3)
	muzzle.Parent = body
	local eject = Instance.new("Attachment")
	eject.Name = "Eject"
	eject.Position = Vector3.new(0.2, 0.12, 0.25)
	eject.Parent = body
end

-- 내 캐릭터 팔 복제 (R6: 팔 통짜 / R15: 아래팔 + 손). 옷(Shirt) 이 보이려면 같은 이름 + Humanoid 필요
local function cloneArms(m: Model)
	local char = Players.LocalPlayer.Character
	rightArm, leftArm = {}, {}
	if not char then
		return
	end
	local function grab(name: string): BasePart?
		local src = char:FindFirstChild(name)
		if not (src and src:IsA("BasePart")) then
			return nil
		end
		local ok, c = pcall(function()
			return src:Clone()
		end)
		if not ok or not c then
			return nil
		end
		for _, d in c:GetChildren() do
			if not (d:IsA("Decal") or d:IsA("SpecialMesh") or d:IsA("SurfaceAppearance") or d:IsA("WrapLayer")) then
				d:Destroy() -- 관절/부착물/스크립트 제거
			end
		end
		setupPart(c)
		c.Parent = m
		return c
	end
	if char:FindFirstChild("Right Arm") then -- R6
		rightArm.single = grab("Right Arm")
		leftArm.single = grab("Left Arm")
	else -- R15
		rightArm.fore, rightArm.hand = grab("RightLowerArm"), grab("RightHand")
		leftArm.fore, leftArm.hand = grab("LeftLowerArm"), grab("LeftHand")
	end
	-- 옷: Humanoid + Shirt/BodyColors 가 같이 있어야 팔에 옷 무늬가 입혀짐
	local hum = Instance.new("Humanoid")
	hum.EvaluateStateMachine = false
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.Parent = m
	for _, cls in { "Shirt", "BodyColors" } do
		local src = char:FindFirstChildOfClass(cls)
		if src then
			local ok, c = pcall(function()
				return src:Clone()
			end)
			if ok and c then
				c.Parent = m
			end
		end
	end
end

function ViewModel.Destroy()
	if current then
		current:Destroy()
	end
	current, currentId, muzzleLocal = nil, nil, nil
	rightArm, leftArm = {}, {}
end

function ViewModel.Set(weaponId: string)
	if currentId == weaponId and current and current.Parent then
		return
	end
	ViewModel.Destroy()
	currentId = weaponId
	local folder = ReplicatedStorage:FindFirstChild("WeaponModels")
	local template = folder and folder:FindFirstChild(weaponId)
	local gun = Instance.new("Model")
	gun.Name = "Gun"
	if template then
		for _, c in template:Clone():GetChildren() do
			c.Parent = gun
		end
	else
		placeholderGun(gun)
	end
	for _, d in gun:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			setupPart(d)
		end
	end
	local primary = gun:FindFirstChildWhichIsA("BasePart", true)
	if not primary then
		gun:Destroy()
		return
	end
	gun.PrimaryPart = primary
	-- 방향: 가장 긴 축 = 총열, 두 번째 = 위아래, Muzzle 쪽이 앞
	local bbCF, size = gun:GetBoundingBox()
	local axes = {
		{ v = bbCF.RightVector, len = size.X },
		{ v = bbCF.UpVector, len = size.Y },
		{ v = bbCF.LookVector, len = size.Z },
	}
	table.sort(axes, function(a, b)
		return a.len > b.len
	end)
	local fwd, len, up = axes[1].v, axes[1].len, axes[2].v
	local function muzzleWorld(): Vector3?
		local mz = gun:FindFirstChild("Muzzle", true)
		if mz and mz:IsA("Attachment") then
			return mz.WorldPosition
		elseif mz and mz:IsA("BasePart") then
			return mz.Position
		end
		return nil
	end
	local mzPos = muzzleWorld()
	if mzPos and (mzPos - bbCF.Position):Dot(fwd) < 0 then
		fwd = -fwd
	end
	-- 무기별 길이(WeaponConfig.viewLength)에 맞춰 키우거나 줄임
	local def = WeaponConfig.Get(weaponId)
	local want = def and def.viewLength or VM.maxLength
	if math.abs(len - want) > 0.05 then
		local s = want / len
		gun:ScaleTo(gun:GetScale() * s)
		bbCF = gun:GetBoundingBox()
		len *= s
		mzPos = muzzleWorld()
	end
	gunLength = len
	-- 모델 안의 표시점 (Attachment 또는 작은 파트, 이름으로 찾음)
	local function point(name: string): Vector3?
		local a = gun:FindFirstChild(name, true)
		if a and a:IsA("Attachment") then
			return a.WorldPosition
		elseif a and a:IsA("BasePart") then
			return a.Position
		end
		return nil
	end
	local stock = bbCF.Position - fwd * len / 2
	local gripPoint = point("Grip") -- 오른손이 쥐는 곳 (없으면 총 길이의 grip 비율 지점)
	hasGrip = gripPoint ~= nil
	local grip = CFrame.fromMatrix(gripPoint or (stock + fwd * len * VM.grip), fwd:Cross(up), up, -fwd)
	gripOffset = grip:Inverse() * gun:GetPivot()
	muzzleLocal = grip:PointToObjectSpace(mzPos or (bbCF.Position + fwd * len / 2))
	local function localOf(name: string): Vector3?
		local p = point(name)
		return p and grip:PointToObjectSpace(p) or nil
	end
	foreLocal = localOf("Foregrip") -- 왼손 받치는 곳
	ejectLocal = localOf("Eject") -- 탄피 배출구
	aimLocal = localOf("Aim") -- 조준할 때 눈 앞에 오는 가늠자/조준기 위치
	-- 탄창/볼트 파트 기억 (손잡이 기준 위치)
	local function collect(name: string): Moving?
		local list = {}
		local sum = Vector3.zero
		for _, d in gun:GetDescendants() do
			if d.Name == name then
				local parts = d:IsA("BasePart") and { d } or d:GetDescendants()
				for _, p in parts do
					if p:IsA("BasePart") then
						local rel = grip:ToObjectSpace(p.CFrame)
						table.insert(list, { part = p, rel = rel })
						sum += rel.Position
					end
				end
			end
		end
		if #list == 0 then
			return nil
		end
		return { parts = list, center = sum / #list }
	end
	magSet = collect("Mag")
	boltSet = collect("Bolt")
	cylSet = collect("Cylinder")
	hammerSet = collect("Hammer")
	cylAngle, cylTarget = 0, 0

	local m = Instance.new("Model")
	m.Name = "ViewModel"
	gun.Parent = m
	cloneArms(m)
	m.Parent = workspace.CurrentCamera
	current = m
	raiseStart = os.clock()
	kickZ, kickP, kickR = newSpring(), newSpring(), newSpring()
	adsBlend = 0
end

-- 쏠 때: 스프링에 "탁" 충격 (strength 1 = 한 발 세게, 연사는 작게)
function ViewModel.Kick(strength: number?)
	local s = strength or 1
	lastKick = os.clock()
	cylTarget += math.rad(VM.cylinderStep) -- 리볼버 실린더 한 칸
	kickZ.v += VM.kickBack * 60 * s
	kickP.v += VM.kickUp * 60 * s
	kickR.v += (math.random() * 2 - 1) * VM.kickRoll * 60 * s
end

local function gunFrame(): CFrame?
	local gun = current and current:FindFirstChild("Gun")
	if not gun or not gun:IsA("Model") then
		return nil
	end
	return gun:GetPivot() * gripOffset:Inverse()
end

function ViewModel.MuzzlePosition(): Vector3?
	local g = gunFrame()
	return g and muzzleLocal and g:PointToWorldSpace(muzzleLocal) or nil
end

-- 탄피 배출구 위치 ("Eject" 표시가 없으면 nil)
function ViewModel.EjectPosition(): Vector3?
	local g = gunFrame()
	return g and ejectLocal and g:PointToWorldSpace(ejectLocal) or nil
end

-- 리볼버 실린더 가운데 (장전 때 탄피 쏟기용, "Cylinder" 없으면 nil)
function ViewModel.CylinderPosition(): Vector3?
	local g = gunFrame()
	return g and cylSet and g:PointToWorldSpace(cylSet.center) or nil
end

function ViewModel.Axes(): (Vector3?, Vector3?)
	local g = gunFrame()
	if not g then
		return nil, nil
	end
	return g.RightVector, g.UpVector
end

-- 팔 배치: 손 끝이 handPos, 팔은 어깨(화면 밖) 쪽으로 뻗음
local function placeArm(set: ArmSet, handPos: Vector3, shoulder: Vector3, camCF: CFrame)
	local upDir = shoulder - handPos
	if upDir.Magnitude < 0.01 then
		return
	end
	upDir = upDir.Unit
	local right = upDir:Cross(camCF.LookVector)
	right = right.Magnitude > 0.01 and right.Unit or camCF.RightVector
	local function orient(center: Vector3): CFrame
		return CFrame.fromMatrix(center, right, upDir)
	end
	if set.single then -- R6: 아래쪽 끝 = 손
		set.single.CFrame = orient(handPos + upDir * set.single.Size.Y / 2)
	else
		local handLen = set.hand and set.hand.Size.Y or 0.3
		if set.hand then
			set.hand.CFrame = orient(handPos + upDir * handLen / 2)
		end
		if set.fore then
			set.fore.CFrame = orient(handPos + upDir * (handLen + set.fore.Size.Y / 2))
		end
	end
end

-- 매 프레임: state = { ads, hidden, mouseDelta, bolt(0~1|nil), reload(0~1|nil), dt }
function ViewModel.Update(cam: Camera, state)
	if not current or not current.Parent then
		return
	end
	local dt = math.min(state.dt, 1 / 20)
	for _, d in current:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = state.hidden and 1 or 0
		end
	end
	if state.hidden then
		return
	end
	adsBlend += ((state.ads and 1 or 0) - adsBlend) * math.min(dt * VM.adsSpeed, 1)
	-- 스프링들
	local md: Vector2 = state.mouseDelta
	-- 화면을 돌린 반대쪽으로 팔이 살짝 늦게 따라옴
	-- 마우스 "속도"를 부드럽게 걸러서 목표로 삼음 (프레임마다 튀는 값을 그대로 넣으면 탁탁 걸림)
	local inst = dt > 0 and md / dt or Vector2.zero
	mouseVel = mouseVel:Lerp(inst, math.min(dt * 18, 1))
	local amt = VM.swayAmount * (1 - adsBlend * 0.6)
	stepSpring(swayX, VM.swayStiffness, VM.swayDamping, dt, mouseVel.X * amt)
	stepSpring(swayY, VM.swayStiffness, VM.swayDamping, dt, mouseVel.Y * amt)
	stepSpring(kickZ, VM.kickStiffness, VM.kickDamping, dt)
	stepSpring(kickP, VM.kickStiffness, VM.kickDamping, dt)
	stepSpring(kickR, VM.kickStiffness * 0.8, VM.kickDamping, dt)
	local t = os.clock()
	local breathe = math.sin(t * 1.7) * 0.01 * (1 - adsBlend * 0.8)
	local raise = 1 - (1 - math.clamp((t - raiseStart) / VM.raiseTime, 0, 1)) ^ 3

	-- 조준 위치: "Aim" 표시가 있으면 그 점이 화면 정중앙(눈앞)에 오게, 없으면 VM.ads
	local adsCF = aimLocal and CFrame.new(-aimLocal.X, -aimLocal.Y, -VM.adsDistance - aimLocal.Z) or VM.ads
	local base = VM.hip:Lerp(adsCF, adsBlend)
	-- 어깨를 중심으로 팔째 흔들림 (조준 중엔 어깨 대신 거의 눈앞 중심)
	local sx = soft(swayX.x, VM.swayMax)
	local sy = soft(swayY.x, VM.swayMax)
	local pivot = CFrame.new(VM.shoulderPivot:Lerp(Vector3.new(0, -0.6, 0.4), adsBlend))
	local swayCF = pivot * CFrame.Angles(sy, sx, sx * VM.swayRoll) * pivot:Inverse()
	local cf = cam.CFrame * swayCF * base
		* CFrame.new(0, -0.8 * (1 - raise) + breathe, 0) * CFrame.Angles(math.rad(-30) * (1 - raise), 0, 0)
		* CFrame.new(0, 0, math.clamp(kickZ.x, -0.2, 0.6)) * CFrame.Angles(math.clamp(kickP.x, -0.2, 0.5), 0, kickR.x)

	-- 장전: 기울이기 → 탄창 빼기 → 꽂기 → 탁 → 복귀
	local leftDrop = 0
	if state.reload then
		local r = state.reload
		local tilt = smooth(0, 0.12, r) * (1 - smooth(0.85, 1, r))
		local out = smooth(0.15, 0.32, r) * (1 - smooth(0.45, 0.62, r))
		local slap = smooth(0.62, 0.68, r) * (1 - smooth(0.68, 0.8, r))
		cf *= CFrame.new(0, -0.25 * tilt, 0) * CFrame.Angles(math.rad(-12) * tilt, math.rad(10) * tilt, math.rad(32) * tilt)
		cf *= CFrame.new(0, 0.06 * slap, 0) * CFrame.Angles(math.rad(-4) * slap, 0, 0)
		leftDrop = out
	end
	-- 볼트: 굴리기 → 당기기 → 밀기 → 복귀 (boltAnimPortion 안에 빠르게 끝냄)
	local pull, lift = 0, 0
	if state.bolt then
		local b = math.clamp(state.bolt / VM.boltAnimPortion, 0, 1)
		local roll = smooth(0, 0.15, b) * (1 - smooth(0.7, 0.9, b))
		lift = smooth(0.05, 0.15, b) * (1 - smooth(0.62, 0.72, b)) -- 손잡이 들기 → (당기고 밀고) → 내리기
		pull = smooth(0.15, 0.35, b) * (1 - smooth(0.45, 0.62, b))
		local thud = smooth(0.58, 0.63, b) * (1 - smooth(0.63, 0.75, b)) -- 밀어 넣을 때 탁
		cf *= CFrame.Angles(math.rad(4) * roll, 0, math.rad(-24) * roll) * CFrame.new(0.05 * roll, -0.06 * roll, 0)
		cf *= CFrame.new(0, 0, -0.05 * thud) * CFrame.Angles(math.rad(-3) * thud, 0, 0)
	end

	local gun = current:FindFirstChild("Gun")
	if gun and gun:IsA("Model") then
		gun:PivotTo(cf * gripOffset)
	end
	-- 볼트: 손잡이 들고(총열 축으로 회전) 뒤로 당김. 연사 총은 쏠 때마다 뒤로 철컥
	if boltSet then
		local slide = VM.boltTravel * pull + VM.shotSlide * math.clamp(1 - (t - lastKick) / 0.06, 0, 1)
		local c0 = boltSet.center
		local move = CFrame.new(0, 0, slide) * CFrame.new(c0) * CFrame.Angles(0, 0, math.rad(VM.boltLift) * lift) * CFrame.new(-c0)
		for _, e in boltSet.parts do
			e.part.CFrame = cf * move * e.rel
		end
	end
	-- 리볼버 실린더: 쏠 때마다 한 칸 빠르게 돌고, 장전 때 아래 경첩 기준으로 왼쪽으로 열림
	if cylSet then
		cylAngle += (cylTarget - cylAngle) * math.min(dt * 30, 1)
		local c0 = cylSet.center
		local hinge = c0 + Vector3.new(0, -0.3, 0)
		local swing = CFrame.new(hinge) * CFrame.Angles(0, 0, math.rad(VM.cylinderSwing) * leftDrop) * CFrame.new(-hinge)
		local spin = CFrame.new(c0) * CFrame.Angles(0, 0, cylAngle) * CFrame.new(-c0)
		for _, e in cylSet.parts do
			e.part.CFrame = cf * swing * spin * e.rel
		end
	end
	-- 공이치기: 쏘면 앞으로 탁 떨어졌다가 0.25초 동안 다시 젖혀짐
	if hammerSet then
		local cock = math.clamp((t - lastKick) / 0.25, 0, 1)
		local c0 = hammerSet.center
		local move = CFrame.new(c0) * CFrame.Angles(math.rad(VM.hammerCock) * cock, 0, 0) * CFrame.new(-c0)
		for _, e in hammerSet.parts do
			e.part.CFrame = cf * move * e.rel
		end
	end
	-- 탄창: 장전 때 아래로 빠졌다(살짝 기울며) 다시 꽂힘
	if magSet and leftDrop > 0 then
		local c0 = magSet.center
		local move = CFrame.new(-0.1 * leftDrop, -VM.magDrop * leftDrop, 0.2 * leftDrop)
			* CFrame.new(c0) * CFrame.Angles(math.rad(-15) * leftDrop, 0, math.rad(20) * leftDrop) * CFrame.new(-c0)
		for _, e in magSet.parts do
			e.part.CFrame = cf * move * e.rel
		end
	end
	-- 손: 오른손 = 손잡이(볼트 땐 뒤로 당김, 손 위로), 왼손 = 총열 받침(장전 땐 아래로 탄창 빼기)
	-- Grip/Foregrip 표시가 있으면 손이 정확히 그 자리 (없으면 대략 총 아래)
	local rBase = hasGrip and Vector3.new(0, -0.1, 0) or Vector3.new(0.05, -0.25, 0.15)
	local rHand = cf:PointToWorldSpace(rBase + Vector3.new(0.25 * pull, 0.35 * pull, 0.55 * pull))
	local lBase = foreLocal and (foreLocal + Vector3.new(0, -0.12, 0)) or Vector3.new(-0.05, -0.3, -gunLength * (VM.foregrip - VM.grip))
	local lHand = cf:PointToWorldSpace(lBase + Vector3.new(0, -0.9 * leftDrop, 0.4 * leftDrop))
	local camCF = cam.CFrame
	placeArm(rightArm, rHand, camCF:PointToWorldSpace(Vector3.new(1.2, -2.2, 0.6):Lerp(Vector3.new(0.7, -2, 0.6), adsBlend)), camCF)
	placeArm(leftArm, lHand, camCF:PointToWorldSpace(Vector3.new(-1.1, -2.2, -0.2):Lerp(Vector3.new(-0.8, -2, -0.3), adsBlend)), camCF)
end

return ViewModel
