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
	hip = CFrame.new(1.05, -1.2, -2.5), -- 평소 위치 (카메라 기준 오른쪽, 아래, 앞)
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
	-- (빠르게 돌릴 때 끝에서 "탁 걸리고 휙 튕기던" 문제 → 양 줄이고, 끝 걸림/튕김 없이 부드럽게)
	swayAmount = 0.00004, -- 마우스 속도(픽셀/초) 1 당 흔들림 (라디안)
	swayMax = 0.2, -- 최대 흔들림 (넉넉히 → 보통은 닿지 않음)
	swayRoll = 0.7, -- 좌우로 돌 때 기울기 비율
	swayStiffness = 110, -- 당기는 힘
	swayStiffBoost = 0, -- 멀수록 더 세게 당기기 (0 = 끔, 일정하게)
	swayDamping = 0.95, -- 1 에 가까울수록 튕김 없이 스르륵
	adsStiffness = 260, -- 조준(우클릭) 들어가는 스프링: 클수록 빠름
	adsDamping = 0.72, -- 1 보다 작으면 들어가서 살짝 자리 잡음
	adsDistance = 1.9, -- (무기에 adsDistance 없을 때) "Aim" 점이 조준할 때 눈앞 이 거리에 옴
	aimFollow = 0.6, -- 총이 반동으로 튄 각도 중 총알/조준점이 따라가는 비율
	raiseTime = 0.32, -- 꺼낼 때 (끝에서 살짝 넘쳤다가 자리)
	-- 차 관성: 차가 가속/감속/회전하면 총이 반대로 살짝 밀렸다 돌아옴
	inertia = 0.0022, -- 카메라 가속도 1 당 밀리는 거리
	inertiaMax = 0.28,
	inertiaStiffness = 140,
	inertiaDamping = 0.55,
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
local adsDist = 1.9 -- 이 무기의 조준 거리 (WeaponConfig.adsDistance)
local hipCF = CFrame.new(1.05, -1.2, -2.5) -- 이 무기의 평소 위치 (WeaponConfig.vmHip)
local adsRollRad = 0 -- 조준할 때 꺾는 각도 (리볼버 45°)
local oneHanded = false -- 한손 파지 (왼손은 장전 때만)
local speedLoader: Model? = nil -- 리볼버 스피드로더 (장전 때만 보임)
local cylSpinV = 0 -- 리볼버 실린더 헛도는 속도 (라디안/초, 점점 줄어듦)
local cylLength, loaderLength = 0.4, 0.22 -- 실린더 길이, 스피드로더 길이 (스피드로더를 실린더 뒤에 딱 맞게)
local chamberRadius = 0.066 -- 실린더 축에서 약실까지 거리 (README 원본 값 × 크기)
local chamberRound: BasePart? = nil -- 스나 약실 탄환 (볼트 젖혔을 때만 보임)
local chamberLocal = CFrame.identity
local boltHandleLocal: Vector3? = nil -- 볼트 손잡이 끝 (오른손이 잡으러 가는 곳)
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
local adsS = newSpring()
local inX, inY, inZ = newSpring(), newSpring(), newSpring() -- 차 관성
local lastCamPos: Vector3? = nil -- nil 이면 첫 프레임 (관성 계산 건너뜀)
local lastCamVel = Vector3.zero -- 직전 프레임 내 몸 속도
local accSmooth = Vector3.zero
local prevReload, prevBolt = 0, 0 -- 장전/볼트 "탁" 순간 감지용

-- 끝에서 살짝 넘쳤다가 자리 잡는 곡선 (0→1)
local function backOut(u: number): number
	local c = 1.6
	u -= 1
	return 1 + (c + 1) * u * u * u + c * u * u
end

-- 점 p 를 중심으로 rot 만큼 돌리는 변환 (손잡이 기준 좌표)
local function aboutPoint(p: Vector3, rot: CFrame): CFrame
	return CFrame.new(p) * rot * CFrame.new(-p)
end

-- 내 화면 전용 물리 파편 폴더 (던진 탄창 등)
local function localFX(): Folder
	local f = workspace:FindFirstChild("LocalFX")
	if not f then
		f = Instance.new("Folder")
		f.Name = "LocalFX"
		f.Parent = workspace
	end
	return f :: Folder
end

-- 파트 묶음을 지금 모양 그대로 복제해서 물리로 날림 (던진 탄창, 버린 스피드로더). 3초 뒤 사라짐
local function throwParts(list: { { part: BasePart, world: CFrame } }, vel: Vector3, ang: Vector3)
	local m = Instance.new("Model")
	m.Name = "Thrown"
	local first: BasePart? = nil
	for _, e in list do
		local c = e.part:Clone()
		c.CFrame = e.world
		c.Anchored = false
		c.CanCollide = true
		c.CanQuery = false
		c.CanTouch = false
		c.Massless = false
		c.LocalTransparencyModifier = 0
		c.Parent = m
		if first then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = first, c
			w.Parent = c
		else
			first = c
		end
	end
	m.Parent = localFX()
	if first then
		first.AssemblyLinearVelocity = vel
		first.AssemblyAngularVelocity = ang
	end
	game:GetService("Debris"):AddItem(m, 3)
