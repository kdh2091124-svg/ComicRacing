-- PVP 깔때기 아레나 생성기
-- Studio 명령줄 (:Clone() 꼭 붙이기):
--
--   require(game.ServerStorage.Tools.ArenaBuilder:Clone()).Build()
--
-- 모양 (위에서 보면 과녁, 옆에서 보면 계단식 깔때기):
--   바깥 고리(가장 높음) → 경사면 → 중간 고리 → 경사면 → 안쪽 고리 → 가운데 장외 구멍
--   층과 층 사이에는 넓은 나선 경사로(갈림길)가 고리길 옆에 나란히 붙어 있어서
--   고리길을 가로막지 않고, 끊김 없이 위아래로 오갈 수 있음
--   안쪽 고리에는 구멍을 가로지르는 좁은 다리 하나
--   바깥 벽 군데군데 뚫림 (밀려나면 바깥으로 떨어짐), 고리마다 천천히 도는 회전 쟁기 (캠핑 방지)
--
-- • 기존 Workspace.Map 은 ServerStorage 로 백업 (지운 게 아님), 지형(Terrain)은 비움
-- • 구멍에 떨어지면 drownY(GameplayConfig.Health) 아래로 내려가서 폭발 = 장외
-- • 모든 크기/높이는 아래 A 표에서만 고치면 됨

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local ArenaBuilder = {}

local A = {
	center = Vector3.new(0, 0, 0),
	baseY = -60, -- 블록 밑바닥 (구멍 벽이 깊어 보이게)
	segDeg = 2, -- 원을 몇 도씩 잘라서 만들지 (작을수록 매끈, 파트 많아짐)
	-- 고리길: 안쪽 반지름, 바깥 반지름, 윗면 높이
	rings = {
		{ name = "Outer", r0 = 520, r1 = 620, top = 100 },
		{ name = "Middle", r0 = 320, r1 = 420, top = 55 },
		{ name = "Inner", r0 = 130, r1 = 220, top = 25 },
	},
	pitRadius = 130, -- 이 안은 장외 구멍
	-- 경사로(갈림길): 위 고리 i 와 아래 고리 i+1 사이. 시작 각도(도)마다 하나씩, +각도 방향으로 내려감
	ramps = {
		{ band = 1, startDeg = { 0, 90, 180, 270 } },
		{ band = 2, startDeg = { 45, 135, 225, 315 } },
	},
	rampGrade = 0.13, -- 경사로 평균 기울기 (가운데가 가장 가파름, 약 1.5배)
	rampFlatLength = 70, -- 경사로 양 끝의 평평한 합류 구간 길이 (고리길과 같은 높이)
	rampSlack = 4, -- 다음 경사로와 최소 이만큼(칸) 떨어지게
	-- 바깥 벽, 바깥 데크
	wallHeight = 8,
	deckWidth = 140,
	-- true 면 바깥 벽/데크 전부 없음 → 바깥 가장자리 어디서든 떨어져 장외 (안쪽 구멍처럼 연석만)
	outerOpen = true,
	-- outerOpen = false 일 때만: 벽 뚫린 곳 (경사로 합류 구간은 피해서)
	gaps = {
		{ centerDeg = 78, widthDeg = 14 },
		{ centerDeg = 168, widthDeg = 14 },
		{ centerDeg = 258, widthDeg = 14 },
		{ centerDeg = 348, widthDeg = 14 },
	},
	-- 회전 쟁기 (캠핑 방지): 고리 위를 천천히 돌며 비스듬한 날로 차를 한쪽으로 밀어냄
	--   ring = 몇 번째 고리, count = 개수, speed = 도는 속도(스터드/초), dir = 1 또는 -1 (도는 방향)
	--   push = "out" 바깥쪽으로 / "in" 안쪽(구멍)으로
	plows = {
		{ ring = 1, count = 2, speed = 22, dir = 1, push = "out", startDeg = 40 },
		{ ring = 2, count = 2, speed = 18, dir = -1, push = "in", startDeg = 0 },
		{ ring = 3, count = 1, speed = 14, dir = 1, push = "in", startDeg = 90 },
	},
	-- 네모난 큰 막 + 그 위 스나이퍼 (장외로 나가면 쏴서 터뜨림. 실제 판정/사격은 서버 ArenaService)
	curtainMargin = 130, -- 바깥 고리에서 막까지 거리
	curtainAbove = 140, -- 바깥 고리보다 막이 얼마나 높은지
	snipersPerSide = 2,
	sniperScale = 3, -- 스나이퍼 크기 (멀리서도 보이게 크게). 템플릿을 쓰면 템플릿 크기 × 이 값
	-- 직접 자세 잡은 스나이퍼 템플릿 (Studio 에서 ServerStorage.ArenaModels.Sniper 에 두기, docs/MODEL_RULES.md)
	-- 없으면 블록 스나이퍼로 대신 만듦
	sniperTemplateFolder = "ArenaModels",
	sniperTemplateName = "Sniper",
	sniperRifleName = "SniperRifle", -- 같은 폴더에 총 모델 (Model 또는 Tool). 있으면 자동으로 손에 쥐어줌
	-- R6 리그면 코드가 "서서 쏴" 자세로 꺾어줌 (리그는 기본 자세 그대로 넣으면 됨)
	-- 좌표는 R6 기본 크기 기준, 몸 중심(몸통 가운데)에서: X = 오른쪽, Y = 위, Z = 뒤 (앞 = -Z)
	sniperPose = {
		enabled = true,
		torsoYaw = -35, -- 몸통을 틀어서 왼어깨가 앞으로 (실제 저격 자세)
		rightHand = Vector3.new(0.35, 0.35, -1.0), -- 오른손 = 방아쇠/손잡이
		leftHand = Vector3.new(0.35, 0.45, -2.3), -- 왼손 = 총열 받침
		rightFoot = Vector3.new(0.75, -3, 0.65), -- 오른발 뒤로
		leftFoot = Vector3.new(-0.5, -3, -0.7), -- 왼발 앞으로
		headYaw = 30, -- 몸통이 튼 만큼 고개는 다시 앞으로
		headPitch = -8, -- 살짝 숙여서 조준경 보기
		headRoll = -12, -- 총 쪽(오른쪽)으로 고개 기울임 (볼 붙이기)
		gunHeight = 0.55, -- 총이 지나가는 높이
		gunX = 0.35, -- 총이 지나가는 좌우 위치 (오른쪽 어깨 앞)
		rifleGrip = 0.35, -- 총 길이 중 오른손이 쥐는 위치 (0 = 개머리판 끝, 1 = 총구)
		rifleFlip = false, -- 총이 거꾸로(개머리판이 앞으로) 쥐어지면 true (총 안에 Muzzle 이 있으면 자동)
		rifleUpsideDown = false, -- 총이 뒤집혀(조준경이 아래로) 쥐어지면 true
	},
	floorDrop = 8, -- 가장 낮은 고리보다 이만큼 아래로 떨어지면 장외 (구멍)
	plowAngleDeg = 35, -- 날이 비스듬한 정도 (0 이면 그냥 미는 막대)
	plowHeight = 6,
	plowThick = 4,
	plowLift = 0.5, -- 바닥에서 띄우는 높이 (바닥에 안 끌리게)
	-- 다리 (구멍 가로지르기)
	bridgeWidth = 26,
	bridgeDeg = 0, -- 다리 방향 (도)
	rampRails = false, -- 경사로 노란 난간 (false = 없음 → 언제든 박아서 넘길 수 있음)
	railWallHeight = 7, -- 난간 켰을 때 뒤의 투명 벽 높이
	colors = {
		ring = { Color3.fromRGB(70, 72, 88), Color3.fromRGB(78, 76, 96), Color3.fromRGB(86, 74, 96) },
		slope = Color3.fromRGB(240, 170, 90),
		ramp = Color3.fromRGB(60, 120, 200),
		rail = Color3.fromRGB(255, 210, 60),
		curbA = Color3.fromRGB(230, 50, 50),
		curbB = Color3.fromRGB(245, 245, 245),
		wall = Color3.fromRGB(240, 240, 245),
		deck = Color3.fromRGB(110, 200, 90),
		bridge = Color3.fromRGB(255, 210, 60),
		lava = Color3.fromRGB(255, 90, 20),
		buff = Color3.fromRGB(60, 230, 200),
		curtain = Color3.fromRGB(255, 70, 90),
		rim = Color3.fromRGB(45, 48, 60),
		sniperBody = Color3.fromRGB(70, 90, 60),
		sniperSkin = Color3.fromRGB(240, 200, 160),
		sniperGun = Color3.fromRGB(25, 25, 30),
		plowA = Color3.fromRGB(255, 200, 30),
		plowB = Color3.fromRGB(30, 30, 35),
	},
}

