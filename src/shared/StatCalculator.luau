-- "최종 능력치 = 차 기본값 + 튜닝 보정" 계산은 여기서만 한다 (문서 8-2).
-- 나중에 이벤트 보너스/스킨 효과도 여기에 추가.

local Config = script.Parent:WaitForChild("Config")
local VehicleConfig = require(Config:WaitForChild("VehicleConfig"))
local TuningConfig = require(Config:WaitForChild("TuningConfig"))
local TireConfig = require(Config:WaitForChild("TireConfig"))

export type TuningState = {
	levels: { [string]: number }?,
	sliders: { [string]: number }?,
	tire: string?,
}

local StatCalculator = {}

function StatCalculator.Compute(vehicleId: string, tuning: TuningState?): { [string]: number }
	local def = VehicleConfig.Get(vehicleId)
	assert(def, "StatCalculator: 없는 차 id " .. tostring(vehicleId))

	local stats = table.clone(VehicleConfig.BaseStats)
	if def.stats then
		for k, v in def.stats do
			stats[k] = v
		end
	end

	-- 전체 속도 배율 (VehicleConfig.GlobalScale)
	for statName, mul in VehicleConfig.GlobalScale or {} do
		if stats[statName] then
			stats[statName] *= mul
		end
	end

	local t = tuning or {}
	if t.levels then
		for itemId, level in t.levels do
			local item = TuningConfig.Items[itemId]
			if item and item.kind == "Level" and item.affects then
				local lv = math.clamp(level, 0, item.maxLevel)
				for statName, perLevel in item.affects do
					if stats[statName] then
						stats[statName] *= 1 + perLevel * lv
					end
				end
			end
		end
	end

	local tire = TireConfig.Types[t.tire or TireConfig.Default] or TireConfig.Types[TireConfig.Default]
	stats.grip *= tire.gripMultiplier

	return stats
end

-- 모델 Attribute 로 저장/읽기 (서버가 쓰고 클라이언트가 읽음)
local PREFIX = "Stat_"

function StatCalculator.WriteToModel(model: Instance, stats: { [string]: number })
	for k, v in stats do
		model:SetAttribute(PREFIX .. k, v)
	end
end

function StatCalculator.ReadFromModel(model: Instance): { [string]: number }
	local stats = table.clone(VehicleConfig.BaseStats)
	for name, value in model:GetAttributes() do
		if string.sub(name, 1, #PREFIX) == PREFIX and type(value) == "number" then
			stats[string.sub(name, #PREFIX + 1)] = value
		end
	end
	return stats
end

return StatCalculator