end

local function throwSet(set: Moving, gripCF: CFrame, vel: Vector3, ang: Vector3)
	local list = {}
	for _, e in set.parts do
		table.insert(list, { part = e.part, world = gripCF * e.rel })
	end
	throwParts(list, vel, ang)
end

local function throwModel(model: Model, vel: Vector3, ang: Vector3)
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, { part = d, world = d.CFrame })
		end
	end
	throwParts(list, vel, ang)
end

-- 총에 순간 충격 (장전 탁, 볼트 철컥): z = 뒤로, p = 총구 들림, r = 비틀림
local function jolt(z: number, p: number, r: number)
	kickZ.v += z * 60
	kickP.v += p * 60
	kickR.v += r * 60
end

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
	adsDist = def and def.adsDistance or VM.adsDistance
	hipCF = (def and def.vmHip) and CFrame.new(def.vmHip) or VM.hip
	adsRollRad = math.rad(def and def.adsRoll or 0)
	oneHanded = def ~= nil and def.oneHanded == true
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
	-- 볼트 손잡이 = 볼트 파트들 중 가장 오른쪽(+X) 끝
	boltHandleLocal = nil
	if boltSet then
		local bestX = -math.huge
		for _, e in boltSet.parts do
			local tip = e.rel.Position -- 파트 가운데
			local x = tip.X + math.max(e.part.Size.X, e.part.Size.Z) * 0.3
			if x > bestX then
				bestX = x
				boltHandleLocal = Vector3.new(x, tip.Y, tip.Z)
			end
		end
	end
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
	-- 볼트식(스나)이면 약실 탄환: 배출구 안쪽에 총열 방향으로 놓인 황동 탄 (볼트 젖혔을 때만 보임)
	chamberRound = nil
	cylSpinV = 0
	if def and def.boltTime and ejectLocal then
		local rnd = Instance.new("Part")
		rnd.Name = "ChamberRound"
		rnd.Shape = Enum.PartType.Cylinder
		rnd.Size = Vector3.new(0.55, 0.12, 0.12) * modelScale
		rnd.Color = Color3.fromRGB(225, 175, 70)
		rnd.Material = Enum.Material.Metal
		setupPart(rnd)
		rnd.Parent = m
		-- 배출구 위치에서 총 안쪽으로 살짝, 원통 축(X)을 총열(Z) 방향으로
		chamberLocal = CFrame.new(ejectLocal.Position + Vector3.new(-0.04 * modelScale, -0.02 * modelScale, -0.05 * modelScale))
			* CFrame.Angles(0, math.pi / 2, 0)
		chamberRound = rnd
	end
	-- 리볼버면 스피드로더 (검은 링 + 황동 탄 6발) 만들어 둠 (장전 때만 보임)
	speedLoader = nil
	if cylSet then
		local sl = Instance.new("Model")
		sl.Name = "SpeedLoader"
		local S = modelScale
		-- 실린더 크기 재기 (손잡이 기준 Z = 실린더 축): 길이, 지름
		local zMin, zMax, rMax = math.huge, -math.huge, 0
		for _, e in cylSet.parts do
			local rel, sz = e.rel, e.part.Size
			local ex = Vector3.new(
				math.abs(rel.RightVector.X) * sz.X + math.abs(rel.UpVector.X) * sz.Y + math.abs(rel.LookVector.X) * sz.Z,
				math.abs(rel.RightVector.Y) * sz.X + math.abs(rel.UpVector.Y) * sz.Y + math.abs(rel.LookVector.Y) * sz.Z,
				math.abs(rel.RightVector.Z) * sz.X + math.abs(rel.UpVector.Z) * sz.Y + math.abs(rel.LookVector.Z) * sz.Z
			) / 2
			local p = rel.Position - cylSet.pivot
			zMin = math.min(zMin, p.Z - ex.Z)
			zMax = math.max(zMax, p.Z + ex.Z)
			rMax = math.max(rMax, math.abs(p.X) + ex.X, math.abs(p.Y) + ex.Y)
		end
		cylLength = math.clamp(zMax - zMin, 0.1 * S, 1.2 * S)
		local diam = math.clamp(rMax * 2, 0.2 * S, 1.0 * S)
		chamberRadius = math.min(0.066 * S, diam * 0.32) -- README: 축에서 0.066 (원본 크기 기준)
		if chamberRadius < diam * 0.18 then
			chamberRadius = diam * 0.3 -- 모델이 README 와 다르면 지름 기준
		end
		loaderLength = cylLength * 0.35
		local roundDiam = diam * 0.2
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(loaderLength, diam * 0.92, diam * 0.92)
		ring.Color = Color3.fromRGB(30, 30, 34)
		ring.Material = Enum.Material.Metal
		ring.CFrame = CFrame.Angles(0, math.pi / 2, 0) -- 원통 축 = Z (총열 방향)
		setupPart(ring)
		ring.Parent = sl
		for i = 0, 5 do
			local a = i * math.pi / 3 + math.pi / 2 -- 맨 위 약실부터 (README: 맨 위가 총열과 일직선)
			local round = Instance.new("Part")
			round.Shape = Enum.PartType.Cylinder
			round.Size = Vector3.new(cylLength * 0.9, roundDiam, roundDiam)
			round.Color = Color3.fromRGB(225, 175, 70)
			round.Material = Enum.Material.Metal
			-- 탄은 스피드로더 앞쪽(-Z)으로 튀어나와 약실에 들어감
			round.CFrame = CFrame.new(math.cos(a) * chamberRadius, math.sin(a) * chamberRadius, -(loaderLength + cylLength * 0.9) / 2)
				* CFrame.Angles(0, math.pi / 2, 0)
			setupPart(round)
			round.Parent = sl
		end
		sl.WorldPivot = CFrame.identity -- 기준 = 링 가운데, 축 = Z
		sl.Parent = m
		speedLoader = sl
	end
	m.Parent = workspace.CurrentCamera
	current = m
	raiseStart = os.clock()
	kickZ, kickP, kickR = newSpring(), newSpring(), newSpring()
	adsBlend = 0
	adsS = newSpring()
	inX, inY, inZ = newSpring(), newSpring(), newSpring()
	lastCamPos, lastCamVel, accSmooth = nil, Vector3.zero, Vector3.zero
	prevReload, prevBolt = 0, 0
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

