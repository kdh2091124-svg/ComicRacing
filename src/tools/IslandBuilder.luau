-- 섬 월드 생성기 (오리지널 배치): 바다로 둘러싼 섬 하나에
--   남쪽 해안 바둑판 도심(대로, 해변 도로, 부두, 딜러샵) / 도심 북쪽 강과 다리 /
--   북동쪽 설산 고갯길 + 북서쪽 서킷 / 서쪽 해안도로 + 긴 다리 + 공항 활주로 + 숲 / 동쪽 사막 협곡
-- Studio 명령줄 (:Clone() 꼭 붙이기):
--
--   require(game.ServerStorage.Tools.IslandBuilder:Clone()).Build()
--
-- • 기존 Workspace.Map 은 ServerStorage 로 백업, 지형(Terrain)은 새로 만듦
-- • 길 까는 기술은 RoadEngine 모듈 (자동 다리/입구, U 자 헤어핀, 경사 상한, 지형 채우기/깎기)
-- • 좌표: x = 동(+)/서(-), z = 남(+)/북(-), 땅 높이 4, 바다 수면 1

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Tools = game:GetService("ServerStorage"):WaitForChild("Tools")
local E = require(Tools:WaitForChild("RoadEngine"):Clone()) -- 명령줄 캐시 피하려고 복제해서 읽음
local newPart = E.newPart

local IslandBuilder = {}

local LAND_Y = 4 -- 땅 윗면
local SEA_Y = 1 -- 바다 수면
local SEA_FLOOR = -30
local CY = 4.5 -- 도심 도로 높이

