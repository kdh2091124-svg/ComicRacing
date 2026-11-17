-- 타이어 종류. 지형별 접지 차이는 미정(문서 3-3) → terrainGrip 은 지금 사용 안 함.
local TireConfig = {}

TireConfig.Default = "Slick"

TireConfig.Types = {
	Slick = { name = "슬릭", price = 0, gripMultiplier = 1.0 },
	OffRoad = { name = "오프로드", price = 2000, gripMultiplier = 0.95, terrainGrip = { Snow = 1.3, Basalt = 1.3, Sand = 1.3 } }, -- TEMP
	Racing = { name = "레이싱", price = 4000, gripMultiplier = 1.12 }, -- TEMP
}

return TireConfig
