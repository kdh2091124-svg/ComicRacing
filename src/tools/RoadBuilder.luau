-- 월드 생성기: 큰 오픈월드 도로망 + 중앙 도시 + 가파른 고갯길 산. Studio 명령줄에서 실행:
-- (:Clone() 을 꼭 붙이기 — 안 붙이면 명령줄이 예전 코드를 기억해서 수정이 반영 안 됨)
--
--   require(game.ServerStorage.Tools.RoadBuilder:Clone()).Build()
--
-- • 기존 Workspace.Map 은 지우지 않고 ServerStorage.Map_backup_시간 으로 옮겨 둠
-- • 지형(Terrain)은 새로 만듦 (기존 지형을 지움). 지형을 남기려면 Build({ keepTerrain = true })
-- • Ctrl+Z 로 되돌리기 가능
--
-- 길이 서로 막거나 끊기지 않게 하는 규칙 (자동):
--   1) 자동 다리: 다른 길 위를 지나는 구간은 아래를 채우지 않고 다리(바닥판)로 → 아래 길을 막지 않음
--   2) 자동 입구: 같은 높이로 다른 길이 닿는 곳(갈림길/교차로)은 가드레일/흰 테두리선을 비움
--   3) 갈림길 주변은 큰 길 기울기를 0 으로 펴서 단차 없앰
--   4) 경사 제한: 어떤 구간도 maxGrade 보다 가파르지 않게 높이를 자동으로 다듬음 (급경사로 길이 끊기지 않게)
--   5) 꺾이는 곳은 조각을 더 겹쳐서 틈이 안 생김
--   6) 길 아래는 지형(Terrain)으로 채움 (파트 벽 대신)
-- 생성이 끝나면 Output 에 "길 점검" 결과가 나옴 (길마다 최대 경사, 자동 다리, 입구 수)

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local RoadBuilder = {}

local STYLE = {
	roadWidth = 46,
	shoulder = 9,
	groundY = 0,
	asphalt = Color3.fromRGB(78, 80, 96),
	grass = Color3.fromRGB(110, 230, 120),
	whiteLine = Color3.fromRGB(245, 245, 245),
	yellowLine = Color3.fromRGB(255, 225, 40),
	rail = Color3.fromRGB(190, 195, 210),
	ground = Color3.fromRGB(95, 200, 105),
	deck = Color3.fromRGB(150, 155, 170),
	dirt = Color3.fromRGB(165, 125, 80), -- 비포장 지름길
	railWallHeight = 7, -- 가드레일 뒤 투명 벽 높이 (이보다 높이 날아야 밖으로 나감)
	junctionFlatRadius = 100, -- 갈림길 주변 이 거리 안은 큰 길 기울기 0 으로
	sameLevel = 4, -- 높이 차이가 이 안이면 "같은 높이로 닿음" → 입구
	underClear = 4, -- 다른 길이 이보다 낮으면 "아래 지나감" → 이 구간은 다리
	maxGrade = 16, -- 이보다 가파른 구간은 자동으로 높이를 다듬음 (도). 너무 가파른 곳 방지
	maxGradeWarn = 13, -- 점검: 이 각도보다 가파르면 표시
}

----------------------------------------------------------------------
-- 레이아웃
----------------------------------------------------------------------
local CITY_CENTER = Vector3.new(0, 24, 0)
local RING_RADIUS = 380

-- 바깥 월드 크기 배율 (도시는 그대로, 바깥 도로/산 위치만 줄이거나 늘림). 이동 시간이 길면 낮추기
local WORLD = 0.6
local function W(x: number, y: number, z: number, extra: { [string]: any }?)
	local p = { x * WORLD, y, z * WORLD }
	for k, v in extra or {} do
		p[k] = v
	end
	return p
end
local function near(x: number, z: number)
	return { x * WORLD, z * WORLD }
end

-- 고갯길 (북서쪽 산)
-- "거북이 그리기" 방식: 직선 몇 스터드, 반지름 몇으로 몇 도 회전 → 진짜 원호라서 헤어핀이 각지지 않고 U 자로 부드러움
local TOUGE = {
	base = Vector3.new(-1700 * WORLD, 50, -1850 * WORLD), -- 고속도로에서 갈라지는 곳 (여기서 산 쪽으로 출발)
	dir = Vector3.new(-1, 0, -1).Unit, -- 산꼭대기 방향
	startLateral = 0,
	pointSpacing = 6, -- 경로 점 간격
}

