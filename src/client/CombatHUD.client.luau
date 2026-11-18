-- 전투 화면 연출 (보조수가 아니어도 항상 동작)
-- • 내가 맞음: 화면 가장자리 빨갛게 번쩍 + 맞은 방향 화살표 (내 차가 맞으면 주황)
-- • 내가 맞힘: 맞은 자리에 데미지 숫자 (머리 = 크게 노랑, 차 = 주황, 킬 = 빨강) + 맞은 대상 하얗게 번쩍
-- • 체력: 내 체력 바(왼쪽 아래), 다른 차 위에 차 HP + 탄 사람 체력
-- • 다운 알림: 우리 차 운전수/보조수가 죽으면 위에 알림 + 부활 카운트다운, 내가 죽으면 가운데 카운트다운

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Weapon") :: RemoteEvent

local player = Players.LocalPlayer
local RESPAWN = WeaponConfig.General.respawnTime

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false) -- 기본 체력 바 대신 아래 것 사용
end)

local gui = Instance.new("ScreenGui")
gui.Name = "CombatHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function newFrame(parent: Instance, size: UDim2, pos: UDim2, color: Color3, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = pos
	f.AnchorPoint = anchor or Vector2.zero
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function newText(parent: Instance, size: UDim2, pos: UDim2, textSize: number, anchor: Vector2?): TextLabel
	local t = Instance.new("TextLabel")
	t.Size = size
	t.Position = pos
	t.AnchorPoint = anchor or Vector2.zero
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextSize = textSize
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.3
	t.Parent = parent
	return t
end

----------------------------------------------------------------------
-- 1) 내가 맞음: 빨간 가장자리 + 방향 화살표
----------------------------------------------------------------------

local edges = {}
for _, spec in {
	{ UDim2.new(1, 0, 0.1, 0), UDim2.new(0, 0, 0, 0) },
	{ UDim2.new(1, 0, 0.1, 0), UDim2.new(0, 0, 0.9, 0) },
	{ UDim2.new(0.06, 0, 1, 0), UDim2.new(0, 0, 0, 0) },
	{ UDim2.new(0.06, 0, 1, 0), UDim2.new(0.94, 0, 0, 0) },
} do
	local f = newFrame(gui, spec[1], spec[2], Color3.fromRGB(255, 30, 30))
	f.BackgroundTransparency = 1
	local grad = Instance.new("UIGradient") -- 안쪽으로 갈수록 투명
	grad.Transparency = NumberSequence.new(0, 1)
	grad.Rotation = (spec[2].Y.Scale > 0.5 and -90) or (spec[2].X.Scale > 0.5 and 180) or (spec[1].X.Scale < 0.5 and 0) or 90
	grad.Parent = f
	table.insert(edges, f)
end
local edgeAlpha = 1 -- 1 = 안 보임

type Arrow = { label: TextLabel, from: Vector3, t: number }
local arrows: { Arrow } = {}

local function hurt(amount: number, from: Vector3, kind: string)
	local strength = math.clamp(amount / 40, 0.25, 0.9)
	edgeAlpha = math.min(edgeAlpha, 1 - strength)
	local color = kind == "car" and Color3.fromRGB(255, 150, 40) or Color3.fromRGB(255, 40, 40)
	for _, f in edges do
		f.BackgroundColor3 = color
	end
	local label = newText(gui, UDim2.fromOffset(40, 40), UDim2.fromScale(0.5, 0.5), 38, Vector2.new(0.5, 0.5))
	label.Text = "▲"
	label.TextColor3 = color
	table.insert(arrows, { label = label, from = from, t = 0 })
	if #arrows > 5 then
		arrows[1].label:Destroy()
		table.remove(arrows, 1)
	end
end

----------------------------------------------------------------------
-- 2) 내가 맞힘: 데미지 숫자 + 대상 번쩍
----------------------------------------------------------------------

