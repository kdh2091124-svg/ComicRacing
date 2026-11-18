-- 차 목록과 기본 능력치.
-- 새 차 추가 = Vehicles 배열에 한 줄 + (선택) ReplicatedStorage.VehicleModels 에 같은 id 이름의 모델.
-- 모델이 없으면 placeholder(크기/색) 로 임시 상자 차를 만들어 준다.
-- ⚠️ 모든 수치는 TEMP (개발자 확인 전 임시값). 문서 7장 9번.

local VehicleConfig = {}

-- 모든 차 공통 기본값. 차마다 stats 에 적은 값만 덮어쓴다.
-- 단위: 속도 studs/s, 가속 studs/s², 각도 도(degree)
VehicleConfig.BaseStats = {
	maxSpeed = 110, -- TEMP 최고 속도
	acceleration = 95, -- TEMP 가속 (로블록스 중력이 강해서 오르막 25°까지 오르려면 90 이상 필요)
	reverseRatio = 0.35, -- 후진 최고속/가속 = 전진의 이 비율
	brake = 150, -- TEMP 브레이크 감속
	rollingResistance = 8, -- 가속 안 할 때 자연 감속
	steerAngle = 32, -- 최대 조향각
	grip = 1.1, -- 타이어 마찰계수 (1.0 = 무게만큼 옆으로 버팀). 클수록 덜 미끄러짐
	driftPower = 1, -- 드리프트 회전 세기 배율 (차마다 다르게. 클수록 과감하게 돎)
	suspensionRest = 2.4, -- 서스펜션 길이 (studs)
	suspensionStiffness = 260, -- 스프링 세기 (무게 기준). 낮을수록 부드럽고 출렁임
	suspensionDamping = 12, -- 출렁임 잡는 힘. 4 는 너무 통통 튐 → 12. 2*sqrt(stiffness)=32 이면 거의 안 출렁
	wheelRadius = 1.2,
	density = 0.7, -- 차체 밀도 (무게)
	hp = 100, -- TEMP
	boostPower = 0.45, -- 부스터 시 최고속/가속 +45%
	boostDuration = 3, -- 부스터 풀충전으로 쓸 수 있는 초
	boostRecharge = 0.12, -- 초당 충전량 (0~1)
}

-- 전체 속도 배율: 모든 차에 곱해짐 (차끼리 차이는 그대로 유지). 속도감 조절은 여기 하나로
VehicleConfig.GlobalScale = {
	maxSpeed = 1.4, -- 넓은 도로에 비해 느려서 +40%
	acceleration = 1.2,
	brake = 1.2,
}

-- 공통 서스펜션 배치 (물리용 보이지 않는 바퀴 위치).
-- 모든 차가 이 기본 배치를 써서 조작감이 거의 같고, 차 크기에 따라 "조금만" 넓어지거나 좁아진다.
-- 눈에 보이는 바퀴(Wheel_ 파트)는 모델 생김새대로 아무 데나 둬도 물리에 영향 없음.
VehicleConfig.BaseLayout = {
	track = 5.5, -- 좌우 바퀴 간격
	wheelbase = 7.5, -- 앞뒤 바퀴 간격
	mountAboveBottom = 1.0, -- 서스펜션 시작점 = 차체 바닥에서 이만큼 위 (모든 차 같은 차고)
	sizeInfluence = 0.25, -- 차 크기가 배치에 주는 영향 (0 = 모든 차 완전 동일, 1 = 차 크기 그대로)
	minScale = 0.85,
	maxScale = 1.3,
}

export type VehicleDef = {
	id: string,
	name: string,
	price: number,
	seats: number, -- 운전석 포함 총 좌석 수
	stats: { [string]: number }?,
	effect: string?, -- 특수 효과 모듈 id (나중에 Effects 폴더에서 찾음)
	layout: { track: number?, wheelbase: number? }?, -- (선택) 이 차만 서스펜션 배치를 직접 지정
	placeholder: { size: Vector3, color: Color3 },
}