local FRICTIONLESS = PhysicalProperties.new(0.7, 0, 0, 100, 1)

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local DT = math.rad(A.segDeg)
local N = math.floor(360 / A.segDeg + 0.5)

local function angleOf(i: number): number
	return i * DT
end

local function polar(r: number, th: number, y: number): Vector3
	return A.center + Vector3.new(r * math.cos(th), y, r * math.sin(th))
end

-- 원 위 th 지점에서 +각도 방향 (앞), 로컬 X 는 중심 쪽
local function segFrame(r: number, th: number, y: number): CFrame
	local pos = polar(r, th, y)
	local tangent = Vector3.new(-math.sin(th), 0, math.cos(th))
	return CFrame.lookAt(pos, pos + tangent)
end

local function segLen(rOuter: number): number
	return 2 * rOuter * math.tan(DT / 2) + 0.6 -- 살짝 겹쳐서 틈 없게
end

-- 고리 블록 (밑바닥부터 윗면까지 꽉 찬 덩어리 → 아래로 파고들 구멍 없음)
local function ringBlock(parent: Instance, r0: number, r1: number, th: number, top: number, color: Color3, name: string)
	local h = top - A.baseY
	local cf = segFrame((r0 + r1) / 2, th, A.baseY + h / 2)
	return newPart(parent, name, Vector3.new(r1 - r0, h, segLen(r1)), cf, color, Enum.Material.Concrete)
end

