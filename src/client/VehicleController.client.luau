-- 레이캐스트 서스펜션 차량 조종 (운전자 클라이언트에서 물리 계산).
-- 원리: 바퀴 위치마다 아래로 보이지 않는 선(레이)을 쏴서 땅까지 거리를 재고,
--       스프링 힘 + 옆미끄럼 방지 + 구동/브레이크 힘을 계산해 차체에 한 번에 준다.
-- 서버가 운전석에 앉은 사람에게 네트워크 소유권을 주므로 이 힘이 실제 물리에 반영된다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StatCalculator = require(Shared:WaitForChild("StatCalculator"))
local Physics = require(Shared.Config.GameplayConfig).Physics
local CamConfig = require(Shared.Config.GameplayConfig).Camera
local HealthConfig = require(Shared.Config.GameplayConfig).Health
local InputConfig = require(Shared.Config.InputConfig)

local InputState = require(script.Parent:WaitForChild("InputState"))
local ChaseCamera = require(script.Parent:WaitForChild("ChaseCamera"))
local MobileControls = require(script.Parent:WaitForChild("MobileControls"))
local HUD = require(script.Parent:WaitForChild("HUD"))
local VehicleEffects = require(script.Parent:WaitForChild("VehicleEffects"))
local TrialClient = require(script.Parent:WaitForChild("TrialClient"))
local ClientSettings = require(script.Parent:WaitForChild("ClientSettings"))
local EffectsConfig = require(Shared.Config.EffectsConfig)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local VehicleAction = Remotes:WaitForChild("VehicleAction") :: RemoteEvent
local VehicleFX = Remotes:WaitForChild("VehicleFX") :: RemoteEvent

VehicleEffects.Start() -- 모든 차의 스키드/스파크/연기/부스터 불꽃 (내 차 + 다른 사람 차)

local player = Players.LocalPlayer
local WHEEL_PREFIX = "Wheel_" -- 보이는 바퀴 (그림)
local SUSP_PREFIX = "Susp_" -- 물리 서스펜션 위치

-- 물리 바퀴 (보이지 않음, 모든 차 공통 배치)
type Wheel = {
	att: Attachment,
	isFront: boolean,
	offset: number, -- 마운트에서 땅까지 내려간 거리
}

-- 보이는 바퀴 (모델 생김새대로, 가장 가까운 물리 바퀴의 출렁임을 따라 움직임)
type Visual = {
	weld: Weld,
	basePos: Vector3,
	baseRot: CFrame,
	isFront: boolean,
	link: Wheel?,
	spin: number,
}

local session: {
	model: Model,
	chassis: BasePart,
	stats: { [string]: number },
	wheels: { Wheel },
	visuals: { Visual },
	force: VectorForce,
	torque: Torque,
	conn: RBXScriptConnection,
	steer: number,
	throttle: number,
	brake: number,
	driftBlend: number,
	frontCount: number,
	rearCount: number,
	wheelbase: number,
	inertiaK: number,
	wantYaw: number,
	driftDir: number, -- 0 = 드리프트 아님, 1 = 오른쪽, -1 = 왼쪽
	driftHold: number,
	oppositeTime: number,
	recover: number,
	wallTime: number,
	driftWasDown: boolean,
	spacePressedAt: number,
	steerPressedAt: number,
	lastSteerSign: number,
	lastDriftDir: number,
	lastGrounded: boolean,
	airTime: number,
	driftCharge: number,
	wasDrifting: boolean,
	exitBoostTime: number,
	exitBoostPower: number,
	fxDrift: boolean,
	fxTier: number,
	fxBoost: boolean,
	prevVel: Vector3,
	lastImpact: number,
	lastDamage: number,
	lastHazard: number,
	prevPos: Vector3?,
	lastCF: CFrame?,
	topSpeed: number,
	boost: number,
	flippedTime: number,
	params: RaycastParams,
	paramsAge: number,
}? = nil

local function refreshRayFilter(s)
	local ignore: { Instance } = { s.model }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	s.params.FilterDescendantsInstances = ignore
	s.paramsAge = 0
end

