-- 트라이얼 (혼자 기록 경쟁) 서버.
-- 시간은 서버 시계로 잰다. 클라이언트는 "출발선 지남 / 체크포인트 지남" 만 보고하고, 서버가 검사한다.
--   클라 → 서버: Trial:FireServer("Start", courseId) / ("CP", index) / ("Cancel")
--   서버 → 클라: "Started", course, pbSplits, pbTime / "Split", index, time, delta
--                "Finished", time, prevBest, isNewBest / "Rejected", reason
-- 최고 기록은 지금은 서버 메모리에만 (나가면 사라짐). 3단계 저장 시스템에서 DataStore 로 옮김.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrialConfig = require(ReplicatedStorage.Shared.Config.GameplayConfig).Trial
local CourseData = require(script.Parent.CourseData)

local Trial = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Trial") :: RemoteEvent

type Run = {
	course: CourseData.Course,
	startTime: number,
	nextIndex: number,
	total: number,
	splits: { number },
	lastTime: number,
	lastPos: Vector3,
}

local active: { [Player]: Run } = {}
local best: { [Player]: { [string]: { time: number, splits: { number } } } } = {}

local function driverChassis(player: Player): BasePart?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not seat or seat.Name ~= "DriverSeat" then
		return nil
	end
	local model = seat:FindFirstAncestorOfClass("Model")
	if not model or not model:GetAttribute("VehicleId") then
		return nil
	end
	return model.PrimaryPart
end

local function stop(player: Player)
	active[player] = nil
	player:SetAttribute("TrialCourse", nil)
end

local function reject(player: Player, reason: string)
	stop(player)
	Trial:FireClient(player, "Rejected", reason)
end

local function onStart(player: Player, courseId: any)
	if type(courseId) ~= "string" or player:GetAttribute("InRace") then
		return
	end
	local course = CourseData.Get(courseId)
	local chassis = driverChassis(player)
	if not course or not chassis then
		return
	end
	if (chassis.Position - course.start.cframe.Position).Magnitude > 80 then
		return
	end
	local now = os.clock()
	active[player] = {
		course = course,
		startTime = now,
		nextIndex = 1,
		total = #course.cps * course.laps,
		splits = {},
		lastTime = now,
		lastPos = course.start.cframe.Position,
	}
	player:SetAttribute("TrialCourse", courseId)
	local pb = best[player] and best[player][courseId]
	Trial:FireClient(player, "Started", course, pb and pb.splits or nil, pb and pb.time or nil)
end

local function onCheckpoint(player: Player, index: any)
	local run = active[player]
	if not run or type(index) ~= "number" or index ~= run.nextIndex then
		return
	end
	local n = #run.course.cps
	local cp = run.course.cps[(index - 1) % n + 1]
	local cpPos = cp.cframe.Position
	local chassis = driverChassis(player)
	if not chassis then
		reject(player, "차에서 내림")
		return
	end
	if (chassis.Position - cpPos).Magnitude > TrialConfig.cpMaxDistance then
		return -- 아직 도착 안 함 (복제 지연일 수 있으니 무효 처리는 안 함)
	end
	local now = os.clock()
	local dist = (cpPos - run.lastPos).Magnitude
	if dist / math.max(now - run.lastTime, 0.01) > TrialConfig.maxPlausibleSpeed then
		reject(player, "기록 무효 (비정상 속도)")
		return
	end

	local t = now - run.startTime
	run.splits[index] = t
	run.lastTime = now
	run.lastPos = cpPos

	local courseId = run.course.id
	local pb = best[player] and best[player][courseId]
	local delta = pb and pb.splits[index] and (t - pb.splits[index]) or nil

	if index >= run.total then
		local isNew = (pb == nil) or t < pb.time
		if isNew then
			best[player] = best[player] or {}
			best[player][courseId] = { time = t, splits = table.clone(run.splits) }
		end
		stop(player)
		Trial:FireClient(player, "Finished", t, pb and pb.time or nil, isNew, delta)
		-- TODO(7단계 기록 탭): 서버/전체 순위 저장
		return
	end
	run.nextIndex += 1
	Trial:FireClient(player, "Split", index, t, delta)
end

if not TrialConfig.enabled then
	return -- 트라이얼 꺼짐 (GameplayConfig.Trial.enabled)
end

Trial.OnServerEvent:Connect(function(player: Player, action: any, a: any)
	if action == "Start" then
		onStart(player, a)
	elseif action == "CP" then
		onCheckpoint(player, a)
	elseif action == "Cancel" then
		stop(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	active[player] = nil
	best[player] = nil
end)
