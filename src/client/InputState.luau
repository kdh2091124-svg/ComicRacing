-- 운전 입력 모으기: 키보드 + 게임패드 + 모바일 버튼을 한 곳으로.
-- 운전 중에만 Enable() → Space 점프, F 등 걸을 때 키와 안 겹치게.

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputConfig = require(ReplicatedStorage.Shared.Config.InputConfig)

local InputState = {}

local held: { [string]: { [string]: boolean } } = {}
local onPress: ((string) -> ())? = nil
local stickX = 0
local enabled = false
local stickConn: RBXScriptConnection? = nil

local PRIORITY = Enum.ContextActionPriority.High.Value + 10

local function setHeld(action: string, source: string, down: boolean)
	held[action] = held[action] or {}
	held[action][source] = down or nil
end

local function isHeld(action: string): boolean
	local t = held[action]
	return t ~= nil and next(t) ~= nil
end

local function holdHandler(name: string, state: Enum.UserInputState, input: InputObject)
	local action = string.sub(name, 5) -- "Car_" 제거
	if state == Enum.UserInputState.Begin then
		setHeld(action, input.KeyCode.Name, true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		setHeld(action, input.KeyCode.Name, false)
	end
	return Enum.ContextActionResult.Sink
end

local function pressHandler(name: string, state: Enum.UserInputState, _input: InputObject)
	if state == Enum.UserInputState.Begin and onPress then
		onPress(string.sub(name, 5))
	end
	return Enum.ContextActionResult.Sink
end

function InputState.Enable(pressCallback: (string) -> ())
	if enabled then
		return
	end
	enabled = true
	onPress = pressCallback
	for action, keys in InputConfig.Hold do
		ContextActionService:BindActionAtPriority("Car_" .. action, holdHandler, false, PRIORITY, table.unpack(keys))
	end
	for action, keys in InputConfig.Press do
		ContextActionService:BindActionAtPriority("Car_" .. action, pressHandler, false, PRIORITY, table.unpack(keys))
	end
	stickConn = UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local x = input.Position.X
			stickX = math.abs(x) > InputConfig.GamepadSteerDeadzone and x or 0
		end
	end)
end

function InputState.Disable()
	if not enabled then
		return
	end
	enabled = false
	onPress = nil
	for action in InputConfig.Hold do
		ContextActionService:UnbindAction("Car_" .. action)
	end
	for action in InputConfig.Press do
		ContextActionService:UnbindAction("Car_" .. action)
	end
	if stickConn then
		stickConn:Disconnect()
		stickConn = nil
	end
	table.clear(held)
	stickX = 0
end

-- 모바일 버튼용
function InputState.SetVirtual(action: string, down: boolean)
	setHeld(action, "Touch", down)
end

function InputState.PressVirtual(action: string)
	if onPress then
		onPress(action)
	end
end

function InputState.Read()
	local steer = (isHeld("SteerRight") and 1 or 0) - (isHeld("SteerLeft") and 1 or 0)
	if steer == 0 then
		steer = stickX
	end
	return {
		throttle = isHeld("Throttle") and 1 or 0,
		brake = isHeld("Brake") and 1 or 0,
		steer = steer, -- -1 왼쪽 ~ +1 오른쪽
		drift = isHeld("Drift"),
		boost = isHeld("Boost"),
	}
end

return InputState
