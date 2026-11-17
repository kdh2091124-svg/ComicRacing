-- 돈 관련 수치. 전부 TEMP (문서 7장 14번). 실제 지급 로직은 5단계(주행 수입), 6단계(레이스 보상).

local EconomyConfig = {}

-- 주행 수입: 속도가 빠를수록 많이 (개발자 확정)
EconomyConfig.Driving = {
	tickSeconds = 1,
	minSpeed = 20, -- 이 속도 미만이면 수입 0
	moneyPerSecondAtMaxSpeed = 6, -- TEMP 최고속 기준 초당
	curve = 1.5, -- (속도/최고속)^curve → 빠를수록 확 많이
	-- 방치(오토) 방지: 같은 좁은 구역을 계속 돌면 수입 감소
	antiAfk = { cellSize = 150, windowSeconds = 120, minUniqueCells = 4, penaltyMultiplier = 0.2 },
}

-- 레이스 보상 (개발자 확정 규칙):
-- 꼴찌라도 완주하면 보상. 참여 인원이 많을수록 더 많이.
-- 솔로 레이스나 짧은 코스는 보상 감소.
EconomyConfig.Race = {
	finishBase = 100, -- TEMP 완주 기본
	perParticipant = 60, -- TEMP 참가자 1명당 추가
	placeBonus = { 150, 90, 50 }, -- TEMP 1~3등 추가
	soloMultiplier = 0.3, -- TEMP 혼자 달리면
	courseLengthMultiplier = { PointToPoint = 1.0, Circuit = 1.0 }, -- 코스별 길이 반영은 6단계에서 실제 거리로 계산
	dnfReward = 0, -- 미완주
}

return EconomyConfig
