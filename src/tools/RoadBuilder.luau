-- 도로 생성기: 부드러운 곡선 도로망을 깐다 (구조물 없이 길만). Studio 명령줄에서 실행:
-- (:Clone() 을 꼭 붙이기 — 안 붙이면 명령줄이 예전 코드를 기억해서 수정이 반영 안 됨)
--
--   require(game.ServerStorage.Tools.RoadBuilder:Clone()).Build()
--
-- • 기존 Workspace.Map 은 지우지 않고 ServerStorage.Map_backup_시간 으로 옮겨 둠 (Ctrl+Z 가능)
-- • 길 모양은 아래 ROUTES 의 점들만 고치면 됨: { x, y(높이), z, bank = 기울기(도, +면 오른쪽이 낮음), bridge = true }
-- • 점과 점 사이는 자동으로 부드러운 곡선 (Catmull-Rom 곡선)
--
-- 생김새 (레퍼런스 스타일):
--   아스팔트 + 노란 중앙 점선 + 흰 테두리선, 양옆 초록 갓길, 그 아래 푸른 회색 절벽 둑
--   다리(bridge) 구간은 둑 대신 기둥, 높거나 기울어진 구간엔 가드레일

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local RoadBuilder = {}

local STYLE = {
	roadWidth = 46, -- 차도 폭 (넓게: 드리프트/추월 여유)
	shoulder = 10, -- 양옆 잔디 갓길 폭
	step = 5, -- 곡선을 이 길이(스터드)마다 나눠서 조각으로 깖
	groundY = 0, -- 바닥 높이
	asphalt = Color3.fromRGB(78, 80, 96),
	grass = Color3.fromRGB(110, 230, 120),
	cliff = Color3.fromRGB(70, 90, 170), -- 둑 옆면 (푸른 회색)
	whiteLine = Color3.fromRGB(245, 245, 245),
	yellowLine = Color3.fromRGB(255, 225, 40),
	rail = Color3.fromRGB(190, 195, 210),
	ground = Color3.fromRGB(95, 200, 105),
	pillar = Color3.fromRGB(150, 155, 170),
	railHeight = 15, -- 바닥보다 이만큼 높으면 가드레일
}

-- ===== 길 모양 =====
-- 그리는 순서가 중요: 먼저 그린 길에 나중 길이 "붙을" 수 있음 (join)
--
-- 1) Highway: 바깥 큰 순환 고속도로
--   A 출발 직선 + 언덕 꼭대기 (살짝 뜨는 구간)
--   B 오른쪽으로 크게 도는 기울어진 커브
--   C 지그재그로 올라가는 언덕길
--   D 꼭대기 헤어핀 (드리프트 구간)
--   E 구불구불 내리막
--   F 출발 직선 위를 지나가는 다리 (입체 교차)
--   G 왼쪽으로 크게 도는 기울어진 커브
--   H 출발점으로 돌아오는 빠른 커브
-- 2) CenterRing: 가운데 큰 O 자 순환 도로 (안쪽으로 살짝 기울어짐)
-- 3) Spoke*: O 자에서 고속도로로 뻗는 갈림길 4개 (서/북/동/남)
-- 4) WestBypass: 고속도로 출발 직선 끝에서 서쪽 언덕으로 크게 돌아 G 커브로 다시 합류하는 우회로
--
-- 점 형식: { x, 높이, z, bank = 기울기(도), bridge = true }
--   또는 { join = "다른 길 이름", near = { x, z } } → 그 길에서 (x, z) 에 가장 가까운 지점에 정확히 붙음 (갈림길)

-- 가운데 O 자 도로 점 만들기 (시계 방향 → 안쪽이 오른쪽, bank + 면 안쪽으로 기울어짐)
local function ringPoints(center: Vector3, radius: number, count: number, bank: number)
	local pts = {}
	for k = 0, count - 1 do
		local a = k / count * math.pi * 2
		table.insert(pts, { center.X + math.cos(a) * radius, center.Y, center.Z + math.sin(a) * radius, bank = bank })
	end
	return pts