-- 명령: { "s", 길이, 경사 }            직선 (경사 0.25 ≈ 14°)
--       { "t", 각도, 반지름, 경사 }     회전 (+ 는 산 쪽으로 돌며 왼쪽, - 는 오른쪽. 헤어핀 = ±180)
--       { "mark", "이름" }              지름길 붙일 위치 표시
-- 헤어핀은 +180 / -180 을 번갈아 써야 계속 산 쪽으로 올라감
local TOUGE_PROGRAM = {
	-- 0) 고속도로에서 산으로 들어가는 진입로 → 오른쪽으로 돌며 첫 구간
	{ "s", 220, 0.03 },
	{ "t", -90, 140, 0.05 },
	-- 1) 완만한 S 스위퍼
	{ "s", 120, 0.08 },
	{ "t", 30, 300, 0.10 },
	{ "s", 80, 0.08 },
	{ "t", -30, 300, 0.10 },
	{ "s", 60, 0.08 },
	-- 2) 급한 U 헤어핀 (안쪽에 지름길 1)
	{ "mark", "cut1a" },
	{ "t", 180, 55, 0.12 },
	{ "mark", "cut1b" },
	-- 3) 가파른 직선 쫘아악
	{ "s", 300, 0.25 },
	-- 4) 넓게 도는 U 턴 (완만)
	{ "t", -180, 90, 0.08 },
	-- 5) 빠른 S 시케인
	{ "s", 40, 0.10 },
	{ "t", 35, 60, 0.12 },
	{ "t", -70, 60, 0.12 },
	{ "t", 35, 60, 0.12 },
	{ "s", 60, 0.10 },
	-- 6) 급한 U 헤어핀
	{ "t", 180, 50, 0.12 },
	-- 7) 쉬는 구간 (거의 평평)
	{ "s", 220, 0.03 },
	-- 8) U 헤어핀 (안쪽에 지름길 2)
	{ "mark", "cut2a" },
	{ "t", -180, 55, 0.12 },
	{ "mark", "cut2b" },
	-- 9) 가파른 직선 쫘아악
	{ "s", 300, 0.25 },
	-- 10) 연속 U 헤어핀
	{ "t", 180, 50, 0.12 },
	{ "s", 90, 0.12 },
	{ "t", -180, 50, 0.12 },
	-- 11) 긴 스위퍼로 꼭대기
	{ "s", 120, 0.10 },
	{ "t", 40, 200, 0.10 },
	{ "t", -40, 200, 0.10 },
	{ "s", 80, 0.05 },
}

local function ringPoints(center: Vector3, radius: number, count: number, bank: number)
	local pts = {}
	for k = 0, count - 1 do
		local a = k / count * math.pi * 2
		table.insert(pts, { center.X + math.cos(a) * radius, center.Y, center.Z + math.sin(a) * radius, bank = bank })
	end
	return pts
end


-- 고갯길 경로 만들기 → 월드 좌표 점 목록 + 지름길 위치(marks)
local function tougePath(): ({ any }, { [string]: Vector3 })
	local T = TOUGE
	local u = T.dir
	local v = Vector3.new(-u.Z, 0, u.X)
	local a, l, y = 0, T.startLateral, T.base.Y
	local heading = math.rad(90) -- 0 = 오른쪽(+좌우), 90° = 산 쪽. 고속도로에서 산 쪽을 보고 출발
	local pts = {}
	local marks: { [string]: Vector3 } = {}
	local function world(): Vector3
		local p = T.base + u * a + v * l
		return Vector3.new(p.X, y, p.Z)
	end
	local function emit()
		local p = world()
		table.insert(pts, { p.X, p.Y, p.Z })
	end
	for _, cmd in TOUGE_PROGRAM do
		if cmd[1] == "mark" then
			marks[cmd[2]] = world()
		elseif cmd[1] == "s" then
			local len, grade = cmd[2], cmd[3]
			local n = math.max(math.ceil(len / T.pointSpacing), 1)
			for _ = 1, n do
				local ds = len / n
				a += math.sin(heading) * ds
				l += math.cos(heading) * ds
				y += grade * ds
				emit()
			end
		elseif cmd[1] == "t" then
			local ang, r, grade = math.rad(cmd[2]), cmd[3], cmd[4]
			local arc = math.abs(ang) * r
			local n = math.max(math.ceil(arc / T.pointSpacing), 1)
			for _ = 1, n do
				local ds = arc / n
				heading += ang / n
				a += math.sin(heading) * ds
				l += math.cos(heading) * ds
				y += grade * ds
				emit()
			end
		end
	end
	return pts, marks
end

local TOUGE_POINTS, TOUGE_MARKS = tougePath()

