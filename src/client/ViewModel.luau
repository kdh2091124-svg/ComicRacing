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
	swayAmount = 0.00008, -- 마우스 속도(픽셀/초) 1 당 흔들림 (라디안)
	swayMax = 0.16, -- 최대 흔들림 (라디안, 넓게)
	swayRoll = 0.9, -- 좌우로 돌 때 기울기 비율
	swayStiffness = 150, -- 기본 당기는 힘
	swayStiffBoost = 5, -- 많이 밀렸을수록 당기는 힘이 (1 + 밀린비율² × 이 값)배 → 멀면 확 빠르게
	swayDamping = 0.5, -- 0.4~0.6 = 살짝 튕기며 자리 잡음 (쫄깃), 1 = 출렁임 없음
	adsSpeed = 16,
	adsDistance = 1.1, -- 총에 "Aim" 표시가 있으면 조준할 때 그 점이 눈앞 이 거리에 정확히 옴
	raiseTime = 0.25,
	-- 총 안의 움직이는 파트 (이름으로 찾음, 파트 또는 그 이름의 Model/Folder). 회전 중심 = 파트의 피벗(PivotOffset)
	-- 거리 값은 "원본 모델 크기" 기준 → 총을 키우거나 줄인 만큼 같이 바뀜 (docs/WeaponRig_README 수치)
	boltTravel = 0.40, -- Bolt: 볼트 당길 때 뒤로 가는 거리
	boltLift = 60, -- Bolt: 손잡이 들어 올리는 각도 (총열 축 기준, 도)
	shotSlide = 0.22, -- Bolt: 연사 총은 쏠 때마다 뒤로 철컥 하는 거리
	magDrop = 1.2, -- Mag: 장전 때 탄창이 빠지는 거리
	coverOpen = 95, -- Cover(스나 볼트 창 덮개): 볼트 당길 때 열리는 각도
	coverBounce = 12, -- Cover: 열리고 닫힐 때 덜컹 튕기는 각도
	-- 리볼버: Cylinder(실린더), Hammer(공이치기), Trigger(방아쇠), CylinderHinge(실린더 여는 경첩 Attachment)
	cylinderStep = 60, -- 한 발마다 실린더 도는 각도 (6연발 = 60)
	cylinderSwing = 80, -- 장전 때 실린더가 왼쪽으로 열리는 각도
	hammerCock = 35, -- 쏠 때 공이치기가 젖혀졌다 떨어지는 각도
	triggerPull = 22, -- 쏠 때 방아쇠 당기는 각도
	-- 콜라캐논: Mag(콜라캔) + MagLid(뚜껑, 같이 움직임), MagLoad(포구의 캔 넣는 곳 Attachment)
	canLift = 0.65, -- 장전: 컵에서 위로 뽑는 거리
	canPush = 0.3, -- 장전: 포신 안으로 밀어 넣는 거리 (캔 길이 절반에 더해짐)
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