-- 순서 = 상점 표시 순서. 수치 전부 TEMP.
VehicleConfig.Vehicles = {
	{ id = "ShoppingCart", name = "마트 카트", price = 0, seats = 2, placeholder = { size = Vector3.new(4, 2, 6), color = Color3.fromRGB(190, 190, 200) } },
	{ id = "OfficeChair", name = "사무실 의자", price = 500, seats = 1, stats = { steerAngle = 42, grip = 1.3, maxSpeed = 100 }, placeholder = { size = Vector3.new(3.5, 2, 3.5), color = Color3.fromRGB(40, 40, 45) } },
	{ id = "LawnMower", name = "잔디깎이", price = 800, seats = 1, stats = { steerAngle = 40, grip = 1.25, maxSpeed = 98 }, placeholder = { size = Vector3.new(4, 2, 5), color = Color3.fromRGB(60, 160, 60) } },
	{ id = "LeatherSofa", name = "가죽 소파", price = 1200, seats = 3, stats = { grip = 1.2, density = 0.9, hp = 120 }, placeholder = { size = Vector3.new(8, 2.5, 4.5), color = Color3.fromRGB(110, 60, 35) } },
	{ id = "MiniPiano", name = "미니 피아노", price = 1500, seats = 2, stats = { acceleration = 115 }, placeholder = { size = Vector3.new(6, 3, 4), color = Color3.fromRGB(20, 20, 20) } },
	{ id = "Bed", name = "침대", price = 1600, seats = 2, placeholder = { size = Vector3.new(5, 2, 8), color = Color3.fromRGB(230, 230, 240) } },
	{ id = "Bathtub", name = "욕조", price = 1800, seats = 2, effect = "WaterSlosh", placeholder = { size = Vector3.new(4.5, 2.5, 7), color = Color3.fromRGB(245, 245, 250) } },
	{ id = "DoubleCart", name = "2단 쇼핑카트", price = 2000, seats = 4, placeholder = { size = Vector3.new(4.5, 3, 7), color = Color3.fromRGB(200, 60, 60) } },
	{ id = "GiantSkateboard", name = "거대 스케이트보드", price = 2200, seats = 2, stats = { driftPower = 1.3 }, placeholder = { size = Vector3.new(4, 1, 10), color = Color3.fromRGB(240, 120, 40) } },
	{ id = "RubberDuck", name = "거대 고무오리", price = 2400, seats = 2, effect = "QuackHorn", placeholder = { size = Vector3.new(6, 4, 7), color = Color3.fromRGB(255, 215, 0) } },
	{ id = "PizzaBike", name = "피자 배달 오토바이", price = 2600, seats = 1, stats = { acceleration = 105, steerAngle = 36 }, placeholder = { size = Vector3.new(2.5, 2, 6), color = Color3.fromRGB(220, 40, 40) } },
	{ id = "KettleCar", name = "주전자 자동차", price = 3000, seats = 2, effect = "KettleSteam", placeholder = { size = Vector3.new(5, 3.5, 6), color = Color3.fromRGB(180, 180, 190) } },
	{ id = "Fridge", name = "냉장고", price = 3500, seats = 2, effect = "FridgeFoodBurst", stats = { hp = 160, density = 1.0, maxSpeed = 104 }, placeholder = { size = Vector3.new(4.5, 6, 4.5), color = Color3.fromRGB(235, 240, 245) } },
	{ id = "VendingMachine", name = "자판기", price = 3800, seats = 2, effect = "VendingCans", stats = { hp = 160, density = 1.0, maxSpeed = 104 }, placeholder = { size = Vector3.new(5, 6, 4), color = Color3.fromRGB(30, 90, 200) } },
	{ id = "Coffin", name = "관", price = 4200, seats = 1, stats = { maxSpeed = 120 }, placeholder = { size = Vector3.new(3.5, 2, 8), color = Color3.fromRGB(60, 35, 25) } },
	{ id = "IceCreamTruck", name = "아이스크림 트럭", price = 4500, seats = 6, effect = "IceCreamHorn", stats = { density = 0.9, maxSpeed = 104 }, placeholder = { size = Vector3.new(7, 5, 13), color = Color3.fromRGB(255, 190, 220) } },
	{ id = "Excavator", name = "포크레인", price = 5000, seats = 1, stats = { maxSpeed = 85, hp = 200, density = 1.3 }, placeholder = { size = Vector3.new(7, 4, 10), color = Color3.fromRGB(240, 180, 20) } },
	{ id = "ChairExtinguisher", name = "바퀴의자 + 소화기", price = 5200, seats = 1, effect = "ExtinguisherBoost", stats = { boostPower = 0.6 }, placeholder = { size = Vector3.new(3.5, 2, 3.5), color = Color3.fromRGB(200, 30, 30) } },
	{ id = "RocketToilet", name = "로켓 변기", price = 6000, seats = 1, stats = { maxSpeed = 124 }, placeholder = { size = Vector3.new(3.5, 3, 5), color = Color3.fromRGB(250, 250, 250) } },
	{ id = "TourBus", name = "관광버스", price = 7000, seats = 8, stats = { density = 0.8, maxSpeed = 100, hp = 180 }, placeholder = { size = Vector3.new(8, 6, 22), color = Color3.fromRGB(70, 140, 220) } },
	{ id = "HypergamyCar", name = "하이퍼가미 카", price = 7500, seats = 1, stats = { density = 0.15, hp = 40 }, placeholder = { size = Vector3.new(7, 0.4, 9), color = Color3.fromRGB(240, 230, 200) } },
	{ id = "ChairRocket", name = "의자 달린 로켓", price = 9000, seats = 1, stats = { maxSpeed = 140, steerAngle = 12, grip = 0.85 }, placeholder = { size = Vector3.new(3, 3, 10), color = Color3.fromRGB(150, 150, 160) } },
	{ id = "Hypercar", name = "하이퍼카", price = 15000, seats = 2, stats = { maxSpeed = 128, acceleration = 105, grip = 1.2 }, placeholder = { size = Vector3.new(6, 2, 11), color = Color3.fromRGB(230, 30, 60) } },
} :: { VehicleDef }

VehicleConfig.DefaultVehicleId = "ShoppingCart"

VehicleConfig.ById = {} :: { [string]: VehicleDef }
for _, def in VehicleConfig.Vehicles do
	assert(VehicleConfig.ById[def.id] == nil, "VehicleConfig: 중복 id " .. def.id)
	VehicleConfig.ById[def.id] = def
end

function VehicleConfig.Get(id: string): VehicleDef?
	return VehicleConfig.ById[id]
end

return VehicleConfig
