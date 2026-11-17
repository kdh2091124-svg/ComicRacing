-- 트라이얼 (혼자 기록 경쟁) 클라이언트.
--   • 코스 출발선을 지나가면 시작 (서버가 시간을 잼)
--   • 체크포인트 통과 → 서버에 보고 → 구간 기록 + 내 최고 기록 대비 +/- 표시
--   • Backspace: 처음부터 다시 (출발선 뒤로 이동, 다시 지나가면 시작)
--   • R: 마지막 체크포인트로 복귀 (트라이얼 밖에서는 그 자리에서 차 세우기)
--   • 떨어지면 자동 복귀
--   • 내 최고 기록 고스트 (지금은 이번 접속 동안만. 저장/상대 고스트는 저장 시스템 이후)
-- VehicleController 가 운전 중 매 프레임 Step() 을 부른다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CourseConfig = require(Shared.Config.CourseConfig)
local TrialConfig = require(Shared.Config.GameplayConfig).Trial
local HUD = require(script.Parent:WaitForChild("HUD"))
local Ghost = require(script.Parent:WaitForChild("Ghost"))

local Trial = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Trial") :: RemoteEvent

local TrialClient = {}

type Course = {
	id: string,
	name: string,
	laps: number,
	start: { cframe: CFrame, size: Vector3 },
	cps: { { cframe: CFrame, size: Vector3, section: string } },
}

local state = {
	phase = "Idle", -- Idle / Starting / Running
	course = nil :: Course?,
	lastCourse = nil :: Course?, -- 재시작용 (끝난 뒤에도 기억)
	nextIndex = 1,
	total = 0,
	pbSplits = nil :: { number }?,
	clientStart = 0,
	model = nil :: Model?,
	prevPos = nil :: Vector3?,
	recording = {} :: { { t: number, cf: CFrame } },
	lastSample = 0,
	bestGhosts = {} :: { [string]: { { t: number, cf: CFrame } } },
}

-- 선(얇은 판)을 앞 방향(LookVector)으로 통과했는지
local function crossed(cf: CFrame, size: Vector3, p0: Vector3, p1: Vector3, marginY: number): boolean
	local a = cf:PointToObjectSpace(p0)
	local b = cf:PointToObjectSpace(p1)
	if a.Z > 0 and b.Z <= 0 then
		local t = a.Z / (a.Z - b.Z)
		local hit = a:Lerp(b, t)
		return math.abs(hit.X) <= size.X / 2 + 4 and math.abs(hit.Y) <= size.Y / 2 + marginY
	end
	return false
end