-- 지금 총이 반동으로 튄 각도 (라디안): 총알/조준점이 이만큼 같이 따라감
--   pitch = 총구 들림 (위 +), yaw = 비틀림 → 좌우
function ViewModel.AimKick(): (number, number)
	if not current or not current.Parent then
		return 0, 0
	end
	local p = math.clamp(kickP.x, -0.2, 0.5) * VM.aimFollow
	local y = math.clamp(kickR.x, -0.3, 0.3) * VM.aimFollow * 0.5
	return p, y
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
	-- 조준: 스프링으로 착 들어가서 살짝 자리 잡음
	stepSpring(adsS, VM.adsStiffness, VM.adsDamping, dt, state.ads and 1 or 0)
	adsBlend = math.clamp(adsS.x, -0.05, 1.08)
	-- 차 관성: 내 몸(=탄 차) 가속도의 반대로 총이 밀림. 화면 흔들림에 안 흔들리게 몸 속도로 계산
	local root = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local velW = (root and root:IsA("BasePart")) and root.AssemblyLinearVelocity or Vector3.zero
	if lastCamPos and dt > 0 then
		local rawAcc = (velW - lastCamVel) / dt
		lastCamVel = velW
		accSmooth = accSmooth:Lerp(rawAcc, math.min(dt * 12, 1)) -- 물리 떨림 거르기
		local acc = cam.CFrame:VectorToObjectSpace(accSmooth)
		local k = VM.inertia * (1 - adsBlend * 0.6)
		local function tgt(a: number): number
			return math.clamp(-a * k, -VM.inertiaMax, VM.inertiaMax)
		end
		stepSpring(inX, VM.inertiaStiffness, VM.inertiaDamping, dt, tgt(acc.X))
		stepSpring(inY, VM.inertiaStiffness, VM.inertiaDamping, dt, tgt(acc.Y))
		stepSpring(inZ, VM.inertiaStiffness, VM.inertiaDamping, dt, tgt(acc.Z))
	end
	lastCamPos = velW -- (첫 프레임 표시용)
	lastCamVel = velW
	-- 스프링들
	local md: Vector2 = state.mouseDelta
	-- 화면을 돌린 반대쪽으로 팔이 살짝 늦게 따라옴
	-- 마우스 "속도"를 부드럽게 걸러서 목표로 삼음 (프레임마다 튀는 값을 그대로 넣으면 탁탁 걸림)
	local inst = dt > 0 and md / dt or Vector2.zero
	mouseVel = mouseVel:Lerp(inst, math.min(dt * 10, 1))
	local amt = VM.swayAmount * (1 - adsBlend * 0.6)
	stepSway(swayX, mouseVel.X * amt, dt, VM.swayMax, VM.swayStiffness, VM.swayStiffBoost, VM.swayDamping)
	stepSway(swayY, mouseVel.Y * amt, dt, VM.swayMax, VM.swayStiffness, VM.swayStiffBoost, VM.swayDamping)
	stepSpring(kickZ, VM.kickStiffness, VM.kickDamping, dt)
	stepSpring(kickP, VM.kickStiffness, VM.kickDamping, dt)
	stepSpring(kickR, VM.kickStiffness * 0.8, VM.kickDamping, dt)
	local t = os.clock()
	local breathe = math.sin(t * 1.7) * 0.01 * (1 - adsBlend * 0.8)
	local raise = backOut(math.clamp((t - raiseStart) / VM.raiseTime, 0, 1)) -- 꺼낼 때 살짝 넘쳤다 자리

	-- 조준 위치: "Aim" 표시가 있으면 그 점이 화면 정중앙(눈앞)에 오게, 없으면 VM.ads
	local adsCF = aimLocal and CFrame.new(-aimLocal.X, -aimLocal.Y, -adsDist - aimLocal.Z) or VM.ads
	-- 조준할 때 꺾기 (리볼버 45° 갱스터): 가늠쇠 점을 중심으로 돌려서 조준은 그대로
	if adsRollRad ~= 0 then
		adsCF *= aboutPoint(aimLocal or Vector3.zero, CFrame.Angles(0, 0, adsRollRad))
	end
	local base = hipCF:Lerp(adsCF, adsBlend)
	-- 어깨를 중심으로 팔째 흔들림 (조준 중엔 어깨 대신 거의 눈앞 중심)
	local sx = soft(swayX.x, VM.swayMax)
	local sy = soft(swayY.x, VM.swayMax)
	local pivot = CFrame.new(VM.shoulderPivot:Lerp(Vector3.new(0, -0.6, 0.4), adsBlend))
	local swayCF = pivot * CFrame.Angles(sy, sx, sx * VM.swayRoll) * pivot:Inverse()
	local inertiaCF = CFrame.new(inX.x, inY.x, inZ.x) * CFrame.Angles(inY.x * 0.25, 0, -inX.x * 0.6)
	local cf = cam.CFrame * inertiaCF * swayCF * base
		* CFrame.new(0, -0.9 * (1 - raise) + breathe, 0) * CFrame.Angles(math.rad(-35) * (1 - raise), math.rad(8) * (1 - raise), 0)
		* CFrame.new(0, 0, math.clamp(kickZ.x, -0.2, 0.6)) * CFrame.Angles(math.clamp(kickP.x, -0.2, 0.5), 0, kickR.x)

	-- 장전: 기울이기 → 탄창 빼기 → 꽂기 → 탁 → 복귀
	local leftDrop = 0
	local r = state.reload or 0
	local S0 = modelScale
	-- 장전 방식: 콜라캔(MagLoad) / 리볼버(Cylinder) / 스나(Mag + 볼트식) / AK(Mag) / 기본
	local style = magLoadLocal and "cola" or (cylSet and "revolver")
		or (magSet and (state.boltAction and "sniper" or "ak")) or "basic"
	local magMove: CFrame? = nil -- 새 탄창 위치 (손잡이 기준 이동)
	local magHidden = false
	local loaderPose: CFrame? = nil -- 스피드로더 위치 (손잡이 기준)
	local cylOpen = 0 -- 리볼버 실린더 열림 (0~1)
	local leftTarget: Vector3? = nil -- 왼손을 여기로 (손잡이 기준)
	local rightTarget: Vector3? = nil -- 오른손을 여기로 (손잡이 기준, 콜라캔 옮길 때)
	local showLeft = not oneHanded
	local rPull, rLift = 0, 0 -- 장전 중 볼트/노리쇠 당김, 손잡이 들기
	local chamberShow = false -- 스나 약실 탄환 보이기
	local function crossed(x: number): boolean
		return prevReload < x and r >= x
	end
	local function bump(a: number, b: number, c: number, d: number): number
		return smooth(a, b, r) * (1 - smooth(c, d, r))
	end
	-- 새 탄창이 아래에서 올라와 끼워지는 이동 (off 1 = 아래 멀리, 0 = 제자리)
	local function magFrom(off: number, push: number, side: number): CFrame
		return CFrame.new(side * S0 * off, (-1.8 * off - 0.3 * (1 - push)) * S0, 0.3 * S0 * off)
			* aboutPoint((magSet :: Moving).pivot, CFrame.Angles(math.rad(-35) * off, 0, math.rad(25) * off))
	end

	if state.reload and style == "ak" then
		-- 1) 반대로 살짝 준비(0~0.06) → "/" 방향(총 위쪽이 오른쪽)으로 탁 쳐서 탄창 날리기(0.09)
		-- 2) 부드럽게 쏘는 자세(I)로 복귀(0.1~0.26)
		local wind = smooth(0, 0.06, r) * (1 - smooth(0.06, 0.085, r))
		local snap = smooth(0.06, 0.095, r) * (1 - smooth(0.11, 0.26, r))
		cf *= CFrame.Angles(0, 0, math.rad(10) * wind)
		cf *= CFrame.new(0.1 * snap, 0.04 * snap, 0) * CFrame.Angles(math.rad(-4) * snap, math.rad(-6) * snap, math.rad(-55) * snap)
		if crossed(0.09) and magSet then
			-- 총이 오른쪽으로 꺾이면서 아래쪽 탄창은 왼쪽 아래로 빙글빙글 날아감
			throwSet(magSet, cf, -cam.CFrame.RightVector * 22 - cam.CFrame.UpVector * 3 + cam.CFrame.LookVector * 3, cam.CFrame.LookVector * 22)
			jolt(0.02, -0.04, -0.14)
		end
		if r >= 0.09 and r < 0.24 then
			magHidden = true
		end
		-- 3) 아래서 새 탄창 (0.24~0.42) → 탁 (0.44) → 확인으로 한 번 더 강하게 탁! (0.5)
		if r >= 0.24 and r < 0.54 and magSet then
			magMove = magFrom(1 - smooth(0.24, 0.41, r), smooth(0.41, 0.44, r), -0.4)
			local slap = bump(0.46, 0.48, 0.49, 0.5) -- 손을 살짝 내렸다가 위로 탁
			leftTarget = (magMove * CFrame.new(magSet.pivot)).Position + Vector3.new(0, (-0.25 - 0.3 * slap) * S0, 0.05)
		end
		if crossed(0.44) then
			jolt(0.08, 0.06, -0.03)
		end
		if crossed(0.5) then
			jolt(0.2, 0.18, -0.08) -- 강하게 탁!
		end
		-- 4) 왼쪽으로 돌려서 왼손이 장전 손잡이 찰칵 (0.56~0.8) → 부드럽게 복귀
		local roll = smooth(0.54, 0.64, r) * (1 - smooth(0.8, 0.94, r))
		cf *= CFrame.new(-0.1 * roll, 0.05 * roll, 0) * CFrame.Angles(math.rad(-4) * roll, math.rad(-12) * roll, math.rad(38) * roll)
		rPull = smooth(0.66, 0.71, r) * (1 - smooth(0.73, 0.76, r))
		if crossed(0.71) then
			jolt(0.07, 0.03, 0.07) -- 찰칵 (당김)
		end
		if crossed(0.76) then
			jolt(-0.05, -0.03, -0.05) -- 철컥 (놓음)
		end
		if r >= 0.58 and r < 0.82 and boltSet then
			leftTarget = boltSet.pivot + Vector3.new(0.05, 0.12, (0.12 + VM.boltTravel * rPull) * S0)
		end
	elseif state.reload and style == "sniper" then
		-- 탄창 쪽이 보이게 살짝 기울임
		local tilt = smooth(0, 0.08, r) * (1 - smooth(0.42, 0.5, r))
		cf *= CFrame.new(0, -0.1 * tilt, 0) * CFrame.Angles(math.rad(-6) * tilt, math.rad(12) * tilt, math.rad(-22) * tilt)
		-- 1) 왼손이 탄창 버튼 딱 → 탄창이 빠져 떨어짐
		if r < 0.12 and magSet then
			leftTarget = magSet.pivot + Vector3.new(0, -0.1 * S0, -0.15 * S0)
		end
		if crossed(0.07) and magSet then
			throwSet(magSet, cf, -Vector3.yAxis * 4 - cam.CFrame.RightVector * 2, Vector3.new(0, 0, 2))
			jolt(0.02, -0.03, 0.04)
		end
		if r >= 0.07 and r < 0.16 then
			magHidden = true
		end
		-- 2) 새 탄창 꽂기 (0.31) → 한 번 탁 쳐서 정확히 (0.39)
		if r >= 0.16 and r < 0.44 and magSet then
			local seat = smooth(0.36, 0.39, r)
			magMove = magFrom(1 - smooth(0.16, 0.29, r), smooth(0.29, 0.32, r) * (0.8 + 0.2 * seat), -0.4)
			local tap = bump(0.34, 0.36, 0.38, 0.4)
			leftTarget = (magMove * CFrame.new(magSet.pivot)).Position + Vector3.new(0, (-0.22 - 0.25 * tap) * S0, 0)
		end
		if crossed(0.32) then
			jolt(0.08, 0.05, 0)
		end
		if crossed(0.39) then
			jolt(0.16, 0.12, -0.05)
		end
		-- 3) 볼트 강하게 촥 (0.5~0.57) → 잠깐 대기 (약실 탄환 보임) → 한 번에 탁 놓기 (0.74~0.77)
		local roll = smooth(0.46, 0.52, r) * (1 - smooth(0.8, 0.9, r))
		cf *= CFrame.Angles(math.rad(4) * roll, 0, math.rad(20) * roll) * CFrame.new(-0.05 * roll, -0.05 * roll, 0)
		rLift = smooth(0.5, 0.53, r) * (1 - smooth(0.76, 0.785, r))
		rPull = smooth(0.53, 0.57, r) * (1 - smooth(0.74, 0.765, r))
		chamberShow = rPull > 0.6
		if crossed(0.57) then
			jolt(0.17, 0.06, -0.1) -- 촥
		end
		if crossed(0.77) then
			jolt(-0.15, -0.08, 0.08) -- 탁
		end
	elseif state.reload and style == "revolver" then
		-- 1) "/" 반대 방향(총 위쪽이 왼쪽)으로 탁 쳐서 실린더 열고 휙 돌림 (0~0.08)
		local snapOpen = smooth(0, 0.05, r) * (1 - smooth(0.08, 0.16, r))
		cf *= CFrame.new(-0.08 * snapOpen, 0, 0) * CFrame.Angles(math.rad(-6) * snapOpen, 0, math.rad(42) * snapOpen)
		cylOpen = backOut(math.clamp((r - 0.03) / 0.05, 0, 1)) * (1 - smooth(0.67, 0.7, r))
		if crossed(0.04) then
			jolt(0.02, -0.06, 0.18)
			cylSpinV = 18 -- 열리면서 촤라락 돎
		end
		-- 2) 천천히 들어 올림 (0.14~0.34) → 탄피가 촤르르 하나씩 빠짐 (WeaponClient), 올린 채 유지
		local up = smooth(0.14, 0.34, r) * (1 - smooth(0.6, 0.68, r))
		cf *= CFrame.new(-0.15 * up, 0.3 * up, 0.25 * up) * CFrame.Angles(math.rad(75) * up, math.rad(-12) * up, math.rad(-10) * up)
		-- 3) 올린 채로 실린더 크기에 맞는 스피드로더를 콕 (0.38~0.53) → 왼쪽으로 빼서 버리기 (0.56~0.62)
		if r >= 0.38 and r < 0.62 and cylSet then
			local come = smooth(0.38, 0.5, r)
			local push = smooth(0.5, 0.53, r)
			local leave = smooth(0.55, 0.61, r)
			local swing = hingeLocal and (hingeLocal * CFrame.Angles(0, 0, math.rad(VM.cylinderSwing) * cylOpen) * hingeLocal:Inverse())
				or aboutPoint(cylSet.pivot + Vector3.new(0, -0.12 * S0, 0), CFrame.Angles(0, 0, math.rad(VM.cylinderSwing) * cylOpen))
			local depth = cylLength / 2 + loaderLength / 2
			local rear = swing * CFrame.new(cylSet.pivot + Vector3.new(0, 0, depth + 0.35 * S0 * (1 - push)))
			loaderPose = rear * CFrame.new(-0.5 * S0 * (1 - come) - 0.9 * S0 * leave, -0.2 * S0 * (1 - come), 1.0 * S0 * (1 - come) + 0.3 * S0 * leave)
			leftTarget = loaderPose.Position + Vector3.new(0, -0.06, 0.15 * S0)
			showLeft = true
		end
		if crossed(0.53) then
			jolt(0.12, -0.04, 0) -- 콕
		end
		if crossed(0.61) and speedLoader then
			throwModel(speedLoader, -cam.CFrame.RightVector * 7 - Vector3.yAxis * 4, Vector3.new(3, 5, 0)) -- 버림
		end
		-- 4) 내리면서 "/" 방향(총 위쪽이 오른쪽)으로 탁 쳐서 실린더 닫기 (0.68) → 살짝 돎 → 제자리
		local snapClose = smooth(0.64, 0.69, r) * (1 - smooth(0.72, 0.85, r))
		cf *= CFrame.Angles(0, math.rad(-6) * snapClose, math.rad(-48) * snapClose)
		if crossed(0.68) then
			jolt(0.1, 0.05, -0.24)
			cylSpinV = 9
		end
	elseif state.reload and style == "cola" then
		-- 내려서 포구를 위로 + 왼손이 총열을 잡음 → 오른손이 콜라 꺼내 위에서 쑤욱 → 고쳐 잡기
		local low = smooth(0, 0.14, r) * (1 - smooth(0.82, 0.94, r))
		cf *= CFrame.new(-0.2 * low, -0.55 * low, 0.3 * low) * CFrame.Angles(math.rad(62) * low, math.rad(-10) * low, math.rad(-8) * low)
		showLeft = true
		if low > 0.05 then
			local barrel = magLoadLocal and magLoadLocal.Position * 0.6 or Vector3.new(0, 0, -gunLength * 0.4)
			leftTarget = barrel + Vector3.new(0, -0.12 * S0, 0)
		end
		if crossed(0.74) then
			jolt(0.08, -0.04, 0) -- 쑤욱 끝
		end
		if crossed(0.92) then
			jolt(0.06, 0.05, 0.05) -- 고쳐 잡기
		end
	elseif state.reload then
		-- 기본: 비틀며 들기 → 제자리
		local tilt = math.min(backOut(math.clamp(r / 0.14, 0, 1)), 1 - backOut(math.clamp((r - 0.86) / 0.14, 0, 1)))
		cf *= CFrame.new(0.08 * tilt, -0.2 * tilt, 0.05 * tilt) * CFrame.Angles(math.rad(-8) * tilt, math.rad(18) * tilt, math.rad(38) * tilt)
	end
	prevReload = r
	-- 볼트: 굴리기 → 당기기 → 밀기 → 복귀 (boltAnimPortion 안에 빠르게 끝냄)
	local pull, lift = 0, 0
	-- 볼트 동작 진행도 b (0~1): 쏜 뒤 볼트(스나) 또는 장전 끝의 노리쇠 후퇴→전진(AR/스나)
	local boltB: number? = nil
	if state.bolt then
		boltB = math.clamp(state.bolt / VM.boltAnimPortion, 0, 1)
	end
	local bNow = boltB or 0
	-- 볼트 당길 때 철컥, 밀어 넣을 때 탁 (스프링 충격)
	if boltB then
		if prevBolt < 0.2 and bNow >= 0.2 then
			jolt(0.12, 0.05, -0.08)
		end
		if prevBolt < 0.6 and bNow >= 0.6 then
			jolt(-0.1, -0.06, 0.06)
		end
	end
	prevBolt = bNow
	if boltB then
		local b = boltB
		-- 볼트식(스나)은 손잡이 들기/내리기 + 총을 크게 굴림, AR 은 그냥 당겼다 놓기 + 살짝 굴림
		local rollAmt = state.boltAction and 24 or 12
		local roll = smooth(0, 0.15, b) * (1 - smooth(0.7, 0.9, b))
		lift = state.boltAction and smooth(0.05, 0.15, b) * (1 - smooth(0.62, 0.72, b)) or 0
		pull = smooth(0.15, 0.35, b) * (1 - smooth(0.45, 0.62, b))
		local thud = smooth(0.58, 0.63, b) * (1 - smooth(0.63, 0.75, b)) -- 밀어 넣을 때 탁
		-- 총을 왼쪽으로 굴려서 오른쪽 볼트가 보이게 (예전 반대 방향)
		cf *= CFrame.Angles(math.rad(4) * roll, 0, math.rad(rollAmt) * roll) * CFrame.new(-0.05 * roll, -0.06 * roll, 0)
		cf *= CFrame.new(0, 0, -0.05 * thud) * CFrame.Angles(math.rad(-3) * thud, 0, 0)
	end
	-- 장전 중 볼트/노리쇠 (위 장전 동작에서 정함)
	pull = math.max(pull, rPull)
	lift = math.max(lift, rLift)

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
	local boltMoveCF = CFrame.identity
	if boltSet then
		local slide = VM.boltTravel * S * pull + VM.shotSlide * S * math.clamp(1 - (t - lastKick) / 0.06, 0, 1)
		boltMoveCF = CFrame.new(0, 0, slide) * about(boltSet.pivot, CFrame.Angles(0, 0, math.rad(VM.boltLift) * lift))
		apply(boltSet, boltMoveCF)
	end
	-- 스나 볼트 창 덮개: 당기는 순간 확 열리고(덜컹), 다 밀면 닫히며 한 번 더 덜컹
	if coverSet then
		local b = boltB or 0
		local open = boltB and (smooth(0.15, 0.2, b) * (1 - smooth(0.62, 0.66, b))) or 0
		local w1 = math.clamp((b - 0.2) / 0.14, 0, 1) -- 열린 뒤 덜컹
		local w2 = math.clamp((b - 0.66) / 0.12, 0, 1) -- 닫힌 뒤 덜컹
		local bounce = 0
		if boltB then
			bounce = -VM.coverBounce * math.sin(w1 * math.pi * 2) * (1 - w1)
				+ VM.coverBounce * 0.5 * math.sin(w2 * math.pi * 2) * (1 - w2) * (w2 > 0 and 1 or 0)
		end
		if rPull > 0 then
			open = math.max(open, math.min(rPull * 3, 1)) -- 장전 중 볼트 당기면 덮개도 열림
		end
		apply(coverSet, about(coverSet.pivot, CFrame.Angles(0, 0, math.rad(VM.coverOpen * open + bounce))))
	end
	-- 스나 약실 탄환: 볼트가 뒤로 젖혀져 있을 때 배출구 안에 보임
	if chamberRound then
		chamberRound.CFrame = cf * chamberLocal
		chamberRound.LocalTransparencyModifier = (chamberShow or (state.bolt and pull > 0.6)) and 0 or 1
	end
	-- 리볼버 실린더: 쏠 때마다 Z축 60° 한 칸, 장전 때 CylinderHinge 축으로 80° 열림, 열고 닫을 때 헛돎
	if cylSet then
		cylTarget += cylSpinV * dt
		cylSpinV -= cylSpinV * math.min(dt * 3, 1)
		cylAngle += (cylTarget - cylAngle) * math.min(dt * 30, 1)
		local swing
		if hingeLocal then
			swing = hingeLocal * CFrame.Angles(0, 0, math.rad(VM.cylinderSwing) * cylOpen) * hingeLocal:Inverse()
		else
			swing = about(cylSet.pivot + Vector3.new(0, -0.12 * S, 0), CFrame.Angles(0, 0, math.rad(VM.cylinderSwing) * cylOpen))
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
	local canPose: CFrame? = nil -- 콜라캔 장전 중 위치 (오른손이 따라감)
	if magSet and magLoadLocal and state.reload then
		-- 콜라캐논: 오른손이 컵에서 뽑기(+Y) → 포구 위로 (포구가 하늘을 봄) → 위에서 아래로 쑤욱 → (안 보임) → 새 캔이 컵에 올라옴
		local home = CFrame.new(magSet.pivot)
		local lifted = CFrame.new(0, VM.canLift * S, 0) * home
		local L = magLoadLocal
		local inward = L.LookVector
		local front = CFrame.fromMatrix(L.Position - inward * (canHalf + 0.3 * S), L.RightVector, inward)
		local inside = front + inward * (canHalf + 0.3 * S + VM.canPush * S + canHalf)
		local pose
		local hide = false
		if r < 0.16 then
			pose = home
		elseif r < 0.32 then
			pose = home:Lerp(lifted, smooth(0.16, 0.32, r))
		elseif r < 0.52 then
			pose = lifted:Lerp(front, smooth(0.32, 0.52, r))
		elseif r < 0.74 then
			pose = front:Lerp(inside, smooth(0.52, 0.74, r)) -- 쑤욱
		elseif r < 0.86 then
			pose, hide = inside, true
		else
			pose = CFrame.new(0, -0.6 * S * (1 - smooth(0.86, 1, r)), 0) * home
		end
		apply(magSet, pose * home:Inverse())
		for _, e in magSet.parts do
			e.part.LocalTransparencyModifier = hide and 1 or 0
		end
		if r > 0.1 and r < 0.76 then
			canPose = pose
		end
		leftDrop = 0
	elseif magSet and (magHidden or magMove) then
		-- 탄창 던지기 장전: 던진 직후엔 총에 탄창 없음, 그다음 새 탄창이 왼손과 함께 올라와 끼워짐
		if magMove then
			apply(magSet, magMove)
		end
		for _, e in magSet.parts do
			e.part.LocalTransparencyModifier = magHidden and 1 or 0
		end
	elseif magSet and leftDrop > 0 then
		-- 일반 탄창: 장전 때 아래로 빠졌다(살짝 기울며) 다시 꽂힘
		apply(magSet, CFrame.new(-0.1 * leftDrop, -VM.magDrop * S * leftDrop, 0.2 * leftDrop)
			* about(magSet.pivot, CFrame.Angles(math.rad(-15) * leftDrop, 0, math.rad(20) * leftDrop)))
	end
	-- 리볼버 스피드로더: 장전 중에만 보임
	if speedLoader then
		if loaderPose then
			speedLoader:PivotTo(cf * loaderPose)
		end
		for _, d in speedLoader:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = loaderPose and 0 or 1
			end
		end
	end
	-- 손: 오른손 = 손잡이(볼트 땐 뒤로 당김, 손 위로), 왼손 = 총열 받침(장전 땐 아래로 탄창 빼기)
	-- Grip/Foregrip 표시가 있으면 손이 정확히 그 자리 (없으면 대략 총 아래)
	local rBase = hasGrip and Vector3.new(0, -0.1, 0) or Vector3.new(0.05, -0.25, 0.15)
	-- 볼트식(스나)은 오른손이 볼트를 당김, AK 는 왼손이 당기니 오른손은 손잡이 그대로
	local rPullHand = state.boltAction and pull or 0
	local rHand = cf:PointToWorldSpace(rBase + Vector3.new(0.25 * rPullHand, 0.35 * rPullHand, 0.55 * rPullHand))
	local lBase = foreLocal and (foreLocal + Vector3.new(0, -0.12, 0)) or Vector3.new(-0.05, -0.3, -gunLength * (VM.foregrip - VM.grip))
	local lHand = cf:PointToWorldSpace(lBase + Vector3.new(0, -0.9 * leftDrop, 0.4 * leftDrop))
	if canPose then
		rightTarget = canPose.Position + Vector3.new(0.12, -0.1, 0) -- 콜라캔 장전: 오른손이 캔을 쥐고 옮김
	end
	-- 볼트식(스나): 오른손이 손잡이에서 볼트 손잡이까지 실제로 뻗어서 잡고 같이 움직임
	if state.boltAction and boltHandleLocal and not rightTarget then
		local reach = 0
		if state.bolt then
			reach = smooth(0, 0.12, bNow) * (1 - smooth(0.8, 0.95, bNow))
		elseif style == "sniper" then
			reach = smooth(0.44, 0.5, r) * (1 - smooth(0.8, 0.86, r))
		end
		if reach > 0 then
			local handle = boltMoveCF * boltHandleLocal + Vector3.new(0, -0.04 * S, 0.06 * S)
			rightTarget = rBase:Lerp(handle, reach)
		end
	end
	if rightTarget then
		rHand = cf:PointToWorldSpace(rightTarget)
	end
	if leftTarget then
		lHand = cf:PointToWorldSpace(leftTarget) -- 새 탄창 / 스피드로더를 쥔 왼손
	end
	local camCF = cam.CFrame
	-- 한손 파지(리볼버): 오른팔은 더 쭉 뻗음
	local rShoulder = oneHanded and Vector3.new(0.6, -1.9, 0.5) or Vector3.new(1.2, -2.2, 0.6)
	placeArm(rightArm, rHand, camCF:PointToWorldSpace(rShoulder:Lerp(Vector3.new(0.5, -1.8, 0.6), adsBlend)), camCF)
	if showLeft then
		placeArm(leftArm, lHand, camCF:PointToWorldSpace(Vector3.new(-1.1, -2.2, -0.2):Lerp(Vector3.new(-0.8, -2, -0.3), adsBlend)), camCF)
	else
		for _, p in { leftArm.single, leftArm.fore, leftArm.hand } do
			if p then
				p.LocalTransparencyModifier = 1 -- 한손 파지: 왼손 안 보임
			end
		end
	end
end

return ViewModel