local function damageNumber(amount: number, pos: Vector3, kind: string, killed: boolean)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.CFrame = CFrame.new(pos + Vector3.new((math.random() - 0.5) * 2, 1, (math.random() - 0.5) * 2))
	anchor.Parent = workspace.CurrentCamera
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(120, 50)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = anchor
	bb.Parent = anchor
	local big = kind == "head" or killed
	local t = newText(bb, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), big and 34 or 24)
	t.Text = tostring(math.floor(amount + 0.5))
	t.TextColor3 = killed and Color3.fromRGB(255, 60, 60)
		or kind == "head" and Color3.fromRGB(255, 220, 50)
		or kind == "car" and Color3.fromRGB(255, 160, 60)
		or Color3.new(1, 1, 1)
	local info = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(bb, info, { StudsOffset = Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(t, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.75, function()
		anchor:Destroy()
	end)
end

local function flash(target: Instance)
	if not target:IsA("Model") or not target.Parent then
		return
	end
	local h = Instance.new("Highlight")
	h.FillColor = Color3.new(1, 1, 1)
	h.OutlineTransparency = 1
	h.FillTransparency = 0.25
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = target
	TweenService:Create(h, TweenInfo.new(0.12), { FillTransparency = 1 }):Play()
	task.delay(0.13, function()
		h:Destroy()
	end)
end

----------------------------------------------------------------------
-- 3) 체력: 내 체력 바 + 다른 차 머리 위
----------------------------------------------------------------------

local myBarBack = newFrame(gui, UDim2.fromOffset(240, 20), UDim2.new(0, 24, 1, -40), Color3.fromRGB(30, 30, 35), Vector2.new(0, 1))
myBarBack.BackgroundTransparency = 0.3
local myBar = newFrame(myBarBack, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Color3.fromRGB(90, 220, 110))
local myText = newText(myBarBack, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 15)
myText.Text = "체력"

local function hpColor(r: number): Color3
	return Color3.fromRGB(255, 70, 60):Lerp(Color3.fromRGB(90, 220, 110), math.clamp(r, 0, 1))
end

type Overhead = { gui: BillboardGui, car: Frame, crew: Frame }
local overheads: { [Model]: Overhead } = {}

local function makeOverhead(model: Model, chassis: BasePart): Overhead
	local bb = Instance.new("BillboardGui")
	bb.Name = "CombatOverhead"
	bb.Size = UDim2.fromOffset(110, 30)
	bb.StudsOffsetWorldSpace = Vector3.new(0, model:GetExtentsSize().Y + 3, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 450
	bb.Adornee = chassis
	bb.Parent = gui
	local back = newFrame(bb, UDim2.new(1, 0, 0, 10), UDim2.fromScale(0, 0), Color3.fromRGB(30, 30, 35))
	back.BackgroundTransparency = 0.2
	local car = newFrame(back, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Color3.fromRGB(90, 220, 110))
	local crew = Instance.new("Frame")
	crew.BackgroundTransparency = 1
	crew.Size = UDim2.new(1, 0, 0, 14)
	crew.Position = UDim2.new(0, 0, 0, 13)
	crew.Parent = bb
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 3)
	list.Parent = crew
	return { gui = bb, car = car, crew = crew }
end

local function updateOverhead(o: Overhead, model: Model)
	local hp, maxHp = model:GetAttribute("HP"), model:GetAttribute("MaxHP")
	if type(hp) == "number" and type(maxHp) == "number" and maxHp > 0 then
		local r = hp / maxHp
		o.car.Size = UDim2.fromScale(math.clamp(r, 0, 1), 1)
		o.car.BackgroundColor3 = hpColor(r)
	end
	-- 탄 사람: 운전석 먼저, 칸마다 작은 바 (운 = 운전수, 보 = 보조수)
	local seats = {}
	for _, s in model:GetDescendants() do
		if s:IsA("Seat") and s.Occupant then
			table.insert(seats, s)
		end
	end
	table.sort(seats, function(a, b)
		return (a.Name == "DriverSeat" and 0 or 1) < (b.Name == "DriverSeat" and 0 or 1)
	end)
	local slots = {}
	for _, c in o.crew:GetChildren() do
		if c:IsA("Frame") then
			table.insert(slots, c)
		end
	end
	for i, s in seats do
		local slot = slots[i]
		if not slot then
			slot = newFrame(o.crew, UDim2.fromOffset(52, 14), UDim2.fromScale(0, 0), Color3.fromRGB(30, 30, 35))
			slot.BackgroundTransparency = 0.2
			slot.LayoutOrder = i
			local fill = newFrame(slot, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Color3.new(1, 1, 1))
			fill.Name = "Fill"
			local tag = newText(slot, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 11)
			tag.Name = "Tag"
		end
		local hum = (s :: Seat).Occupant :: Humanoid
		local r = hum.MaxHealth > 0 and hum.Health / hum.MaxHealth or 0
		local fill = slot:FindFirstChild("Fill") :: Frame
		fill.Size = UDim2.fromScale(math.clamp(r, 0, 1), 1)
		fill.BackgroundColor3 = hpColor(r)
		;(slot:FindFirstChild("Tag") :: TextLabel).Text = s.Name == "DriverSeat" and "운전" or "보조"
		slot.Visible = true
	end
	for i = #seats + 1, #slots do
		slots[i].Visible = false
	end
end

----------------------------------------------------------------------
-- 3-2) 조준경 반짝임: 다른 보조수가 스나로 조준 중이면 그 사람 머리에 번쩍이는 별
----------------------------------------------------------------------