-- 경사면: 안쪽(r0, low) → 바깥(r1, high). 미끄러져 내려오는 깔때기 벽
local function slopeBlock(parent: Instance, r0: number, r1: number, th: number, low: number, high: number)
	local run, rise = r1 - r0, high - low
	local len = math.sqrt(run * run + rise * rise)
	local a = math.atan2(rise, run)
	local T = rise + 10 -- 두께: 경사면 아래가 비지 않게 충분히
	local cf = segFrame((r0 + r1) / 2, th, (low + high) / 2) * CFrame.Angles(0, 0, -a) * CFrame.new(0, -T / 2, 0)
	newPart(parent, "Slope", Vector3.new(len, T, segLen(r1)), cf, A.colors.slope, Enum.Material.SmoothPlastic)
	ringBlock(parent, r0, r1, th, low, A.colors.slope, "SlopeFill")
end

-- 블록 스나이퍼 (엎드린 게 아니라 서서 저격총 겨눔). 서버가 쏠 때 몸을 돌려 조준함
--   Model Attribute "Sniper" = true, 총구 파트 이름 "Muzzle"
local function makeSniper(parent: Instance, feet: Vector3, lookAt: Vector3, k: number, idx: number): Model
	local m = Instance.new("Model")
	m.Name = "Sniper" .. idx
	m:SetAttribute("Sniper", true)
	local base = CFrame.lookAt(feet, Vector3.new(lookAt.X, feet.Y, lookAt.Z))
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * k, y * k, z * k)
	end
	local C = A.colors
	for _, x in { -0.5, 0.5 } do
		newPart(m, "Leg", Vector3.new(1, 2, 1) * k, at(x, 1, 0), C.sniperBody)
	end
	local torso = newPart(m, "Torso", Vector3.new(2, 2, 1) * k, at(0, 3, 0), C.sniperBody)
	newPart(m, "Head", Vector3.new(1.2, 1.2, 1.2) * k, at(0, 4.6, 0), C.sniperSkin)
	newPart(m, "Helmet", Vector3.new(1.4, 0.5, 1.4) * k, at(0, 5.3, 0), C.sniperBody)
	newPart(m, "ArmR", Vector3.new(0.8, 0.8, 2) * k, at(0.9, 3.4, -0.9), C.sniperBody)
	newPart(m, "ArmL", Vector3.new(0.8, 0.8, 2) * k, at(-0.5, 3.4, -1.4), C.sniperBody)
	newPart(m, "Rifle", Vector3.new(0.4, 0.5, 5) * k, at(0.3, 3.7, -2.6), C.sniperGun, Enum.Material.Metal)
	newPart(m, "Scope", Vector3.new(0.3, 0.3, 1.2) * k, at(0.3, 4.1, -2), C.sniperGun, Enum.Material.Metal)
	local muzzle = newPart(m, "Muzzle", Vector3.new(0.3, 0.3, 0.3) * k, at(0.3, 3.7, -5.2), C.sniperGun)
	muzzle.Transparency = 1
	-- 빨간 조준 점 (멀리서도 "날 보고 있다" 느낌)
	local eye = newPart(m, "LaserDot", Vector3.new(0.25, 0.25, 0.1) * k, at(0.3, 3.7, -5.1), Color3.fromRGB(255, 30, 30), Enum.Material.Neon)
	eye.CanCollide = false
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	m.PrimaryPart = torso
	m.Parent = parent
	return m
end

-- 팔다리 회전: 늘어뜨린 방향(아래) → d 방향으로 가장 짧게 돌리기 (팔이 이상하게 비틀리지 않게)
local function limbRot(d: Vector3): CFrame
	local from, to = Vector3.new(0, -1, 0), d.Unit
	local axis = from:Cross(to)
	local dot = math.clamp(from:Dot(to), -1, 1)
	if axis.Magnitude < 1e-4 then
		return dot > 0 and CFrame.identity or CFrame.Angles(math.pi, 0, 0)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- R6 리그를 "서서 쏴" 자세로 꺾음. 성공하면 몸 기준 프레임(원래 서 있던 몸통 CFrame) 반환
