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
	plowAngleDeg = 35, -- 날이 비스듬한 정도 (0 이면 그냥 미는 막대)
	plowHeight = 6,
	plowThick = 4,
	plowLift = 0.5, -- 바닥에서 띄우는 높이 (바닥에 안 끌리게)
	-- 다리 (구멍 가로지르기)
	bridgeWidth = 26,
	bridgeDeg = 0, -- 다리 방향 (도)
	railWallHeight = 7, -- 경사로 가장자리 투명 벽 높이
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
			if h - lo > 1.5 then
				local railCF = segFrame(r0 + 0.8, th, h) * CFrame.Angles(beta, 0, 0)
				local rail = newPart(fRails, "Rail", Vector3.new(1.2, 2.5, segLen(r0 + 1)), railCF * CFrame.new(0, 1.25, 0), A.colors.rail)
				rail.CanCollide = false
				local wall = newPart(fRails, "RailWall", Vector3.new(1, A.railWallHeight, segLen(r0 + 1)), railCF * CFrame.new(0, A.railWallHeight / 2, 0), A.colors.rail)
				wall.Transparency = 1
				wall.CustomPhysicalProperties = FRICTIONLESS
			end
		end
		-- 시작 모서리 (위 고리 높이에서 경사면 쪽으로 떨어지는 곳): 가로 난간
		local th0 = angleOf(R.s) - DT / 2
		local edgeCF = segFrame(rm, th0, hi)
		local edge = newPart(fRails, "Rail", Vector3.new(r1 - r0, 2.5, 1.2), edgeCF * CFrame.new(0, 1.25, 0), A.colors.rail)
		edge.CanCollide = false
		local edgeWall = newPart(fRails, "RailWall", Vector3.new(r1 - r0, A.railWallHeight, 1), edgeCF * CFrame.new(0, A.railWallHeight / 2, 0), A.colors.rail)
		edgeWall.Transparency = 1
		edgeWall.CustomPhysicalProperties = FRICTIONLESS
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
