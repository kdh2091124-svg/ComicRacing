-- 도로 엔진: 여러 월드 생성기가 같이 쓰는 "길 까는 기술" 모음.
--   • 점/곡선 → 부드러운 도로 (Catmull-Rom), 거북이 그리기(직선/원호)로 U 자 헤어핀
--   • join: 다른 길에 정확히 붙는 갈림길
--   • 자동 다리(다른 길 위), 자동 입구(같은 높이로 닿는 곳 가드레일/테두리선 비움)
--   • 갈림길 주변 기울기 펴기, 경사 상한(끊김 방지), 꺾인 곳 더 겹치기
--   • 길 아래 지형 채우기 + 길 위 지형 깎기
--   • 가드레일 = 보이는 난간(충돌 없음) + 투명 매끈한 벽
--
-- 길(route) 옵션:
--   name, points, closed, width, step, rails(true/false), fill(false), lowerExtra,
--   style("dirt" / "wood"), shoulder(갓길 폭), shoulderColor, fillMaterial, lineColor

local RoadEngine = {}

local STYLE = {
	roadWidth = 46,
	shoulder = 9,
	groundY = 0, -- 생성기가 바꿈 (땅 높이)
	asphalt = Color3.fromRGB(78, 80, 96),
	grass = Color3.fromRGB(110, 230, 120),
	whiteLine = Color3.fromRGB(245, 245, 245),
	yellowLine = Color3.fromRGB(255, 225, 40),
	rail = Color3.fromRGB(190, 195, 210),
	deck = Color3.fromRGB(150, 155, 170),
	dirt = Color3.fromRGB(165, 125, 80),
	wood = Color3.fromRGB(150, 105, 65),
	railWallHeight = 7,
	junctionFlatRadius = 100,
	sameLevel = 4,
	underClear = 4,
	maxGrade = 16,
	maxGradeWarn = 13,
	carveHeight = 60, -- 길 위로 이만큼 지형을 깎음
}
RoadEngine.STYLE = STYLE

----------------------------------------------------------------------
-- 기본 도구
----------------------------------------------------------------------
function RoadEngine.newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
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
local newPart = RoadEngine.newPart

function RoadEngine.makeSign(parent: Instance, cf: CFrame, size: Vector3, text: string, bg: Color3, fg: Color3)
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
	return board
end

local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

----------------------------------------------------------------------
-- 거북이 그리기: 직선/원호 명령으로 경로 만들기 (헤어핀이 진짜 U 자)
--   spec = { base: Vector3, dir: Vector3(앞=산 쪽), startLateral, headingDeg(0=오른쪽, 90=앞), spacing, program }
--   program: { "s", 길이, 경사 } / { "t", 각도, 반지름, 경사 } / { "mark", 이름 }
----------------------------------------------------------------------
function RoadEngine.turtle(spec): ({ any }, { [string]: Vector3 })
	local u = spec.dir.Unit
	local v = Vector3.new(-u.Z, 0, u.X)
	local a, l, y = 0, spec.startLateral or 0, spec.base.Y
	local heading = math.rad(spec.headingDeg or 0)
	local spacing = spec.spacing or 6
	local pts = {}
	local marks: { [string]: Vector3 } = {}
	local function world(): Vector3
		local p = spec.base + u * a + v * l
		return Vector3.new(p.X, y, p.Z)
	end
	local function emit()
		local p = world()
		table.insert(pts, { p.X, p.Y, p.Z })
	end
	for _, cmd in spec.program do
		if cmd[1] == "mark" then
			marks[cmd[2]] = world()
		elseif cmd[1] == "s" then
			local len, grade = cmd[2], cmd[3]
			local n = math.max(math.ceil(len / spacing), 1)
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
			local n = math.max(math.ceil(arc / spacing), 1)
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

----------------------------------------------------------------------
-- 곡선 나누기 / 경사 제한 / 방향
----------------------------------------------------------------------
export type Sample = { pos: Vector3, bank: number, bridge: boolean, opening: boolean, under: boolean }

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

