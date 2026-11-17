-- 내 차 권한 설정 (개발자 확정)
--   Drive: 누가 내 차를 운전할 수 있나   (모두 / 친구만 / 나만)
--   Ride : 누가 내 차에 동승할 수 있나   (모두 / 친구만 / 나만)
-- 값은 Player Attribute "Perm_Drive", "Perm_Ride" 에 둔다 (클라이언트 UI 가 읽음).
-- 저장(DataStore)은 3단계 저장 시스템에서 연결.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameplayConfig = require(ReplicatedStorage.Shared.Config.GameplayConfig)
local VehicleRules = GameplayConfig.Vehicle

local PermissionService = {}

local KINDS = { Drive = true, Ride = true }
local validLevel = {}
for _, lv in VehicleRules.permissionLevels do
	validLevel[lv] = true
end

local friendCache: { [string]: boolean } = {}

local function isFriend(a: Player, bUserId: number): boolean
	local key = math.min(a.UserId, bUserId) .. "_" .. math.max(a.UserId, bUserId)
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return a:IsFriendsWith(bUserId)
	end)
	local value = ok and result == true
	if ok then
		friendCache[key] = value
	end
	return value
end

function PermissionService.Init(player: Player)
	for kind, level in VehicleRules.defaultPermissions do
		if player:GetAttribute("Perm_" .. kind) == nil then
			player:SetAttribute("Perm_" .. kind, level)
		end
	end
end

function PermissionService.Set(player: Player, kind: any, level: any): boolean
	if type(kind) ~= "string" or not KINDS[kind] then
		return false
	end
	if type(level) ~= "string" or not validLevel[level] then
		return false
	end
	player:SetAttribute("Perm_" .. kind, level)
	return true
end

-- kind = "Drive" | "Ride"
function PermissionService.CanUse(player: Player, ownerUserId: number, kind: string): boolean
	if player.UserId == ownerUserId then
		return true
	end
	local owner = Players:GetPlayerByUserId(ownerUserId)
	if not owner then
		return false -- 주인 없는 차는 아무도 못 탐 (주인이 나가면 차도 사라짐)
	end
	local level = owner:GetAttribute("Perm_" .. kind) or VehicleRules.defaultPermissions[kind]
	if level == "Everyone" then
		return true
	elseif level == "Friends" then
		return isFriend(player, ownerUserId)
	end
	return false
end

return PermissionService
