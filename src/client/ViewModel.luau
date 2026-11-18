-- 1인칭 내 무기 (내 화면 전용): 총 + 팔이 화면 오른쪽 아래에 보이고 움직임
--   들어 올리기, 마우스 따라 흔들림(스웨이), 숨쉬기, 쏠 때 반동, 볼트 당기기, 장전, 우클릭 조준(가운데로)
-- 총 모델: ReplicatedStorage.WeaponModels.<id> (Tool/Model). 가장 긴 쪽 = 총열, "Muzzle" 쪽이 앞. 없으면 상자 총
-- 크기/위치는 VM 표에서 조절

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ViewModel = {}

local VM = {
	hip = CFrame.new(0.95, -0.85, -1.9), -- 평소 위치 (카메라 기준 오른쪽, 아래, 앞)
	ads = CFrame.new(0, -0.42, -1.45), -- 우클릭 조준 위치 (가운데)
	maxLength = 3.6, -- 총이 이보다 길면 이 길이로 줄임 (화면을 너무 가리지 않게)
	grip = 0.35, -- 총 길이 중 오른손이 쥐는 곳 (0 = 개머리판 끝)
	swayAmount = 0.0018, -- 마우스 움직임에 따라 총이 늦게 따라오는 정도
	swayReturn = 9,
	kickBack = 0.28, -- 쏠 때 뒤로 밀리는 거리
	kickUp = 7, -- 쏠 때 총구가 들리는 각도 (도)
	kickReturn = 14,
	adsSpeed = 12,
	raiseTime = 0.35, -- 무기 꺼낼 때 아래에서 올라오는 시간
	armColor = Color3.fromRGB(240, 200, 160),
	sleeveColor = Color3.fromRGB(60, 70, 90),
}
ViewModel.Settings = VM

local current: Model? = nil
local currentId: string? = nil
local gripOffset = CFrame.identity -- 손잡이 기준 → 모델 피벗
local gunLength = 3
local muzzleLocal: Vector3? = nil -- 손잡이 기준 총구 위치
local arms: { Part } = {}
local raiseStart = 0
local swayRot = Vector2.zero
local kick = 0
local adsBlend = 0

local function part(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function placeholder(): Model
	local m = Instance.new("Model")
	local body = part("Body", Vector3.new(0.35, 0.5, 2.6), Color3.fromRGB(35, 35, 40), m)
	body.Material = Enum.Material.Metal
	local mag = part("Mag", Vector3.new(0.25, 0.6, 0.35), Color3.fromRGB(25, 25, 28), m)
	mag.CFrame = body.CFrame * CFrame.new(0, -0.5, -0.2)
	local sight = part("Sight", Vector3.new(0.15, 0.2, 0.5), Color3.fromRGB(25, 25, 28), m)
	sight.CFrame = body.CFrame * CFrame.new(0, 0.35, 0.3)
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.05, -1.3)
	muzzle.Parent = body
	return m
end

function ViewModel.Destroy()
	if current then
		current:Destroy()
	end
	current, currentId, muzzleLocal = nil, nil, nil
	table.clear(arms)
end

-- 무기 바꾸면 새로 만듦 (아래에서 올라오는 모션부터)
function ViewModel.Set(weaponId: string, armColor: Color3?)
	if currentId == weaponId and current and current.Parent then
		return
	end
	ViewModel.Destroy()
	currentId = weaponId
	local folder = ReplicatedStorage:FindFirstChild("WeaponModels")
	local template = folder and folder:FindFirstChild(weaponId)
	local m = Instance.new("Model")
	m.Name = "ViewModel"
	local src: Instance = template and template:Clone() or placeholder()
	for _, c in src:GetChildren() do
		c.Parent = m
	end
	for _, d in m:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	-- 기준 파트 고정 (나중에 팔을 넣어도 피벗이 안 바뀌게)
	local primary = m:FindFirstChildWhichIsA("BasePart", true)
	if not primary then
		m:Destroy()
		return
	end
	m.PrimaryPart = primary
	-- 방향 찾기: 가장 긴 축 = 총열, 두 번째 = 위아래, 총구(Muzzle) 쪽이 앞
	local bbCF, size = m:GetBoundingBox()
	local axes = {
		{ v = bbCF.RightVector, len = size.X },
		{ v = bbCF.UpVector, len = size.Y },
		{ v = bbCF.LookVector, len = size.Z },
	}
	table.sort(axes, function(a, b)
		return a.len > b.len
	end)
	local fwd, len, up = axes[1].v, axes[1].len, axes[2].v
	local mz = m:FindFirstChild("Muzzle", true)
	local mzPos = mz and (mz:IsA("Attachment") and mz.WorldPosition or mz:IsA("BasePart") and mz.Position) or nil
	if mzPos and (mzPos - bbCF.Position):Dot(fwd) < 0 then
		fwd = -fwd
	end
	-- 너무 길면 줄임
	if len > VM.maxLength then
		local s = VM.maxLength / len
		m:ScaleTo(m:GetScale() * s)
		bbCF, size = m:GetBoundingBox()
		len *= s
		if mz then
			mzPos = mz:IsA("Attachment") and mz.WorldPosition or (mz :: BasePart).Position
		end
	end
	gunLength = len
	local stock = bbCF.Position - fwd * len / 2
	local grip = CFrame.fromMatrix(stock + fwd * len * VM.grip, fwd:Cross(up), up, -fwd)
	gripOffset = grip:Inverse() * m:GetPivot()
	muzzleLocal = grip:PointToObjectSpace(mzPos or (bbCF.Position + fwd * len / 2))
	-- 팔 (오른팔 = 손잡이, 왼팔 = 총열 받침)
	local color = armColor or VM.armColor
	for _, name in { "RightArm", "LeftArm" } do
		local arm = part(name, Vector3.new(0.42, 0.42, 1.9), VM.sleeveColor, m)
		local hand = part(name .. "Hand", Vector3.new(0.38, 0.38, 0.4), color, m)
		table.insert(arms, arm)
		table.insert(arms, hand)
	end
	m.Parent = workspace.CurrentCamera
	current = m
	raiseStart = os.clock()
	kick, adsBlend = 0, 0