-- 길 목록 (위에서부터 순서대로. 나중 길이 앞의 길에 join 으로 붙을 수 있음)
--   점: { x, 높이, z, bank = 기울기(도, + 면 오른쪽이 낮음), bridge = true }   (바깥 월드는 W(...) 로 써서 WORLD 배율 적용)
--       { join = "길 이름", near = { x, z } }
--   옵션: width, step(조각 길이), rails(true 항상 / false 없음), fill(false = 아래 지형 안 채움), closed
local ROUTES = {
	-- 바깥 순환 고속도로 (반시계: 남 → 동 → 북 → 서)
	{
		name = "Highway",
		closed = true,
		width = 58,
		step = 8,
		points = {
			W(0, 20, 2500),
			W(900, 28, 2380, { bank = -5 }),
			W(1750, 38, 1950, { bank = -8 }),
			W(2350, 48, 1250, { bank = -6 }),
			W(2600, 56, 450),
			W(2620, 74, 0), -- 언덕 꼭대기 (살짝 뜀)
			W(2600, 52, -500),
			W(2380, 44, -1300, { bank = -7 }),
			W(1850, 36, -2000, { bank = -8 }),
			W(1000, 30, -2450, { bank = -5 }),
			W(150, 32, -2580),
			W(-700, 40, -2450, { bank = -5 }),
			W(-1450, 50, -2050, { bank = -8 }),
			W(-2050, 46, -1350, { bank = -7 }),
			W(-2350, 40, -500),
			W(-2380, 34, 350),
			W(-2150, 28, 1150, { bank = -6 }),
			W(-1650, 24, 1900, { bank = -8 }),
			W(-850, 20, 2380, { bank = -5 }),
		},
	},
	{
		name = "CenterRing",
		closed = true,
		width = 46,
		step = 6,
		rails = false,
		points = ringPoints(CITY_CENTER, RING_RADIUS, 20, 4),
	},
	{
		name = "CityStreetNS",
		width = 40,
		step = 6,
		rails = false,
		fill = false,
		points = {
			{ join = "CenterRing", near = { CITY_CENTER.X, CITY_CENTER.Z - RING_RADIUS } },
			{ CITY_CENTER.X, CITY_CENTER.Y, CITY_CENTER.Z },
			{ join = "CenterRing", near = { CITY_CENTER.X, CITY_CENTER.Z + RING_RADIUS } },
		},
	},
	{
		name = "CityStreetEW",
		width = 40,
		step = 6,
		rails = false,
		fill = false,
		lowerExtra = -0.06,
		points = {
			{ join = "CenterRing", near = { CITY_CENTER.X - RING_RADIUS, CITY_CENTER.Z } },
			{ CITY_CENTER.X, CITY_CENTER.Y, CITY_CENTER.Z },
			{ join = "CenterRing", near = { CITY_CENTER.X + RING_RADIUS, CITY_CENTER.Z } },
		},
	},
	{
		name = "NorthRoad", -- 굽이치는 언덕길
		width = 44,
		step = 6,
		points = {
			{ join = "CenterRing", near = { 0, -RING_RADIUS } },
			W(60, 30, -1000),
			W(-160, 42, -1500, { bank = 6 }),
			W(120, 40, -2000, { bank = -6 }),
			{ join = "Highway", near = near(150, -2580) },
		},
	},
	{
		name = "EastRoad", -- 고속 직선 + 완만한 언덕
		width = 46,
		step = 8,
		points = {
			{ join = "CenterRing", near = { RING_RADIUS, 0 } },
			W(1100, 30, 40),
			W(1750, 40, -40),
			{ join = "Highway", near = near(2350, 1250) },
		},
	},
	{
		name = "SouthRoad", -- 해안 S 커브
		width = 44,
		step = 6,
		points = {
			{ join = "CenterRing", near = { 0, RING_RADIUS } },
			W(300, 22, 1050, { bank = 6 }),
			W(-280, 22, 1600, { bank = -7 }),
			W(220, 20, 2100, { bank = 6 }),
			{ join = "Highway", near = near(0, 2500) },
		},
	},
	{
		name = "WestRoad", -- 서쪽 들판길
		width = 44,
		step = 6,
		points = {
			{ join = "CenterRing", near = { -RING_RADIUS, 0 } },
			W(-1150, 30, 120),
			W(-1800, 36, -120, { bank = -5 }),
			{ join = "Highway", near = near(-2350, -500) },
		},
	},
	-- 고갯길 (다운힐)
	{
		name = "Touge",
		width = 34,
		step = 4,
		rails = true,
		points = (function()
			local pts = {
				{ join = "Highway", near = near(-1700, -1850) },
			}
			for _, p in TOUGE_POINTS do
				table.insert(pts, p)
			end
			return pts
		end)(),
	},
	-- 지름길: 헤어핀 안쪽을 가로지르는 비포장 샛길 (빠르지만 좁음)
	{
		name = "Shortcut1",
		width = 22,
		step = 4,
		style = "dirt",
		points = {
			{ join = "Touge", near = { TOUGE_MARKS.cut1a.X, TOUGE_MARKS.cut1a.Z } },
			{ join = "Touge", near = { TOUGE_MARKS.cut1b.X, TOUGE_MARKS.cut1b.Z } },
		},
	},
	{
		name = "Shortcut2",
		width = 22,
		step = 4,
		style = "dirt",
		points = {
			{ join = "Touge", near = { TOUGE_MARKS.cut2a.X, TOUGE_MARKS.cut2a.Z } },
			{ join = "Touge", near = { TOUGE_MARKS.cut2b.X, TOUGE_MARKS.cut2b.Z } },
		},
	},
}

