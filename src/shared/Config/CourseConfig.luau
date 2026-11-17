-- 레이스 코스. 새 코스 = Courses 에 한 줄 + Workspace.Map.Courses.<id> 폴더 배치.
-- 폴더 구조: Courses/<id>/Start (출발 위치 파트), Courses/<id>/Checkpoints/CP1, CP2 ... (마지막 CP = 결승)
-- type: "PointToPoint"(긴 맵, 1바퀴) / "Circuit"(둥근 맵, laps 바퀴)
-- enabled=false 는 아직 맵에 체크포인트가 없는 코스 (투표에 안 나옴).

local CourseConfig = {}

CourseConfig.Courses = {
	{ id = "PeakToSea", name = "정상에서 바다까지", type = "PointToPoint", laps = 1, enabled = true },
	{ id = "DowntownDownhill", name = "도심 다운힐", type = "PointToPoint", laps = 1, enabled = true },
	{ id = "CityBlockCircuit", name = "도심 블록 서킷", type = "Circuit", laps = 3, enabled = true },
	{ id = "AvalancheEscape", name = "눈사태 탈출", type = "PointToPoint", laps = 1, enabled = false },
	{ id = "MTBDeathTrail", name = "MTB 데스 트레일", type = "PointToPoint", laps = 1, enabled = false },
	{ id = "VolcanoEscape", name = "화산 탈출", type = "PointToPoint", laps = 1, enabled = false },
	{ id = "DockDash", name = "부두 질주", type = "PointToPoint", laps = 1, enabled = false },
	{ id = "CraterRing", name = "분화구 링", type = "Circuit", laps = 3, enabled = false },
	{ id = "ParkingSpiral", name = "주차장 나선탑", type = "Circuit", laps = 3, enabled = false },
	{ id = "FrozenLake", name = "빙판 호수", type = "Circuit", laps = 2, enabled = false },
	{ id = "ConstructionCircuit", name = "공사장 서킷", type = "Circuit", laps = 2, enabled = false },
	{ id = "WineryHills", name = "와이너리 언덕", type = "Circuit", laps = 2, enabled = false },
}

CourseConfig.ById = {}
for _, c in CourseConfig.Courses do
	CourseConfig.ById[c.id] = c
end

return CourseConfig