-- 스웨이 스프링: 목표에서 멀수록 당기는 힘이 커짐 (멀면 빠르게, 가까우면 부드럽게 + 살짝 튕김)
local function stepSway(s: Spring, target: number, dt: number, maxV: number, k0: number, boost: number, zeta: number)
	local steps = math.max(math.ceil(dt / (1 / 240)), 1)
	local h = dt / steps
	for _ = 1, steps do
		local diff = target - s.x
		local r = math.min(math.abs(diff) / maxV, 2)
		local k = k0 * (1 + r * r * boost)
		local c = 2 * zeta * math.sqrt(k)
		s.v += (k * diff - c * s.v) * h
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
local ejectLocal: CFrame? = nil -- 탄피 배출구 (앞쪽 -Z = 탄피 날아갈 방향)
local aimLocal: Vector3? = nil
local hingeLocal: CFrame? = nil -- 리볼버 실린더 경첩 (앞쪽 -Z = 축 방향)
local magLoadLocal: CFrame? = nil -- 콜라캐논 캔 넣는 곳 (앞쪽 -Z = 포신 안쪽)
local canHalf = 0.35 -- 콜라캔 길이 절반
local modelScale = 1 -- 원본 모델 대비 지금 크기 (거리 값에 곱함)
local hasGrip = false
type ArmSet = { hand: BasePart?, fore: BasePart?, single: BasePart? }
local rightArm: ArmSet = {}
local leftArm: ArmSet = {}
local raiseStart = 0
local lastKick = 0
-- 움직이는 파트: 손잡이 기준 원래 위치 + 회전 중심
type Moving = { parts: { { part: BasePart, rel: CFrame } }, pivot: Vector3 }
local magSet: Moving? = nil
local boltSet: Moving? = nil
local cylSet: Moving? = nil
local hammerSet: Moving? = nil
local coverSet: Moving? = nil
local triggerSet: Moving? = nil
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
	-- "Handle" 이 있으면 기준 파트 (오른손 위치, 앞쪽 -Z = 총구 방향)
	local handle = gun:FindFirstChild("Handle", true)
	local primary = (handle and handle:IsA("BasePart")) and handle or gun:FindFirstChildWhichIsA("BasePart", true)
	if not primary then
		gun:Destroy()
		return
	end
	gun.PrimaryPart = primary
	-- 방향: Handle 이 있으면 Handle 방향 그대로, 없으면 가장 긴 축 = 총열 + Muzzle 쪽이 앞
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
	local useHandle = handle ~= nil and handle:IsA("BasePart")
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
	modelScale = 1
	if math.abs(len - want) > 0.05 then
		local s = want / len
		gun:ScaleTo(gun:GetScale() * s)
		bbCF = gun:GetBoundingBox()
		len *= s
		modelScale = s
		mzPos = muzzleWorld()
	end
	gunLength = len
	if useHandle then
		local hcf = (handle :: BasePart).CFrame
		fwd, up = hcf.LookVector, hcf.UpVector
	end
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
	local gripPoint = point("Grip") or (useHandle and (handle :: BasePart).Position or nil) -- 오른손 (없으면 grip 비율 지점)
	hasGrip = gripPoint ~= nil
	local grip = CFrame.fromMatrix(gripPoint or (stock + fwd * len * VM.grip), fwd:Cross(up), up, -fwd)
	gripOffset = grip:Inverse() * gun:GetPivot()
	muzzleLocal = grip:PointToObjectSpace(mzPos or (bbCF.Position + fwd * len / 2))
	local function localOf(name: string): Vector3?
		local p = point(name)
		return p and grip:PointToObjectSpace(p) or nil
	end
	-- 방향까지 있는 표시점 (Attachment 의 앞쪽 -Z 가 의미 있는 것)
	local function frameOf(name: string): CFrame?
		local a = gun:FindFirstChild(name, true)
		if a and a:IsA("Attachment") then
			return grip:ToObjectSpace(a.WorldCFrame)
		elseif a and a:IsA("BasePart") then
			return grip:ToObjectSpace(a.CFrame)
		end
		return nil
	end
	foreLocal = localOf("Foregrip") -- 왼손 받치는 곳
	ejectLocal = frameOf("Eject") -- 탄피 배출구 (앞쪽 = 탄피 방향)
	aimLocal = localOf("Aim") -- 조준할 때 눈 앞에 오는 가늠자/조준기 위치
	hingeLocal = frameOf("CylinderHinge") -- 리볼버 실린더 여는 경첩
	magLoadLocal = frameOf("MagLoad") -- 콜라캐논 캔 넣는 곳
	-- 움직이는 파트 기억: 손잡이 기준 위치 + 회전 중심(파트 피벗 = 모델 만들 때 맞춘 실제 축/경첩)
	local function collect(names: { string }): Moving?
		local list = {}
		local pivot: Vector3? = nil
		for _, name in names do
			for _, d in gun:GetDescendants() do
				if d.Name == name and (d:IsA("BasePart") or d:IsA("Model") or d:IsA("Folder")) then
					if not pivot and (d:IsA("BasePart") or d:IsA("Model")) then
						pivot = grip:PointToObjectSpace((d :: any):GetPivot().Position)
					end
					local parts = d:IsA("BasePart") and { d } or d:GetDescendants()
					for _, p in parts do
						if p:IsA("BasePart") then
							table.insert(list, { part = p, rel = grip:ToObjectSpace(p.CFrame) })
						end
					end
				end
			end
		end
		if #list == 0 then
			return nil
		end
		if not pivot then
			local sum = Vector3.zero
			for _, e in list do
				sum += e.rel.Position
			end
			pivot = sum / #list
		end
		return { parts = list, pivot = pivot :: Vector3 }
	end
	magSet = collect({ "Mag", "MagLid" }) -- 콜라캐논 뚜껑(MagLid)도 캔과 같이 움직임
	boltSet = collect({ "Bolt" })
	cylSet = collect({ "Cylinder" })
	hammerSet = collect({ "Hammer" })
	coverSet = collect({ "Cover" })
	triggerSet = collect({ "Trigger" })
	cylAngle, cylTarget = 0, 0
	-- 콜라캔 길이 절반 (포신에 넣을 때)
	canHalf = 0.35 * modelScale
	if magSet then
		local hi = 0
		for _, e in magSet.parts do
			hi = math.max(hi, e.part.Size.Y / 2, e.part.Size.X / 2, e.part.Size.Z / 2)
		end
		canHalf = math.max(hi, 0.1)
	end

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

