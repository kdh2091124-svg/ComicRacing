-- 아레나 장외 판정 (서버 공용)
-- ArenaBuilder 가 Workspace.Map 에 남긴 Attribute 로 판단. 아레나 맵이 아니면 항상 "장외 아님"
--   ArenaCenter (Vector3), ArenaOuterR (바깥 고리 바깥 반지름), ArenaPitR (가운데 구멍 반지름),
--   ArenaFloorY (가장 낮은 고리보다 조금 아래. 이 높이 아래로 떨어지면 장외)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Arena = require(ReplicatedStorage.Shared.Config.GameplayConfig).Arena

local ArenaBounds = {}

local function data()
	local map = workspace:FindFirstChild("Map")
	if not map then
		return nil
	end
	local center, outerR, pitR, floorY = map:GetAttribute("ArenaCenter"), map:GetAttribute("ArenaOuterR"),
		map:GetAttribute("ArenaPitR"), map:GetAttribute("ArenaFloorY")
	if typeof(center) ~= "Vector3" or type(outerR) ~= "number" or type(pitR) ~= "number" or type(floorY) ~= "number" then
		return nil
	end
	return center, outerR, pitR, floorY
end

-- 떨어지는 장외 대상을 쏘는 높이 (이 "바닥"에 닿기 직전에 쏨)
function ArenaBounds.ShotY(): number?
	local map = workspace:FindFirstChild("Map")
	local y = map and map:GetAttribute("ArenaShotY")
	return type(y) == "number" and y or nil
end

function ArenaBounds.IsArena(): boolean
	return data() ~= nil
end

-- margin > 0 이면 더 안쪽까지 "위험"으로 봄 (부활 위치 기록용: 가장자리/구멍 근처는 피함)
function ArenaBounds.IsOut(pos: Vector3, margin: number?): boolean
	local center, outerR, pitR, floorY = data()
	if not center then
		return false
	end
	local m = margin or 0
	local r = Vector2.new(pos.X - center.X, pos.Z - center.Z).Magnitude
	if r > outerR + Arena.oobMargin - m then
		return true
	end
	if pos.Y < floorY then
		return true
	end
	if m > 0 and r < pitR + m then
		return true
	end
	return false
end

-- 아레나 부활 위치 하나 (ArenaSpawn 표시 중 랜덤). 아레나가 아니면 nil
function ArenaBounds.SpawnCFrame(): CFrame?
	local map = workspace:FindFirstChild("Map")
	if not map or not ArenaBounds.IsArena() then
		return nil
	end
	local spots = {}
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("ArenaSpawn") then
			table.insert(spots, d)
		end
	end
	if #spots == 0 then
		return nil
	end
	return spots[math.random(1, #spots)].CFrame + Vector3.new(0, 3, 0)
end

return ArenaBounds