end

local RING_CENTER = Vector3.new(330, 20, -230)
local RING_RADIUS = 200

local ROUTES = {
	{
		name = "Highway",
		width = 56, -- 고속도로는 더 넓게
		closed = true,
		points = {
			-- A
			{ 0, 10, 600 },
			{ 0, 14, 300 },
			{ 0, 26, 70 },
			{ 0, 26, 20 },
			{ 0, 10, -130 },
			{ 0, 10, -420 },
			-- B
			{ 60, 12, -640, bank = 8 },
			{ 220, 16, -780, bank = 10 },
			{ 420, 20, -820, bank = 8 },
			-- C
			{ 600, 28, -760 },
			{ 720, 40, -640, bank = 6 },
			{ 680, 52, -500, bank = -6 },
			{ 800, 64, -380, bank = 6 },
			{ 740, 76, -250, bank = -4 },
			-- D
			{ 840, 84, -110 },
			{ 960, 84, -70, bank = 8 },
			{ 1010, 82, 40, bank = 10 },
			{ 950, 78, 130, bank = 8 },
			-- E
			{ 820, 66, 150 },
			{ 680, 54, 250, bank = -6 },
			{ 540, 46, 200, bank = 6 },
			{ 400, 40, 290, bank = -5 },
			{ 260, 36, 390 },
			-- F (다리)
			{ 130, 36, 430, bridge = true },
			{ 0, 36, 440, bridge = true },
			{ -130, 36, 440, bridge = true },
			-- G
			{ -300, 30, 470, bank = -6 },
			{ -470, 22, 570, bank = -10 },
			{ -550, 16, 730, bank = -8 },
			-- H
			{ -480, 12, 890, bank = -6 },
			{ -300, 10, 960 },
			{ -120, 10, 920, bank = -5 },
			{ 0, 10, 780 },
		},
	},
	{
		name = "CenterRing",
		closed = true,
		width = 46,
		points = ringPoints(RING_CENTER, RING_RADIUS, 16, 5),
	},
	-- 갈림길: O 자 → 고속도로
	{
		name = "SpokeWest",
		width = 40,
		points = {
			{ join = "CenterRing", near = { RING_CENTER.X - RING_RADIUS, RING_CENTER.Z } },
			{ join = "Highway", near = { 0, -230 } },
		},
	},
	{
		name = "SpokeNorth",
		width = 40,
		points = {
			{ join = "CenterRing", near = { RING_CENTER.X, RING_CENTER.Z - RING_RADIUS } },
			{ 330, 19, -620 },
			{ join = "Highway", near = { 420, -820 } },
		},
	},
	{
		name = "SpokeEast",
		width = 40,
		points = {
			{ join = "CenterRing", near = { RING_CENTER.X + RING_RADIUS, RING_CENTER.Z } },
			{ 650, 42, -270 },
			{ join = "Highway", near = { 760, -330 } },
		},
	},
	{
		name = "SpokeSouth",
		width = 40,
		points = {
			{ join = "CenterRing", near = { RING_CENTER.X, RING_CENTER.Z + RING_RADIUS } },
			{ 350, 30, 130 },
			{ join = "Highway", near = { 400, 290 } },
		},
	},
	-- 큰 우회로: 출발 직선 끝 → 서쪽 언덕 → G 커브 합류
	{
		name = "WestBypass",
		width = 46,
		points = {
			{ join = "Highway", near = { 0, -470 } },
			{ -200, 14, -540 },
			{ -450, 30, -460, bank = -6 },
			{ -650, 45, -220, bank = 6 },
			{ -720, 40, 100 },
			{ -640, 30, 360, bank = -6 },
			{ join = "Highway", near = { -470, 570 } },
		},
	},
}