local function collectWheels(chassis: BasePart): { Wheel }
	local wheels = {}
	for _, att in chassis:GetChildren() do
		if att:IsA("Attachment") and string.sub(att.Name, 1, #SUSP_PREFIX) == SUSP_PREFIX then
			table.insert(wheels, {
				att = att,
				isFront = att.Position.Z < 0, -- 앞 = -Z
				offset = 0,
			})
		end
	end
	return wheels
end

local function collectVisuals(model: Model, wheels: { Wheel }): { Visual }
	local visuals = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and string.sub(part.Name, 1, #WHEEL_PREFIX) == WHEEL_PREFIX then
			local weld = part:FindFirstChild("WheelWeld")
			if weld and weld:IsA("Weld") then
				local pos = weld.C0.Position
				-- 가장 가까운 물리 바퀴와 연결 (앞뒤/좌우 기준)
				local best, bestDist = nil, math.huge
				for _, w in wheels do
					local d = (Vector2.new(w.att.Position.X, w.att.Position.Z) - Vector2.new(pos.X, pos.Z)).Magnitude
					if d < bestDist then
						best, bestDist = w, d
					end
				end
				table.insert(visuals, {
					weld = weld,
					basePos = pos,
					baseRot = weld.C0.Rotation,
					isFront = pos.Z < 0,
					link = best,
					spin = 0,
				})
			end
		end
	end
	return visuals
end

-- 평소(A/D) 최대 회전 속도. 빠를수록 줄지만 0 이 되진 않음 (부스터 중에도 핸들이 먹게)
--   옆 가속도 = base + perSpeed × 속도 → 회전 한계 = 옆 가속도 / 속도
local function normalYawCap(stats, speed: number, boosting: boolean): number
	local lat = Physics.normalLatAccelBase + Physics.normalLatAccelPerSpeed * speed
	lat *= stats.grip / 1.1
	if boosting then
		lat *= Physics.boostGrip
	end
	return lat / math.max(speed, 5)
end

local function step(dt: number)
	local s = session
	if not s then
		return
	end
	local chassis = s.chassis
	if not chassis.Parent then
		return
	end
	-- 폭발 직전 정지(히트스톱) 중: 차가 고정돼서 무게가 무한대로 잡힘 → 주행 계산 쉬기
	if chassis.Anchored or s.model:GetAttribute("Exploding") then
		s.force.Force = Vector3.zero
		s.torque.Torque = Vector3.zero
		return
	end
	local stats = s.stats

	s.paramsAge += dt
	if s.paramsAge > 1 then
		refreshRayFilter(s)
	end

	local cf = chassis.CFrame
	local up, fwd, right = cf.UpVector, cf.LookVector, cf.RightVector
	local mass = chassis.AssemblyMass
	local com = chassis.AssemblyCenterOfMass
	local vel = chassis.AssemblyLinearVelocity
	local angVel = chassis.AssemblyAngularVelocity
	local fwdSpeed = vel:Dot(fwd)
	local input = InputState.Read()
	-- 설정 > 주행 보조 (끄면 스핀 방지, 자동 카운터, 벽 방향 맞춤이 꺼짐)
	local assist = ClientSettings.Get("DriveAssist") and 1 or 0

	-- 벽 긁기: 비스듬히 박으면 속도를 거의 유지하고 벽을 따라 미끄러짐 (정면 충돌만 멈춤)
	-- 직전 프레임보다 수평 속도가 갑자기 줄었으면 "벽에 닿음" → 줄어든 방향이 벽 쪽
	do
		local WS = Physics.WallScrape
		local pv = s.prevVel
		local flatPrev = Vector3.new(pv.X, 0, pv.Z)
		local flatNow = Vector3.new(vel.X, 0, vel.Z)
		local lost = flatPrev - flatNow
		if flatPrev.Magnitude > WS.minSpeed and lost.Magnitude > WS.minDeltaV
			and flatNow.Magnitude < flatPrev.Magnitude - WS.minSpeedLoss then
			local intoWall = lost.Unit
			local incidence = math.abs(flatPrev.Unit:Dot(intoWall)) -- 1 = 정면, 0 = 나란히
			if incidence < WS.headOnCos then
				local normalPart = intoWall * flatPrev:Dot(intoWall)
				local along = flatPrev - normalPart
				local newFlat = along * WS.keep - intoWall * normalPart.Magnitude * WS.bounce
				chassis.AssemblyLinearVelocity = newFlat + Vector3.new(0, vel.Y, 0)
				-- 박은 충격으로 휙 돌아가는 것도 줄임
				chassis.AssemblyAngularVelocity = Vector3.new(angVel.X, angVel.Y * WS.yawKeep, angVel.Z)
				vel = chassis.AssemblyLinearVelocity
				angVel = chassis.AssemblyAngularVelocity
				fwdSpeed = vel:Dot(fwd)
				s.wallTime = WS.alignTime -- 잠깐 동안 차 머리를 벽 따라 가는 방향으로 맞춰줌
				-- 긁히는 쪽에 불똥
				local now = os.clock()
				if now - s.lastImpact > 0.12 then
					s.lastImpact = now
					local hitPos = chassis.Position + intoWall * (chassis.Size.X / 2) - Vector3.new(0, chassis.Size.Y / 2, 0)
					local strength = math.clamp(normalPart.Magnitude / 60, 0.3, 1)
					VehicleEffects.PlayImpact(s.model, hitPos, strength)
					VehicleFX:FireServer("Impact", hitPos, strength)
				end
			end
		end
	end

	-- ===== 드리프트 (누르고 있는 동안 도는 방식) =====
	-- Space + A(또는 D) 로 시작하면 그 방향으로 "고정". Space 를 떼면 끝.
	-- 꾹 = 계속 돌아서 깊어짐, 톡톡 = 짧게 돌고 얕음 (Space 뗀 사이엔 느슨한 각도 유지)
	-- 드리프트 중 같은 방향키 = 더 깊게, 반대 방향키 = 얕게 (반대 키를 오래 누르면 반대쪽으로 전환)
	local D = Physics.Drift
	local absSpeed = math.abs(fwdSpeed)
	local flatSpeed = (vel - Vector3.yAxis * vel.Y).Magnitude
	-- 입력 순서 허용: Space 와 방향키를 inputBuffer 초 안에만 누르면 순서 상관없이 시작
	local now = os.clock()
	if input.drift and not s.driftWasDown then
		s.spacePressedAt = now
	end
	s.driftWasDown = input.drift
	if input.steer ~= 0 then
		s.steerPressedAt = now
	end
	if s.driftDir == 0 then
		local spaceRecent = input.drift or (now - s.spacePressedAt) < D.inputBuffer
		local steerRecent = input.steer ~= 0 or (now - s.steerPressedAt) < D.inputBuffer
		if spaceRecent and steerRecent and input.drift and fwdSpeed > D.minSpeed and s.lastGrounded then
			local steerSign = input.steer ~= 0 and input.steer or s.lastSteerSign
			s.driftDir = steerSign > 0 and 1 or -1
			-- 누르는 순간 바로 그립을 놓음 (기다림 없음)
			s.driftBlend = math.max(s.driftBlend, D.entryBlend)
			-- 타격감: 카메라 툭 + 타이어 연기/불똥 한 번에 펑
			ChaseCamera.Punch(CamConfig.driftEntryPunch)
			VehicleEffects.PlayDriftBurst(s.model)
		end
	elseif not input.drift or flatSpeed < D.minSpeed * 0.6 then
		s.driftDir = 0
		s.oppositeTime = 0
	else
		-- 드리프트 중 반대 방향키를 잠깐 꾹 누르면 반대쪽 드리프트로 전환
		if input.steer ~= 0 and (input.steer > 0 and 1 or -1) ~= s.driftDir then
			s.oppositeTime += dt
			if s.oppositeTime >= D.switchHoldTime then
				s.driftDir = -s.driftDir
				s.oppositeTime = 0
			end
		else
			s.oppositeTime = 0
		end
	end
	if input.steer ~= 0 then
		s.lastSteerSign = input.steer
	end
	local wantDrift = s.driftDir ~= 0
	if input.drift then
		s.driftHold += dt
	else
		s.driftHold = 0
	end
	local blendRate = wantDrift and D.blendIn or D.blendOut
	s.driftBlend += ((wantDrift and 1 or 0) - s.driftBlend) * math.min(dt * blendRate, 1)

	-- 조향: 빠를수록 덜 꺾임
	local speedRatio = math.clamp(absSpeed / stats.maxSpeed, 0, 1)
	local maxSteer = math.rad(stats.steerAngle) * (1 - speedRatio * (1 - Physics.highSpeedSteerFactor))
	-- 차가 미끄러지는 각도 (+ = 진행 방향이 차 머리보다 오른쪽)
	local sideVel, longVelBody = vel:Dot(right), vel:Dot(fwd)
	-- 90° 넘게 돌아도 각도가 정확히 나오게 (전엔 앞방향 속도 3 미만이면 0 으로 처리돼 드리프트가 고장남)
	local beta = (flatSpeed > 3) and math.atan2(sideVel, longVelBody) or 0

	-- 앞바퀴: 평소엔 살짝 자동 카운터, 드리프트 중엔 진행 방향을 향해 (그림 + 평소 주행용)
	-- 후진 중엔 카운터 안 함 (후진하면 각도가 ±180° 라 바퀴가 끝까지 꺾이던 문제)
	local counterBeta = (longVelBody > 3) and beta or 0
	local counter = math.clamp(counterBeta * (Physics.counterSteerAssist * assist + 0.8 * s.driftBlend), -maxSteer, maxSteer)
	-- 앞바퀴 각도도 평소 회전 한계에 맞춰 줄임 → 타이어와 한계가 서로 싸우지 않아 억지로 밀리는 느낌 없음
	local boostingNow = (input.boost and s.boost > 0) or s.exitBoostTime > 0
	local yawCap = normalYawCap(stats, flatSpeed, boostingNow)
	local steerCap = math.atan(yawCap * s.wheelbase / math.max(flatSpeed, 1)) * 1.05
	local inputSteer = input.steer * math.min(maxSteer, steerCap)
	local targetSteer = math.clamp(inputSteer * (1 - s.driftBlend) + counter, -maxSteer * 1.3, maxSteer * 1.3)
	-- 꺾을 땐 steerSpeed, 풀거나 반대로 넘길 땐 더 빨리 (손 떼면 바로 직진, 좌우 전환 빠릿)
	local returning = math.abs(targetSteer) < math.abs(s.steer) or targetSteer * s.steer < 0
	local steerRate = returning and Physics.steerReturnSpeed or Physics.steerSpeed
	s.steer += (targetSteer - s.steer) * math.min(dt * steerRate, 1)

	-- 드리프트 충전 → 끝날 때 탈출 부스트
	-- 각도를 유지하며 오래 미끄러질수록 단계가 오름. Space 떼는 순간 단계만큼 가속.
	local DB = Physics.DriftBoost
	local slidingWell = s.driftBlend > 0.6 and math.abs(beta) > math.rad(DB.minAngle)
	if slidingWell then
		s.driftCharge += dt
	end
	if math.abs(beta) > math.rad(DB.spinOutAngle) then
		s.driftCharge = 0 -- 너무 돌아서 스핀 → 충전 날아감
	end
	local tier = 0
	for i, need in DB.tierTimes do
		if s.driftCharge >= need then
			tier = i
		end
	end
	if s.wasDrifting and not wantDrift then
		if tier > 0 and DB.enabled then
			s.exitBoostTime = DB.duration
			s.exitBoostPower = DB.tierPower[tier]
		end
		s.driftCharge = 0
		tier = 0
	end
	s.wasDrifting = wantDrift and s.driftBlend > 0.3
	s.exitBoostTime = math.max(s.exitBoostTime - dt, 0)
	local exitBoosting = s.exitBoostTime > 0
	HUD.SetDriftTier(DB.enabled and tier or 0, exitBoosting)

	-- 부스터 (Shift)
	local boosting = input.boost and s.boost > 0 and input.throttle > 0
	if boosting then
		s.boost = math.max(s.boost - dt / stats.boostDuration, 0)
	elseif not input.boost then
		s.boost = math.min(s.boost + dt * stats.boostRecharge, 1)
	end
	local boostMul = boosting and (1 + stats.boostPower) or 1
	if exitBoosting then
		-- 끝날 때쯤 서서히 줄어듦
		boostMul *= 1 + s.exitBoostPower * math.min(s.exitBoostTime / (DB.duration * 0.4), 1)
	end
	local maxSpeed = stats.maxSpeed * boostMul

	-- 페달을 부드럽게 (키보드는 0/1 이라 바로 넣으면 "훅" 튐)
	local rise = math.min(dt * Physics.pedalRise, 1)
	local fall = math.min(dt * Physics.pedalFall, 1)
	s.throttle += (input.throttle - s.throttle) * (input.throttle > s.throttle and rise or fall)
	s.brake += (input.brake - s.brake) * (input.brake > s.brake and rise or fall)

	-- 앞뒤 가속도 결정
	local accel = 0
	if s.throttle > 0.01 and input.brake == 0 then
		if fwdSpeed < -2 then
			accel = stats.brake * s.throttle
		else
			-- 최고속에 가까워질수록 힘이 부드럽게 줄어듦 (딱 끊기지 않게)
			local ratio = math.clamp(fwdSpeed / maxSpeed, 0, 1)
			accel = stats.acceleration * s.throttle * boostMul * (1 - ratio ^ Physics.powerCurve)
		end
	elseif s.brake > 0.01 then
		if fwdSpeed > 2 then
			accel = -stats.brake * s.brake
		else
			local ratio = math.clamp(-fwdSpeed / (stats.maxSpeed * stats.reverseRatio), 0, 1)
			accel = -stats.acceleration * stats.reverseRatio * s.brake * (1 - ratio ^ Physics.powerCurve)
		end
	end
	-- 굴림 저항은 항상 조금 (페달 놓았을 때 서서히 멈춤)
	if s.throttle < 0.05 and s.brake < 0.05 then
		accel += -math.clamp(fwdSpeed * 0.5, -stats.rollingResistance, stats.rollingResistance)
	end

	local rayLen = stats.suspensionRest + stats.wheelRadius
	local wheelCount = #s.wheels
	local massPer = mass / math.max(wheelCount, 1)
	local totalF = Vector3.zero
	local totalT = Vector3.zero
	local grounded = 0
	local steerRot = CFrame.fromAxisAngle(up, -s.steer) -- +steer = 오른쪽
	-- 페달 안 밟고 거의 멈춰 있으면 바퀴가 꽉 잡아서 혼자 굴러가지 않게
	local holding = s.throttle < 0.05 and s.brake < 0.05 and math.abs(fwdSpeed) < Physics.holdSpeed
	-- 빠를수록 타이어가 점점 밀림 (저속 = 착 붙음, 고속 = 점점 바깥으로 밀려나감)
	local speedGrip = 1 - (1 - Physics.highSpeedGrip) * speedRatio ^ Physics.gripFalloffCurve
	-- 드리프트 중엔 타이어 옆 힘 대신 아래 "카툰 미끄러짐" 이 차를 조종
	-- 타이어 그립도 풀릴 때 서서히 (제곱근 → 블렌드가 꽤 내려가야 그립이 붙음)
	local tireLatMul = 1 - D.tireLatCut * math.sqrt(s.driftBlend)
	local onLava = false
	-- 드리프트 끝난 뒤 그립 회복: recoverTime 동안 옆 그립이 recoverMinGrip → 100% 로 천천히 돌아옴
	-- (한 번에 돌아오면 차가 진행 방향으로 "억지로 확" 잡힘)
	if wantDrift then
		s.recover = 0
	else
		-- 방향키를 누르고 있으면 훨씬 빨리 회복 → 드리프트 끝나자마자 반대로 꺾어도 바로 먹음
		local speedUp = (input.steer ~= 0) and D.recoverSteerBoost or 1
		s.recover = math.min(s.recover + dt * speedUp / D.recoverTime, 1)
	end
	local recoverEase = s.recover * s.recover * (3 - 2 * s.recover) -- 부드러운 곡선
	local recoverGrip = D.recoverMinGrip + (1 - D.recoverMinGrip) * recoverEase
	tireLatMul *= recoverGrip

	for _, w in s.wheels do
		local origin = (cf * w.att.CFrame).Position
		local result = workspace:Raycast(origin, -up * rayLen, s.params)
		if result then
			grounded += 1
			if result.Instance:GetAttribute("Hazard") == "Lava" then
				onLava = true
			end
			local compression = rayLen - result.Distance
			local contact = result.Position
			local pointVel = vel + angVel:Cross(contact - com)

			-- 1) 스프링
			local springF = massPer * (stats.suspensionStiffness * compression - stats.suspensionDamping * pointVel:Dot(up))
			-- 범프 스톱: 끝까지 눌리면 단단하게 받쳐서 차체가 바닥을 긁지 않게
			local stopStart = stats.suspensionRest * Physics.bumpStopStart
			if compression > stopStart then
				springF += massPer * stats.suspensionStiffness * Physics.bumpStopStrength * (compression - stopStart)
			end
			-- 너무 큰 힘은 잘라서 착지 때 "뽀잉" 튀는 것 방지
			springF = math.clamp(springF, 0, massPer * workspace.Gravity * Physics.maxSpringG)
			-- 땅 방향(법선)으로 밀어야 차체가 살짝 기울어도 앞으로 쏠려 가지 않음
			local springDir = result.Normal
			totalF += springDir * springF
			totalT += (contact - com):Cross(springDir * springF)

			-- 2) 바퀴 방향 (앞바퀴만 조향)
			local wFwd, wRight = fwd, right
			if w.isFront then
				wFwd = steerRot:VectorToWorldSpace(fwd)
				wRight = steerRot:VectorToWorldSpace(right)
			end

			-- 3) 타이어 접지 한계 = 마찰계수 × 바퀴를 누르는 힘
			--    (브레이크 밟으면 앞바퀴에 무게가 실려 앞이 잘 물고, 뒤가 가벼워져 잘 미끄러짐)
			local mu = stats.grip * (w.isFront and Physics.frontGrip or Physics.rearGrip) * speedGrip
			if boosting or exitBoosting then
				mu *= Physics.boostGrip -- 부스터 중엔 접지 보너스 (부스터 + 코너/드리프트 조합 유도)
			end
			-- 접지 계산엔 출렁임을 걸러낸 무게를 씀 → 고속에서 서스펜션이 출렁여도 접지가 "훅훅" 끊기지 않음
			local staticLoad = massPer * workspace.Gravity
			local gripLoad = springF + (staticLoad - springF) * Physics.gripLoadSmoothing
			local maxGrip = mu * gripLoad
			if maxGrip ~= maxGrip or maxGrip < 0 then
				maxGrip = 0 -- 숫자가 깨지면(NaN/음수) 그립 0 으로 안전하게
			end

			-- 4) 구동/브레이크: 가속은 뒷바퀴 위주 → 코너에서 밟으면 꼬리가 나감
			local driveF
			if holding then
				driveF = -pointVel:Dot(wFwd) * Physics.holdGrip * massPer
			elseif accel > 0 and fwdSpeed >= 0 then
				local share = w.isFront and (1 - Physics.rearDriveBias) or Physics.rearDriveBias
				driveF = accel * mass * share / (w.isFront and s.frontCount or s.rearCount)
			else
				driveF = accel * massPer
			end
			driveF = math.clamp(driveF, -maxGrip, maxGrip) -- 넘치면 헛바퀴
			if driveF > 0 then
				-- 드리프트 중엔 엔진 힘 대부분이 바퀴 헛도는 데 쓰임 → 꾹 누르면 느려짐
				driveF *= 1 - D.engineCut * s.driftBlend
			end

			-- 5) 옆 힘: 미끄러지는 각도(슬립각)에 따라
			--    살짝 미끄러질 땐 꽉 잡다가, 한계를 넘으면 힘이 떨어져서 "주르륵" 밀림
			local longVel = pointVel:Dot(wFwd)
			local latVel = pointVel:Dot(wRight)
			local slip = math.atan2(math.abs(latVel), math.max(math.abs(longVel), Physics.slipLowSpeed))
			local curve
			if slip < Physics.slipPeak then
				curve = math.sin(slip / Physics.slipPeak * math.pi / 2)
			else
				local t = math.clamp((slip - Physics.slipPeak) / (Physics.slipFull - Physics.slipPeak), 0, 1)
				curve = 1 - (1 - Physics.slideRatio) * t
			end
			-- 가속/브레이크에 접지를 쓴 만큼 옆으로 쓸 수 있는 접지가 줄어듦 (마찰원)
			-- frictionCircle 이 낮을수록 가속하면서 꺾어도 덜 미끄러짐 (저속 출발 코너에서 쭉쭉 밀리던 원인)
			local usedByDrive = driveF * Physics.frictionCircle
			local latAvail = math.sqrt(math.max(maxGrip * maxGrip - usedByDrive * usedByDrive, 0))
			local latF = -math.sign(latVel) * curve * latAvail
			-- 옆 속도를 넘어서 반대로 튕기지 않게 (저속 떨림 방지)
			local cancel = math.abs(latVel) * massPer / math.max(dt, 1 / 240) * 0.5
			latF = math.clamp(latF, -cancel, cancel) * tireLatMul

			local planarF = wRight * latF + wFwd * driveF
			totalF += planarF

			-- 뒤집힘 완화: 힘이 작용하는 높이를 무게중심 쪽으로 끌어올림
			local lever = contact - com
			lever -= up * lever:Dot(up) * Physics.antiPitchRoll
			totalT += lever:Cross(planarF)

			w.offset = math.clamp(result.Distance - stats.wheelRadius, 0, stats.suspensionRest)
		else
			w.offset = stats.suspensionRest
		end
	end

	-- 고속에서 차가 살짝 튀어 바퀴가 잠깐 떠도 "땅에 있음"으로 봐줌 (0.3초)
	if grounded > 0 then
		s.airTime = 0
	else
		s.airTime += dt
	end
	s.lastGrounded = s.airTime < Physics.groundGraceTime

	-- 아케이드 보정
	local tilt = up:Cross(Vector3.yAxis) -- 기울어진 만큼 세우는 방향
	if grounded > 0 then
		totalT += tilt * Physics.uprightGround * mass
		totalF += -up * mass * workspace.Gravity * Physics.downforce * speedRatio
		local yawRate = angVel:Dot(up) -- +면 왼쪽으로 도는 중
		local inertia = mass * s.inertiaK
		-- 드리프트가 풀릴 때 평소 보정이 "서서히" 돌아오게 (제곱 → 끝무렵에야 힘이 붙음, 억지로 확 잡히지 않음)
		-- 회복 중이라도 방향키를 누르면 핸들 보정은 바로 100% (손 놓고 있을 때만 스르륵 회복)
		local normalW = (1 - s.driftBlend) ^ 2 * ((input.steer ~= 0) and 1 or recoverGrip)

		-- [평소 주행] 스핀 방지: 핸들 꺾은 만큼(타이어 한계 안에서)만 돌게, 목표는 서서히 바뀜
		local wantYaw = -fwdSpeed * math.tan(s.steer) / s.wheelbase
		local maxYaw = normalYawCap(stats, flatSpeed, boosting or exitBoosting) * speedGrip
		wantYaw = math.clamp(wantYaw, -maxYaw, maxYaw)
		s.wantYaw += (wantYaw - s.wantYaw) * math.min(dt * Physics.yawTargetSmooth, 1)
		totalT += -up * (yawRate - s.wantYaw) * Physics.yawStability * assist * inertia * normalW

		-- [카툰 드리프트] 회전 속도를 직접 부드럽게 조종
		if s.driftBlend > 0.01 then
			local dir = s.driftDir ~= 0 and s.driftDir or s.lastDriftDir
			-- 안쪽 키 = 더 깊게, 바깥 키 = 얕게, 안 누름 = 기본. 각도는 회전과 미끄러짐이 맞는 지점에서 자연스럽게 정해짐
			local depthInput = input.steer * dir -- +1 안쪽(깊게), -1 바깥(얕게)
			-- Space 누르고 있으면 baseYaw (holdRampTime 동안 올라감), 뗀 사이(톡톡 사이)엔 tapYaw 로 느슨하게
			local holdFactor = 0
			if input.drift then
				holdFactor = D.holdRampTime > 0 and math.clamp(s.driftHold / D.holdRampTime, 0, 1) or 1
			end
			local base = D.tapYaw + (D.baseYaw - D.tapYaw) * holdFactor
			-- 안쪽 키 = 더 깊게, 바깥 키 = 반대로 돌려서 실제로 펴짐 (내가 꺾은 대로 가게)
			local steerPart = depthInput >= 0 and D.steerYaw * depthInput or D.outwardYaw * depthInput
			local yawSpeed = (base + steerPart) * (stats.driftPower or 1)
			-- 스핀 방지는 아주 깊을 때만
			local angle = math.max(-dir * beta, 0) -- 지금 드리프트 방향 쪽 각도
			local guard = math.clamp((math.rad(D.spinGuardAngle) - angle) / math.rad(15), 0, 1)
			yawSpeed *= guard
			-- 저속에선 덜 돌게 (제자리 팽이 방지)
			yawSpeed *= math.clamp(flatSpeed / (D.minSpeed * 2), 0.3, 1)
			local targetYaw = -dir * yawSpeed -- 오른쪽 드리프트 = 시계방향
			totalT += -up * (yawRate - targetYaw) * D.yawResponse * inertia * s.driftBlend

			-- 미끄러짐: 진행 방향이 차 머리 쪽으로 "천천히" 휘어 따라옴 → 쭈욱 길게 미끄러짐
			-- (방향만 휘게 하고 속도는 안 깎음. 속도 손실은 아래 drag 하나로만)
			local flatVel = vel - up * vel:Dot(up)
			if flatVel.Magnitude > 1 then
				local vDir = flatVel.Unit
				local leftOfVel = up:Cross(vDir)
				local side = fwd:Dot(leftOfVel) -- + 면 차 머리가 진행 방향보다 왼쪽
				totalF += leftOfVel * side * flatVel.Magnitude * D.traction * mass * s.driftBlend
				-- 카빙: 차가 도는 만큼 진행 방향도 "바로" 같이 휨 → 스페이스 누르자마자 코너를 파고듦
				-- (이게 없으면 차 머리만 돌고 실제 이동은 한동안 직진이라 방향 전환이 안 되는 느낌)
				totalF += leftOfVel * yawRate * flatVel.Magnitude * D.carve * mass * s.driftBlend

				-- 속도: 드리프트 꾹 누르고 있으면 조금씩 감속 (엑셀 밟으면 일부 보충)
				local push = D.speedKeep * s.throttle - D.drag
				totalF += flatVel.Unit * mass * push * s.driftBlend
			end
			s.lastDriftDir = dir
		end
	else
		-- 공중 보정: 실제 물리 대신 차를 수평으로 세우고 날아가는 방향으로 똑바로 떨어지게
		local inertia = mass * s.inertiaK -- 차 크기에 맞춰 힘 조절 (큰 차도 똑같이 반응)
		local w = Physics.airLevelSpeed
		local pitchRoll = angVel - Vector3.yAxis * angVel:Dot(Vector3.yAxis)
		totalT += (tilt * w * w - pitchRoll * 2 * Physics.airLevelDampingRatio * w) * inertia

		-- 방향: A/D 누르면 그쪽으로 돌고, 안 누르면 날아가는 방향을 바라봄
		local yawRate = angVel:Dot(Vector3.yAxis)
		local targetYaw = 0
		if input.steer ~= 0 then
			targetYaw = -input.steer * Physics.airYawSpeed
		else
			local flatVel = vel * Vector3.new(1, 0, 1)
			local flatFwd = fwd * Vector3.new(1, 0, 1)
			if flatVel.Magnitude > 10 and flatFwd.Magnitude > 0.1 then
				local side = flatFwd.Unit:Cross(flatVel.Unit).Y -- +면 속도가 왼쪽
				if fwdSpeed < 0 then
					side = -side -- 후진으로 날면 뒤가 진행 방향
				end
				targetYaw = side * Physics.airHeadingAlign
			end
		end
		totalT += Vector3.yAxis * (targetYaw - yawRate) * Physics.airYawResponse * inertia
	end
	totalF += -vel * mass * Physics.airDrag

	-- 벽 긁은 직후: 차 머리를 진행 방향(벽 따라)으로 맞추고 회전을 죽여서 벽에 대가리 들이미는 것 방지
	s.wallTime = math.max(s.wallTime - dt, 0)
	if s.wallTime > 0 then
		local WS = Physics.WallScrape
		local flatVel = vel - Vector3.yAxis * vel.Y
		local inertia = mass * s.inertiaK
		local weight = s.wallTime / WS.alignTime -- 처음엔 세게, 점점 약하게
		if flatVel.Magnitude > 5 then
			local heading = flatVel.Unit
			if fwdSpeed < 0 then
				heading = -heading
			end
			local side = fwd:Dot(Vector3.yAxis:Cross(heading)) -- + 면 차 머리가 진행 방향보다 왼쪽
			totalT += -Vector3.yAxis * side * WS.alignStrength * assist * inertia * weight
		end
		totalT += -Vector3.yAxis * angVel.Y * WS.alignDamping * assist * inertia * weight
	end

	s.force.Force = totalF
	s.torque.Torque = totalT

	-- 뒤집힌 채 멈추면 자동 복구
	if Physics.autoFlip then
		if up.Y < 0.2 and vel.Magnitude < 6 then
			s.flippedTime += dt
			if s.flippedTime > Physics.autoFlipDelay then
				s.flippedTime = 0
				local flat = fwd * Vector3.new(1, 0, 1)
				if flat.Magnitude < 0.1 then
					flat = Vector3.new(0, 0, -1)
				end
				local pos = chassis.Position + Vector3.new(0, 4, 0)
				s.model:PivotTo(CFrame.lookAt(pos, pos + flat.Unit))
				chassis.AssemblyLinearVelocity = Vector3.zero
				chassis.AssemblyAngularVelocity = Vector3.zero
			end
		else
			s.flippedTime = 0
		end
	end

	-- 바퀴 그림 (내 화면에서만 움직임): 주차 높이 기준으로 연결된 물리 바퀴만큼 오르내림
	local parkedOffset = math.max(stats.suspensionRest - workspace.Gravity / stats.suspensionStiffness, 0)
	for _, v in s.visuals do
		v.spin = (v.spin - fwdSpeed / stats.wheelRadius * dt) % (math.pi * 2)
		local drop = v.link and (v.link.offset - parkedOffset) or 0
		local rot = v.isFront and CFrame.Angles(0, -s.steer, 0) or CFrame.identity
		v.weld.C0 = CFrame.new(v.basePos - Vector3.new(0, drop, 0)) * rot * CFrame.Angles(v.spin, 0, 0) * v.baseRot
	end

	ChaseCamera.SetBoosting(boosting or exitBoosting)
	ChaseCamera.SetSpeedRatio(flatSpeed / stats.maxSpeed)
	ChaseCamera.SetDrift(s.driftBlend, s.driftDir ~= 0 and s.driftDir or s.lastDriftDir)

	-- 이펙트 상태: 바뀔 때만 서버로 (서버가 모델 Attribute 로 모두에게 알림). 내 화면은 바로 적용
	-- 스키드: Space 드리프트 중이거나, 그냥 옆으로 크게 미끄러질 때 (땅에 닿아 있을 때만)
	local sliding = math.abs(beta) > math.rad(EffectsConfig.slideSkidAngle) and flatSpeed > 20
	local fxDrift = (s.driftBlend > 0.5 or sliding) and s.lastGrounded
	local fxBoost = boosting or exitBoosting
	if fxDrift ~= s.fxDrift or tier ~= s.fxTier or fxBoost ~= s.fxBoost then
		s.fxDrift, s.fxTier, s.fxBoost = fxDrift, tier, fxBoost
		s.model:SetAttribute("FX_Drift", fxDrift)
		s.model:SetAttribute("FX_Tier", tier)
		s.model:SetAttribute("FX_Boost", fxBoost)
		VehicleFX:FireServer("State", fxDrift, tier, fxBoost)
	end

	-- 순간이동(재시작/복귀/뒤집힘 복구) 직후엔 충돌로 치지 않음
	local now = os.clock()
	local teleported = s.prevPos ~= nil and (chassis.Position - s.prevPos).Magnitude > math.max(flatSpeed * dt * 3, 30)
	s.prevPos = chassis.Position

	-- 충돌 스파크: 속도가 갑자기 확 바뀌면 (벽에 박음, 세게 착지)
	local hitAccel = (vel - s.prevVel).Magnitude / math.max(dt, 1 / 240)
	if not teleported and hitAccel > EffectsConfig.impactAccel and s.prevVel.Magnitude > EffectsConfig.impactMinSpeed and now - s.lastImpact > 0.25 then
		s.lastImpact = now
		local dir = s.prevVel.Unit
		local hitPos = chassis.Position + dir * (chassis.Size.Z / 2) - up * (chassis.Size.Y / 2)
		local strength = math.clamp((s.prevVel - vel).Magnitude / 60, 0.3, 1.5)
		VehicleEffects.PlayImpact(s.model, hitPos, strength)
		VehicleFX:FireServer("Impact", hitPos, strength)
	end

	-- 충돌 데미지: 한 프레임 속도 변화가 클수록 (정면 꽈앙 > 착지 > 비스듬히 긁기)
	local dv = (s.prevVel - vel).Magnitude
	if not teleported and dv > HealthConfig.minImpactSpeed and now - s.lastDamage > 0.2 then
		s.lastDamage = now
		local dmg = math.min((dv - HealthConfig.minImpactSpeed) * HealthConfig.damagePerSpeed, HealthConfig.maxPerHit)
		local hp = s.model:GetAttribute("HP")
		if type(hp) == "number" and hp - dmg <= 0 and s.lastCF then
			-- 치명타! 서버 답을 기다리지 않고 "닿은 그 순간" 위치로 되돌려 바로 정지
			-- (기다리면 통신 지연 동안 차가 벽에 밀착돼서 ][ 모양이 된 뒤에 멈춤)
			s.model:PivotTo(s.lastCF)
			chassis.Anchored = true
			s.force.Force = Vector3.zero
			s.torque.Torque = Vector3.zero
			VehicleEffects.PlayPreExplosion(s.model, chassis.Position, HealthConfig.tickDelay + 0.3)
			-- 혹시 서버가 치명타가 아니라고 판단하면 (회복 타이밍 차이 등) 1초 뒤 풀어줌
			local model = s.model
			task.delay(1.2, function()
				if chassis.Parent and not model:GetAttribute("Exploding") and not model:GetAttribute("Exploded") then
					chassis.Anchored = false
				end
			end)
		else
			ChaseCamera.Punch(math.clamp(dv / 80, 0.3, 1.5))
		end
		VehicleFX:FireServer("Damage", dmg)
	end
	s.prevVel = vel
	s.lastCF = s.model:GetPivot() -- 다음 프레임에 쓸 "박기 직전" 위치

	-- 용암 / 물
	if onLava and now - s.lastHazard > 0.2 then
		s.lastHazard = now
		VehicleFX:FireServer("Lava")
	end
	if chassis.Position.Y < HealthConfig.drownY and now - s.lastHazard > 1 then
		s.lastHazard = now
		VehicleFX:FireServer("Drown")
	end
	HUD.SetHP(s.model:GetAttribute("HP"), s.model:GetAttribute("MaxHP"))
	s.topSpeed = math.max(s.topSpeed, flatSpeed)
	HUD.Update(flatSpeed, s.boost, s.topSpeed)

	-- 트라이얼 (출발선/체크포인트 통과, 고스트, 낙하 복귀)
	TrialClient.Step(s.model, chassis, dt)