--   팔다리 파트를 직접 옮기고, 나중에 관절을 없애고 전부 고정 → 자세가 절대 안 풀림
local function poseR6(m: Model): CFrame?
	local P = A.sniperPose
	local torso = m:FindFirstChild("Torso")
	local head = m:FindFirstChild("Head")
	local ra, la = m:FindFirstChild("Right Arm"), m:FindFirstChild("Left Arm")
	local rl, ll = m:FindFirstChild("Right Leg"), m:FindFirstChild("Left Leg")
	for _, p in { torso, head, ra, la, rl, ll } do
		if not (p and p:IsA("BasePart")) then
			return nil -- R6 아님 → 자세는 템플릿 그대로
		end
	end
	local body = { torso, head, ra, la, rl, ll }
	local isBody = {}
	for _, p in body do
		isBody[p] = true
	end
	local hrp = m:FindFirstChild("HumanoidRootPart")
	-- 모자/액세서리처럼 몸에 붙은 것들: 붙은 위치 기억 → 몸 옮긴 뒤 다시 붙임
	local riders = {}
	for _, j in m:GetDescendants() do
		if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
			local p0, p1 = (j :: any).Part0, (j :: any).Part1
			if p0 and p1 then
				for _, pair in { { p0, p1 }, { p1, p0 } } do
					local bodyPart, other = pair[1], pair[2]
					if isBody[bodyPart] and not isBody[other] and other ~= hrp then
						table.insert(riders, { part = other, to = bodyPart, offset = bodyPart.CFrame:ToObjectSpace(other.CFrame) })
					end
				end
			end
		end
	end

	local Bf = (torso :: BasePart).CFrame -- 원래 서 있던 몸
	local T = Bf * CFrame.Angles(0, math.rad(P.torsoYaw), 0)
	;(torso :: BasePart).CFrame = T
	local function limb(part: BasePart, topLocal: Vector3, targetB: Vector3)
		local top = T:PointToWorldSpace(topLocal)
		local d = Bf:PointToWorldSpace(targetB) - top
		if d.Magnitude < 0.01 then
			return
		end
		d = d.Unit
		part.CFrame = CFrame.new(top + d * part.Size.Y / 2) * (T.Rotation * limbRot(T:VectorToObjectSpace(d)))
	end
	limb(ra :: BasePart, Vector3.new(1.5, 0.9, 0), P.rightHand)
	limb(la :: BasePart, Vector3.new(-1.5, 0.9, 0), P.leftHand)
	limb(rl :: BasePart, Vector3.new(0.5, -1, 0), P.rightFoot)
	limb(ll :: BasePart, Vector3.new(-0.5, -1, 0), P.leftFoot)
	;(head :: BasePart).CFrame = T * CFrame.new(0, 1, 0) * CFrame.Angles(0, math.rad(P.headYaw), 0)
		* CFrame.Angles(math.rad(P.headPitch), 0, math.rad(P.headRoll)) * CFrame.new(0, (head :: BasePart).Size.Y / 2, 0)
	for _, r in riders do
		r.part.CFrame = r.to.CFrame * r.offset
	end
	return Bf
end

-- 총 모델을 손에 쥐어줌: 가장 긴 축 = 총열 방향. 총구(Muzzle)가 있으면 그쪽이 앞, 없으면 rifleFlip 으로 정함
local function attachRifle(m: Model, rifleTemplate: Instance, Bf: CFrame)
	local P = A.sniperPose
	local r = Instance.new("Model")
	r.Name = "Rifle"
	for _, c in rifleTemplate:Clone():GetChildren() do
		c.Parent = r -- Tool 이든 Model 이든 안의 것만 꺼냄
	end
	for _, d in r:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
			d:Destroy()
		end
	end
	local bbCF, size = r:GetBoundingBox()
	local axes = {
		{ v = bbCF.RightVector, len = size.X },
		{ v = bbCF.UpVector, len = size.Y },
		{ v = bbCF.LookVector, len = size.Z },
	}
	table.sort(axes, function(a, b)
		return a.len > b.len
	end)
	local fwd, len, up = axes[1].v, axes[1].len, axes[2].v -- 가장 긴 축 = 총열, 두 번째 = 위아래
	local muzzle = r:FindFirstChild("Muzzle", true)
	local muzzlePos = muzzle and (muzzle:IsA("Attachment") and muzzle.WorldPosition or muzzle:IsA("BasePart") and muzzle.Position)
	if muzzlePos then
		if (muzzlePos - bbCF.Position):Dot(fwd) < 0 then
			fwd = -fwd
		end
	elseif P.rifleFlip then
		fwd = -fwd
	end
	if P.rifleUpsideDown then
		up = -up
	end
	local stock = bbCF.Position - fwd * len / 2
	local gripNow = stock + fwd * len * P.rifleGrip
	local current = CFrame.fromMatrix(gripNow, fwd:Cross(up), up, -fwd)
	local gripTarget = Bf:PointToWorldSpace(Vector3.new(P.gunX, P.gunHeight, P.rightHand.Z))
	local wanted = CFrame.new(gripTarget) * Bf.Rotation
	r:PivotTo(wanted * current:Inverse() * r:GetPivot())
	-- 총구가 없으면 총 끝에 만들어 줌
	if not muzzlePos then
		local tip = gripTarget + Bf.LookVector * len * (1 - P.rifleGrip)
		local best, bestD = nil, -math.huge
		for _, p in r:GetDescendants() do
			if p:IsA("BasePart") then
				local dd = (p.Position - gripTarget):Dot(Bf.LookVector)
				if dd > bestD then
					best, bestD = p, dd
				end
			end
		end
		if best then
			local att = Instance.new("Attachment")
			att.Name = "Muzzle"
			att.Position = best.CFrame:PointToObjectSpace(tip)
			att.Parent = best
		end
	end
	r.Parent = m
end