local function limitGrade(samples: { Sample })
	local g = math.tan(math.rad(STYLE.maxGrade))
	local function horiz(a: Vector3, b: Vector3): number
		return (Vector2.new(a.X, a.Z) - Vector2.new(b.X, b.Z)).Magnitude
	end
	for _ = 1, 2 do
		for i = 2, #samples - 1 do
			local prev, s = samples[i - 1].pos, samples[i].pos
			local m = g * horiz(prev, s)
			samples[i].pos = Vector3.new(s.X, math.clamp(s.Y, prev.Y - m, prev.Y + m), s.Z)
		end
		for i = #samples - 1, 2, -1 do
			local nxt, s = samples[i + 1].pos, samples[i].pos
			local m = g * horiz(nxt, s)
			samples[i].pos = Vector3.new(s.X, math.clamp(s.Y, nxt.Y - m, nxt.Y + m), s.Z)
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
-- 1단계: 계획
----------------------------------------------------------------------
export type Plan = {
	route: any,
	samples: { Sample },
	width: number,
	half: number,
	trimStart: number,
	trimEnd: number,
	lower: number,
	joinPoints: { Vector3 },
}

function RoadEngine.plan(routes): { Plan }
	local plans: { Plan } = {}
	local byName: { [string]: Plan } = {}
	for _, route in routes do
		local width = route.width or STYLE.roadWidth
		local resolved = {}
		local trimStart, trimEnd = 0, 0
		for i, p in route.points do
			if p.join then
				local target = byName[p.join]
				assert(target, "[RoadEngine] '" .. route.name .. "' 가 붙으려는 길 '" .. tostring(p.join) .. "' 이 먼저 있어야 해요")
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
			half = width / 2 + (route.shoulder or STYLE.shoulder),
			trimStart = trimStart,
			trimEnd = trimEnd,
			lower = ((trimStart > 0 or trimEnd > 0) and -0.06 or 0) + (route.lowerExtra or 0),
			joinPoints = {},
		}
		byName[route.name] = plan
		table.insert(plans, plan)
	end

	local CELL = 100
	local grid: { [string]: { { plan: Plan, s: Sample } } } = {}
	for _, plan in plans do
		for _, s in plan.samples do
			local k = math.floor(s.pos.X / CELL) .. "," .. math.floor(s.pos.Z / CELL)
			grid[k] = grid[k] or {}
			table.insert(grid[k], { plan = plan, s = s })
		end
	end
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

function RoadEngine.find(plans: { Plan }, name: string): Plan?
	for _, p in plans do
		if p.route.name == name then
			return p
		end
	end
	return nil
end

----------------------------------------------------------------------
-- 2단계: 깔기
----------------------------------------------------------------------
export type Box = { cf: CFrame, size: Vector3, material: Enum.Material? }

local function buildRoute(parent: Instance, plan: Plan, fills: { Box }, carves: { Box })
	local route = plan.route
	local folder = Instance.new("Folder")
	folder.Name = route.name
	folder.Parent = parent
	local samples = plan.samples
	local W = plan.width
	local S = route.shoulder or STYLE.shoulder
	local half = plan.half
	local style = route.style
	local roadColor = (style == "dirt" and STYLE.dirt) or (style == "wood" and STYLE.wood) or STYLE.asphalt
	local roadMat = (style == "dirt" and Enum.Material.Ground) or (style == "wood" and Enum.Material.WoodPlanks) or nil
	local shoulderColor = route.shoulderColor or STYLE.grass

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

		newPart(folder, "Road", Vector3.new(W, 2, L), cf(0, -1), roadColor, roadMat)
		if S > 0 then
			newPart(folder, "Shoulder", Vector3.new(W + S * 2, 2, L), cf(0, -1.05), shoulderColor)
		end
		table.insert(carves, { cf = CFrame.fromMatrix(mid + up * (STYLE.carveHeight / 2 + 0.2), right, up, -fwd), size = Vector3.new(W + S * 2 + 4, STYLE.carveHeight, L + 1) })

		if not inTrim and style == nil then
			if not opening then
				for _, side in { -1, 1 } do
					newPart(folder, "EdgeLine", Vector3.new(0.6, 0.08, L), cf(side * (W / 2 - 1.2), 0.04), STYLE.whiteLine)
				end
			end
			if i % 2 == 0 and not opening then
				newPart(folder, "CenterDash", Vector3.new(0.6, 0.08, len * 0.7), cf(0, 0.04), route.lineColor or STYLE.yellowLine)
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
				table.insert(fills, {
					cf = CFrame.lookAt(center, center + flat.Unit),
					size = Vector3.new(W + S * 2 + 6, top - bottom, L + 2),
					material = route.fillMaterial,
				})
			end
		end

		local needRail = route.rails == true or isBridge or math.abs(bank) > 3
		if route.rails ~= false and needRail and not inTrim and not opening then
			for _, side in { -1, 1 } do
				local x = side * (W / 2 + S - 1)
				local rail = newPart(folder, "Rail", Vector3.new(0.4, 0.9, L), cf(x, 2.4), STYLE.rail, Enum.Material.Metal)
				rail.CanCollide = false
				if i % 3 == 0 then
					local post = newPart(folder, "RailPost", Vector3.new(0.5, 2.4, 0.5), cf(x, 1.2), STYLE.rail, Enum.Material.Metal)
					post.CanCollide = false
				end
				local wall = newPart(folder, "RailWall", Vector3.new(1, STYLE.railWallHeight, L), cf(x + side * 0.5, STYLE.railWallHeight / 2), STYLE.rail)
				wall.Transparency = 1
				wall.CastShadow = false
				wall.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 100)
			end
		end
	end