end

-- 주행 코드에서 에러가 나면 조용히 멈추지 않고 화면 + Output 에 한 번 알려줌 (버그 찾기용)
local reportedError = false
local function safeStep(dt: number)
	local ok, err = pcall(step, dt)
	if not ok and not reportedError then
		reportedError = true
		warn("[VehicleController] 주행 코드 에러: " .. tostring(err))
		HUD.Toast("주행 코드 에러! Output 창 확인")
	end
end

local function onPress(action: string)
	if action == "Exit" then
		VehicleAction:FireServer("Exit")
	elseif action == "Lights" then
		VehicleAction:FireServer("Lights")
	elseif action == "Camera" then
		ChaseCamera.Toggle()
	elseif action == "Restart" or action == "Respawn" then
		TrialClient.OnKey(action)
	end
end

local function stopDriving()
	local s = session
	if not s then
		return
	end
	session = nil
	s.conn:Disconnect()
	TrialClient.OnStopDriving()
	if s.model.Parent then
		s.model:SetAttribute("FX_Drift", false)
		s.model:SetAttribute("FX_Tier", 0)
		s.model:SetAttribute("FX_Boost", false)
	end
	s.force:Destroy()
	s.torque:Destroy()
	InputState.Disable()
	ChaseCamera.Stop()
	MobileControls.Hide()
	HUD.SetDriving(false)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