local COLORS = {
	ocean = Color3.fromRGB(60, 140, 220),
	seaFloor = Color3.fromRGB(230, 200, 150),
	sidewalk = Color3.fromRGB(205, 205, 210),
	desertShoulder = Color3.fromRGB(230, 170, 110),
	terrain = {
		[Enum.Material.Grass] = Color3.fromRGB(110, 200, 90),
		[Enum.Material.Sand] = Color3.fromRGB(250, 220, 175),
		[Enum.Material.Sandstone] = Color3.fromRGB(235, 125, 75), -- 사막 (주황)
		[Enum.Material.Rock] = Color3.fromRGB(115, 100, 90),
		[Enum.Material.Ground] = Color3.fromRGB(130, 100, 70),
	},
	buildings = {
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
}

----------------------------------------------------------------------
-- 땅 (둥근 모서리 직사각형들) — 사이사이 빈 곳은 바다/강
----------------------------------------------------------------------
local LAND = {
	{ name = "City", x0 = -1000, x1 = 1050, z0 = 220, z1 = 860, mat = Enum.Material.Grass, r = 140 },
	{ name = "Beach", x0 = -1000, x1 = 1050, z0 = 820, z1 = 960, mat = Enum.Material.Sand, r = 120, top = 2.5 },
	{ name = "North", x0 = -750, x1 = 1350, z0 = -1500, z1 = -80, mat = Enum.Material.Grass, r = 220 },
	{ name = "West", x0 = -2300, x1 = -1250, z0 = -1500, z1 = 1150, mat = Enum.Material.Grass, r = 260 },
	{ name = "WestBeach", x0 = -2420, x1 = -2250, z0 = -1300, z1 = 1000, mat = Enum.Material.Sand, r = 80, top = 2.5 },
	{ name = "East", x0 = 1050, x1 = 2700, z0 = -1500, z1 = 1000, mat = Enum.Material.Sandstone, r = 260 },
}

local function roundedRect(L)
	local terrain = workspace.Terrain
	local top = L.top or LAND_Y
	local h = top - SEA_FLOOR
	local cy = SEA_FLOOR + h / 2
	local r = math.min(L.r, (L.x1 - L.x0) / 2, (L.z1 - L.z0) / 2)
	local cx, cz = (L.x0 + L.x1) / 2, (L.z0 + L.z1) / 2
	local w, d = L.x1 - L.x0, L.z1 - L.z0
	terrain:FillBlock(CFrame.new(cx, cy, cz), Vector3.new(w - 2 * r, h, d), L.mat)
	terrain:FillBlock(CFrame.new(cx, cy, cz), Vector3.new(w, h, d - 2 * r), L.mat)
	for _, c in { { L.x0 + r, L.z0 + r }, { L.x1 - r, L.z0 + r }, { L.x0 + r, L.z1 - r }, { L.x1 - r, L.z1 - r } } do
		terrain:FillCylinder(CFrame.new(c[1], cy, c[2]), h, r, L.mat)
	end
end

----------------------------------------------------------------------
-- 길
----------------------------------------------------------------------
local AVENUE_X = { -700, -350, 0, 350, 700 }

-- 북쪽 고갯길 (설산): 구간마다 성격이 다름, 헤어핀은 진짜 U 자
local TOUGE_SPEC = {
	base = Vector3.new(0, CY, -400),
	dir = Vector3.new(0, 0, -1), -- 북쪽이 산
	startLateral = 0,
	headingDeg = 90, -- 산 쪽을 보고 출발
	spacing = 6,
	program = {
		{ "s", 160, 0.02 }, -- 진입로
		{ "t", -90, 120, 0.04 }, -- 오른쪽으로 돌며 첫 구간
		{ "s", 100, 0.08 }, -- 완만한 S 스위퍼
		{ "t", 30, 260, 0.10 },
		{ "t", -30, 260, 0.10 },
		{ "mark", "cut1a" },
		{ "t", 180, 55, 0.12 }, -- U 헤어핀 (안쪽 지름길)
		{ "mark", "cut1b" },
		{ "s", 280, 0.25 }, -- 가파른 직선
		{ "t", -180, 85, 0.08 }, -- 넓은 U 턴
		{ "s", 40, 0.10 }, -- S 시케인
		{ "t", 35, 60, 0.12 },
		{ "t", -70, 60, 0.12 },
		{ "t", 35, 60, 0.12 },
		{ "s", 50, 0.10 },
		{ "t", 180, 50, 0.12 }, -- U 헤어핀
		{ "s", 200, 0.03 }, -- 쉬는 구간
		{ "mark", "cut2a" },
		{ "t", -180, 55, 0.12 }, -- U 헤어핀 (안쪽 지름길)
		{ "mark", "cut2b" },
		{ "s", 280, 0.25 }, -- 가파른 직선
		{ "t", 180, 50, 0.12 }, -- 연속 U 헤어핀
		{ "s", 80, 0.12 },
		{ "t", -180, 50, 0.12 },
		{ "s", 100, 0.10 }, -- 스위퍼로 꼭대기
		{ "t", 40, 180, 0.10 },
		{ "t", -40, 180, 0.10 },
		{ "s", 80, 0.04 },
	},
}

local function cityStreet(name: string, z: number, x0: number, x1: number, width: number)
	return {
		name = name,
		width = width,
		step = 8,
		rails = false,
		fill = false,
		shoulderColor = COLORS.sidewalk,
		points = { { x0, CY, z }, { (x0 + x1) / 2, CY, z }, { x1, CY, z } },
	}
end

local function buildRoutes(): { any }
	local touge, marks = E.turtle(TOUGE_SPEC)
	local routes = {
		-- 도심 가로(동서) 도로
		cityStreet("NorthEdge", 300, -900, 1000, 34),
		cityStreet("Boulevard", 470, -1000, 1050, 56), -- 대로
		cityStreet("MidStreet", 640, -900, 950, 34),
		cityStreet("BeachRoad", 800, -950, 1000, 40),
	}
	-- 도심 세로(남북) 도로
	for i, x in AVENUE_X do
		table.insert(routes, {
			name = "Avenue" .. i,
			width = 34,
			step = 8,
			rails = false,
			fill = false,
			lowerExtra = -0.04, -- 교차로에서 가로 도로가 위로 (깜빡임 방지)
			shoulderColor = COLORS.sidewalk,
			points = { { x, CY, 300 }, { x, CY, 550 }, { x, CY, 800 } },
		})
	end
	-- 부두 (해변 도로 → 바다 쪽으로 쭉, 나무 바닥)
	table.insert(routes, {
		name = "Pier",
		width = 30,
		shoulder = 0,
		step = 8,
		style = "wood",
		rails = true,
		points = {
			{ join = "BeachRoad", near = { 0, 800 } },
			{ 0, 5, 880 },
			{ 0, 6, 980, bridge = true },
			{ 0, 6, 1260, bridge = true },
		},
	})
	-- 북쪽: 강 건너는 다리 → 고갯길 입구
	table.insert(routes, {
		name = "NorthRoad",
		width = 44,
		step = 6,
		points = {
			{ join = "Avenue3", near = { 0, 300 } },
			{ 0, 9, 200, bridge = true },
			{ 0, 14, 70, bridge = true },
			{ 0, 9, -60, bridge = true },
			{ 0, 5, -200 },
			{ 0, CY, -400 },
		},
	})
	-- 고갯길
	local tougePts = { { join = "NorthRoad", near = { 0, -400 } } }
	for _, p in touge do
		table.insert(tougePts, p)
	end
	table.insert(routes, { name = "Touge", width = 34, step = 4, rails = true, points = tougePts })
	for _, k in { "1", "2" } do
		local a, b = marks["cut" .. k .. "a"], marks["cut" .. k .. "b"]
		table.insert(routes, {
			name = "TougeShortcut" .. k,
			width = 22,
			step = 4,
			style = "dirt",
			points = {
				{ join = "Touge", near = { a.X, a.Z } },
				{ join = "Touge", near = { b.X, b.Z } },
			},
		})
	end
	-- 서킷 (북서쪽, 산 반대편)
	table.insert(routes, {
		name = "Racetrack",
		closed = true,
		width = 40,
		step = 5,
		rails = true,
		points = {
			{ -650, CY, -180 },
			{ -200, CY, -180 },
			{ -130, CY, -250, bank = -6 },
			{ -150, CY, -450, bank = -6 },
			{ -290, CY, -490 },
			{ -360, CY, -400 },
			{ -470, CY, -530, bank = -5 },
			{ -620, CY, -500, bank = -6 },
			{ -690, CY, -350, bank = -6 },
		},
	})
	table.insert(routes, {
		name = "TrackAccess",
		width = 36,
		step = 6,
		points = {
			{ join = "NorthRoad", near = { 0, -330 } },
			{ -65, CY, -335 },
			{ join = "Racetrack", near = { -140, -340 } },
		},
	})
	-- 서쪽 해안도로 (공항 옆)
	table.insert(routes, {
		name = "WestCoast",
		width = 50,
		step = 8,
		points = {
			{ -1450, CY, 1050 },
			{ -1560, CY, 600 },
			{ -1500, 6, 100 },
			{ -1620, 8, -400, bank = -6 },
			{ -1500, 10, -900 },
			{ -1350, 8, -1350 },
		},
	})
	-- 긴 다리: 대로 서쪽 끝 → 해협 건너 → 서쪽 해안도로
	table.insert(routes, {
		name = "WestBridge",
		width = 50,
		step = 6,
		points = {
			{ join = "Boulevard", near = { -1000, 470 } },
			{ -1080, 8, 480, bridge = true },
			{ -1180, 14, 520, bridge = true },
			{ -1280, 10, 560, bridge = true },
			{ join = "WestCoast", near = { -1450, 620 } },
		},
	})
	table.insert(routes, {
		name = "AirportRoad",
		width = 36,
		step = 6,
		points = {
			{ join = "WestCoast", near = { -1500, -250 } },
			{ -1700, CY, -250 },
			{ -1900, CY, -250 }, -- 활주로 가장자리까지
		},
	})
	-- 동쪽 사막 협곡
	table.insert(routes, {
		name = "DesertRoad",
		width = 46,
		step = 8,
		shoulderColor = COLORS.desertShoulder,
		fillMaterial = Enum.Material.Sandstone,
		points = {
			{ join = "Boulevard", near = { 1050, 470 } },
			{ 1300, 6, 430 },
			{ 1550, 12, 260, bank = -6 },
			{ 1720, 18, -40, bank = -6 },
			{ 1950, 24, -220 },
			{ 2150, 20, -520, bank = 6 },
			{ 2320, 16, -850 },
			{ 2200, 12, -1200 },
		},
	})
	table.insert(routes, {
		name = "CanyonRun",
		width = 40,
		step = 6,
		shoulderColor = COLORS.desertShoulder,
		fillMaterial = Enum.Material.Sandstone,
		points = {
			{ join = "DesertRoad", near = { 1720, -40 } },
			{ 2000, 10, 300, bank = 6 },
			{ 2300, 16, 560 },
			{ 2520, 22, 220, bank = 6 },
			{ 2420, 26, -160, bank = 6 },
			{ join = "DesertRoad", near = { 2150, -520 } },
		},
	})
	return routes
end

----------------------------------------------------------------------
-- 도심 블록 채우기
----------------------------------------------------------------------
local function makeBuilding(parent: Instance, base: Vector3, w: number, d: number, h: number, color: Color3)
	local m = Instance.new("Model")
	m.Name = "Building"
	newPart(m, "Body", Vector3.new(w, h, d), CFrame.new(base + Vector3.new(0, h / 2, 0)), color)
	local y = 10
	while y < h - 6 do
		newPart(m, "Windows", Vector3.new(w + 0.4, 4, d + 0.4), CFrame.new(base + Vector3.new(0, y, 0)), COLORS.window, Enum.Material.Glass)
		y += 13
	end
	newPart(m, "Roof", Vector3.new(w + 2, 2, d + 2), CFrame.new(base + Vector3.new(0, h + 1, 0)), COLORS.roof)
	m.Parent = parent
end

local function makeTree(parent: Instance, ground: Vector3, s: number, palm: boolean?)
	local m = Instance.new("Model")
	m.Name = palm and "Palm" or "Tree"
	local h = (palm and 22 or 14) * s
	newPart(m, "Trunk", Vector3.new(1.6 * s, h, 1.6 * s), CFrame.new(ground + Vector3.new(0, h / 2, 0)), Color3.fromRGB(120, 85, 50), Enum.Material.Wood)
	if palm then
		for k = 0, 3 do
			newPart(m, "Leaf", Vector3.new(12 * s, 0.8, 3 * s), CFrame.new(ground + Vector3.new(0, h, 0)) * CFrame.Angles(0, math.rad(k * 45), math.rad(12)), Color3.fromRGB(60, 170, 70), Enum.Material.Grass)
		end
	else
		local leaves = newPart(m, "Leaves", Vector3.one * 12 * s, CFrame.new(ground + Vector3.new(0, h + 3 * s, 0)), Color3.fromRGB(60, 150, 60), Enum.Material.Grass)
		leaves.Shape = Enum.PartType.Ball
	end
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
	E.makeSign(m, at(0, H + 9, -D / 2 - 1), Vector3.new(W * 0.8, 10, 1), "CAR DEALER", Color3.fromRGB(255, 190, 40), Color3.fromRGB(30, 30, 40))
	for k = -1, 1 do
		local pad = newPart(m, "DisplayPad", Vector3.new(1, 22, 22), at(k * 34, 1.2, 4) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(80, 220, 255), Enum.Material.Neon)
		pad.Shape = Enum.PartType.Cylinder
		pad:SetAttribute("DisplaySlot", k + 2)
	end
	m.Parent = parent
end

local BLOCK_X = { -900, -700, -350, 0, 350, 700, 950 }
local BLOCK_Z = { 300, 470, 640, 800 }
-- 특별한 블록: [가로칸 번호..","..세로칸 번호] = 종류 (나머지는 빌딩)
local SPECIAL = {
	["4,3"] = "dealer", -- 0~350, 640~800 (해변 쪽, 스폰 근처)
	["3,3"] = "park", -- 공원 + 연못
	["3,2"] = "plaza", -- 광장 + 분수
	["4,2"] = "dome", -- 둥근 돔
	["2,2"] = "glassTower", -- 파란 유리 큐브
	["5,3"] = "parking", -- 주차장
	["1,1"] = "park",
}

local function fillBlocks(parent: Instance): CFrame
	local rng = Random.new(2026)
	local inset = 40
	local spawnCF = CFrame.new(265, LAND_Y + 1.4, 720)
	for xi = 1, #BLOCK_X - 1 do
		for zi = 1, #BLOCK_Z - 1 do
			local x0, x1 = BLOCK_X[xi] + inset, BLOCK_X[xi + 1] - inset
			local z0, z1 = BLOCK_Z[zi] + inset, BLOCK_Z[zi + 1] - inset
			if x1 - x0 < 30 or z1 - z0 < 30 then
				continue
			end
			local c = Vector3.new((x0 + x1) / 2, LAND_Y, (z0 + z1) / 2)
			local w, d = x1 - x0, z1 - z0
			local kind = SPECIAL[xi .. "," .. zi] or "buildings"
			local block = Instance.new("Folder")
			block.Name = "Block_" .. xi .. "_" .. zi .. "_" .. kind
			block.Parent = parent
			-- 블록 바닥 (보도 색)
			newPart(block, "Lot", Vector3.new(w, 1, d), CFrame.new(c + Vector3.new(0, 0.4, 0)), COLORS.sidewalk, Enum.Material.Concrete)
			if kind == "dealer" then
				makeDealer(block, c + Vector3.new(0, 0.9, 0), Vector3.new(0, 0, 1)) -- 유리 앞면이 해변 도로 쪽
				local sp = Vector3.new(c.X + 90, LAND_Y + 1.4, c.Z) -- 전시장 옆 (길 위에 두면 턱이 생김)
				spawnCF = CFrame.lookAt(sp, sp + Vector3.new(0, 0, 1))
			elseif kind == "park" then
				newPart(block, "Grass", Vector3.new(w, 1, d), CFrame.new(c + Vector3.new(0, 0.7, 0)), Color3.fromRGB(110, 200, 90), Enum.Material.Grass)
				local pond = newPart(block, "Pond", Vector3.new(1, math.min(w, d) * 0.5, math.min(w, d) * 0.5), CFrame.new(c + Vector3.new(0, 1.25, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 160, 230), Enum.Material.Glass)
				pond.Shape = Enum.PartType.Cylinder
				for _ = 1, 8 do
					local p = c + Vector3.new(rng:NextNumber(-w / 2, w / 2), 1.2, rng:NextNumber(-d / 2, d / 2))
					if (p - c).Magnitude > math.min(w, d) * 0.3 then
						makeTree(block, p, rng:NextNumber(0.8, 1.2))
					end
				end
			elseif kind == "plaza" then
				local f = newPart(block, "Fountain", Vector3.new(4, 30, 30), CFrame.new(c + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(240, 240, 245), Enum.Material.Marble)
				f.Shape = Enum.PartType.Cylinder
				local water = newPart(block, "Water", Vector3.new(1, 26, 26), CFrame.new(c + Vector3.new(0, 4.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(90, 180, 240), Enum.Material.Glass)
				water.Shape = Enum.PartType.Cylinder
			elseif kind == "dome" then
				local r = math.min(w, d) * 0.45
				newPart(block, "DomeBase", Vector3.new(r * 2, 14, r * 2), CFrame.new(c + Vector3.new(0, 7.9, 0)), Color3.fromRGB(235, 235, 240))
				local dome = newPart(block, "Dome", Vector3.one * r * 2, CFrame.new(c + Vector3.new(0, 14.9, 0)), Color3.fromRGB(250, 250, 255), Enum.Material.SmoothPlastic)
				dome.Shape = Enum.PartType.Ball
			elseif kind == "glassTower" then
				local s = math.min(w, d) * 0.7
				newPart(block, "Tower", Vector3.new(s, 120, s), CFrame.new(c + Vector3.new(0, 60.9, 0)), Color3.fromRGB(60, 110, 200), Enum.Material.Glass)
			elseif kind == "parking" then
				for k = -3, 3 do
					newPart(block, "Stripe", Vector3.new(0.6, 0.1, d * 0.4), CFrame.new(c + Vector3.new(k * (w / 8), 0.95, 0)), Color3.new(1, 1, 1))
				end
			else
				-- 빌딩 2~4채
				local n = rng:NextInteger(2, 4)
				for k = 1, n do
					local bw = (w / n) * 0.8
					local bx = x0 + (k - 0.5) * (w / n)
					local bd = d * rng:NextNumber(0.6, 0.9)
					makeBuilding(block, Vector3.new(bx, LAND_Y + 0.9, c.Z), bw, bd, rng:NextInteger(30, 140), COLORS.buildings[rng:NextInteger(1, #COLORS.buildings)])
				end
			end
		end
	end
	return spawnCF
end

----------------------------------------------------------------------
-- 지역 꾸미기
----------------------------------------------------------------------
local function decorate(map: Instance, plans)
	local rng = Random.new(77)
	-- 해변 야자수
	local beach = Instance.new("Folder")
	beach.Name = "Beach"
	beach.Parent = map
	for x = -900, 950, 70 do
		if math.abs(x) > 40 then -- 부두 자리 비움
			makeTree(beach, Vector3.new(x + rng:NextNumber(-15, 15), 2.5, 885 + rng:NextNumber(-20, 20)), rng:NextNumber(0.9, 1.2), true)
		end
	end
	-- 서쪽 숲 (길/활주로 피해서)
	local forest = Instance.new("Folder")
	forest.Name = "Forest"
	forest.Parent = map
	local placed = 0
	for _ = 1, 600 do
		if placed >= 220 then
			break
		end
		local p = Vector3.new(rng:NextNumber(-2200, -1300), LAND_Y, rng:NextNumber(-1400, 1050))
		local onRunway = p.X > -2050 and p.X < -1850 and p.Z > -950 and p.Z < 450
		if not onRunway and not E.nearAnyRoad(plans, p, 20) then
			makeTree(forest, p, rng:NextNumber(0.9, 1.5))
			placed += 1
		end
	end
	-- 공항 활주로
	local airport = Instance.new("Folder")
	airport.Name = "Airport"
	airport.Parent = map
	newPart(airport, "Runway", Vector3.new(90, 1, 1300), CFrame.new(-1950, LAND_Y + 0.05, -250), Color3.fromRGB(70, 72, 85))
	for z = -850, 350, 60 do
		newPart(airport, "RunwayDash", Vector3.new(2, 0.1, 30), CFrame.new(-1950, LAND_Y + 0.6, z), Color3.new(1, 1, 1))
	end
end

local function desertMesas(plans)
	local terrain = workspace.Terrain
	local rng = Random.new(31)
	local placed = 0
	for _ = 1, 300 do
		if placed >= 40 then
			break
		end
		local p = Vector3.new(rng:NextNumber(1150, 2600), 0, rng:NextNumber(-1400, 900))
		if not E.nearAnyRoad(plans, p, 70) then
			local w, d = rng:NextNumber(40, 130), rng:NextNumber(40, 130)
			local h = rng:NextNumber(30, 130)
			terrain:FillBlock(CFrame.new(p.X, LAND_Y + h / 2 - 2, p.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Vector3.new(w, h, d), Enum.Material.Sandstone)
			placed += 1
		end
	end
end

----------------------------------------------------------------------

function IslandBuilder.Build()
	local recording = ChangeHistoryService:TryBeginRecording("IslandBuilder")
	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing.Name = "Map_backup_" .. os.time()
		existing.Parent = game:GetService("ServerStorage")
		warn("[IslandBuilder] 기존 맵을 ServerStorage." .. existing.Name .. " 로 옮겨 뒀어요 (지운 게 아님)")
	end
	local terrain = workspace.Terrain
	terrain:Clear()
	for mat, color in COLORS.terrain do
		terrain:SetMaterialColor(mat, color)
	end
	E.STYLE.groundY = LAND_Y

	local map = Instance.new("Folder")
	map.Name = "Map"

	-- 바다
	-- 파트 한 변 최대 2048 이라 바다를 타일로 깔기 (6x6 = 약 12000 x 12000)
	local sea = Instance.new("Folder")
	sea.Name = "Sea"
	sea.Parent = map
	local TILE = 2000
	for ix = -3, 2 do
		for iz = -3, 2 do
			local cx, cz = (ix + 0.5) * TILE, (iz + 0.5) * TILE
			local ocean = newPart(sea, "Ocean", Vector3.new(TILE, 2, TILE), CFrame.new(cx, SEA_Y - 1, cz), COLORS.ocean, Enum.Material.Glass)
			ocean.Transparency = 0.3
			ocean.CanCollide = false
			ocean.CanQuery = false
			ocean.CastShadow = false
			newPart(sea, "SeaFloor", Vector3.new(TILE, 4, TILE), CFrame.new(cx, SEA_FLOOR - 2, cz), COLORS.seaFloor, Enum.Material.Sand)
		end
	end

	-- 땅
	for _, L in LAND do
		roundedRect(L)
	end

	-- 길
	local roads = Instance.new("Folder")
	roads.Name = "Roads"
	roads.Parent = map
	local plans = E.plan(buildRoutes())
	local fills, carves = E.build(roads, plans)

	-- 산 (고갯길 아래, 위로 갈수록 바위 → 눈)
	local touge = E.find(plans, "Touge")
	if touge then
		E.mountainUnder(touge.samples, LAND_Y, {
			{ 0, Enum.Material.Grass },
			{ 0.35, Enum.Material.Ground },
			{ 0.6, Enum.Material.Rock },
			{ 0.8, Enum.Material.Snow },
		}, SEA_FLOOR) -- 바다 쪽으로 나간 산자락도 바다 밑까지 채움
	end
	desertMesas(plans)

	-- 도심
	local city = Instance.new("Folder")
	city.Name = "City"
	city.Parent = map
	local spawnCF = fillBlocks(city)
	decorate(map, plans)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MainSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = spawnCF
	spawn.Color = Color3.fromRGB(80, 200, 255)
	spawn.Parent = map

	map.Parent = workspace
	-- 길 아래 채우고, 길 위 깎기 (산/바위가 길을 덮지 않게 마지막에)
	E.applyTerrain(fills, carves)

	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	local parts = 0
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format("[IslandBuilder] 완료: 파트 %d개. 스폰 = 도심 딜러샵 앞", parts))
	E.report(plans)
end

return IslandBuilder