----------------------------------------------------------------------
-- 기본 도구
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

local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

type Sample = { pos: Vector3, bank: number, bridge: boolean, opening: boolean, under: boolean }

local function sampleRoute(points, closed: boolean, step: number): { Sample }
	local n = #points
	local function idx(i: number): number
		if closed then
			return (i - 1) % n + 1
		end
		return math.clamp(i, 1, n)
	end
	local function P(i: number): Vector3
		local p = points[idx(i)]
		return Vector3.new(p[1], p[2], p[3])
	end
	local samples: { Sample } = {}
	local last = closed and n or n - 1
	for i = 1, last do
		local p0, p1, p2, p3 = P(i - 1), P(i), P(i + 1), P(i + 2)
		local a, b = points[idx(i)], points[idx(i + 1)]
		local count = math.max(math.ceil((p2 - p1).Magnitude / step), 1)
		for k = 0, count - 1 do
			local t = k / count
			local s = t * t * (3 - 2 * t)
			table.insert(samples, {
				pos = catmull(p0, p1, p2, p3, t),
				bank = (a.bank or 0) * (1 - s) + (b.bank or 0) * s,
				bridge = (a.bridge == true) or (b.bridge == true),
				opening = false,
				under = false,
			})
		end
	end
	if closed then
		local first = samples[1]
		table.insert(samples, { pos = first.pos, bank = first.bank, bridge = first.bridge, opening = false, under = false })
	else
		local lp = points[n]
		table.insert(samples, { pos = P(n), bank = lp.bank or 0, bridge = lp.bridge == true, opening = false, under = false })
	end
	return samples
end

-- 경사 제한: 앞 → 뒤, 뒤 → 앞으로 훑으며 이웃 조각과 높이 차이를 maxGrade 이하로 (양 끝 높이는 유지)
local function limitGrade(samples: { Sample })
	local g = math.tan(math.rad(STYLE.maxGrade))
	local function horiz(a: Vector3, b: Vector3): number
		return (Vector2.new(a.X, a.Z) - Vector2.new(b.X, b.Z)).Magnitude
	end
	for _ = 1, 2 do
		for i = 2, #samples - 1 do
			local prev, s = samples[i - 1].pos, samples[i].pos
			local m = g * horiz(prev, s)
			local y = math.clamp(s.Y, prev.Y - m, prev.Y + m)
			samples[i].pos = Vector3.new(s.X, y, s.Z)
		end
		for i = #samples - 1, 2, -1 do
			local nxt, s = samples[i + 1].pos, samples[i].pos
			local m = g * horiz(nxt, s)
			local y = math.clamp(s.Y, nxt.Y - m, nxt.Y + m)
			samples[i].pos = Vector3.new(s.X, y, s.Z)
		end
	end
end

local function frame(a: Vector3, b: Vector3, bankDeg: number)
	local fwd = (b - a).Unit
	local right = fwd:Cross(Vector3.yAxis)
	if right.Magnitude < 0.01 then
		right = Vector3.xAxis
	end
	right = right.Unit
	local up = right:Cross(fwd).Unit
	local r = math.rad(bankDeg)
	local right2 = (right * math.cos(r) - up * math.sin(r)).Unit
	local up2 = right2:Cross(fwd).Unit
	return right2, up2, fwd
end

----------------------------------------------------------------------
-- 1단계: 계획 (모양 계산, 갈림길 붙이기, 다리/입구 판정)
----------------------------------------------------------------------
type Plan = {
	route: any,
	samples: { Sample },
	width: number,
	half: number,
	trimStart: number,
	trimEnd: number,
	lower: number,
	joinPoints: { Vector3 },
}

