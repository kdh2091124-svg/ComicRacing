-- 임시 HUD: 속도/부스터 게이지, 차 꺼내기(개발용), 내 차 권한 설정, 알림.
-- 정식 UI 디자인은 나중에 교체.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local VehicleConfig = require(Shared.Config.VehicleConfig)
local GameplayConfig = require(Shared.Config.GameplayConfig)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local VehicleAction = Remotes:WaitForChild("VehicleAction") :: RemoteEvent
local Notify = Remotes:WaitForChild("Notify") :: RemoteEvent

local ClientSettings = require(script.Parent:WaitForChild("ClientSettings"))

local player = Players.LocalPlayer
local HUD = {}

local DARK = Color3.fromRGB(20, 20, 25)
local ACCENT = Color3.fromRGB(255, 170, 30)

local function corner(parent: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = parent
end

local function button(parent: Instance, text: string, size: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	b.Size = size
	b.BackgroundColor3 = DARK
	b.BackgroundTransparency = 0.2
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	corner(b)
	b.Parent = parent
	return b
end

local gui = Instance.new("ScreenGui")
gui.Name = "RacingHUD"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

-- 왼쪽 위 메뉴 버튼
local menuBar = Instance.new("Frame")
menuBar.BackgroundTransparency = 1
menuBar.Position = UDim2.fromOffset(12, 60)
menuBar.Size = UDim2.fromOffset(140, 90)
menuBar.Parent = gui
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.Parent = menuBar

local spawnBtn = button(menuBar, "차 꺼내기", UDim2.fromOffset(140, 36))
local settingsBtn = button(menuBar, "설정", UDim2.fromOffset(140, 36))

-- 차 목록 패널
local spawnPanel = Instance.new("ScrollingFrame")
spawnPanel.Visible = false
spawnPanel.Position = UDim2.fromOffset(160, 60)
spawnPanel.Size = UDim2.fromOffset(220, 320)
spawnPanel.BackgroundColor3 = DARK
spawnPanel.BackgroundTransparency = 0.15
spawnPanel.ScrollBarThickness = 6
spawnPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
spawnPanel.CanvasSize = UDim2.new()
corner(spawnPanel)
spawnPanel.Parent = gui
local spawnList = Instance.new("UIListLayout")
spawnList.Padding = UDim.new(0, 4)
spawnList.Parent = spawnPanel
local spPad = Instance.new("UIPadding")
spPad.PaddingTop = UDim.new(0, 6)
spPad.PaddingLeft = UDim.new(0, 6)
spPad.PaddingRight = UDim.new(0, 12)
spPad.Parent = spawnPanel

for i, def in VehicleConfig.Vehicles do
	local b = button(spawnPanel, string.format("%s  (%d인승)", def.name, def.seats), UDim2.new(1, 0, 0, 32))
	b.LayoutOrder = i
	b.TextSize = 14
	b.MouseButton1Click:Connect(function()
		VehicleAction:FireServer("Spawn", def.id)
		spawnPanel.Visible = false
	end)
end

-- 권한 설정 패널
local permPanel = Instance.new("Frame")
permPanel.Visible = false
permPanel.Position = UDim2.fromOffset(160, 60)
permPanel.Size = UDim2.fromOffset(330, 190)
permPanel.BackgroundColor3 = DARK
permPanel.BackgroundTransparency = 0.15
corner(permPanel)
permPanel.Parent = gui

local permButtons: { [string]: { [string]: TextButton } } = {}
local function permRow(kind: string, title: string, y: number)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(12, y)
	label.Size = UDim2.fromOffset(300, 20)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = title
	label.Parent = permPanel
	permButtons[kind] = {}
	for i, level in GameplayConfig.Vehicle.permissionLevels do
		local b = button(permPanel, GameplayConfig.Vehicle.permissionLabels[level], UDim2.fromOffset(96, 30))
		b.Position = UDim2.fromOffset(12 + (i - 1) * 104, y + 22)
		b.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
		b.MouseButton1Click:Connect(function()
			VehicleAction:FireServer("SetPermission", kind, level)
		end)
		permButtons[kind][level] = b
	end
end
permRow("Drive", "내 차 운전 가능", 8)
permRow("Ride", "내 차 동승 가능", 66)

local function refreshPerms()
	for kind, buttons in permButtons do
		local current = player:GetAttribute("Perm_" .. kind)
		for level, b in buttons do
			b.BackgroundColor3 = (level == current) and ACCENT or Color3.fromRGB(55, 55, 65)
			b.TextColor3 = (level == current) and DARK or Color3.new(1, 1, 1)
		end
	end
end
player.AttributeChanged:Connect(function(name)
	if string.sub(name, 1, 5) == "Perm_" then
		refreshPerms()
	end
end)
refreshPerms()

-- 주행 보조 켜기/끄기 (내 조작에만 적용)
do
	local y = 124
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(12, y)
	label.Size = UDim2.fromOffset(300, 20)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = "주행 보조 (스핀 방지, 자동 카운터)"
	label.Parent = permPanel
	local onBtn = button(permPanel, "켜기", UDim2.fromOffset(96, 30))
	onBtn.Position = UDim2.fromOffset(12, y + 22)
	local offBtn = button(permPanel, "끄기", UDim2.fromOffset(96, 30))
	offBtn.Position = UDim2.fromOffset(116, y + 22)
	local function refreshAssist()
		local on = ClientSettings.Get("DriveAssist")
		onBtn.BackgroundColor3 = on and ACCENT or Color3.fromRGB(55, 55, 65)
		onBtn.TextColor3 = on and DARK or Color3.new(1, 1, 1)
		offBtn.BackgroundColor3 = (not on) and ACCENT or Color3.fromRGB(55, 55, 65)
		offBtn.TextColor3 = (not on) and DARK or Color3.new(1, 1, 1)
	end
	onBtn.MouseButton1Click:Connect(function()
		ClientSettings.Set("DriveAssist", true)
	end)
	offBtn.MouseButton1Click:Connect(function()
		ClientSettings.Set("DriveAssist", false)
	end)
	ClientSettings.Changed:Connect(refreshAssist)
	refreshAssist()
end

spawnBtn.MouseButton1Click:Connect(function()
	spawnPanel.Visible = not spawnPanel.Visible
	permPanel.Visible = false
end)
settingsBtn.MouseButton1Click:Connect(function()
	permPanel.Visible = not permPanel.Visible
	spawnPanel.Visible = false
end)

-- 운전 패널 (아래 가운데)
local drivePanel = Instance.new("Frame")
drivePanel.Visible = false
drivePanel.AnchorPoint = Vector2.new(0.5, 1)
drivePanel.Position = UDim2.new(0.5, 0, 1, -16)
drivePanel.Size = UDim2.fromOffset(320, 82)
drivePanel.BackgroundColor3 = DARK
drivePanel.BackgroundTransparency = 0.3
corner(drivePanel, 10)
drivePanel.Parent = gui

local speedLabel = Instance.new("TextLabel")
speedLabel.BackgroundTransparency = 1
speedLabel.Size = UDim2.new(1, 0, 0, 36)
speedLabel.Font = Enum.Font.GothamBlack
speedLabel.TextSize = 28
speedLabel.TextColor3 = Color3.new(1, 1, 1)
speedLabel.Parent = drivePanel

local boostBack = Instance.new("Frame")
boostBack.Position = UDim2.new(0, 12, 0, 42)
boostBack.Size = UDim2.new(1, -24, 0, 12)
boostBack.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
corner(boostBack, 6)
boostBack.Parent = drivePanel
local boostFill = Instance.new("Frame")
boostFill.Size = UDim2.fromScale(1, 1)
boostFill.BackgroundColor3 = Color3.fromRGB(60, 200, 255)
corner(boostFill, 6)
boostFill.Parent = boostBack

-- HP 바 (부스터 게이지 아래)
local hpBack = Instance.new("Frame")
hpBack.Position = UDim2.new(0, 12, 0, 60)
hpBack.Size = UDim2.new(1, -24, 0, 12)
hpBack.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
corner(hpBack, 6)
hpBack.Parent = drivePanel
local hpFill = Instance.new("Frame")
hpFill.Size = UDim2.fromScale(1, 1)
hpFill.BackgroundColor3 = Color3.fromRGB(90, 230, 110)
corner(hpFill, 6)
hpFill.Parent = hpBack
local lastHp = nil :: number?

function HUD.SetHP(hp: any, maxHp: any)
	if type(hp) ~= "number" or type(maxHp) ~= "number" or maxHp <= 0 then
		return
	end
	local r = math.clamp(hp / maxHp, 0, 1)
	hpFill.Size = UDim2.fromScale(r, 1)
	-- 초록 → 노랑 → 빨강
	hpFill.BackgroundColor3 = Color3.fromRGB(255, 70, 60):Lerp(Color3.fromRGB(90, 230, 110), r)
	if lastHp and hp < lastHp - 1 then
		-- 맞으면 바가 하얗게 번쩍
		hpBack.BackgroundColor3 = Color3.new(1, 1, 1)
		task.delay(0.08, function()
			hpBack.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
		end)
	end
	lastHp = hp
end

-- 동승자 "내리기" 버튼 (모바일 포함 모두)
local passengerBtn = button(gui, "내리기 (F)", UDim2.fromOffset(160, 44))
passengerBtn.AnchorPoint = Vector2.new(0.5, 1)
passengerBtn.Position = UDim2.new(0.5, 0, 1, -20)
passengerBtn.Visible = false
local passengerCallback: (() -> ())? = nil
passengerBtn.MouseButton1Click:Connect(function()
	if passengerCallback then
		passengerCallback()
	end
end)

function HUD.SetPassenger(on: boolean, callback: (() -> ())?)
	passengerBtn.Visible = on
	passengerCallback = callback
end

-- 드리프트 충전 단계 표시 (운전 패널 위)
local driftLabel = Instance.new("TextLabel")
driftLabel.AnchorPoint = Vector2.new(0.5, 1)
driftLabel.Position = UDim2.new(0.5, 0, 0, -6)
driftLabel.Size = UDim2.fromOffset(220, 28)
driftLabel.BackgroundTransparency = 1
driftLabel.Font = Enum.Font.GothamBlack
driftLabel.TextSize = 22
driftLabel.TextStrokeTransparency = 0.4
driftLabel.Text = ""
driftLabel.Parent = drivePanel

local TIER_COLORS = {
	Color3.fromRGB(80, 180, 255),
	Color3.fromRGB(255, 170, 30),
	Color3.fromRGB(255, 70, 200),
}

function HUD.SetDriftTier(tier: number, boosting: boolean)
	if boosting then
		driftLabel.Text = "부스트!"
		driftLabel.TextColor3 = Color3.fromRGB(120, 255, 140)
	elseif tier > 0 then
		driftLabel.Text = "드리프트 " .. string.rep("●", tier)
		driftLabel.TextColor3 = TIER_COLORS[math.min(tier, #TIER_COLORS)]
	else
		driftLabel.Text = ""
	end
end

function HUD.SetDriving(on: boolean)
	drivePanel.Visible = on
	lastHp = nil
	if not on then
		driftLabel.Text = ""
	end
end

function HUD.Update(speedStudsPerSec: number, boost01: number, topSpeed: number?)
	-- 표시용 km/h (스터드/초를 그대로 표시, 느낌용)
	local speed = math.floor(math.abs(speedStudsPerSec) + 0.5)
	if topSpeed then
		speedLabel.Text = string.format("%d km/h   TOP %d", speed, math.floor(topSpeed + 0.5))
	else
		speedLabel.Text = string.format("%d km/h", speed)
	end
	boostFill.Size = UDim2.fromScale(math.clamp(boost01, 0, 1), 1)
end

-- 알림 토스트
local toast = Instance.new("TextLabel")
toast.Visible = false
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 70)
toast.Size = UDim2.fromOffset(360, 40)
toast.BackgroundColor3 = DARK
toast.BackgroundTransparency = 0.2
toast.TextColor3 = Color3.new(1, 1, 1)
toast.Font = Enum.Font.GothamBold
toast.TextSize = 16
corner(toast)
toast.Parent = gui
local toastToken = 0

function HUD.Toast(text: string)
	toastToken += 1
	local my = toastToken
	toast.Text = text
	toast.Visible = true
	task.delay(2.5, function()
		if toastToken == my then
			toast.Visible = false
		end
	end)
end

-- ===== 트라이얼 HUD (화면 위 가운데) =====
local trialPanel = Instance.new("Frame")
trialPanel.Visible = false
trialPanel.AnchorPoint = Vector2.new(0.5, 0)
trialPanel.Position = UDim2.new(0.5, 0, 0, 8)
trialPanel.Size = UDim2.fromOffset(300, 92)
trialPanel.BackgroundColor3 = DARK
trialPanel.BackgroundTransparency = 0.25
corner(trialPanel, 12)
trialPanel.Parent = gui

local function trialLabel(y: number, h: number, size: number, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(0, y)
	l.Size = UDim2.new(1, 0, 0, h)
	l.Font = font
	l.TextSize = size
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Text = ""
	l.Parent = trialPanel
	return l
end

local sectionLabel = trialLabel(4, 22, 17, Enum.Font.GothamBold) -- 구간 이름 + 델타
local timerLabel = trialLabel(26, 36, 32, Enum.Font.GothamBlack) -- 0:12.85
local progressLabel = trialLabel(64, 22, 14, Enum.Font.GothamBold) -- CP 3/8 · LAP 1/3 · 최고 1:02.10

local GOOD = Color3.fromRGB(90, 255, 130)
local BAD = Color3.fromRGB(255, 90, 90)
local trialTotal, trialBest = 0, nil :: number?

local function fmtTime(t: number): string
	local m = math.floor(t / 60)
	local s = t - m * 60
	return string.format("%d:%05.2f", m, s)
end

local function fmtDelta(d: number): string
	return (d >= 0 and "+" or "-") .. string.format("%.2f", math.abs(d))
end

local function progressText(index: number, lap: string?): string
	local parts = { string.format("CP %d/%d", index, trialTotal) }
	if lap then
		table.insert(parts, lap)
	end
	if trialBest then
		table.insert(parts, "최고 " .. fmtTime(trialBest))
	end
	return table.concat(parts, "  ·  ")
end

function HUD.TrialReady(courseName: string)
	trialPanel.Visible = true
	sectionLabel.Text = courseName
	sectionLabel.TextColor3 = Color3.new(1, 1, 1)
	timerLabel.Text = "0:00.00"
	progressLabel.Text = "출발선을 지나면 시작"
end

function HUD.TrialStart(courseName: string, total: number, best: number?, lap: string?)
	trialTotal, trialBest = total, best
	trialPanel.Visible = true
	sectionLabel.Text = courseName
	sectionLabel.TextColor3 = Color3.new(1, 1, 1)
	timerLabel.Text = "0:00.00"
	progressLabel.Text = progressText(0, lap)
end

function HUD.TrialTime(t: number)
	timerLabel.Text = fmtTime(t)
end

function HUD.TrialSplit(index: number, total: number, _t: number, delta: number?, section: string, lap: string?)
	trialTotal = total
	local name = section ~= "" and section or ("CP " .. index)
	if delta then
		sectionLabel.Text = name .. "   " .. fmtDelta(delta)
		sectionLabel.TextColor3 = delta <= 0 and GOOD or BAD
	else
		sectionLabel.Text = name
		sectionLabel.TextColor3 = Color3.new(1, 1, 1)
	end
	progressLabel.Text = progressText(index, lap)
end

function HUD.TrialFinish(t: number, prevBest: number?, isNew: boolean, delta: number?)
	timerLabel.Text = fmtTime(t)
	if isNew then
		sectionLabel.Text = prevBest and ("신기록! " .. fmtDelta(t - prevBest)) or "첫 기록!"
		sectionLabel.TextColor3 = GOOD
	else
		sectionLabel.Text = "완주  " .. (delta and fmtDelta(delta) or "")
		sectionLabel.TextColor3 = BAD
	end
	progressLabel.Text = "Backspace: 다시 도전"
	HUD.Toast(isNew and ("신기록 " .. fmtTime(t)) or ("완주 " .. fmtTime(t)))
end

function HUD.TrialHide()
	trialPanel.Visible = false
end

Notify.OnClientEvent:Connect(function(text)
	if type(text) == "string" then
		HUD.Toast(text)
	end
end)

return HUD
