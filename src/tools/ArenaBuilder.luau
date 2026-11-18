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

	-- 5) 바깥 벽 + 바깥 데크
	local outer = rings[1]
	for i = 0, N - 1 do
		local th = angleOf(i)
		local wall = newPart(fDecor, "OuterWall", Vector3.new(3, A.wallHeight, segLen(outer.r1 + 3)), segFrame(outer.r1 + 1.5, th, outer.top + A.wallHeight / 2), A.colors.wall)
		wall.CustomPhysicalProperties = FRICTIONLESS
		ringBlock(fDecor, outer.r1 + 3, outer.r1 + 3 + A.deckWidth, th, outer.top, A.colors.deck, "Deck").Material = Enum.Material.Grass
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
	print(string.format("[ArenaBuilder] 완료: 파트 %d개, 경사로 %d개, 경사로 최대 기울기 %.1f°", parts, #rampList, math.deg(math.atan(maxGrade))))
	for _, w in warnings do
		warn("[ArenaBuilder] " .. w)
	end
end

return ArenaBuilder