local function planRoutes(): { Plan }
	local plans: { Plan } = {}
	local byName: { [string]: Plan } = {}
	for _, route in ROUTES do
		local width = route.width or STYLE.roadWidth
		local resolved = {}
		local trimStart, trimEnd = 0, 0
		for i, p in route.points do
			if p.join then
				local target = byName[p.join]
				assert(target, "[RoadBuilder] '" .. route.name .. "' 가 붙으려는 길 '" .. tostring(p.join) .. "' 이 먼저 있어야 해요")
				local best, bestD = target.samples[1], math.huge
				for _, s in target.samples do
					local d = (Vector2.new(s.pos.X, s.pos.Z) - Vector2.new(p.near[1], p.near[2])).Magnitude
					if d < bestD then
						best, bestD = s, d
					end
				end
				table.insert(resolved, { best.pos.X, best.pos.Y, best.pos.Z, bank = 0 })
				table.insert(target.joinPoints, best.pos)
				local cut = target.half + 4
				if i == 1 then
					trimStart = cut
				elseif i == #route.points then
					trimEnd = cut
				end
			else
				table.insert(resolved, p)
			end
		end
		local samples = sampleRoute(resolved, route.closed == true, route.step or 6)
		limitGrade(samples)
		local plan: Plan = {
			route = route,
			samples = samples,
			width = width,
			half = width / 2 + STYLE.shoulder,
			trimStart = trimStart,
			trimEnd = trimEnd,
			lower = ((trimStart > 0 or trimEnd > 0) and -0.06 or 0) + (route.lowerExtra or 0),
			joinPoints = {},
		}
		byName[route.name] = plan
		table.insert(plans, plan)
	end

	-- 공간 격자 (가까운 다른 길 조각 빨리 찾기)
	local CELL = 100
	local grid: { [string]: { { plan: Plan, s: Sample } } } = {}
	for _, plan in plans do
		for _, s in plan.samples do
			local k = math.floor(s.pos.X / CELL) .. "," .. math.floor(s.pos.Z / CELL)
			grid[k] = grid[k] or {}
			table.insert(grid[k], { plan = plan, s = s })
		end
	end

	-- 다른 길과의 관계: 같은 높이로 닿으면 입구, 다른 길이 아래로 지나가면 이 구간은 다리
	for _, plan in plans do
		for _, s in plan.samples do
			local cx, cz = math.floor(s.pos.X / CELL), math.floor(s.pos.Z / CELL)
			for dx = -1, 1 do
				for dz = -1, 1 do
					local list = grid[(cx + dx) .. "," .. (cz + dz)]
					if list then
						for _, o in list do
							if o.plan ~= plan then
								local horiz = (Vector2.new(s.pos.X, s.pos.Z) - Vector2.new(o.s.pos.X, o.s.pos.Z)).Magnitude
								if horiz < plan.half + o.plan.half + 6 then
									local dy = s.pos.Y - o.s.pos.Y
									if math.abs(dy) <= STYLE.sameLevel then
										s.opening = true
									elseif dy > STYLE.underClear then
										s.under = true
									end
								end
							end
						end
					end
				end
			end
		end
	end

	-- 갈림길 주변은 큰 길 기울기를 0 으로 부드럽게 (단차 방지)
	for _, plan in plans do
		for _, jp in plan.joinPoints do
			local R = plan.half + STYLE.junctionFlatRadius
			for _, s in plan.samples do
				local d = (Vector2.new(s.pos.X, s.pos.Z) - Vector2.new(jp.X, jp.Z)).Magnitude
				if d < R then
					local t = d / R
					s.bank *= t * t * (3 - 2 * t)
				end
			end
		end
	end
	return plans
end

----------------------------------------------------------------------
-- 2단계: 깔기
----------------------------------------------------------------------
type Fill = { cf: CFrame, size: Vector3 }