local SPAWN = { position = Vector3.new(0, 11, 680), lookAt = Vector3.new(0, 11, 600) }

----------------------------------------------------------------------

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

-- Catmull-Rom 곡선 위의 점
local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

type Sample = { pos: Vector3, bank: number, bridge: boolean }

-- 점들을 부드러운 곡선으로 촘촘하게 나눔
local function sampleRoute(route): { Sample }
	local pts = route.points
	local n = #pts
	local function P(i: number): Vector3
		if route.closed then
			i = (i - 1) % n + 1
		else
			i = math.clamp(i, 1, n)
		end
		local p = pts[i]
		return Vector3.new(p[1], p[2], p[3])
	end
	local function info(i: number)
		if route.closed then
			i = (i - 1) % n + 1
		else
			i = math.clamp(i, 1, n)
		end
		return pts[i]
	end
	local samples: { Sample } = {}
	local last = route.closed and n or n - 1
	for i = 1, last do
		local p0, p1, p2, p3 = P(i - 1), P(i), P(i + 1), P(i + 2)
		local a, b = info(i), info(i + 1)
		local count = math.max(math.ceil((p2 - p1).Magnitude / STYLE.step), 1)
		for k = 0, count - 1 do
			local t = k / count
			-- 기울기는 부드럽게 (smoothstep)
			local s = t * t * (3 - 2 * t)
			table.insert(samples, {
				pos = catmull(p0, p1, p2, p3, t),
				bank = (a.bank or 0) * (1 - s) + (b.bank or 0) * s,
				bridge = (a.bridge == true) or (b.bridge == true),
			})
		end
	end
	if route.closed then
		table.insert(samples, samples[1])
	else
		local lp = pts[n]
		table.insert(samples, { pos = P(n), bank = lp.bank or 0, bridge = lp.bridge == true })
	end
	return samples
end

-- 한 조각의 방향 (오른쪽, 위, 앞) — 기울기(bank) 반영
local function frame(a: Vector3, b: Vector3, bankDeg: number)
	local fwd = (b - a).Unit
	local right = fwd:Cross(Vector3.yAxis)
	if right.Magnitude < 0.01 then
		right = Vector3.xAxis
	end
	right = right.Unit
	local up = right:Cross(fwd).Unit
	local r = math.rad(bankDeg)
	-- bank + 면 오른쪽이 낮아짐 (오른쪽 커브용)
	local right2 = (right * math.cos(r) - up * math.sin(r)).Unit
	local up2 = right2:Cross(fwd).Unit
	return right2, up2, fwd
end

type BuildOpts = {
	width: number,
	trimStart: number, -- 시작점에서 이 거리까지는 차선/가드레일 안 그림 (다른 길에 붙는 곳)
	trimEnd: number,
	lower: number, -- 갈림길은 아주 살짝 낮게 (붙는 큰 길 표면이 위로 오게 → 깜빡임 방지)
	openings: { { pos: Vector3, radius: number } }, -- 이 근처엔 가드레일/테두리선 없음 (갈림길 입구)
}

local function nearOpening(p: Vector3, openings): boolean
	for _, o in openings do
		if (Vector2.new(p.X, p.Z) - Vector2.new(o.pos.X, o.pos.Z)).Magnitude < o.radius then
			return true
		end
	end
	return false
end

