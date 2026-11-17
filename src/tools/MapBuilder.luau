-- 그레이박스(회색 뼈대) 오픈월드 생성기. 게임 실행 중엔 안 돌고, Studio 명령줄에서 한 번 실행한다.
--
--   require(game.ServerStorage.Tools.MapBuilder).Build()
--
-- • Workspace.Map 이 이미 있으면 아무것도 안 한다 (직접 고친 맵 보호).
--   정말 새로 만들려면: require(game.ServerStorage.Tools.MapBuilder).Build({ overwrite = true })
--   → 기존 Map 은 지우지 않고 "Map_backup_시간" 으로 이름만 바꿔 둔다.
-- • 만든 뒤에는 Ctrl+Z 로 되돌릴 수 있다.
-- • 위에서 아래로: 설산(북, 높음) → MTB 숲 → 언덕 주택가/와이너리 → 꼬인 도심 다운힐 → 평지 도심/스폰 → 항구(남, 낮음)
--   화산은 북서쪽, 공사장은 도심 동쪽, 레이스 로비는 맵 밖 동쪽 섬.

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local MapBuilder = {}

local rng = Random.new(20261118)

local C = {
	road = Color3.fromRGB(70, 70, 75),
	grass = Color3.fromRGB(95, 150, 70),
	snow = Color3.fromRGB(240, 245, 250),
	rock = Color3.fromRGB(90, 80, 75),
	sand = Color3.fromRGB(225, 205, 150),
	water = Color3.fromRGB(40, 110, 190),
	lava = Color3.fromRGB(255, 90, 20),
	building = Color3.fromRGB(170, 165, 160),
	wood = Color3.fromRGB(120, 85, 50),
	jump = Color3.fromRGB(255, 200, 0),
	checkpoint = Color3.fromRGB(0, 255, 120),
}

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function part(parent: Instance, props: { [string]: any }, class: string?): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- 윗면 가운데(top)와 크기로 평평한 판
local function slab(parent, name, top: Vector3, size: Vector3, color, material)
	return part(parent, {
		Name = name,
		Size = size,
		CFrame = CFrame.new(top - Vector3.new(0, size.Y / 2, 0)),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

-- 경사면(쐐기). lowEdge: 낮은 쪽 가장자리 가운데(윗면 높이), dir: 올라가는 방향(수평)
local function slope(parent, name, lowEdge: Vector3, dir: Vector3, width, length, rise, color, material)
	dir = (dir * Vector3.new(1, 0, 1)).Unit
	local center = lowEdge + dir * (length / 2) + Vector3.new(0, rise / 2, 0)
	-- WedgePart 는 로컬 +Z 쪽이 높다 → LookVector = -dir
	return part(parent, {
		Name = name,
		Size = Vector3.new(width, rise, length),
		CFrame = CFrame.lookAt(center, center - dir),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}, "WedgePart")
end

-- 점프대 (바닥 가운데 기준)
local function jump(parent, name, base: Vector3, dir: Vector3, jumpType: string, w, l, h)
	local j = slope(parent, name, base - (dir * Vector3.new(1, 0, 1)).Unit * (l / 2), dir, w, l, h, C.jump, Enum.Material.DiamondPlate)
	j:SetAttribute("JumpType", jumpType) -- Shortcut / Connector / Play / Trap (문서 4-3)
	return j
end

local function block(parent, name, center: Vector3, size: Vector3, color, material)
	return part(parent, {
		Name = name,
		Size = size,
		CFrame = CFrame.new(center),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

local function cylinder(parent, name, top: Vector3, radius, height, color, material)
	return part(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(top - Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

local function tree(parent, groundPos: Vector3, scale: number)
	local m = Instance.new("Model")
	m.Name = "Tree"
	local h = 18 * scale
	cylinder(m, "Trunk", groundPos + Vector3.new(0, h, 0), 1.2 * scale, h + 4, C.wood, Enum.Material.Wood)
	part(m, {
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 14 * scale,
		CFrame = CFrame.new(groundPos + Vector3.new(0, h + 4 * scale, 0)),
		Color = Color3.fromRGB(50, 110, 45),
		Material = Enum.Material.Grass,
	})
	m.Parent = parent
end

----------------------------------------------------------------------
-- 높이 지도 (x=0 중심선 기준). 체크포인트 높이 계산에 사용.
-- z: 남(+) ↔ 북(-)
----------------------------------------------------------------------
local H = {
	harbor = 6,
	city = 20,
	hill = 200,
	mtbTop = 450,
	summit = 700,
}
local Z = {
	harborEnd = 900,
	harborStart = 450,
	cityS = 400,
	cityN = -400,
	hillS = -1100,
	hillN = -1600,
	mtbN = -2400,
	peakN = -3000,
	summitN = -3500,
}

local function groundY(z: number): number
	if z >= Z.harborStart then
		return H.harbor
	elseif z >= Z.cityS then
		return H.city + (H.harbor - H.city) * (z - Z.cityS) / (Z.harborStart - Z.cityS)
	elseif z >= Z.cityN then
		return H.city
	elseif z >= Z.hillS then
		return H.city + (H.hill - H.city) * (Z.cityN - z) / (Z.cityN - Z.hillS)
	elseif z >= Z.hillN then
		return H.hill
	elseif z >= Z.mtbN then
		return H.hill + (H.mtbTop - H.hill) * (Z.hillN - z) / (Z.hillN - Z.mtbN)
	elseif z >= Z.peakN then
		return H.mtbTop + (H.summit - H.mtbTop) * (Z.mtbN - z) / (Z.mtbN - Z.peakN)
	end
	return H.summit
end

----------------------------------------------------------------------
-- 구역별 생성
----------------------------------------------------------------------
local function buildCity(map)
	local f = folder(map, "FlatCity")
	slab(f, "Ground", Vector3.new(0, H.city, 0), Vector3.new(1000, 20, 800), C.road, Enum.Material.Asphalt)

	-- 4x4 블록 (가운데 2x2 는 광장)
	local blocks = folder(f, "Buildings")
	for _, bx in { -240, -80, 80, 240 } do
		for _, bz in { -240, -80, 80, 240 } do
			if math.abs(bx) == 80 and math.abs(bz) == 80 then
				continue
			end
			local h = rng:NextInteger(30, 120)
			block(blocks, "Building", Vector3.new(bx, H.city + h / 2, bz), Vector3.new(100, h, 100), C.building, Enum.Material.Concrete)
		end
	end
	-- 광장 + 스폰
	slab(f, "Plaza", Vector3.new(0, H.city + 0.2, 0), Vector3.new(220, 1, 220), Color3.fromRGB(200, 190, 170), Enum.Material.Pavement)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MainSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, H.city + 0.7, 30)
	spawn.Color = Color3.fromRGB(80, 200, 255)
	spawn.Neutral = true
	spawn.Parent = f

	-- 놀이 점프대 (광장)
	jump(f, "PlazaJump", Vector3.new(-60, H.city + 0.7, -60), Vector3.new(0, 0, 1), "Play", 16, 24, 7)
	-- 육교 (도심 블록 서킷용 장식)
	slab(f, "Overpass", Vector3.new(160, H.city + 22, 0), Vector3.new(60, 3, 120), C.road, Enum.Material.Concrete)
	-- 주차장 나선탑 자리 (나중에 손볼 곳)
	block(f, "ParkingTower_TODO", Vector3.new(-430, H.city + 40, 330), Vector3.new(80, 80, 80), Color3.fromRGB(150, 150, 170), Enum.Material.Concrete)
end

local function buildHarbor(map)
	local f = folder(map, "Harbor")
	slope(f, "CityToHarborRamp", Vector3.new(0, H.harbor, Z.harborStart), Vector3.new(0, 0, -1), 1000, Z.harborStart - Z.cityS, H.city - H.harbor, C.road, Enum.Material.Asphalt)
	slab(f, "Ground", Vector3.new(150, H.harbor, (Z.harborStart + Z.harborEnd) / 2), Vector3.new(700, 12, Z.harborEnd - Z.harborStart), C.road, Enum.Material.Concrete)
	slab(f, "Beach", Vector3.new(-350, H.harbor - 0.5, (Z.harborStart + Z.harborEnd) / 2), Vector3.new(300, 12, Z.harborEnd - Z.harborStart), C.sand, Enum.Material.Sand)

	-- 컨테이너 줄
	local containers = folder(f, "Containers")
	local colors = { Color3.fromRGB(200, 60, 50), Color3.fromRGB(40, 110, 180), Color3.fromRGB(230, 150, 30), Color3.fromRGB(60, 150, 80) }
	for row = 0, 3 do
		for i = 0, 5 do
			local stack = rng:NextInteger(1, 2)
			for s = 1, stack do
				block(containers, "Container", Vector3.new(100 + row * 50, H.harbor + 4.5 + (s - 1) * 9, 520 + i * 40), Vector3.new(16, 9, 34), colors[rng:NextInteger(1, #colors)], Enum.Material.CorrodedMetal)
			end
		end
	end

	-- 부두 + 배 (배로 점프해서 골인)
	slab(f, "Pier", Vector3.new(0, H.harbor, Z.harborEnd + 200), Vector3.new(50, 4, 400), C.wood, Enum.Material.WoodPlanks)
	jump(f, "ShipJump", Vector3.new(0, H.harbor, Z.harborEnd + 380), Vector3.new(0, 0, 1), "Shortcut", 30, 30, 10)
	block(f, "Ship", Vector3.new(0, H.harbor + 2, Z.harborEnd + 480), Vector3.new(70, 20, 120), Color3.fromRGB(120, 40, 40), Enum.Material.Metal)

	-- 바다 (지나가면 빠짐. 물 데미지/리스폰은 2단계에서)
	part(f, {
		Name = "Sea",
		Size = Vector3.new(4000, 4, 2500),
		CFrame = CFrame.new(0, 0, Z.harborEnd + 1250),
		Color = C.water,
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		CanCollide = false,
	})
	slab(f, "SeaFloor", Vector3.new(0, -40, Z.harborEnd + 1250), Vector3.new(4000, 4, 2500), C.sand, Enum.Material.Sand)
end

local function buildDownhill(map)
	local f = folder(map, "DowntownDownhill")
	local length = Z.cityN - Z.hillS
	slope(f, "HillSlope", Vector3.new(0, H.city, Z.cityN), Vector3.new(0, 0, -1), 800, length, H.hill - H.city, C.road, Enum.Material.Cobblestone)

	-- 엇갈린 건물 줄 → 지그재그 "꼬인" 길
	local b = folder(f, "Buildings")
	for i = 1, 5 do
		local z = Z.cityN - i * (length / 6)
		local gapSide = (i % 2 == 0) and -1 or 1
		for x = -360, 360, 90 do
			if math.abs(x - gapSide * 200) < 100 then
				continue -- 이쪽에 통로
			end
			if math.abs(x) < 40 and i % 2 == 1 then
				continue -- 가운데 계단 골목
			end
			local h = rng:NextInteger(20, 50)
			local y = groundY(z)
			block(b, "House", Vector3.new(x, y + h / 2 - 4, z), Vector3.new(70, h, 40), Color3.fromRGB(rng:NextInteger(170, 230), rng:NextInteger(140, 200), rng:NextInteger(120, 170)), Enum.Material.Brick)
		end
	end
	-- 시장 천막 (부딪히면 웃기게)
	for i = 1, 4 do
		local z = Z.cityN - 80 - i * 120
		local tent = block(f, "MarketTent", Vector3.new(-120 + i * 60, groundY(z) + 9, z), Vector3.new(24, 1, 18), Color3.fromRGB(220, 60 + i * 30, 60), Enum.Material.Fabric)
		tent.CFrame *= CFrame.Angles(math.rad(10), 0, 0)
	end
	-- 지붕 점프 (지름길)
	local jz = Z.cityN - length * 0.45
	jump(f, "RoofJump", Vector3.new(200, groundY(jz), jz), Vector3.new(0, 0, 1), "Shortcut", 20, 26, 8)
end

local function buildConstruction(map)
	local f = folder(map, "ConstructionSite")
	slab(f, "Ground", Vector3.new(750, H.city, -650), Vector3.new(500, 20, 500), Color3.fromRGB(150, 120, 80), Enum.Material.Ground)
	slab(f, "Link", Vector3.new(475, H.city, -400), Vector3.new(80, 20, 120), C.road, Enum.Material.Asphalt)
	-- 철골 위 길
	for i = 0, 3 do
		slab(f, "SteelBeam", Vector3.new(620 + i * 80, H.city + 18, -650), Vector3.new(14, 2, 300), Color3.fromRGB(200, 90, 40), Enum.Material.Metal)
	end
	slope(f, "BeamRamp", Vector3.new(620, H.city, -480), Vector3.new(0, 0, -1), 14, 50, 18, Color3.fromRGB(200, 90, 40), Enum.Material.Metal)
	-- 크레인
	block(f, "CraneTower", Vector3.new(850, H.city + 60, -800), Vector3.new(8, 120, 8), Color3.fromRGB(240, 190, 20), Enum.Material.Metal)
	block(f, "CraneArm", Vector3.new(800, H.city + 118, -800), Vector3.new(140, 6, 6), Color3.fromRGB(240, 190, 20), Enum.Material.Metal)
	jump(f, "SitePlayJump", Vector3.new(700, H.city, -560), Vector3.new(1, 0, 0), "Play", 18, 24, 9)
end

local function buildHill(map)
	local f = folder(map, "HillTownWinery")
	slab(f, "Ground", Vector3.new(0, H.hill, (Z.hillS + Z.hillN) / 2), Vector3.new(900, 30, Z.hillS - Z.hillN), C.grass, Enum.Material.Grass)
	-- 주택가 (서쪽)
	for i = 1, 10 do
		local x = rng:NextInteger(-420, -80)
		local z = rng:NextInteger(Z.hillN + 40, Z.hillS - 40)
		block(f, "House", Vector3.new(x, H.hill + 8, z), Vector3.new(30, 16, 24), Color3.fromRGB(230, 220, 200), Enum.Material.Brick)
	end
	-- 와이너리 포도밭 (동쪽, 줄줄이)
	local vines = folder(f, "Vineyard")
	for row = 0, 9 do
		block(vines, "VineRow", Vector3.new(120 + row * 30, H.hill + 2, (Z.hillS + Z.hillN) / 2), Vector3.new(4, 4, 360), Color3.fromRGB(70, 120, 50), Enum.Material.Grass)
	end
	block(f, "Winery", Vector3.new(400, H.hill + 12, Z.hillN + 60), Vector3.new(60, 24, 40), Color3.fromRGB(150, 90, 60), Enum.Material.Brick)
end

local function buildForest(map)
	local f = folder(map, "MTBForest")
	local length = Z.hillN - Z.mtbN
	slope(f, "ForestSlope", Vector3.new(0, H.hill, Z.hillN), Vector3.new(0, 0, -1), 700, length, H.mtbTop - H.hill, C.grass, Enum.Material.Grass)
	-- 나무 (가운데 트레일 |x| < 30 은 비움)
	local trees = folder(f, "Trees")
	for _ = 1, 140 do
		local x = rng:NextNumber(-330, 330)
		if math.abs(x) < 30 then
			continue
		end
		local z = rng:NextNumber(Z.mtbN + 20, Z.hillN - 20)
		tree(trees, Vector3.new(x, groundY(z) - 2, z), rng:NextNumber(0.8, 1.4))
	end
	-- 바위
	for _ = 1, 25 do
		local z = rng:NextNumber(Z.mtbN + 40, Z.hillN - 40)
		local x = rng:NextNumber(-250, 250)
		part(f, { Name = "Rock", Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(6, 14), CFrame = CFrame.new(x, groundY(z), z), Color = C.rock, Material = Enum.Material.Rock })
	end
	-- 통나무 다리 (협곡 위)
	local bz = Z.hillN - length * 0.6
	block(f, "Ravine_TODO", Vector3.new(0, groundY(bz) - 1, bz), Vector3.new(700, 2, 40), Color3.fromRGB(40, 30, 20), Enum.Material.Ground).CanCollide = false
	cylinder(f, "LogBridge", Vector3.new(0, groundY(bz) + 2, bz), 3, 60, C.wood, Enum.Material.Wood).CFrame = CFrame.new(0, groundY(bz) + 1, bz) * CFrame.Angles(0, math.rad(90), 0)
	jump(f, "ForestShortcutJump", Vector3.new(80, groundY(Z.hillN - length * 0.3), Z.hillN - length * 0.3), Vector3.new(0, 0, 1), "Shortcut", 16, 22, 7)
end

local function buildSnow(map)
	local f = folder(map, "SnowPeak")
	slope(f, "PeakSlope", Vector3.new(0, H.mtbTop, Z.mtbN), Vector3.new(0, 0, -1), 700, Z.mtbN - Z.peakN, H.summit - H.mtbTop, C.snow, Enum.Material.Snow)
	slab(f, "Summit", Vector3.new(0, H.summit, (Z.peakN + Z.summitN) / 2), Vector3.new(500, 40, Z.peakN - Z.summitN), C.snow, Enum.Material.Snow)
	-- 빙판 호수 (빙판 호수 코스 자리)
	slab(f, "FrozenLake", Vector3.new(150, H.summit + 0.2, -3300), Vector3.new(200, 1, 200), Color3.fromRGB(180, 220, 255), Enum.Material.Ice)
	for _ = 1, 30 do
		local x = rng:NextNumber(-320, 320)
		local z = rng:NextNumber(Z.peakN + 20, Z.mtbN - 20)
		if math.abs(x) > 30 then
			tree(f, Vector3.new(x, groundY(z) - 2, z), rng:NextNumber(0.8, 1.2))
		end
	end
	jump(f, "SnowJump", Vector3.new(-60, groundY(Z.mtbN - 300), Z.mtbN - 300), Vector3.new(0, 0, 1), "Shortcut", 18, 24, 8)
end

local function buildVolcano(map)
	local f = folder(map, "Volcano")
	local baseTop = 300
	-- 언덕 마을 서쪽 → 화산 기슭 오르막
	slope(f, "VolcanoRoad", Vector3.new(-450, H.hill, -1350), Vector3.new(-1, 0, 0), 300, 500, baseTop - H.hill, C.rock, Enum.Material.Basalt)
	slab(f, "Base", Vector3.new(-1250, baseTop, -1350), Vector3.new(700, 40, 700), C.rock, Enum.Material.Basalt)
	-- 원뿔: 층층이 원기둥 + 층 옆에 붙은 경사로 (좌우 번갈아)
	local cx, cz = -1250, -1350
	local tiers = { { 240, 30 }, { 170, 30 }, { 110, 25 } }
	local y = baseTop
	for i, t in tiers do
		local r, h = t[1], t[2]
		y += h
		cylinder(f, "Tier" .. i, Vector3.new(cx, y, cz), r, h, C.rock, Enum.Material.Basalt)
		local side = (i % 2 == 1) and 1 or -1
		slope(f, "TierRamp" .. i, Vector3.new(cx + side * (r + 15), y - h, cz + 50), Vector3.new(0, 0, -1), 40, 100, h, C.rock, Enum.Material.Basalt)
	end
	-- 분화구 + 용암 (분화구 링 코스 자리). 용암 바깥 링(폭 40)을 돌 수 있음
	local lava = cylinder(f, "Lava", Vector3.new(cx, y + 0.5, cz), 70, 1, C.lava, Enum.Material.Neon)
	lava:SetAttribute("Hazard", "Lava") -- 2단계에서 데미지 연결
end

local function buildRaceLobby(map)
	local f = folder(map, "RaceLobby")
	local top = Vector3.new(2500, 100, 0)
	slab(f, "Island", top, Vector3.new(400, 20, 400), Color3.fromRGB(60, 60, 80), Enum.Material.SmoothPlastic)
	-- 참여 원: 이 안에서는 플레이어끼리 안 부딪힘, 차에 탄 채로 들어와 있어야 참여 (6단계에서 로직 연결)
	local circle = cylinder(f, "RaceJoinCircle", top + Vector3.new(0, 0.3, 0), 70, 0.3, Color3.fromRGB(0, 200, 255), Enum.Material.Neon)
	circle.CanCollide = false
	circle.Transparency = 0.5
	local zone = block(f, "RaceJoinZone", top + Vector3.new(0, 15, 0), Vector3.new(140, 30, 140), Color3.new(1, 1, 1), Enum.Material.ForceField)
	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanQuery = false
	zone:SetAttribute("Note", "참여 판정 영역 (원 위 공간)")
	local lobbySpawn = block(f, "LobbyArrival", top + Vector3.new(0, 0.5, 140), Vector3.new(30, 1, 30), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
	lobbySpawn.CanCollide = false
	lobbySpawn.Transparency = 0.7
	local pad = block(f, "VehicleSelectPad", top + Vector3.new(-130, 0.5, 130), Vector3.new(40, 1, 40), Color3.fromRGB(255, 170, 30), Enum.Material.Neon)
	pad:SetAttribute("Note", "여기서 차 고르기 (6단계 UI)")
end

----------------------------------------------------------------------
-- 레이스 코스 체크포인트
----------------------------------------------------------------------
local function checkpoint(parent, name, pos: Vector3, dir: Vector3, width)
	local d = (dir * Vector3.new(1, 0, 1)).Unit
	part(parent, {
		Name = name,
		Size = Vector3.new(width, 30, 4),
		CFrame = CFrame.lookAt(pos + Vector3.new(0, 15, 0), pos + Vector3.new(0, 15, 0) + d),
		Color = C.checkpoint,
		Material = Enum.Material.ForceField,
		Transparency = 0.6,
		CanCollide = false,
		CanQuery = false,
	})
end

local function course(courses, id: string, start: Vector3, startDir: Vector3, points: { Vector3 }, width: number)
	local f = folder(courses, id)
	local s = part(f, {
		Name = "Start",
		Size = Vector3.new(width, 1, 30),
		CFrame = CFrame.lookAt(start + Vector3.new(0, 0.5, 0), start + Vector3.new(0, 0.5, 0) + startDir),
		Color = Color3.new(1, 1, 1),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.5,
		CanCollide = false,
	})
	s:SetAttribute("Note", "출발선. 앞(LookVector) 방향으로 출발")
	local cps = folder(f, "Checkpoints")
	local prev = start
	for i, p in points do
		checkpoint(cps, "CP" .. i, p, p - prev, width)
		prev = p
	end
end

local function on(z: number, x: number?): Vector3
	return Vector3.new(x or 0, groundY(z), z)
end

local function buildCourses(map)
	local courses = folder(map, "Courses")
	local south = Vector3.new(0, 0, 1)

	course(courses, "PeakToSea", on(-3400), south, {
		on(-2700), on(-2200), on(-1800), on(-1350), on(-900), on(-500), on(-160), on(300),
		Vector3.new(0, H.harbor, 700), Vector3.new(0, H.harbor, Z.harborEnd + 150), Vector3.new(0, H.harbor + 12, Z.harborEnd + 480),
	}, 80)

	course(courses, "DowntownDownhill", on(Z.hillS + 20), south, {
		on(-950), on(-750), on(-550), on(-420), on(-160),
	}, 120)

	-- 시계 반대 방향 블록 순환 (마지막 CP = 출발 지점 → 한 바퀴)
	course(courses, "CityBlockCircuit", Vector3.new(-40, H.city, -160), Vector3.new(1, 0, 0), {
		Vector3.new(160, H.city, -160), Vector3.new(160, H.city, 160), Vector3.new(-160, H.city, 160), Vector3.new(-160, H.city, -160), Vector3.new(0, H.city, -160),
	}, 60)
end

----------------------------------------------------------------------

----------------------------------------------------------------------
-- 트라이얼 부가 요소 (기존 맵에 "덧붙이기"만 함. 이미 있으면 건너뜀)
--   • 각 코스 출발선에 게이트(아치 + 코스 이름)
--   • 체크포인트에 구간 이름 (Section) — 이미 적혀 있으면 안 바꿈
--   • 코너마다 방향 안내 표지판 (">>>" / "<<<")
----------------------------------------------------------------------
local function sectionForZ(z: number): string
	if z >= Z.harborStart - 30 then
		return "HARBOR"
	elseif z >= Z.cityN then
		return "DOWNTOWN"
	elseif z >= Z.hillS then
		return "OLD TOWN"
	elseif z >= Z.hillN then
		return "HILLSIDE"
	elseif z >= Z.mtbN then
		return "FOREST TRAIL"
	elseif z >= Z.peakN then
		return "SNOW SLOPE"
	end
	return "SUMMIT"
end

local function textBoard(parent: Instance, name: string, cf: CFrame, size: Vector3, text: string, bg: Color3, fg: Color3)
	local board = part(parent, {
		Name = name,
		Size = size,
		CFrame = cf,
		Color = bg,
		Material = Enum.Material.SmoothPlastic,
	})
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
	return board
end

local function addTrialExtras(map: Instance)
	local courses = map:FindFirstChild("Courses")
	if not courses then
		warn("[MapBuilder] Map.Courses 가 없어서 트라이얼 요소를 못 붙였어요")
		return 0
	end
	local CourseConfig = require(game:GetService("ReplicatedStorage").Shared.Config.CourseConfig)
	local added = 0
	for _, courseFolder in courses:GetChildren() do
		local start = courseFolder:FindFirstChild("Start")
		local cps = courseFolder:FindFirstChild("Checkpoints")
		if not (start and start:IsA("BasePart")) then
			continue
		end
		local def = CourseConfig.ById[courseFolder.Name]
		local courseName = def and def.name or courseFolder.Name

		-- 출발 게이트
		if not courseFolder:FindFirstChild("Gate") then
			local gate = Instance.new("Model")
			gate.Name = "Gate"
			local w = start.Size.X
			local base = start.CFrame * CFrame.new(0, -start.Size.Y / 2, 0)
			for _, side in { -1, 1 } do
				part(gate, {
					Name = "Pillar",
					Size = Vector3.new(4, 24, 4),
					CFrame = base * CFrame.new(side * (w / 2 + 3), 12, 0),
					Color = Color3.fromRGB(40, 40, 50),
					Material = Enum.Material.Metal,
				})
			end
			textBoard(gate, "Banner", base * CFrame.new(0, 26, 0), Vector3.new(w + 10, 6, 1.5),
				"TIME TRIAL · " .. courseName, Color3.fromRGB(255, 190, 30), Color3.fromRGB(20, 20, 25))
			gate.Parent = courseFolder
			added += 1
		end

		if cps then
			-- 구간 이름
			for _, cp in cps:GetChildren() do
				if cp:IsA("BasePart") and cp:GetAttribute("Section") == nil then
					cp:SetAttribute("Section", sectionForZ(cp.Position.Z))
				end
			end

			-- 코너 방향 표지판
			if not courseFolder:FindFirstChild("CornerSigns") then
				local signs = folder(courseFolder, "CornerSigns")
				local list = {}
				for _, cp in cps:GetChildren() do
					local n = tonumber(string.match(cp.Name, "^CP(%d+)$"))
					if n and cp:IsA("BasePart") then
						list[n] = cp.Position
					end
				end
				local prev = start.Position
				for i = 1, #list - 1 do
					local here, nextPos = list[i], list[i + 1]
					if here and nextPos then
						local inDir = ((here - prev) * Vector3.new(1, 0, 1))
						local outDir = ((nextPos - here) * Vector3.new(1, 0, 1))
						if inDir.Magnitude > 1 and outDir.Magnitude > 1 then
							inDir, outDir = inDir.Unit, outDir.Unit
							local turn = inDir:Cross(outDir).Y -- 음수 = 오른쪽
							if math.abs(turn) > math.sin(math.rad(25)) then
								local ground = here - Vector3.new(0, 15, 0) -- CP 판 중심은 땅 위 15
								local signPos = ground + inDir * 30 + Vector3.new(0, 5, 0)
								-- 다가오는 운전자를 바라보게
								local cf = CFrame.lookAt(signPos, signPos - inDir)
								textBoard(signs, "TurnSign", cf, Vector3.new(16, 5, 1),
									turn < 0 and ">>>" or "<<<", Color3.fromRGB(255, 210, 0), Color3.fromRGB(20, 20, 25))
							end
						end
					end
					prev = here
				end
				added += 1
			end
		end
	end
	return added
end

-- 코스(출발 게이트, 초록 체크포인트 벽, 코너 표지판)를 맵에서 치우기 / 다시 꺼내기 (Studio 명령줄)
--   require(game.ServerStorage.Tools.MapBuilder).HideCourses()
--   require(game.ServerStorage.Tools.MapBuilder).ShowCourses()
-- 지우지 않고 ServerStorage.HiddenCourses 로 옮겨만 둠 (레이스 만들 때 다시 꺼냄)
function MapBuilder.HideCourses()
	local map = workspace:FindFirstChild("Map")
	local courses = map and map:FindFirstChild("Courses")
	if not courses then
		warn("[MapBuilder] Workspace.Map.Courses 가 없어요 (이미 치웠을 수도)")
		return
	end
	local recording = ChangeHistoryService:TryBeginRecording("MapBuilder.HideCourses")
	courses.Name = "HiddenCourses"
	courses.Parent = game:GetService("ServerStorage")
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	print("[MapBuilder] 코스를 ServerStorage.HiddenCourses 로 옮겼어요 (지운 게 아님)")
end

function MapBuilder.ShowCourses()
	local hidden = game:GetService("ServerStorage"):FindFirstChild("HiddenCourses")
	local map = workspace:FindFirstChild("Map")
	if not hidden or not map then
		warn("[MapBuilder] 치워둔 코스가 없거나 Workspace.Map 이 없어요")
		return
	end
	local recording = ChangeHistoryService:TryBeginRecording("MapBuilder.ShowCourses")
	hidden.Name = "Courses"
	hidden.Parent = map
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	print("[MapBuilder] 코스를 다시 맵에 꺼냈어요")
end

-- 이미 만든 맵에 트라이얼 요소만 덧붙이기 (Studio 명령줄):
--   require(game.ServerStorage.Tools.MapBuilder).AddTrialExtras()
function MapBuilder.AddTrialExtras()
	local map = workspace:FindFirstChild("Map")
	if not map then
		warn("[MapBuilder] Workspace.Map 이 없어요. 먼저 Build() 하세요")
		return
	end
	local recording = ChangeHistoryService:TryBeginRecording("MapBuilder.AddTrialExtras")
	local added = addTrialExtras(map)
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	print("[MapBuilder] 트라이얼 요소 추가 완료 (" .. added .. "곳). 이미 있던 건 건드리지 않았어요")
end

function MapBuilder.Build(options: { overwrite: boolean? }?)
	local existing = workspace:FindFirstChild("Map")
	if existing then
		if not (options and options.overwrite) then
			warn("[MapBuilder] Workspace.Map 이 이미 있어서 아무것도 안 했어요. 새로 만들려면 Build({ overwrite = true })")
			return
		end
		existing.Name = "Map_backup_" .. os.time()
		existing.Parent = game:GetService("ServerStorage")
		warn("[MapBuilder] 기존 맵을 ServerStorage." .. existing.Name .. " 로 옮겨 뒀어요")
	end

	local recording = ChangeHistoryService:TryBeginRecording("MapBuilder")
	workspace.StreamingEnabled = true

	local map = Instance.new("Folder")
	map.Name = "Map"
	buildCity(map)
	buildHarbor(map)
	buildDownhill(map)
	buildConstruction(map)
	buildHill(map)
	buildForest(map)
	buildSnow(map)
	buildVolcano(map)
	buildRaceLobby(map)
	buildCourses(map)
	addTrialExtras(map)
	map.Parent = workspace

	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end

	local count = 0
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	print(string.format("[MapBuilder] 완료: 파트 %d개. 스폰 = Map.FlatCity.MainSpawn", count))
end

return MapBuilder