local function buildRoute(parent: Instance, plan: Plan, fills: { Fill }, carves: { Fill })
	local route = plan.route
	local folder = Instance.new("Folder")
	folder.Name = route.name
	folder.Parent = parent
	local samples = plan.samples
	local W = plan.width
	local S = STYLE.shoulder
	local half = plan.half

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
		-- 다음 조각과 꺾인 각도 (좌우 + 위아래). 꺾일수록 더 겹쳐서 틈 없게
		local nextS = samples[i + 2]
		local turn = 0
		if nextS then
			local f2 = nextS.pos - b
			if f2.Magnitude > 0.1 then
				turn = math.acos(math.clamp(fwd:Dot(f2.Unit), -1, 1))
			end
		end
		local L = len + 1 + half * turn
		local mid = (a + b) / 2
		local function cf(offRight: number, offUp: number): CFrame
			return CFrame.fromMatrix(mid + right * offRight + up * (offUp + plan.lower), right, up, -fwd)
		end
		local inTrim = cum[i] < plan.trimStart or (totalLen - cum[i + 1]) < plan.trimEnd
		local opening = A.opening or B.opening
		local isBridge = A.bridge or B.bridge or A.under or B.under

		local dirt = route.style == "dirt"
		-- 아스팔트는 두껍게(2) → 위아래로 꺾이는 곳에서도 틈이 안 보임 (비포장 지름길은 흙색)
		newPart(folder, "Road", Vector3.new(W, 2, L), cf(0, -1), dirt and STYLE.dirt or STYLE.asphalt, dirt and Enum.Material.Ground or nil)
		-- 도로 위 30 높이까지 지형 깎을 자리 (풀이 도로로 삐져나오지 않게)
		table.insert(carves, { cf = CFrame.fromMatrix(mid + up * 15.2, right, up, -fwd), size = Vector3.new(W + S * 2 + 4, 30, L + 1) })
		newPart(folder, "Shoulder", Vector3.new(W + S * 2, 2, L), cf(0, -1.05), STYLE.grass)
		if not inTrim and not dirt then
			if not opening then
				for _, side in { -1, 1 } do
					newPart(folder, "EdgeLine", Vector3.new(0.6, 0.08, L), cf(side * (W / 2 - 1.2), 0.04), STYLE.whiteLine)
				end
			end
			if i % 2 == 0 then
				newPart(folder, "CenterDash", Vector3.new(0.6, 0.08, len * 0.7), cf(0, 0.04), STYLE.yellowLine)
			end
		end

		if isBridge then
			newPart(folder, "Deck", Vector3.new(W + S * 2, 2, L), cf(0, -3), STYLE.deck, Enum.Material.Concrete)
		elseif route.fill ~= false and mid.Y - STYLE.groundY > 2 then
			local top = mid.Y - half * math.sin(math.rad(math.abs(bank))) - 3
			local bottom = STYLE.groundY - 2
			local flat = Vector3.new(fwd.X, 0, fwd.Z)
			if top > bottom + 2 and flat.Magnitude > 0.01 then
				local center = Vector3.new(mid.X, (top + bottom) / 2, mid.Z)
				table.insert(fills, { cf = CFrame.lookAt(center, center + flat.Unit), size = Vector3.new(W + S * 2 + 6, top - bottom, L + 2) })
			end
		end

		local needRail = route.rails == true or isBridge or math.abs(bank) > 3
		if route.rails ~= false and needRail and not inTrim and not opening then
			for _, side in { -1, 1 } do
				local x = side * (W / 2 + S - 1)
				-- 보이는 난간: 충돌 없음 (얇고 낮아서 차가 타고 넘거나 걸려서 튕겨 날아가던 원인)
				local rail = newPart(folder, "Rail", Vector3.new(0.4, 0.9, L), cf(x, 2.4), STYLE.rail, Enum.Material.Metal)
				rail.CanCollide = false
				if i % 3 == 0 then
					local post = newPart(folder, "RailPost", Vector3.new(0.5, 2.4, 0.5), cf(x, 1.2), STYLE.rail, Enum.Material.Metal)
					post.CanCollide = false
				end
				-- 실제로 막는 건 투명하고 매끈한 벽 (높이 RAIL_WALL). 웬만한 충돌은 벽 따라 긁고, 크게 날아올라야 넘어감
				local wall = newPart(folder, "RailWall", Vector3.new(1, STYLE.railWallHeight, L), cf(x + side * 0.5, STYLE.railWallHeight / 2), STYLE.rail)
				wall.Transparency = 1
				wall.CastShadow = false
				wall.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 100) -- 마찰 0, 튕김 0
			end
		end
	end
end

----------------------------------------------------------------------
-- 중앙 도시
----------------------------------------------------------------------
local CITY = {
	lotSpacing = 82,
	streetClear = 50,
	edgeClear = 70,
	minHeight = 35,
	maxHeight = 160,
	colors = {
		Color3.fromRGB(120, 215, 210),
		Color3.fromRGB(250, 170, 140),
		Color3.fromRGB(170, 160, 240),
		Color3.fromRGB(250, 220, 130),
		Color3.fromRGB(140, 190, 250),
		Color3.fromRGB(240, 150, 180),
		Color3.fromRGB(235, 235, 240),
	},
	window = Color3.fromRGB(45, 80, 190),
	roof = Color3.fromRGB(90, 95, 110),
	plaza = Color3.fromRGB(205, 200, 190),
}

local function makeSign(parent: Instance, cf: CFrame, size: Vector3, text: string, bg: Color3, fg: Color3)
	local board = newPart(parent, "Sign", size, cf, bg)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.PixelsPerStud = 20
		sg.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = fg
		label.Text = text
		label.Parent = sg
		sg.Parent = board
	end
end

local function makeBuilding(parent: Instance, base: Vector3, w: number, d: number, h: number, color: Color3)
	local m = Instance.new("Model")
	m.Name = "Building"
	newPart(m, "Body", Vector3.new(w, h, d), CFrame.new(base + Vector3.new(0, h / 2, 0)), color)
	local y = 10
	while y < h - 6 do
		newPart(m, "Windows", Vector3.new(w + 0.4, 4, d + 0.4), CFrame.new(base + Vector3.new(0, y, 0)), CITY.window, Enum.Material.Glass)
		y += 13
	end
	newPart(m, "Roof", Vector3.new(w + 2, 2, d + 2), CFrame.new(base + Vector3.new(0, h + 1, 0)), CITY.roof)
	m.Parent = parent