local function buildRoute(parent: Instance, route, samples: { Sample }, opts: BuildOpts)
	local folder = Instance.new("Folder")
	folder.Name = route.name
	folder.Parent = parent
	local W = opts.width
	local S = STYLE.shoulder
	local halfTotal = W / 2 + S

	-- 누적 거리 (끝부분 차선 자르기용)
	local cum = { 0 }
	for i = 2, #samples do
		cum[i] = cum[i - 1] + (samples[i].pos - samples[i - 1].pos).Magnitude
	end
	local totalLen = cum[#samples]

	for i = 1, #samples - 1 do
		local A, B = samples[i], samples[i + 1]
		local a, b = A.pos, B.pos
		local len = (b - a).Magnitude
		if len < 0.1 then
			continue
		end
		local bank = (A.bank + B.bank) / 2
		local right, up, fwd = frame(a, b, bank)
		-- 커브 바깥쪽 틈 메우기: 다음 조각과 꺾인 각도만큼 길이를 늘림
		local nextS = samples[i + 2]
		local turn = 0
		if nextS then
			local f2 = (nextS.pos - b)
			if f2.Magnitude > 0.1 then
				turn = math.acos(math.clamp(fwd:Dot(f2.Unit), -1, 1))
			end
		end
		local extra = 0.6 + halfTotal * turn
		local mid = (a + b) / 2
		local function cf(offsetRight: number, offsetUp: number): CFrame
			local p = mid + right * offsetRight + up * (offsetUp + opts.lower)
			return CFrame.fromMatrix(p, right, up, -fwd)
		end
		local L = len + extra
		local inTrim = cum[i] < opts.trimStart or (totalLen - cum[i + 1]) < opts.trimEnd
		local atOpening = nearOpening(mid, opts.openings)

		-- 아스팔트 (윗면 = 도로 면)
		newPart(folder, "Road", Vector3.new(W, 1, L), cf(0, -0.5), STYLE.asphalt, Enum.Material.SmoothPlastic)
		-- 잔디 갓길 (아스팔트보다 살짝 아래, 양옆으로 넓게)
		newPart(folder, "Shoulder", Vector3.new(W + S * 2, 1, L), cf(0, -0.55), STYLE.grass, Enum.Material.SmoothPlastic)
		if not inTrim then
			-- 흰 테두리선 (갈림길 입구에선 끊김)
			if not atOpening then
				for _, side in { -1, 1 } do
					newPart(folder, "EdgeLine", Vector3.new(0.6, 0.08, L), cf(side * (W / 2 - 1.2), 0.04), STYLE.whiteLine)
				end
			end
			-- 노란 중앙 점선 (한 조각 건너 하나)
			if i % 2 == 0 then
				newPart(folder, "CenterDash", Vector3.new(0.6, 0.08, len * 0.7), cf(0, 0.04), STYLE.yellowLine)
			end
		end

		-- 아래: 다리는 바닥판, 아니면 바닥까지 내려가는 둑
		local roadY = mid.Y
		local heightAboveGround = roadY - STYLE.groundY
		if A.bridge or B.bridge then
			newPart(folder, "Deck", Vector3.new(W + S * 2, 2, L), cf(0, -2), STYLE.pillar, Enum.Material.Concrete)
		elseif heightAboveGround > 1.2 then
			-- 둑 윗면은 도로의 가장 낮은 가장자리보다 아래 (기울어진 커브에서 둑이 튀어나오지 않게)
			local lowEdgeDrop = halfTotal * math.sin(math.rad(math.abs(bank))) + 1.2
			local top = roadY - lowEdgeDrop
			local bottom = STYLE.groundY - 2
			if top > bottom + 0.5 then
				local center = Vector3.new(mid.X, (top + bottom) / 2, mid.Z)
				local flatFwd = Vector3.new(fwd.X, 0, fwd.Z)
				if flatFwd.Magnitude > 0.01 then
					local flatCF = CFrame.lookAt(center, center + flatFwd.Unit)
					newPart(folder, "Bank", Vector3.new(W + S * 2 - 1, top - bottom, L), flatCF, STYLE.cliff, Enum.Material.SmoothPlastic)
				end
			end
		end

		-- 가드레일: 다리, 기울어진 커브, 높은 구간 (갈림길 입구/붙는 끝부분은 비움)
		local needRail = A.bridge or B.bridge or math.abs(bank) > 3 or heightAboveGround > STYLE.railHeight
		if needRail and not inTrim and not atOpening then
			for _, side in { -1, 1 } do
				local x = side * (W / 2 + S - 1)
				newPart(folder, "Rail", Vector3.new(0.4, 0.9, L), cf(x, 2.4), STYLE.rail, Enum.Material.Metal)
				if i % 3 == 0 then
					newPart(folder, "RailPost", Vector3.new(0.5, 2.4, 0.5), cf(x, 1.2), STYLE.rail, Enum.Material.Metal)
				end
			end
		end
	end
	return #samples
end

-- 1단계: 모든 길의 모양을 먼저 계산 (갈림길이 붙을 위치 확정)
local function planRoutes()
	local plans = {}
	local byName = {}
	for _, route in ROUTES do
		local width = route.width or STYLE.roadWidth
		local resolved = {}
		local trimStart, trimEnd = 0, 0
		for idx, p in route.points do
			if p.join then
				local target = byName[p.join]
				assert(target, "[RoadBuilder] '" .. route.name .. "' 가 붙으려는 길 '" .. tostring(p.join) .. "' 이 먼저 정의돼야 해요")
				local best, bestD = nil, math.huge
				for _, s in target.samples do
					local d = (Vector2.new(s.pos.X, s.pos.Z) - Vector2.new(p.near[1], p.near[2])).Magnitude
					if d < bestD then
						best, bestD = s, d
					end
				end
				table.insert(resolved, { best.pos.X, best.pos.Y, best.pos.Z, bank = 0 })
				-- 붙는 큰 길 쪽: 입구 근처 가드레일/테두리선 비우기
				table.insert(target.openings, { pos = best.pos, radius = width / 2 + STYLE.shoulder + 12 })
				-- 이 길 쪽: 큰 길 위로 겹치는 끝부분엔 차선 안 그림
				local cut = target.width / 2 + STYLE.shoulder + 4
				if idx == 1 then
					trimStart = cut
				elseif idx == #route.points then
					trimEnd = cut
				end
			else
				table.insert(resolved, p)
			end
		end
		local r = table.clone(route)
		r.points = resolved
		local plan = {
			route = r,
			samples = sampleRoute(r),
			width = width,
			trimStart = trimStart,
			trimEnd = trimEnd,
			lower = (trimStart > 0 or trimEnd > 0) and -0.06 or 0,
			openings = {},
		}
		byName[route.name] = plan
		table.insert(plans, plan)
	end
	return plans
end

function RoadBuilder.Build()
	local recording = ChangeHistoryService:TryBeginRecording("RoadBuilder")
	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing.Name = "Map_backup_" .. os.time()
		existing.Parent = game:GetService("ServerStorage")
		warn("[RoadBuilder] 기존 맵을 ServerStorage." .. existing.Name .. " 로 옮겨 뒀어요 (지운 게 아님)")
	end
	workspace.StreamingEnabled = true

	local map = Instance.new("Folder")
	map.Name = "Map"

	-- 바닥 (넓은 잔디)
	newPart(map, "Ground", Vector3.new(4000, 4, 4000), CFrame.new(0, STYLE.groundY - 2, 0), STYLE.ground, Enum.Material.SmoothPlastic)

	local roads = Instance.new("Folder")
	roads.Name = "Roads"
	roads.Parent = map
	local total = 0
	-- 1단계: 모양 계산 (갈림길 위치 확정) → 2단계: 실제로 깔기 (입구엔 가드레일 비움)
	for _, plan in planRoutes() do
		total += buildRoute(roads, plan.route, plan.samples, {
			width = plan.width,
			trimStart = plan.trimStart,
			trimEnd = plan.trimEnd,
			lower = plan.lower,
			openings = plan.openings,
		})
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MainSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.lookAt(SPAWN.position, SPAWN.lookAt)
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
	print(string.format("[RoadBuilder] 완료: 도로 조각 %d개, 파트 %d개. 스폰 = Map.MainSpawn", total, parts))
end

return RoadBuilder