end

function RoadEngine.build(parent: Instance, plans: { Plan }): ({ Box }, { Box })
	local fills: { Box } = {}
	local carves: { Box } = {}
	for _, plan in plans do
		buildRoute(parent, plan, fills, carves)
	end
	return fills, carves
end

-- 길 아래 채우기 → 길 위 깎기 (순서 중요)
function RoadEngine.applyTerrain(fills: { Box }, carves: { Box })
	local terrain = workspace.Terrain
	for _, f in fills do
		terrain:FillBlock(f.cf, f.size, f.material or Enum.Material.Grass)
	end
	for _, c in carves do
		terrain:FillBlock(c.cf, c.size, Enum.Material.Air)
	end
end

-- 산: 주어진 길 점들보다 항상 낮게 맞춘 원뿔 (bands: { {비율(0~1, 꼭대기 쪽), 재질} })
function RoadEngine.mountainUnder(samples: { Sample }, groundY: number, bands, baseY: number?)
	local bottom = baseY or (groundY - 2) -- 산 밑면 (바다 위로 나간 산자락이 떠 보이지 않게 낮출 수 있음)
	local terrain = workspace.Terrain
	local topS = samples[#samples].pos
	local summit = Vector3.new(topS.X, 0, topS.Z)
	local peakH = topS.Y - 40 - groundY
	local slope = 0.3
	for _, s in samples do
		local d = (Vector2.new(s.pos.X, s.pos.Z) - Vector2.new(summit.X, summit.Z)).Magnitude
		if d > 1 then
			slope = math.max(slope, (peakH - (s.pos.Y - groundY - 15)) / d)
		end
	end
	local maxR = peakH / slope
	local steps = 50
	for k = 0, steps - 1 do
		local r = maxR * (1 - k / steps)
		local h = math.max(peakH - slope * r, 4)
		local frac = k / steps
		local mat = Enum.Material.Grass
		for _, band in bands do
			if frac >= band[1] then
				mat = band[2]
			end
		end
		local top = groundY + h - 2
		terrain:FillCylinder(CFrame.new(summit.X, (top + bottom) / 2, summit.Z), top - bottom, r, mat)
	end
end

-- 길 점 근처인지 (건물/바위/나무를 길 위에 놓지 않으려고)
function RoadEngine.nearAnyRoad(plans: { Plan }, p: Vector3, margin: number): boolean
	for _, plan in plans do
		local r = plan.half + margin
		for i = 1, #plan.samples, 3 do
			local s = plan.samples[i].pos
			if (Vector2.new(s.X, s.Z) - Vector2.new(p.X, p.Z)).Magnitude < r then
				return true
			end
		end
	end
	return false
end

function RoadEngine.report(plans: { Plan })
	print("[RoadEngine] ===== 길 점검 =====")
	for _, plan in plans do
		local maxGrade, bridges = 0, 0
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
		end
		print(string.format("  %-16s 최대 경사 %4.1f°%s  자동 다리 %d조각", plan.route.name, maxGrade,
			maxGrade > STYLE.maxGradeWarn and " (가파름)" or "", bridges))
		if steepAt and maxGrade > STYLE.maxGradeWarn then
			print(string.format("      가장 가파른 곳: (%d, %d, %d)", steepAt.X, steepAt.Y, steepAt.Z))
		end
	end
end

return RoadEngine