end

function ViewModel.Kick(amount: number?)
	kick = math.min(kick + (amount or 1), 1.6)
end

-- 총구 월드 위치 (내 총알 줄기/섬광 시작점)
function ViewModel.MuzzlePosition(): Vector3?
	if not current or not current.Parent or not muzzleLocal then
		return nil
	end
	local gripCF = current:GetPivot() * gripOffset:Inverse()
	return gripCF:PointToWorldSpace(muzzleLocal)
end

-- 총 방향 (탄피 튀는 방향용)
function ViewModel.Axes(): (Vector3?, Vector3?)
	if not current or not current.Parent then
		return nil, nil
	end
	local gripCF = current:GetPivot() * gripOffset:Inverse()
	return gripCF.RightVector, gripCF.UpVector
end

-- 매 프레임: state = { ads, hidden, mouseDelta, bolt(0~1 진행, nil=아님), reload(bool), dt }
function ViewModel.Update(cam: Camera, state)
	if not current or not current.Parent then
		return
	end
	local dt = state.dt
	-- 숨김 (스나 조준경 화면 중)
	for _, d in current:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = state.hidden and 1 or 0
		end
	end
	if state.hidden then
		return
	end
	adsBlend += ((state.ads and 1 or 0) - adsBlend) * math.min(dt * VM.adsSpeed, 1)
	-- 스웨이: 마우스 반대쪽으로 살짝 늦게 따라옴
	local md: Vector2 = state.mouseDelta
	swayRot += Vector2.new(-md.X, -md.Y) * VM.swayAmount * (1 - adsBlend * 0.7)
	swayRot -= swayRot * math.min(dt * VM.swayReturn, 1)
	swayRot = Vector2.new(math.clamp(swayRot.X, -0.15, 0.15), math.clamp(swayRot.Y, -0.12, 0.12))
	kick -= kick * math.min(dt * VM.kickReturn, 1)
	local t = os.clock()
	local breathe = math.sin(t * 1.6) * 0.012 * (1 - adsBlend * 0.8)
	-- 꺼낼 때 아래에서 올라옴
	local raise = math.clamp((t - raiseStart) / VM.raiseTime, 0, 1)
	raise = 1 - (1 - raise) ^ 3
	local base = VM.hip:Lerp(VM.ads, adsBlend)
	local cf = cam.CFrame * base
		* CFrame.new(0, -0.9 * (1 - raise) + breathe, 0) * CFrame.Angles(math.rad(-35) * (1 - raise), 0, 0)
		* CFrame.Angles(swayRot.Y, swayRot.X, swayRot.X * 0.6)
		* CFrame.new(0, 0, VM.kickBack * kick) * CFrame.Angles(math.rad(VM.kickUp) * kick, 0, 0)
	-- 장전: 총을 내리고 기울임
	if state.reload then
		cf *= CFrame.new(0, -0.35, 0.1) * CFrame.Angles(math.rad(-20), math.rad(12), math.rad(35))
	end
	-- 볼트: 총을 오른쪽으로 굴리고 오른손이 뒤로 당김
	local boltPull = 0
	if state.bolt then
		local b = math.sin(math.clamp(state.bolt, 0, 1) * math.pi) -- 0 → 1 → 0
		cf *= CFrame.Angles(0, 0, math.rad(-18) * b) * CFrame.new(0, -0.08 * b, 0)
		boltPull = b
	end
	current:PivotTo(cf * gripOffset)
	-- 팔 위치: 오른팔은 손잡이에서 오른쪽 뒤 아래로, 왼팔은 총열 아래에서 왼쪽 뒤 아래로
	local foreZ = -gunLength * 0.38
	local rHand = cf * CFrame.new(0, -0.15, 0.1 + boltPull * 0.45)
	local lHand = cf * CFrame.new(0, -0.22, foreZ)
	local function arm(armPart: Part, handPart: Part, handCF: CFrame, shoulder: Vector3)
		handPart.CFrame = handCF
		local s = cam.CFrame:PointToWorldSpace(shoulder)
		local h = handCF.Position
		local mid = (s + h) / 2
		local length = (h - s).Magnitude
		armPart.Size = Vector3.new(0.42, 0.42, math.max(length, 0.5))
		armPart.CFrame = CFrame.lookAt(mid, h)
	end
	if #arms >= 4 then
		arm(arms[1], arms[2], rHand, Vector3.new(0.9, -1.5, 0.3):Lerp(Vector3.new(0.5, -1.3, 0.2), adsBlend))
		arm(arms[3], arms[4], lHand, Vector3.new(-0.9, -1.5, 0):Lerp(Vector3.new(-0.6, -1.3, -0.1), adsBlend))
	end
end

return ViewModel