-- 개발자가 만든 스나이퍼 템플릿 복제: 크기 맞추고, 발바닥을 feet 높이에, 몸 앞이 lookAt 을 보게
local function placeTemplate(template: Model, rifle: Instance?, parent: Instance, feet: Vector3, lookAt: Vector3, scale: number, idx: number): Model
	local m = template:Clone()
	m.Name = "Sniper" .. idx
	m:SetAttribute("Sniper", true)
	-- R6 면 저격 자세로 꺾기 + 총 쥐어주기, 그다음 관절을 전부 없앰 (전부 고정되니 자세가 그대로 남음)
	local Bf = A.sniperPose.enabled and poseR6(m) or nil
	if rifle then
		local torso = m:FindFirstChild("Torso") or m:FindFirstChild("UpperTorso")
		local frame = Bf or (torso and torso:IsA("BasePart") and torso.CFrame) or m:GetPivot()
		attachRifle(m, rifle, frame)
	end
	for _, j in m:GetDescendants() do
		if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
			j:Destroy()
		end
	end
	if scale ~= 1 then
		m:ScaleTo(m:GetScale() * scale)
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true -- 잡은 자세 그대로 고정
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- 이름/체력바 숨김
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			d.RequiresNeck = false -- 관절을 없애도 "죽음" 처리 안 되게
			d.BreakJointsOnDeath = false
			d.EvaluateStateMachine = false -- 서 있으려고 몸을 움직이지 않게
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy() -- Animate 같은 스크립트가 자세를 덮어쓰지 않게
		end
	end
	if not m.PrimaryPart then
		local root = m:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			m.PrimaryPart = root
		end
	end
	-- 방향 먼저 (템플릿의 앞 = 피벗 LookVector), 그다음 발바닥 높이 맞춤
	local pivot = m:GetPivot()
	m:PivotTo(CFrame.lookAt(pivot.Position, pivot.Position + (Vector3.new(lookAt.X, 0, lookAt.Z) - Vector3.new(feet.X, 0, feet.Z))))
	local bbCF, bbSize = m:GetBoundingBox()
	local bottom = bbCF.Position.Y - bbSize.Y / 2
	local p = m:GetPivot()
	m:PivotTo(p + Vector3.new(feet.X - p.Position.X, feet.Y - bottom, feet.Z - p.Position.Z))
	if not m:FindFirstChild("Muzzle", true) then
		warn("[ArenaBuilder] 스나이퍼 템플릿에 'Muzzle'(총구 Attachment 또는 파트)이 없어요 → 몸 중심에서 쏘는 걸로 보임")
	end
	m.Parent = parent
	return m
end

local function smooth(u: number): number
	return u * u * (3 - 2 * u)
end

----------------------------------------------------------------------