local function cpAt(course: Course, index: number)
	return course.cps[(index - 1) % #course.cps + 1]
end

local function placeCar(model: Model, cf: CFrame)
	model:PivotTo(cf)
	local root = model.PrimaryPart
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	state.prevPos = nil -- 순간이동 직후 "선 통과" 오판정 방지
end

local function groundSpot(cf: CFrame, size: Vector3, back: number): CFrame
	-- 판의 바닥 + respawnHeight, 판 뒤쪽(+Z)으로 back 만큼
	return cf * CFrame.new(0, -size.Y / 2 + TrialConfig.respawnHeight + 1, back)
end

local function lapText(): string?
	local course = state.course
	if not course or course.laps <= 1 then
		return nil
	end
	local lap = math.min(math.floor((state.nextIndex - 1) / #course.cps) + 1, course.laps)
	return string.format("LAP %d/%d", lap, course.laps)
end

local function endRun()
	state.phase = "Idle"
	state.course = nil
	Ghost.Stop()
end

-- ===== 서버 응답 =====
Trial.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any)
	if kind == "Started" then
		local course = a :: Course
		state.phase = "Running"
		state.course = course
		state.lastCourse = course
		state.nextIndex = 1
		state.total = #course.cps * course.laps
		state.pbSplits = b
		state.clientStart = os.clock()
		state.recording = {}
		state.lastSample = -1
		HUD.TrialStart(course.name, state.total, c, lapText())
		local ghost = state.bestGhosts[course.id]
		if ghost and state.model then
			Ghost.Start(state.model, ghost)
		end
	elseif kind == "Split" then
		local index, t, delta = a, b, c
		local course = state.course
		if not course then
			return
		end
		state.nextIndex = index + 1
		HUD.TrialSplit(index, state.total, t, delta, cpAt(course, index).section, lapText())
	elseif kind == "Finished" then
		local t, prevBest, isNew, delta = a, b, c, d
		local course = state.course
		if course and isNew then
			state.bestGhosts[course.id] = state.recording
		end
		HUD.TrialFinish(t, prevBest, isNew, delta)
		endRun()
	elseif kind == "Rejected" then
		HUD.Toast(tostring(a))
		HUD.TrialHide()
		endRun()
	end
end)

-- ===== 키 =====
function TrialClient.OnKey(action: string)
	local model = state.model
	if not model then
		return
	end
	if action == "Restart" then
		local course = state.course or state.lastCourse
		if not course then
			return
		end
		if state.phase ~= "Idle" then
			Trial:FireServer("Cancel")
		end
		endRun()
		placeCar(model, groundSpot(course.start.cframe, Vector3.new(0, 0, 0), TrialConfig.restartBehindStart))
		HUD.TrialReady(course.name)
	elseif action == "Respawn" then
		TrialClient.RespawnAtLastCheckpoint()
	end
end

function TrialClient.RespawnAtLastCheckpoint()
	local model = state.model
	if not model then
		return
	end
	local course = state.course
	if state.phase == "Running" and course then
		if state.nextIndex <= 1 then
			placeCar(model, groundSpot(course.start.cframe, Vector3.new(0, 0, 0), 4))
		else
			local cp = cpAt(course, state.nextIndex - 1)
			placeCar(model, groundSpot(cp.cframe, cp.size, 4))
		end
	else
		-- 트라이얼 밖: 그 자리에서 똑바로 세우기
		local root = model.PrimaryPart
		if root then
			local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
			if flat.Magnitude < 0.1 then
				flat = Vector3.new(0, 0, -1)
			end
			local pos = root.Position + Vector3.new(0, 4, 0)
			placeCar(model, CFrame.lookAt(pos, pos + flat.Unit))
		end
	end
end

-- ===== 매 프레임 (운전 중) =====
function TrialClient.Step(model: Model, chassis: BasePart, _dt: number)
	state.model = model
	local p1 = chassis.Position
	local p0 = state.prevPos
	state.prevPos = p1

	if state.phase == "Running" and state.course then
		local course = state.course
		local elapsed = os.clock() - state.clientStart
		HUD.TrialTime(elapsed)

		-- 고스트 녹화
		if elapsed - state.lastSample >= 1 / TrialConfig.ghostSampleRate then
			state.lastSample = elapsed
			table.insert(state.recording, { t = elapsed, cf = model:GetPivot() })
		end
		Ghost.Update(elapsed)

		-- 다음 체크포인트 통과
		if p0 then
			local cp = cpAt(course, state.nextIndex)
			if crossed(cp.cframe, cp.size, p0, p1, 6) then
				Trial:FireServer("CP", state.nextIndex)
			end
		end

		-- 떨어지면 복귀
		if p1.Y < TrialConfig.fallY then
			TrialClient.RespawnAtLastCheckpoint()
		end
		return
	end

	-- 출발선 찾기 (근처에 로드된 코스만)
	if state.phase == "Idle" and p0 and not game.Players.LocalPlayer:GetAttribute("InRace") then
		local map = workspace:FindFirstChild("Map")
		local courses = map and map:FindFirstChild("Courses")
		if courses then
			for _, folder in courses:GetChildren() do
				local def = CourseConfig.ById[folder.Name]
				local start = folder:FindFirstChild("Start")
				if def and def.enabled and start and start:IsA("BasePart") then
					if crossed(start.CFrame, start.Size, p0, p1, 25) then
						state.phase = "Starting"
						Trial:FireServer("Start", folder.Name)
						task.delay(2, function()
							if state.phase == "Starting" then
								state.phase = "Idle" -- 서버가 거절함
							end
						end)
						break
					end
				end
			end
		end
	end
end

-- 차에서 내리면 트라이얼 취소
function TrialClient.OnStopDriving()
	if state.phase ~= "Idle" then
		Trial:FireServer("Cancel")
		HUD.TrialHide()
	end
	endRun()
	state.model = nil
	state.prevPos = nil
end

return TrialClient
