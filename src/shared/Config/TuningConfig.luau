-- 튜닝 항목. 새 항목 = Items 에 한 줄.
-- kind: "Level"(레벨업) / "Slider"(겉모양 조절) / "Choice"(종류 선택)
-- affects: { 능력치이름 = 레벨당 증가 비율 } → StatCalculator 가 읽음.
-- ⚠️ 최대 레벨, 비용 곡선 전부 TEMP (문서 7장 10번). 튜닝 UI/구매는 4단계에서.

local TuningConfig = {}

TuningConfig.Items = {
	Suspension = { name = "서스펜션", kind = "Level", maxLevel = 20, cost = { base = 100, growth = 1.25 }, affects = { suspensionDamping = 0.02, grip = 0.004 } },
	Engine = { name = "엔진", kind = "Level", maxLevel = 20, cost = { base = 150, growth = 1.28 }, affects = { maxSpeed = 0.015, acceleration = 0.01 } },
	Intake = { name = "엑셀(흡기)", kind = "Level", maxLevel = 20, cost = { base = 120, growth = 1.27 }, affects = { acceleration = 0.02 } },
	Brake = { name = "브레이크", kind = "Level", maxLevel = 20, cost = { base = 80, growth = 1.22 }, affects = { brake = 0.03 } },
	TireGrip = { name = "타이어 접지", kind = "Level", maxLevel = 20, cost = { base = 100, growth = 1.25 }, affects = { grip = 0.015 } },
	NitroDuration = { name = "니트로 지속", kind = "Level", maxLevel = 20, cost = { base = 120, growth = 1.26 }, affects = { boostDuration = 0.04, boostRecharge = 0.03 } },
	NitroPower = { name = "니트로 출력", kind = "Level", maxLevel = 20, cost = { base = 140, growth = 1.28 }, affects = { boostPower = 0.025 } },
	-- 슬라이더: 성능 영향은 미정(문서 3-3) → 지금은 겉모양 전용
	RideHeight = { name = "차고", kind = "Slider", min = -0.6, max = 0.6, default = 0 },
	Camber = { name = "캠버", kind = "Slider", min = -12, max = 12, default = 0 },
	Offset = { name = "오프셋", kind = "Slider", min = 0, max = 0.8, default = 0 },
	Tire = { name = "타이어 종류", kind = "Choice", source = "TireConfig" },
}

-- level → level+1 비용
function TuningConfig.CostForLevel(itemId: string, currentLevel: number): number?
	local item = TuningConfig.Items[itemId]
	if not item or item.kind ~= "Level" or currentLevel >= item.maxLevel then
		return nil
	end
	return math.floor(item.cost.base * item.cost.growth ^ currentLevel)
end

return TuningConfig
