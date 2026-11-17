-- 모바일 운전 버튼 (터치 기기에서 운전 중일 때만 보임).
-- 왼쪽: ◀ ▶ 방향 / 오른쪽: 가속, 브레이크, 드리프트, 부스터 / 오른쪽 위: 내리기, 라이트, 시점
-- 위치/크기는 아래 LAYOUT 표만 고치면 됨.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local InputState = require(script.Parent.InputState)

local MobileControls = {}

-- { 액션, 글자, 앵커X, 앵커Y, 위치, 크기, 종류(Hold/Press) }
local LAYOUT = {
	{ "SteerLeft", "◀", 0, 1, UDim2.new(0, 20, 1, -20), 110, "Hold" },
	{ "SteerRight", "▶", 0, 1, UDim2.new(0, 145, 1, -20), 110, "Hold" },
	{ "Throttle", "가속", 1, 1, UDim2.new(1, -20, 1, -20), 120, "Hold" },
	{ "Brake", "브레이크", 1, 1, UDim2.new(1, -150, 1, -20), 95, "Hold" },
	{ "Drift", "드리프트", 1, 1, UDim2.new(1, -150, 1, -125), 85, "Hold" },
	{ "Boost", "부스터", 1, 1, UDim2.new(1, -30, 1, -150), 90, "Hold" },
	{ "Exit", "내리기", 1, 0, UDim2.new(1, -20, 0, 60), 60, "Press" },
	{ "Lights", "라이트", 1, 0, UDim2.new(1, -90, 0, 60), 60, "Press" },
	{ "Camera", "시점", 1, 0, UDim2.new(1, -160, 0, 60), 60, "Press" },
	{ "Respawn", "복귀", 1, 0, UDim2.new(1, -230, 0, 60), 60, "Press" },
	{ "Restart", "재시작", 1, 0, UDim2.new(1, -300, 0, 60), 60, "Press" },
}

local gui: ScreenGui? = nil

local function build(): ScreenGui
	local sg = Instance.new("ScreenGui")
	sg.Name = "MobileDriveControls"
	sg.ResetOnSpawn = false
	sg.Enabled = false
	sg.DisplayOrder = 5

	for _, item in LAYOUT do
		local action, text, ax, ay, pos, size, kind = table.unpack(item)
		local b = Instance.new("TextButton")
		b.Name = action
		b.Text = text
		b.AnchorPoint = Vector2.new(ax, ay)
		b.Position = pos
		b.Size = UDim2.fromOffset(size, size)
		b.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		b.BackgroundTransparency = 0.35
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamBold
		b.TextScaled = true
		b.AutoButtonColor = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = b
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.18, 0)
		pad.PaddingRight = UDim.new(0.18, 0)
		pad.Parent = b

		local function isPointer(input: InputObject)
			return input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
		end
		b.InputBegan:Connect(function(input)
			if not isPointer(input) then
				return
			end
			b.BackgroundTransparency = 0.1
			if kind == "Hold" then
				InputState.SetVirtual(action, true)
			else
				InputState.PressVirtual(action)
			end
		end)
		b.InputEnded:Connect(function(input)
			if not isPointer(input) then
				return
			end
			b.BackgroundTransparency = 0.35
			if kind == "Hold" then
				InputState.SetVirtual(action, false)
			end
		end)
		b.Parent = sg
	end

	sg.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return sg
end

local function setDefaultTouchGui(visible: boolean)
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local touch = pg and pg:FindFirstChild("TouchGui")
	if touch and touch:IsA("ScreenGui") then
		touch.Enabled = visible
	end
end

function MobileControls.Show()
	if not UserInputService.TouchEnabled then
		return
	end
	gui = gui or build()
	gui.Enabled = true
	setDefaultTouchGui(false) -- 기본 조이스틱/점프 버튼 숨김
end

function MobileControls.Hide()
	if gui then
		gui.Enabled = false
		for _, item in LAYOUT do
			if item[7] == "Hold" then
				InputState.SetVirtual(item[1], false)
			end
		end
	end
	setDefaultTouchGui(true)
end

return MobileControls