local glints: { [Player]: BillboardGui } = {}

local function makeGlint(head: BasePart): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Name = "ScopeGlint"
	bb.Size = UDim2.fromScale(5, 5) -- 스터드 단위 (멀어도 보이게 큼)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 0.3, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 3000
	bb.Adornee = head
	bb.Parent = gui
	local core = newFrame(bb, UDim2.fromScale(0.35, 0.35), UDim2.fromScale(0.5, 0.5), Color3.new(1, 1, 1), Vector2.new(0.5, 0.5))
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = core
	for _, rot in { 0, 90, 45, -45 } do
		local ray = newFrame(bb, UDim2.fromScale(rot % 90 == 0 and 1 or 0.6, 0.06), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(200, 240, 255), Vector2.new(0.5, 0.5))
		ray.Rotation = rot
	end
	return bb
end

local function updateGlints(now: number)
	local seen = {}
	for _, p in Players:GetPlayers() do
		local head = p ~= player and p.Character and p.Character:FindFirstChild("Head")
		if head and head:IsA("BasePart") and p:GetAttribute("Scoped") == true then
			seen[p] = true
			local bb = glints[p]
			if not bb or bb.Adornee ~= head then
				if bb then
					bb:Destroy()
				end
				bb = makeGlint(head)
				glints[p] = bb
			end
			-- 반짝반짝 (크기 맥박)
			local s = 4 + 1.6 * math.abs(math.sin(now * 9))
			bb.Size = UDim2.fromScale(s, s)
		end
	end
	for p, bb in glints do
		if not seen[p] then
			bb:Destroy()
			glints[p] = nil
		end
	end
end

----------------------------------------------------------------------
-- 4) 다운 알림 + 부활 카운트다운
----------------------------------------------------------------------

local banner = newText(gui, UDim2.fromOffset(600, 40), UDim2.new(0.5, 0, 0, 90), 26, Vector2.new(0.5, 0))
banner.Visible = false
local bannerUntil, bannerText = 0, ""
local deadText = newText(gui, UDim2.fromOffset(600, 60), UDim2.fromScale(0.5, 0.4), 40, Vector2.new(0.5, 0.5))
deadText.Visible = false
local diedAt: number? = nil

local function showBanner(text: string, color: Color3)
	bannerText = text
	bannerUntil = os.clock() + RESPAWN
	banner.TextColor3 = color
	banner.Visible = true
end

local watched: { [Humanoid]: boolean } = {}
local lastVehicle: Model? = nil

local function vehicleOf(inst: Instance?): Model?
	local folder = workspace:FindFirstChild("Vehicles")
	while inst and inst.Parent ~= folder do
		inst = inst.Parent
	end
	return inst and inst:IsA("Model") and inst or nil
end

