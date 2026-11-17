-- 운전 카메라: 3인칭 추적 ↔ 1인칭 운전석 (C 키)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CamConfig = require(ReplicatedStorage.Shared.Config.GameplayConfig).Camera

local ChaseCamera = {}

local BIND = "CarCamera"
local mode = "Third"
local active = false
local currentCF: CFrame? = nil
local boosting = false

local function setCharacterHidden(hidden: boolean)
	local char = Players.LocalPlayer.Character
	if not char then
		return
	end
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

local speedRatio = 0

function ChaseCamera.SetBoosting(on: boolean)
	boosting = on
end

-- 0 ~ 1+ (최고속 대비). 속도감 연출용
function ChaseCamera.SetSpeedRatio(r: number)
	speedRatio = r
end

local shakeT = 0

-- 드리프트 연출: 0~1 세기와 방향 (+1 오른쪽, -1 왼쪽)
local driftBlend, driftDir = 0, 0
local smoothDrift, smoothRoll = 0, 0
local punch = 0

function ChaseCamera.SetDrift(blend: number, dir: number)
	driftBlend, driftDir = blend, dir
end

-- 순간 흔들림 (드리프트 진입, 큰 충돌 등)
function ChaseCamera.Punch(amount: number)
	punch = math.max(punch, amount)
end

-- ===== 둘러보기: 우클릭 누른 채 마우스 이동 / 게임패드 오른쪽 스틱 =====
-- 손을 떼면 서서히 차 뒤로 돌아옴
local orbitYaw, orbitPitch = 0, 0
local camYaw: number?, camPitch = nil, 0 -- 실제 카메라 각도 (부드럽게 따라감)
local orbiting = false
local stick2 = Vector2.zero
local inputConns: { RBXScriptConnection } = {}

local function stopOrbitInput()
	for _, c in inputConns do
		c:Disconnect()
	end
	table.clear(inputConns)
	orbiting = false
	stick2 = Vector2.zero
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

local function startOrbitInput()
	stopOrbitInput()
	table.insert(inputConns, UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and not processed then
			orbiting = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	end))
	table.insert(inputConns, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			orbiting = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end))
	table.insert(inputConns, UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement and orbiting then
			orbitYaw -= input.Delta.X * CamConfig.orbitSensitivity
			orbitPitch = math.clamp(orbitPitch + input.Delta.Y * CamConfig.orbitSensitivity, CamConfig.orbitPitchMin, CamConfig.orbitPitchMax)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local p = input.Position
			stick2 = Vector2.new(p.X, p.Y)
			if stick2.Magnitude < 0.2 then
				stick2 = Vector2.zero
			end
		end
	end))
end

local function updateOrbit(dt: number)
	if stick2.Magnitude > 0 then
		orbitYaw -= stick2.X * CamConfig.orbitStickSpeed * dt
		orbitPitch = math.clamp(orbitPitch - stick2.Y * CamConfig.orbitStickSpeed * dt, CamConfig.orbitPitchMin, CamConfig.orbitPitchMax)
	elseif not orbiting then
		-- 손 떼면 차 뒤로 돌아오기 (한 바퀴 넘게 돌려도 가까운 쪽으로)
		orbitYaw = (orbitYaw + math.pi) % (2 * math.pi) - math.pi
		local k = math.min(dt * CamConfig.orbitReturnSpeed, 1)
		orbitYaw -= orbitYaw * k
		orbitPitch -= orbitPitch * k
	end
end

