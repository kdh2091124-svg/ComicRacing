-- 키 설정은 여기서만. 키보드 + 게임패드. (모바일은 화면 버튼 → MobileControls)
-- Hold: 누르고 있는 동안 / Press: 누르는 순간 한 번

local InputConfig = {}

InputConfig.Hold = {
	Throttle = { Enum.KeyCode.W, Enum.KeyCode.Up, Enum.KeyCode.ButtonR2 },
	Brake = { Enum.KeyCode.S, Enum.KeyCode.Down, Enum.KeyCode.ButtonL2 },
	SteerLeft = { Enum.KeyCode.A, Enum.KeyCode.Left },
	SteerRight = { Enum.KeyCode.D, Enum.KeyCode.Right },
	Drift = { Enum.KeyCode.Space, Enum.KeyCode.ButtonX },
	Boost = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonA },
}

InputConfig.Press = {
	Exit = { Enum.KeyCode.F, Enum.KeyCode.ButtonY },
	Lights = { Enum.KeyCode.L, Enum.KeyCode.DPadUp },
	Camera = { Enum.KeyCode.C, Enum.KeyCode.ButtonR3 },
	Restart = { Enum.KeyCode.Backspace, Enum.KeyCode.ButtonSelect }, -- 트라이얼: 처음부터 다시
	Respawn = { Enum.KeyCode.R, Enum.KeyCode.DPadDown }, -- 마지막 체크포인트로 복귀
}

InputConfig.GamepadSteerDeadzone = 0.15

return InputConfig