local function watchCrew(model: Model)
	for _, s in model:GetDescendants() do
		if s:IsA("Seat") and s.Occupant and not watched[s.Occupant] then
			local hum = s.Occupant
			local isDriver = s.Name == "DriverSeat"
			watched[hum] = true
			hum.Died:Connect(function()
				if hum.Parent == player.Character then
					return -- 내 죽음은 가운데 카운트다운으로
				end
				if isDriver then
					showBanner("운전수 다운! 차가 멈춰요", Color3.fromRGB(255, 90, 70))
				else
					showBanner("보조수 다운! 공격 불가", Color3.fromRGB(255, 170, 60))
				end
			end)
			hum.AncestryChanged:Connect(function(_, parent)
				if not parent then
					watched[hum] = nil
				end
			end)
		end
	end
end

local function onCharacter(char: Model)
	diedAt = nil
	deadText.Visible = false
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum.Died:Connect(function()
		diedAt = os.clock()
	end)
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

----------------------------------------------------------------------
-- 서버 알림 + 매 프레임
----------------------------------------------------------------------

Remote.OnClientEvent:Connect(function(kind, a, b, c, d, e)
	if kind == "Hurt" and type(a) == "number" and typeof(b) == "Vector3" then
		hurt(a, b, type(c) == "string" and c or "person")
	elseif kind == "Hit" and type(c) == "number" and typeof(d) == "Vector3" then
		damageNumber(c, d, a, b == true)
		if typeof(e) == "Instance" then
			flash(e)
		end
	end
end)

local acc = 0
RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	-- 빨간 가장자리 서서히 사라짐
	edgeAlpha = math.min(edgeAlpha + dt * 2.2, 1)
	for _, f in edges do
		f.BackgroundTransparency = edgeAlpha
	end
	-- 방향 화살표: 카메라 기준 맞은 쪽을 가리킴
	local cam = workspace.CurrentCamera
	for i = #arrows, 1, -1 do
		local ar = arrows[i]
		ar.t += dt
		if ar.t > 0.9 then
			ar.label:Destroy()
			table.remove(arrows, i)
		else
			local rel = cam.CFrame:PointToObjectSpace(ar.from)
			local ang = math.atan2(rel.X, -rel.Z) -- 0 = 정면(화면 위)
			ar.label.Position = UDim2.new(0.5, math.sin(ang) * 130, 0.5, -math.cos(ang) * 130)
			ar.label.Rotation = math.deg(ang)
			ar.label.TextTransparency = math.max(ar.t - 0.4, 0) / 0.5
		end
	end

	updateGlints(now)

	-- 내 체력
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		local r = hum.MaxHealth > 0 and hum.Health / hum.MaxHealth or 0
		myBar.Size = UDim2.fromScale(math.clamp(r, 0, 1), 1)
		myBar.BackgroundColor3 = hpColor(r)
		myText.Text = string.format("체력 %d", math.max(math.floor(hum.Health + 0.5), 0))
	end

	-- 내가 죽음: 부활 카운트다운
	if diedAt then
		local left = math.max(RESPAWN - (now - diedAt), 0)
		deadText.Visible = true
		deadText.Text = string.format("다운! %d초 뒤 부활", math.ceil(left))
		deadText.TextColor3 = Color3.fromRGB(255, 80, 70)
	end

	-- 우리 차 동료 다운 알림
	if banner.Visible then
		local left = bannerUntil - now
		if left <= 0 then
			banner.Visible = false
		else
			banner.Text = string.format("%s (%d초)", bannerText, math.ceil(left))
		end
	end

	-- 10번/초: 머리 위 체력, 우리 차 감시
	acc += dt
	if acc < 0.1 then
		return
	end
	acc = 0
	local mine = hum and vehicleOf(hum.SeatPart)
	if mine then
		lastVehicle = mine
	end
	if lastVehicle and lastVehicle.Parent then
		watchCrew(lastVehicle)
	end
	local folder = workspace:FindFirstChild("Vehicles")
	local seen: { [Model]: boolean } = {}
	if folder then
		for _, model in folder:GetChildren() do
			local chassis = model:IsA("Model") and model.PrimaryPart
			if chassis and model ~= mine and not model:GetAttribute("Exploded") then
				seen[model] = true
				local o = overheads[model] or makeOverhead(model, chassis)
				overheads[model] = o
				updateOverhead(o, model)
			end
		end
	end
	for model, o in overheads do
		if not seen[model] then
			o.gui:Destroy()
			overheads[model] = nil
		end
	end
end)