function ChaseCamera.Start(model: Model, seat: BasePart)
	local chassis = model.PrimaryPart :: BasePart
	local camera = workspace.CurrentCamera
	local size = model:GetExtentsSize()
	local dist = math.max(size.Z * CamConfig.distance, CamConfig.minDistance)
	local height = dist * CamConfig.height
	local fpAttachment = seat:FindFirstChild("DriverCamera") :: Attachment?

	active = true
	currentCF = nil
	camYaw, camPitch = nil, 0
	orbitYaw, orbitPitch = 0, 0
	camera.CameraType = Enum.CameraType.Scriptable
	startOrbitInput()

	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
		if not chassis.Parent then
			return
		end
		local cf = chassis.CFrame
		-- 속도감: 빠를수록 시야가 넓어지고, 부스터면 더 넓게
		local sr = math.clamp(speedRatio, 0, 1.5)
		local targetFov = CamConfig.fov + (CamConfig.speedFov - CamConfig.fov) * math.min(sr, 1)
		if boosting then
			targetFov += CamConfig.boostFovAdd
		end
		smoothDrift += (driftBlend - smoothDrift) * math.min(dt * 6, 1)
		targetFov += CamConfig.driftFovAdd * smoothDrift
		camera.FieldOfView += (targetFov - camera.FieldOfView) * math.min(dt * 5, 1)
		-- 속도감: 고속/부스터에서 살짝 흔들림 + 순간 흔들림(punch)
		shakeT += dt
		punch = math.max(punch - dt * 3, 0)
		local shakeAmt = CamConfig.shake * (math.max(sr - 0.6, 0) ^ 2 + (boosting and 0.25 or 0)) + punch
		local shake = Vector3.new(
			math.noise(shakeT * 13, 0, 0),
			math.noise(0, shakeT * 13, 0),
			0
		) * shakeAmt
		updateOrbit(dt)
		local orbitRot = CFrame.Angles(0, orbitYaw, 0)

		if mode == "First" then
			setCharacterHidden(true)
			local eye = fpAttachment and fpAttachment.WorldCFrame
				or (seat.CFrame * CFrame.new(CamConfig.firstPersonOffset))
			-- 1인칭에서도 둘러보기 (고개 돌리기)
			local look = orbitRot:VectorToWorldSpace(cf.LookVector)
			look = (look - Vector3.yAxis * math.sin(orbitPitch)).Unit
			camera.CFrame = CFrame.lookAt(eye.Position, eye.Position + look, cf.UpVector)
			currentCF = nil
			return
		end
		setCharacterHidden(false)

		-- 수평 방향만 따라가서 차가 뒤집혀도 카메라는 안정적
		local flat = cf.LookVector * Vector3.new(1, 0, 1)
		if flat.Magnitude < 0.1 then
			flat = Vector3.new(0, 0, -1)
		end
		flat = flat.Unit
		-- 드리프트 중엔 차 머리 대신 "진행 방향" 쪽을 따라감 → 차가 옆으로 미끄러지는 각도가 화면에 보임
		local v = chassis.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
		if smoothDrift > 0.01 and v.Magnitude > 10 then
			flat = flat:Lerp(v.Unit, CamConfig.driftFollowVelocity * smoothDrift)
			if flat.Magnitude > 0.01 then
				flat = flat.Unit
			end
		end
		-- 드리프트 방향 반대로 살짝 기울기 (원심력 느낌)
		local targetRoll = math.rad(CamConfig.driftRoll) * driftDir * smoothDrift
		smoothRoll += (targetRoll - smoothRoll) * math.min(dt * 5, 1)
		-- 빠를수록 카메라가 살짝 뒤로 빠짐
		local d = dist * (1 + CamConfig.speedPullBack * math.min(sr, 1.3))
		-- 각도 기준 카메라: 차를 중심으로 (좌우각, 위아래각, 거리) 로 위치를 정함
		-- → 둘러볼 때 항상 원을 그리며 돌고, 위치를 보간하다 차를 가로지르는 문제 없음
		local headingYaw = math.atan2(-flat.X, -flat.Z)
		local targetYaw = headingYaw + orbitYaw
		local basePitch = math.atan2(height * 0.7, d)
		local targetPitch = math.clamp(basePitch + orbitPitch, -0.2, 1.35)
		local alpha = 1 - math.exp(-CamConfig.followSharpness * dt)
		if camYaw == nil then
			camYaw, camPitch = targetYaw, targetPitch
		end
		-- 가까운 쪽으로 돌기 (한 바퀴 차이 보정)
		local diff = (targetYaw - camYaw + math.pi) % (2 * math.pi) - math.pi
		-- 드래그 중엔 손 따라 바로, 아닐 땐 부드럽게 차 뒤로 따라감
		camYaw += diff * (orbiting and 1 or alpha)
		camPitch += (targetPitch - camPitch) * (orbiting and 1 or alpha)
		local focus = chassis.Position + Vector3.new(0, height * 0.3, 0)
		local look = CFrame.fromEulerAnglesYXZ(-camPitch, camYaw, 0).LookVector
		local pos = focus - look * math.sqrt(d * d + (height * 0.7) ^ 2)
		currentCF = CFrame.lookAt(pos, focus)
		camera.CFrame = currentCF * CFrame.Angles(0, 0, smoothRoll) * CFrame.new(shake)
		if orbiting then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition -- 기본 카메라가 풀어버리는 것 방지
		end
	end)
end

function ChaseCamera.Toggle()
	mode = (mode == "Third") and "First" or "Third"
end

function ChaseCamera.Stop()
	if not active then
		return
	end
	active = false
	RunService:UnbindFromRenderStep(BIND)
	stopOrbitInput()
	driftBlend, driftDir, smoothDrift, smoothRoll, punch = 0, 0, 0, 0, 0
	setCharacterHidden(false)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = CamConfig.fov
	local hum = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		camera.CameraSubject = hum
	end
end

return ChaseCamera
