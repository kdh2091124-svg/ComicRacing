-- 맵에 배치된 코스(Workspace.Map.Courses.<id>)를 읽어서 정리한 데이터로 만든다.
-- 서버는 맵 전체를 갖고 있으므로 여기서 읽어 클라이언트에 보내 준다
-- (클라이언트는 StreamingEnabled 때문에 먼 체크포인트가 아직 없을 수 있음).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CourseConfig = require(ReplicatedStorage.Shared.Config.CourseConfig)

local CourseData = {}

export type Checkpoint = { cframe: CFrame, size: Vector3, section: string }
export type Course = {
	id: string,
	name: string,
	type: string,
	laps: number,
	start: { cframe: CFrame, size: Vector3 },
	cps: { Checkpoint },
}

local cache: { [string]: Course } = {}

function CourseData.Get(courseId: string): Course?
	if cache[courseId] then
		return cache[courseId]
	end
	local def = CourseConfig.ById[courseId]
	local map = workspace:FindFirstChild("Map")
	local courses = map and map:FindFirstChild("Courses")
	local folder = courses and courses:FindFirstChild(courseId)
	if not def or not folder then
		return nil
	end
	local start = folder:FindFirstChild("Start")
	local cpFolder = folder:FindFirstChild("Checkpoints")
	if not (start and start:IsA("BasePart") and cpFolder) then
		warn("[CourseData] " .. courseId .. ": Start 파트나 Checkpoints 폴더가 없음")
		return nil
	end

	local list = {}
	for _, cp in cpFolder:GetChildren() do
		local n = tonumber(string.match(cp.Name, "^CP(%d+)$"))
		if n and cp:IsA("BasePart") then
			table.insert(list, { n = n, part = cp })
		end
	end
	table.sort(list, function(a, b)
		return a.n < b.n
	end)
	if #list == 0 then
		warn("[CourseData] " .. courseId .. ": 체크포인트(CP1, CP2...)가 없음")
		return nil
	end

	local cps = {}
	for _, item in list do
		table.insert(cps, {
			cframe = item.part.CFrame,
			size = item.part.Size,
			section = item.part:GetAttribute("Section") or "",
		})
	end

	local course: Course = {
		id = courseId,
		name = def.name,
		type = def.type,
		laps = def.laps or 1,
		start = { cframe = start.CFrame, size = start.Size },
		cps = cps,
	}
	cache[courseId] = course
	return course
end

return CourseData