-- 탄피 배출구 위치 + 탄피 날아갈 방향 ("Eject" 의 앞쪽 -Z). 없으면 nil
function ViewModel.EjectPosition(): (Vector3?, Vector3?)
	local g = gunFrame()
	if not g or not ejectLocal then
		return nil, nil
	end
	local w = g * ejectLocal
	return w.Position, w.LookVector
end

-- 리볼버 실린더 가운데 (장전 때 탄피 쏟기용, "Cylinder" 없으면 nil)
function ViewModel.CylinderPosition(): Vector3?
	local g = gunFrame()
	return g and cylSet and g:PointToWorldSpace(cylSet.pivot) or nil
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
	stepSway(swayX, mouseVel.X * amt, dt, VM.swayMax, VM.swayStiffness, VM.swayStiffBoost, VM.swayDamping)
	stepSway(swayY, mouseVel.Y * amt, dt, VM.swayMax, VM.swayStiffness, VM.swayStiffBoost, VM.swayDamping)
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
	local S = modelScale
	-- 움직이는 파트 공통: 손잡이 기준 move 를 적용 (회전은 그 파트의 피벗을 중심으로, 축은 총 기준 X/Y/Z)
	local function apply(set: Moving, move: CFrame)
		for _, e in set.parts do
			e.part.CFrame = cf * move * e.rel
		end
	end
	local function about(p: Vector3, rot: CFrame): CFrame
		return CFrame.new(p) * rot * CFrame.new(-p)
	end
	-- 볼트: 들기(Z축 +60°) → 당기기(+Z 0.40) → 밀기 → 내리기. 연사 총은 쏠 때마다 +Z 0.22 철컥
	if boltSet then
		local slide = VM.boltTravel * S * pull + VM.shotSlide * S * math.clamp(1 - (t - lastKick) / 0.06, 0, 1)
		apply(boltSet, CFrame.new(0, 0, slide) * about(boltSet.pivot, CFrame.Angles(0, 0, math.rad(VM.boltLift) * lift)))
	end
	-- 스나 볼트 창 덮개: 당기는 순간 확 열리고(덜컹), 다 밀면 닫히며 한 번 더 덜컹
	if coverSet then
		local b = state.bolt and math.clamp(state.bolt / VM.boltAnimPortion, 0, 1) or 0
		local open = state.bolt and (smooth(0.15, 0.2, b) * (1 - smooth(0.62, 0.66, b))) or 0
		local w1 = math.clamp((b - 0.2) / 0.14, 0, 1) -- 열린 뒤 덜컹
		local w2 = math.clamp((b - 0.66) / 0.12, 0, 1) -- 닫힌 뒤 덜컹
		local bounce = 0
		if state.bolt then
			bounce = -VM.coverBounce * math.sin(w1 * math.pi * 2) * (1 - w1)
				+ VM.coverBounce * 0.5 * math.sin(w2 * math.pi * 2) * (1 - w2) * (w2 > 0 and 1 or 0)
		end
		apply(coverSet, about(coverSet.pivot, CFrame.Angles(0, 0, math.rad(VM.coverOpen * open + bounce))))
	end
	-- 리볼버 실린더: 쏠 때마다 Z축 60° 한 칸, 장전 때 CylinderHinge 축으로 80° 열림
	if cylSet then
		cylAngle += (cylTarget - cylAngle) * math.min(dt * 30, 1)
		local swing
		if hingeLocal then
			swing = hingeLocal * CFrame.Angles(0, 0, math.rad(VM.cylinderSwing) * leftDrop) * hingeLocal:Inverse()
		else
			swing = about(cylSet.pivot + Vector3.new(0, -0.12 * S, 0), CFrame.Angles(0, 0, math.rad(VM.cylinderSwing) * leftDrop))
		end
		apply(cylSet, swing * about(cylSet.pivot, CFrame.Angles(0, 0, cylAngle)))
	end
	-- 공이치기: 쏘는 순간 X축 +35° 젖혀졌다가 탁 떨어짐 (평소엔 내려가 있음)
	if hammerSet then
		local since = t - lastKick
		local cock = since < 0.03 and 1 or math.clamp(1 - (since - 0.03) / 0.04, 0, 1)
		apply(hammerSet, about(hammerSet.pivot, CFrame.Angles(math.rad(VM.hammerCock) * cock, 0, 0)))
	end
	-- 방아쇠: 쏠 때 X축 -22° 당겼다 놓음
	if triggerSet then
		local pullT = math.clamp(1 - (t - lastKick) / 0.12, 0, 1)
		apply(triggerSet, about(triggerSet.pivot, CFrame.Angles(math.rad(-VM.triggerPull) * pullT, 0, 0)))
	end
	-- 탄창/콜라캔
	local canPose: CFrame? = nil -- 콜라캔 장전 중 위치 (왼손이 따라감)
	if magSet and magLoadLocal and state.reload then
		-- 콜라캐논: 컵에서 뽑기(+Y) → 눕혀서 포구 앞으로 → 포신 안으로 밀기 → (안 보임) → 새 캔이 컵에 올라옴
		local r = state.reload
		local home = CFrame.new(magSet.pivot)
		local lifted = CFrame.new(0, VM.canLift * S, 0) * home
		local L = magLoadLocal
		local inward = L.LookVector
		local front = CFrame.fromMatrix(L.Position - inward * (canHalf + 0.15 * S), L.RightVector, inward)
		local inside = front + inward * (canHalf + 0.15 * S + VM.canPush * S + canHalf)
		local pose
		local hide = false
		if r < 0.08 then
			pose = home
		elseif r < 0.25 then
			pose = home:Lerp(lifted, smooth(0.08, 0.25, r))
		elseif r < 0.5 then
			pose = lifted:Lerp(front, smooth(0.25, 0.5, r))
		elseif r < 0.68 then
			pose = front:Lerp(inside, smooth(0.5, 0.68, r))
		elseif r < 0.85 then
			pose, hide = inside, true
		else
			pose = CFrame.new(0, -0.6 * S * (1 - smooth(0.85, 1, r)), 0) * home
		end
		apply(magSet, pose * home:Inverse())
		for _, e in magSet.parts do
			e.part.LocalTransparencyModifier = hide and 1 or 0
		end
		if r > 0.08 and r < 0.68 then
			canPose = pose
		end
		leftDrop = 0 -- 일반 탄창 동작/실린더 열기 대신
	elseif magSet and leftDrop > 0 then
		-- 일반 탄창: 장전 때 아래로 빠졌다(살짝 기울며) 다시 꽂힘
		apply(magSet, CFrame.new(-0.1 * leftDrop, -VM.magDrop * S * leftDrop, 0.2 * leftDrop)
			* about(magSet.pivot, CFrame.Angles(math.rad(-15) * leftDrop, 0, math.rad(20) * leftDrop)))
	end
	-- 손: 오른손 = 손잡이(볼트 땐 뒤로 당김, 손 위로), 왼손 = 총열 받침(장전 땐 아래로 탄창 빼기)
	-- Grip/Foregrip 표시가 있으면 손이 정확히 그 자리 (없으면 대략 총 아래)
	local rBase = hasGrip and Vector3.new(0, -0.1, 0) or Vector3.new(0.05, -0.25, 0.15)
	local rHand = cf:PointToWorldSpace(rBase + Vector3.new(0.25 * pull, 0.35 * pull, 0.55 * pull))
	local lBase = foreLocal and (foreLocal + Vector3.new(0, -0.12, 0)) or Vector3.new(-0.05, -0.3, -gunLength * (VM.foregrip - VM.grip))
	local lHand = cf:PointToWorldSpace(lBase + Vector3.new(0, -0.9 * leftDrop, 0.4 * leftDrop))
	if canPose then
		lHand = cf:PointToWorldSpace(canPose.Position + Vector3.new(0, -0.15, 0)) -- 콜라캔 장전: 왼손이 캔을 쥐고 옮김
	end
	local camCF = cam.CFrame
	placeArm(rightArm, rHand, camCF:PointToWorldSpace(Vector3.new(1.2, -2.2, 0.6):Lerp(Vector3.new(0.7, -2, 0.6), adsBlend)), camCF)
	placeArm(leftArm, lHand, camCF:PointToWorldSpace(Vector3.new(-1.1, -2.2, -0.2):Lerp(Vector3.new(-0.8, -2, -0.3), adsBlend)), camCF)
end

return ViewModel