end

-- 딜러샵: 유리 전시장 + 간판 + 차 전시대 3개 (상점 UI 연결용 Attribute: DealerShop, DisplaySlot)
local function makeDealer(parent: Instance, base: Vector3, facing: Vector3)
	local m = Instance.new("Model")
	m.Name = "DealerShop"
	m:SetAttribute("DealerShop", true)
	local W, D, H = 110, 70, 28
	local look = CFrame.lookAt(base, base + facing)
	local function at(x: number, y: number, z: number): CFrame
		return look * CFrame.new(x, y, z)
	end
	newPart(m, "Floor", Vector3.new(W, 1, D), at(0, 0.5, 0), Color3.fromRGB(235, 235, 240))
	newPart(m, "BackWall", Vector3.new(W, H, 2), at(0, H / 2, D / 2), Color3.fromRGB(40, 45, 60))
	newPart(m, "SideWall", Vector3.new(2, H, D), at(-W / 2, H / 2, 0), Color3.fromRGB(40, 45, 60))
	newPart(m, "SideWall", Vector3.new(2, H, D), at(W / 2, H / 2, 0), Color3.fromRGB(40, 45, 60))
	local glass = newPart(m, "Glass", Vector3.new(W, H - 6, 0.6), at(0, (H - 6) / 2 + 1, -D / 2), Color3.fromRGB(170, 220, 255), Enum.Material.Glass)
	glass.Transparency = 0.6
	glass.CanCollide = false
	newPart(m, "Roof", Vector3.new(W + 4, 3, D + 4), at(0, H + 1.5, 0), Color3.fromRGB(255, 190, 40))
	makeSign(m, at(0, H + 9, -D / 2 - 1), Vector3.new(W * 0.8, 10, 1), "CAR DEALER", Color3.fromRGB(255, 190, 40), Color3.fromRGB(30, 30, 40))
	for k = -1, 1 do
		local pad = newPart(m, "DisplayPad", Vector3.new(1, 22, 22), at(k * 34, 1.2, 4) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(80, 220, 255), Enum.Material.Neon)
		pad.Shape = Enum.PartType.Cylinder
		pad:SetAttribute("DisplaySlot", k + 2)
	end
	m.Parent = parent
end

