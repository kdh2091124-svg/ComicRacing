-- 스나이퍼 락온 화면 연출
-- 서버(ArenaService)가 장외 대상(차 또는 캐릭터)에 Attribute "SniperLock" = 스나이퍼 이름 을 붙이면
--   • 스나이퍼 총구 → 대상까지 빨간 레이저 (모두에게 보임)
--   • 대상 위에 빨간 락온 괄호: 빙글 돌며 크게 → 조여들어 딱 고정, "LOCK ON" 깜빡 (모두에게 보임)
--   • 내가 락온당했으면 화면 가장자리 빨갛게 + 경고 문구
-- 쏘는 건 서버가 함 (여기선 보이기만)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage.Shared.Config.GameplayConfig).Arena

local player = Players.LocalPlayer
local RED = Color3.fromRGB(255, 40, 40)

type Visual = { beam: Part, gui: BillboardGui, box: Frame, label: TextLabel, start: number }
local visuals: { [Model]: Visual } = {}

-- 화면 경고 (내가 락온당했을 때)
local warnGui = Instance.new("ScreenGui")
warnGui.Name = "SniperWarning"
warnGui.IgnoreGuiInset = true
warnGui.ResetOnSpawn = false
warnGui.Enabled = false
warnGui.Parent = player:WaitForChild("PlayerGui")
local edges = {}
for _, spec in {
	{ UDim2.new(1, 0, 0.08, 0), UDim2.new(0, 0, 0, 0) },
	{ UDim2.new(1, 0, 0.08, 0), UDim2.new(0, 0, 0.92, 0) },
	{ UDim2.new(0.05, 0, 1, 0), UDim2.new(0, 0, 0, 0) },
	{ UDim2.new(0.05, 0, 1, 0), UDim2.new(0.95, 0, 0, 0) },
} do
	local f = Instance.new("Frame")
	f.Size, f.Position = spec[1], spec[2]
	f.BackgroundColor3 = RED
	f.BorderSizePixel = 0
	f.Parent = warnGui
	table.insert(edges, f)
end
local warnText = Instance.new("TextLabel")
warnText.Size = UDim2.new(1, 0, 0.08, 0)
warnText.Position = UDim2.new(0, 0, 0.14, 0)
warnText.BackgroundTransparency = 1
warnText.Font = Enum.Font.GothamBlack
warnText.TextScaled = true
warnText.TextColor3 = Color3.new(1, 1, 1)
warnText.TextStrokeTransparency = 0
warnText.TextStrokeColor3 = RED
warnText.Text = "SNIPER LOCK-ON!" -- TODO 영어 전환 때 그대로 둬도 됨
warnText.Parent = warnGui

local function corner(parent: Instance, ax: number, ay: number)
	-- 모서리 "ㄱ" 괄호 한 개 = 가로 막대 + 세로 막대
	local len, thick = 0.3, 0.07
	for _, horizontal in { true, false } do
		local f = Instance.new("Frame")
		f.BackgroundColor3 = RED
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(ax, ay)
		f.Position = UDim2.fromScale(ax, ay)
		f.Size = horizontal and UDim2.fromScale(len, thick) or UDim2.fromScale(thick, len)
		f.Parent = parent
	end
end

local function makeVisual(target: Model, part: BasePart): Visual
	local beam = Instance.new("Part")
	beam.Name = "SniperLaser"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = RED
	beam.Size = Vector3.new(0.3, 0.3, 1)
	beam.Parent = workspace.CurrentCamera

	local size = target:GetExtentsSize()
	local s = math.max(size.X, size.Z, 6) * 1.3
	local gui = Instance.new("BillboardGui")
	gui.Name = "LockOn"
	gui.Adornee = part
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromScale(s, s) -- 스터드 단위
	gui.Parent = player:WaitForChild("PlayerGui")
	local box = Instance.new("Frame")
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.BackgroundTransparency = 1
	box.Parent = gui
	corner(box, 0, 0)
	corner(box, 1, 0)
	corner(box, 0, 1)
	corner(box, 1, 1)
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromScale(0.08, 0.08)
	dot.BackgroundColor3 = RED
	dot.BorderSizePixel = 0
	dot.Parent = box
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 1.05)
	label.Size = UDim2.fromScale(1.4, 0.25)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = RED
	label.TextStrokeTransparency = 0.3
	label.Text = "LOCK ON"
	label.Visible = false
	label.Parent = gui
	return { beam = beam, gui = gui, box = box, label = label, start = os.clock() }
end

local function destroyVisual(target: Model)
	local v = visuals[target]
	if v then
		v.beam:Destroy()
		v.gui:Destroy()
		visuals[target] = nil
	end
end

local function targetPart(target: Model): BasePart?
	local p = target.PrimaryPart or target:FindFirstChild("HumanoidRootPart")
	return (p and p:IsA("BasePart")) and p or nil
end

local function isMine(target: Model): boolean
	local char = player.Character
	if target == char then
		return true
	end
	if target:GetAttribute("OwnerUserId") == player.UserId then
		return true
	end
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.SeatPart ~= nil and hum.SeatPart:IsDescendantOf(target)
end

local function candidates(): { Model }
	local list = {}
	local vehicles = workspace:FindFirstChild("Vehicles")
	if vehicles then
		for _, m in vehicles:GetChildren() do
			if m:IsA("Model") then
				table.insert(list, m)
			end
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

local function findSniper(name: string): Model?
	local map = workspace:FindFirstChild("Map")
	local s = map and name ~= "" and map:FindFirstChild(name, true)
	return (s and s:IsA("Model")) and s or nil
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local seen: { [Model]: boolean } = {}
	local mineLocked = false
	for _, target in candidates() do
		local name = target:GetAttribute("SniperLock")
		local part = targetPart(target)
		if type(name) == "string" and part then
			seen[target] = true
			local v = visuals[target] or makeVisual(target, part)
			visuals[target] = v
			-- 레이저: 총구 → 대상 (살짝 깜빡)
			local sniper = findSniper(name)
			local muzzle = sniper and sniper:FindFirstChild("Muzzle")
			if muzzle and muzzle:IsA("BasePart") then
				local from, to = muzzle.Position, part.Position
				local d = (to - from).Magnitude
				v.beam.Size = Vector3.new(0.3, 0.3, d)
				v.beam.CFrame = CFrame.lookAt((from + to) / 2, to)
				v.beam.Transparency = 0.15 + 0.25 * math.abs(math.sin(now * 25))
			else
				v.beam.Transparency = 1
			end
			-- 락온 괄호: 크게 빙글 → 조여들어 고정
			local e = math.clamp((now - v.start) / Arena.lockAnimTime, 0, 1)
			e = 1 - (1 - e) ^ 3
			local sc = 1 + 1.6 * (1 - e)
			v.box.Size = UDim2.fromScale(sc, sc)
			v.box.Rotation = 135 * (1 - e)
			v.label.Visible = e >= 1 and (now * 6) % 1 < 0.6
			if isMine(target) then
				mineLocked = true
			end
		end
	end
	for target in visuals do
		if not seen[target] then
			destroyVisual(target)
		end
	end
	warnGui.Enabled = mineLocked
	if mineLocked then
		local a = 0.45 + 0.3 * math.abs(math.sin(now * 10))
		for _, f in edges do
			f.BackgroundTransparency = a
		end
		warnText.TextTransparency = (now * 5) % 1 < 0.5 and 0 or 0.4
	end
end)