end

local function startDriving(seat: Seat, hum: Humanoid)
	stopDriving()
	local model = seat:FindFirstAncestorOfClass("Model")
	if not model or not model:GetAttribute("VehicleId") then
		return
	end
	local chassis = model.PrimaryPart or model:FindFirstChild("Chassis")
	if not chassis or not chassis:IsA("BasePart") then
		return
	end

	-- Space(드리프트)가 점프로 차에서 튕겨나가지 않게
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	local att = Instance.new("Attachment")
	att.Name = "DriveForceAttachment"
	att.Parent = chassis
	local force = Instance.new("VectorForce")
	force.Attachment0 = att
	force.ApplyAtCenterOfMass = true
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.Force = Vector3.zero
	force.Parent = chassis
	local torque = Instance.new("Torque")
	torque.Attachment0 = att
	torque.RelativeTo = Enum.ActuatorRelativeTo.World
	torque.Torque = Vector3.zero
	torque.Parent = chassis
	force.Destroying:Connect(function()
		att:Destroy()
	end)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	local wheels = collectWheels(chassis)
	local s = {
		model = model,
		chassis = chassis,
		stats = StatCalculator.ReadFromModel(model),
		wheels = wheels,
		visuals = collectVisuals(model, wheels),
		force = force,
		torque = torque,
		-- 물리 계산 "직전"에 힘을 넣어야 한 프레임 늦게 반응하는 출렁임이 없음
		conn = RunService.PreSimulation:Connect(safeStep),
		steer = 0,
		throttle = 0,
		brake = 0,
		driftBlend = 0,
		frontCount = 0,
		rearCount = 0,
		wheelbase = 7,
		inertiaK = 5,
		wantYaw = 0,
		driftDir = 0,
		driftHold = 0,
		oppositeTime = 0,
		recover = 1,
		wallTime = 0,
		driftWasDown = false,
		spacePressedAt = -1,
		steerPressedAt = -1,
		lastSteerSign = 1,
		lastDriftDir = 1,
		lastGrounded = false,
		airTime = 0,
		driftCharge = 0,
		wasDrifting = false,
		exitBoostTime = 0,
		exitBoostPower = 0,
		fxDrift = false,
		fxTier = 0,
		fxBoost = false,
		prevVel = chassis.AssemblyLinearVelocity,
		lastImpact = 0,
		lastDamage = 0,
		lastHazard = 0,
		prevPos = nil,
		lastCF = nil,
		topSpeed = 0,
		boost = 1,
		flippedTime = 0,
		params = params,
		paramsAge = 0,
	}
	for _, w in s.wheels do
		if w.isFront then
			s.frontCount += 1
		else
			s.rearCount += 1
		end
	end
	local minZ, maxZ = math.huge, -math.huge
	for _, w in s.wheels do
		minZ = math.min(minZ, w.att.Position.Z)
		maxZ = math.max(maxZ, w.att.Position.Z)
	end
	s.wheelbase = math.max(maxZ - minZ, 2)
	-- 회전 관성 근사 (상자 모양 기준, 무게 1당)
	local size = chassis.Size
	s.inertiaK = (size.X * size.X + size.Y * size.Y + size.Z * size.Z) / 12
	-- 한쪽 축에 바퀴가 없으면 (이상한 모델) 전부 균등 구동
	if s.frontCount == 0 or s.rearCount == 0 then
		s.frontCount = math.max(#s.wheels, 1) * (1 - Physics.rearDriveBias)
		s.rearCount = math.max(#s.wheels, 1) * Physics.rearDriveBias
	end
	refreshRayFilter(s)
	session = s

	InputState.Enable(onPress)
	ChaseCamera.Start(model, seat)
	MobileControls.Show()
	HUD.SetDriving(true)
end

-- 동승자: 점프로 튕겨 나가지 않게 막고, F(또는 화면 버튼)로만 내림 (서버가 속도 검사)
local PASSENGER_EXIT = "PassengerExit"
local function setPassenger(hum: Humanoid, on: boolean)
	ContextActionService:UnbindAction(PASSENGER_EXIT)
	if on then
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		ContextActionService:BindActionAtPriority(PASSENGER_EXIT, function(_, state)
			if state == Enum.UserInputState.Begin then
				VehicleAction:FireServer("Exit")
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 10, table.unpack(InputConfig.Press.Exit))
		HUD.SetPassenger(true, function()
			VehicleAction:FireServer("Exit")
		end)
	else
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		HUD.SetPassenger(false)
	end
end

local function onCharacter(char: Model)
	stopDriving()
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	-- 다시 태어나면 카메라를 기본 모드로 되돌리고 새 캐릭터를 따라가게
	-- (죽을 때 운전 카메라가 꺼지면서 대상이 "죽은 캐릭터"로 남아, 죽은 자리만 보이던 문제)
	local function resetCamera()
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Custom
		cam.CameraSubject = hum
	end
	resetCamera()
	task.delay(0.2, function()
		if hum.Parent and not session then
			resetCamera()
		end
	end)
	hum.Seated:Connect(function(active, seatPart)
		local inVehicle = active and seatPart and seatPart:IsA("Seat")
			and seatPart:FindFirstAncestorOfClass("Model") ~= nil
			and (seatPart:FindFirstAncestorOfClass("Model") :: Model):GetAttribute("VehicleId") ~= nil
		if inVehicle and seatPart.Name == "DriverSeat" then
			setPassenger(hum, false)
			startDriving(seatPart, hum)
		elseif inVehicle then
			stopDriving()
			setPassenger(hum, true)
		else
			stopDriving()
			setPassenger(hum, false)
		end
	end)
	hum.Died:Connect(function()
		stopDriving()
		setPassenger(hum, false)
	end)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end