function ArenaBuilder.Build(options: { keepTerrain: boolean? }?)
	options = options or {}
	local recording = ChangeHistoryService:TryBeginRecording("ArenaBuilder")
	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing.Name = "Map_backup_" .. os.time()
		existing.Parent = game:GetService("ServerStorage")
		warn("[ArenaBuilder] 기존 맵을 ServerStorage." .. existing.Name .. " 로 옮겨 뒀어요 (지운 게 아님)")
	end
	if not (options :: any).keepTerrain then
		workspace.Terrain:Clear()
	end

	local map = Instance.new("Folder")
	map.Name = "Map"
	local fRings = folder(map, "Rings")
	local fSlopes = folder(map, "Slopes")
	local fRamps = folder(map, "Ramps")
	local fRails = folder(map, "Rails")
	local fDecor = folder(map, "Decor")
	local fMarks = folder(map, "Markers")
	local rings = A.rings
	local warnings = {}

	-- 1) 고리길 + 가장자리 연석 (빨강/흰색, 충돌 없음 = 턱 없음)
	for ri, ring in rings do
		local color = A.colors.ring[ri] or A.colors.ring[1]
		for i = 0, N - 1 do
			local th = angleOf(i)
			ringBlock(fRings, ring.r0, ring.r1, th, ring.top, color, ring.name)
			local curb = newPart(fDecor, "Curb", Vector3.new(4, 0.2, segLen(ring.r0 + 4)), segFrame(ring.r0 + 2, th, ring.top + 0.05), (i % 2 == 0) and A.colors.curbA or A.colors.curbB)
			curb.CanCollide = false
			curb.CanQuery = false
		end
	end

	-- 2) 경사로가 차지하는 칸 정하기
	local rampAt: { [number]: { [number]: { k: number, n: number, flat: number, desc: number } } } = {}
	local rampList = {}
	for _, spec in A.ramps do
		local b = spec.band
		local upper, lower = rings[b], rings[b + 1]
		assert(upper and lower, "[ArenaBuilder] ramps.band " .. b .. " 아래에 고리가 없어요")
		rampAt[b] = rampAt[b] or {}
		local rm = (lower.r1 + upper.r0) / 2
		local step = rm * DT
		local drop = upper.top - lower.top
		local desc = math.ceil(drop / (A.rampGrade * step))
		local flat = math.ceil(A.rampFlatLength / step)
		local n = desc + flat * 2
		local spacing = 360 / #spec.startDeg / A.segDeg
		if n + A.rampSlack > spacing then
			table.insert(warnings, string.format("%d층 경사로가 너무 길어서 서로 붙어요 (%d칸 > %d칸). rampGrade 를 키우거나 경사로 수를 줄이세요", b, n, math.floor(spacing)))
		end
		for _, deg in spec.startDeg do
			local s = math.floor(deg / A.segDeg + 0.5)
			local info = { band = b, s = s, n = n, flat = flat, desc = desc, upper = upper, lower = lower, step = step }
			table.insert(rampList, info)
			for k = 0, n - 1 do
				rampAt[b][(s + k) % N] = { k = k, n = n, flat = flat, desc = desc }
			end
		end
	end

	-- 3) 층 사이 경사면 (경사로 자리는 비움)
	for b = 1, #rings - 1 do
		local upper, lower = rings[b], rings[b + 1]
		for i = 0, N - 1 do
			if not (rampAt[b] and rampAt[b][i]) then
				slopeBlock(fSlopes, lower.r1, upper.r0, angleOf(i), lower.top, upper.top)
			end
		end
	end

	-- 4) 경사로: 고리 사이 띠 전체 폭, 양 끝은 고리와 같은 높이로 평평 (합류 구간)
	local maxGrade = 0
	for _, R in rampList do
		local r0, r1 = R.lower.r1, R.upper.r0
		local hi, lo = R.upper.top, R.lower.top
		local function H(t: number): number
			if t <= R.flat then
				return hi
			elseif t >= R.flat + R.desc then
				return lo
			end
			return hi - (hi - lo) * smooth((t - R.flat) / R.desc)
		end
		local rm = (r0 + r1) / 2
		for k = 0, R.n - 1 do
			local th = angleOf(R.s + k)
			local h = H(k + 0.5)
			local grade = (H(k + 1) - H(k)) / R.step
			maxGrade = math.max(maxGrade, math.abs(grade))
			local beta = math.atan(grade)
			local depth = h - A.baseY + 6
			local cf = segFrame(rm, th, h) * CFrame.Angles(beta, 0, 0)
			newPart(fRamps, "Ramp", Vector3.new(r1 - r0, depth, segLen(r1)), cf * CFrame.new(0, -depth / 2, 0), A.colors.ramp, Enum.Material.Concrete)
			-- 안쪽 가장자리: 아래 고리보다 높은 곳만 난간 (끝 합류 구간은 열림)
			if A.rampRails and h - lo > 1.5 then
				local railCF = segFrame(r0 + 0.8, th, h) * CFrame.Angles(beta, 0, 0)
				local rail = newPart(fRails, "Rail", Vector3.new(1.2, 2.5, segLen(r0 + 1)), railCF * CFrame.new(0, 1.25, 0), A.colors.rail)
				rail.CanCollide = false
				local wall = newPart(fRails, "RailWall", Vector3.new(1, A.railWallHeight, segLen(r0 + 1)), railCF * CFrame.new(0, A.railWallHeight / 2, 0), A.colors.rail)
				wall.Transparency = 1
				wall.CustomPhysicalProperties = FRICTIONLESS
			end
		end
		-- 시작 모서리 (위 고리 높이에서 경사면 쪽으로 떨어지는 곳): 가로 난간
		if A.rampRails then
			local th0 = angleOf(R.s) - DT / 2
			local edgeCF = segFrame(rm, th0, hi)
			local edge = newPart(fRails, "Rail", Vector3.new(r1 - r0, 2.5, 1.2), edgeCF * CFrame.new(0, 1.25, 0), A.colors.rail)
			edge.CanCollide = false
			local edgeWall = newPart(fRails, "RailWall", Vector3.new(r1 - r0, A.railWallHeight, 1), edgeCF * CFrame.new(0, A.railWallHeight / 2, 0), A.colors.rail)
			edgeWall.Transparency = 1
			edgeWall.CustomPhysicalProperties = FRICTIONLESS
		end
		-- 버프 아이템 자리 (아이템 기능은 아직 없음, 위치 표시만)
		for _, spot in { { R.upper, R.s + 2 }, { R.lower, R.s + R.n - 3 } } do
			local ring, idx = spot[1], spot[2]
			local p = newPart(fMarks, "BuffSpawn", Vector3.one * 4, CFrame.new(polar((ring.r0 + ring.r1) / 2, angleOf(idx), ring.top + 4)), A.colors.buff, Enum.Material.Neon)
			p.Shape = Enum.PartType.Ball
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p:SetAttribute("BuffSpawn", true)
		end
	end

	-- 5) 바깥 벽 + 바깥 데크 (뚫린 곳은 빼고, 대신 가장자리에 빨강/흰 경고 연석)
	local outer = rings[1]
	local function inGap(th: number): boolean
		if A.outerOpen then
			return true
		end
		local deg = math.deg(th)
		for _, g in A.gaps do
			local d = (deg - g.centerDeg + 180) % 360 - 180
			if math.abs(d) <= g.widthDeg / 2 then
				return true
			end
		end
		return false
	end
	for i = 0, N - 1 do
		local th = angleOf(i)
		if inGap(th) then
			local curb = newPart(fDecor, "GapCurb", Vector3.new(4, 0.2, segLen(outer.r1)), segFrame(outer.r1 - 2, th, outer.top + 0.05), (i % 2 == 0) and A.colors.curbA or A.colors.curbB)
			curb.CanCollide = false
			curb.CanQuery = false
			continue
		end
		local wall = newPart(fDecor, "OuterWall", Vector3.new(3, A.wallHeight, segLen(outer.r1 + 3)), segFrame(outer.r1 + 1.5, th, outer.top + A.wallHeight / 2), A.colors.wall)
		wall.CustomPhysicalProperties = FRICTIONLESS
		ringBlock(fDecor, outer.r1 + 3, outer.r1 + 3 + A.deckWidth, th, outer.top, A.colors.deck, "Deck").Material = Enum.Material.Grass
	end

	-- 5-2) 회전 쟁기: 가운데 고정 기둥(보이지 않음)에 경첩(HingeConstraint 모터)으로 연결된 날.
	--   물리로 도니까 차를 진짜로 밀어냄. 게임 중엔 서버가 물리를 맡음 (ArenaService)
	local fPlows = folder(map, "Plows")
	local plowCount = 0
	for _, spec in A.plows do
		local ring = rings[spec.ring]
		assert(ring, "[ArenaBuilder] plows.ring " .. tostring(spec.ring) .. " 고리가 없어요")
		local pushOut = spec.push == "out"
		-- 바깥 고리에 벽이 있으면 밀려가는 끝에 여유를 둬서 차가 벽과 날 사이에 끼지 않게
		local walled = spec.ring == 1 and not A.outerOpen
		local rIn = ring.r0 + (pushOut and 4 or 2)
		local rOut = ring.r1 - (pushOut and (walled and 12 or 2) or 4)
		local rm = (rIn + rOut) / 2
		local psi = math.rad(A.plowAngleDeg) * spec.dir * (pushOut and 1 or -1)
		local len = (rOut - rIn) / math.cos(psi)
		local y = ring.top + A.plowLift + A.plowHeight / 2
		local pivotPos = A.center + Vector3.new(0, y, 0)
		local axisCF = CFrame.fromMatrix(pivotPos, Vector3.yAxis, Vector3.xAxis) -- X 축이 위 = 경첩 회전축
		local pivot = newPart(fPlows, "PlowPivot_" .. ring.name, Vector3.one * 2, CFrame.new(pivotPos), A.colors.plowB)
		pivot.Transparency = 1
		pivot.CanCollide = false
		pivot.CanQuery = false
		pivot.CanTouch = false
		for k = 0, spec.count - 1 do
			local phi = math.rad(spec.startDeg) + k * 2 * math.pi / spec.count
			local cf = segFrame(rm, phi, y) * CFrame.Angles(0, psi, 0)
			local arm = newPart(fPlows, "Plow_" .. ring.name, Vector3.new(len, A.plowHeight, A.plowThick), cf, A.colors.plowA, Enum.Material.Metal)
			arm.Anchored = false
			arm.CustomPhysicalProperties = PhysicalProperties.new(100, 0, 0, 100, 1) -- 무겁고 미끄러움
			arm:SetAttribute("ServerPhysics", true)
			arm:SetAttribute("Hazard", "Plow")
			arm:SetAttribute("Bumper", true) -- 닿으면 "통" 튕김 (GameplayConfig.Physics.Bumper)
			-- 검정 줄무늬 (보기용, 날에 붙임)
			for s = -2, 2 do
				local stripe = newPart(arm, "Stripe", Vector3.new(len / 10, A.plowHeight + 0.1, A.plowThick + 0.1), cf * CFrame.new(s * len / 5, 0, 0), A.colors.plowB, Enum.Material.Metal)
				stripe.Anchored = false
				stripe.CanCollide = false
				stripe.Massless = true
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = arm, stripe
				w.Parent = stripe
			end
			local a0 = Instance.new("Attachment")
			a0.Name = "PlowAxis" .. k
			a0.CFrame = pivot.CFrame:ToObjectSpace(axisCF)
			a0.Parent = pivot
			local a1 = Instance.new("Attachment")
			a1.Name = "PlowAxis"
			a1.CFrame = arm.CFrame:ToObjectSpace(axisCF)
			a1.Parent = arm
			local hinge = Instance.new("HingeConstraint")
			hinge.Attachment0, hinge.Attachment1 = a0, a1
			hinge.ActuatorType = Enum.ActuatorType.Motor
			hinge.AngularVelocity = spec.speed / rm * spec.dir
			hinge.MotorMaxTorque = 1e12
			hinge.MotorMaxAcceleration = 2
			hinge.Parent = arm
			plowCount += 1
		end
	end

	-- 6) 구멍 가로지르는 다리 (안쪽 고리 높이, 난간 없음 → 밀리면 장외)
	local inner = rings[#rings]
	local bth = math.rad(A.bridgeDeg)
	local bdir = Vector3.new(math.cos(bth), 0, math.sin(bth))
	local blen = (inner.r0 + 30) * 2
	newPart(fDecor, "Bridge", Vector3.new(A.bridgeWidth, 4, blen), CFrame.lookAt(A.center + Vector3.new(0, inner.top - 2, 0), A.center + Vector3.new(0, inner.top - 2, 0) + bdir), A.colors.bridge, Enum.Material.Metal)

	-- 7) 구멍 바닥 용암 (보기용, 충돌 없음. 실제 장외 판정은 drownY)
	local lava = newPart(fDecor, "PitLava", Vector3.new(2, A.pitRadius * 2, A.pitRadius * 2), CFrame.new(A.center + Vector3.new(0, A.baseY + 10, 0)) * CFrame.Angles(0, 0, math.rad(90)), A.colors.lava, Enum.Material.Neon)
	lava.Shape = Enum.PartType.Cylinder
	lava.CanCollide = false
	lava.CanQuery = false

	-- 7-2) 네모난 큰 막 (통과 가능, 보기용) + 막 위 통로 + 스나이퍼
	local fCurtain = folder(map, "Curtain")
	local S = outer.r1 + A.curtainMargin -- 중심에서 막까지 (반)
	local topY = outer.top + A.curtainAbove
	local wallH = topY - A.baseY
	local sides = {
		{ Vector3.new(0, 0, -S), Vector3.new(1, 0, 0) },
		{ Vector3.new(0, 0, S), Vector3.new(1, 0, 0) },
		{ Vector3.new(-S, 0, 0), Vector3.new(0, 0, 1) },
		{ Vector3.new(S, 0, 0), Vector3.new(0, 0, 1) },
	}
	local sniperIdx = 0
	local templateFolder = game:GetService("ServerStorage"):FindFirstChild(A.sniperTemplateFolder)
	local sniperTemplate = templateFolder and templateFolder:FindFirstChild(A.sniperTemplateName)
	if sniperTemplate and not sniperTemplate:IsA("Model") then
		sniperTemplate = nil
	end
	local sniperRifle = templateFolder and templateFolder:FindFirstChild(A.sniperRifleName)
	print(sniperTemplate and "[ArenaBuilder] 스나이퍼: 직접 만든 템플릿 사용" or "[ArenaBuilder] 스나이퍼: 템플릿 없음 → 블록 스나이퍼",
		sniperRifle and "/ 총 모델 사용" or "/ 총 모델 없음")
	for _, side in sides do
		local mid, along = A.center + side[1], side[2]
		local look = CFrame.lookAt(mid, mid + along) -- Z 축 = 막 방향
		local curtain = newPart(fCurtain, "Curtain", Vector3.new(2, wallH, S * 2 + 2), look * CFrame.new(0, A.baseY + wallH / 2, 0), A.colors.curtain, Enum.Material.ForceField)
		curtain.CanCollide = false
		curtain.CanQuery = false
		curtain.CanTouch = false
		curtain.CastShadow = false
		local rim = newPart(fCurtain, "Rim", Vector3.new(14, 4, S * 2 + 14), look * CFrame.new(0, topY + 2, 0), A.colors.rim, Enum.Material.Metal)
		rim.CanQuery = false
		for k = 1, A.snipersPerSide do
			sniperIdx += 1
			local t = (k / (A.snipersPerSide + 1)) * 2 - 1 -- -1 ~ 1 사이 고르게
			local feet = mid + along * (t * S) + Vector3.new(0, topY + 4, 0)
			local aimAt = A.center + Vector3.new(0, outer.top, 0)
			if sniperTemplate then
				placeTemplate(sniperTemplate :: Model, sniperRifle, fCurtain, feet, aimAt, A.sniperScale, sniperIdx)
			else
				makeSniper(fCurtain, feet, aimAt, A.sniperScale, sniperIdx)
			end
		end
	end

	-- 장외 판정용 정보 (서버 ArenaBounds 가 읽음)
	map:SetAttribute("ArenaCenter", A.center)
	map:SetAttribute("ArenaOuterR", outer.r1)
	map:SetAttribute("ArenaPitR", A.pitRadius)
	map:SetAttribute("ArenaFloorY", inner.top - A.floorDrop)
	map:SetAttribute("ArenaShotY", A.baseY + 14) -- 떨어지는 차를 쏘는 "바닥" (구멍 용암 높이 근처)

	-- 8) 스폰: 바깥 고리. 나중에 PVP 부활 위치로 쓸 표시 8개 (ArenaSpawn)
	local rmOuter = (outer.r0 + outer.r1) / 2
	for k = 0, 7 do
		local th = math.rad(22.5 + k * 45)
		local m = newPart(fMarks, "ArenaSpawn", Vector3.new(8, 1, 14), segFrame(rmOuter, th, outer.top + 0.5), A.colors.buff)
		m.Transparency = 1
		m.CanCollide = false
		m.CanQuery = false
		m.CanTouch = false
		m:SetAttribute("ArenaSpawn", k + 1)
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MainSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = segFrame(rmOuter, math.rad(22.5), outer.top - 0.45) -- 거의 묻어서 턱 없음
	spawn.Color = Color3.fromRGB(80, 200, 255)
	spawn.Parent = map

	map.Parent = workspace
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end

	local parts = 0
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format("[ArenaBuilder] 완료: 파트 %d개, 경사로 %d개 (최대 기울기 %.1f°), 바깥 %s, 회전 쟁기 %d개", parts, #rampList, math.deg(math.atan(maxGrade)), A.outerOpen and "전부 뚫림" or (#A.gaps .. "군데 뚫림"), plowCount))
	for _, w in warnings do
		warn("[ArenaBuilder] " .. w)
	end
end

return ArenaBuilder