local function buildCity(map: Instance): CFrame
	local city = Instance.new("Folder")
	city.Name = "City"
	city.Parent = map
	local c = CITY_CENTER
	local innerR = RING_RADIUS - 23 - STYLE.shoulder

	local plateau = newPart(city, "Plateau", Vector3.new(c.Y - STYLE.groundY + 2, innerR * 2 + 4, innerR * 2 + 4),
		CFrame.new(c.X, (c.Y + STYLE.groundY) / 2 - 1.05, c.Z) * CFrame.Angles(0, 0, math.rad(90)), CITY.plaza, Enum.Material.Concrete)
	plateau.Shape = Enum.PartType.Cylinder

	local dealerBase = c + Vector3.new(105, 0, RING_RADIUS * 0.55)
	makeDealer(city, dealerBase, Vector3.new(-1, 0, 0))

	local rng = Random.new(1118)
	local buildings = Instance.new("Folder")
	buildings.Name = "Buildings"
	buildings.Parent = city
	local reach = innerR - CITY.edgeClear
	for gx = -reach, reach, CITY.lotSpacing do
		for gz = -reach, reach, CITY.lotSpacing do
			local p = Vector3.new(gx, 0, gz)
			if p.Magnitude > reach or math.abs(gx) < CITY.streetClear or math.abs(gz) < CITY.streetClear then
				continue
			end
			if (c + p - dealerBase).Magnitude < 115 then
				continue
			end
			local w = rng:NextInteger(36, 58)
			local d = rng:NextInteger(36, 58)
			makeBuilding(buildings, c + p, w, d, rng:NextInteger(CITY.minHeight, CITY.maxHeight), CITY.colors[rng:NextInteger(1, #CITY.colors)])
		end
	end

	local spawnPos = Vector3.new(c.X, c.Y + 1, dealerBase.Z + 20)
	return CFrame.lookAt(spawnPos, spawnPos + Vector3.new(0, 0, -1))
end

----------------------------------------------------------------------
-- 지형: 고갯길 산 + 길 아래 채우기
----------------------------------------------------------------------
local function buildTerrain(fills: { Fill }, carves: { Fill }, tougeSamples: { Sample })
	local terrain = workspace.Terrain
	-- 고갯길 산: 꼭대기에서 멀어질수록 낮아지는 원뿔.
	-- 실제 고갯길 모든 점을 검사해서, 어디서든 길보다 15 이상 낮도록 기울기를 자동으로 정함 (산이 길을 덮지 않음)
	local summitSample = tougeSamples[#tougeSamples].pos
	local summit = Vector3.new(summitSample.X, 0, summitSample.Z)
	local peakH = summitSample.Y - 40
	local slope = 0.3
	for _, s in tougeSamples do
		local d = (Vector2.new(s.pos.X, s.pos.Z) - Vector2.new(summit.X, summit.Z)).Magnitude
		if d > 1 then
			slope = math.max(slope, (peakH - (s.pos.Y - 15)) / d)
		end
	end
	local maxR = peakH / slope
	local steps = 50
	for k = 0, steps - 1 do
		local r = maxR * (1 - k / steps)
		local h = math.max(peakH - slope * r, 4)
		local mat = (k > steps * 0.7) and Enum.Material.Rock or ((k > steps * 0.35) and Enum.Material.Ground or Enum.Material.Grass)
		terrain:FillCylinder(CFrame.new(summit.X, STYLE.groundY + h / 2 - 2, summit.Z), h, r, mat)
	end
	for _, f in fills do
		terrain:FillBlock(f.cf, f.size, Enum.Material.Grass)
	end
	-- 도로 위 공간의 지형(풀)을 깎아냄: 산비탈이나 둑이 도로/갓길 위로 삐져나오지 않게
	for _, c in carves do
		terrain:FillBlock(c.cf, c.size, Enum.Material.Air)
	end
end

----------------------------------------------------------------------
-- 점검 보고
----------------------------------------------------------------------
local function report(plans: { Plan })
	print("[RoadBuilder] ===== 길 점검 =====")
	for _, plan in plans do
		local maxGrade, bridges, openings = 0, 0, 0
		local steepAt: Vector3? = nil
		for i = 1, #plan.samples - 1 do
			local a, b = plan.samples[i].pos, plan.samples[i + 1].pos
			local horiz = (Vector2.new(a.X, a.Z) - Vector2.new(b.X, b.Z)).Magnitude
			if horiz > 0.1 then
				local g = math.deg(math.atan(math.abs(b.Y - a.Y) / horiz))
				if g > maxGrade then
					maxGrade, steepAt = g, a
				end
			end
			if plan.samples[i].under then
				bridges += 1
			end
			if plan.samples[i].opening then
				openings += 1
			end
		end
		print(string.format("  %-14s 최대 경사 %4.1f°%s  자동 다리 %d조각  입구 %d조각", plan.route.name, maxGrade,
			maxGrade > STYLE.maxGradeWarn and " (가파름)" or "", bridges, openings))
		if steepAt and maxGrade > STYLE.maxGradeWarn then
			print(string.format("      가장 가파른 곳: (%d, %d, %d)", steepAt.X, steepAt.Y, steepAt.Z))
		end
	end
	print(string.format("  경사 상한 %d° (이보다 가파른 곳은 자동으로 다듬어서 길이 끊기지 않음)", STYLE.maxGrade))
end

----------------------------------------------------------------------

function RoadBuilder.Build(options: { keepTerrain: boolean? }?)
	local recording = ChangeHistoryService:TryBeginRecording("RoadBuilder")
	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing.Name = "Map_backup_" .. os.time()
		existing.Parent = game:GetService("ServerStorage")
		warn("[RoadBuilder] 기존 맵을 ServerStorage." .. existing.Name .. " 로 옮겨 뒀어요 (지운 게 아님)")
	end
	if not (options and options.keepTerrain) then
		workspace.Terrain:Clear()
	end
	workspace.StreamingEnabled = true

	local map = Instance.new("Folder")
	map.Name = "Map"
	newPart(map, "Ground", Vector3.new(14000, 4, 14000), CFrame.new(0, STYLE.groundY - 2, 0), STYLE.ground)

	local roads = Instance.new("Folder")
	roads.Name = "Roads"
	roads.Parent = map
	local plans = planRoutes()
	local fills: { Fill } = {}
	local carves: { Fill } = {}
	for _, plan in plans do
		buildRoute(roads, plan, fills, carves)
	end

	local spawnCF = buildCity(map)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MainSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = spawnCF
	spawn.Color = Color3.fromRGB(80, 200, 255)
	spawn.Parent = map

	map.Parent = workspace
	local tougeSamples = {}
	for _, plan in plans do
		if plan.route.name == "Touge" then
			tougeSamples = plan.samples
		end
	end
	buildTerrain(fills, carves, tougeSamples)

	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	local parts = 0
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format("[RoadBuilder] 완료: 파트 %d개, 지형 채우기 %d곳. 스폰 = 도시 딜러샵 앞", parts, #fills))
	report(plans)
end

return RoadBuilder
