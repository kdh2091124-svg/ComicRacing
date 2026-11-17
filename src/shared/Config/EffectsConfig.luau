-- 차량 이펙트 수치 (스키드 마크, 스파크, 연기, 부스터 불꽃, 충돌 스파크).
-- 텍스처는 로블록스 기본 내장 파티클 (에셋 업로드 필요 없음). 나중에 전용 그림으로 바꾸려면 여기만 수정.

local EffectsConfig = {}

EffectsConfig.Textures = {
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
}

EffectsConfig.maxDistance = 400 -- 카메라에서 이보다 먼 차는 이펙트 끔 (성능)
EffectsConfig.slideSkidAngle = 14 -- 드리프트 아니어도 이 각도 이상 미끄러지면 스키드 마크

EffectsConfig.Skid = {
	width = 0.9,
	lifetime = 3, -- 자국이 남는 시간 (초)
	color = Color3.fromRGB(25, 25, 25),
	transparency = 0.35,
}

-- 드리프트 불똥 / 불씨. 오래 끌수록 색이 바뀜 (흰 → 파랑 → 주황 → 분홍)
EffectsConfig.Sparks = {
	baseRate = 35, -- 드리프트 중 기본 불똥 수 (초당)
	ratePerTier = 30, -- 단계마다 추가
	emberRate = 14, -- 천천히 떠오르는 불씨 (초당)
	tierColors = {
		[0] = Color3.fromRGB(255, 225, 150),
		[1] = Color3.fromRGB(90, 190, 255),
		[2] = Color3.fromRGB(255, 150, 40),
		[3] = Color3.fromRGB(255, 80, 220),
	},
}

-- 드리프트 중 뒷바퀴 뒤로 짧게 남는 빛나는 꼬리선 (색은 위 단계 색)
EffectsConfig.Glow = {
	enabled = false, -- 꺼둠 (개발자 요청)
	height = 0.7, -- 꼬리선 높이 (스터드)
	lifetime = 0.35, -- 꼬리 길이 (초)
	transparency = 0.15,
}

EffectsConfig.Smoke = {
	rate = 40,
	color = Color3.fromRGB(245, 245, 250), -- 처음 색
	endColor = Color3.fromRGB(190, 190, 200), -- 사라질 때 색
}

-- 부스터 불꽃 (하얀 속불 + 주황 겉불) 과 차 옆 빛줄기
EffectsConfig.Flame = {
	coreRate = 120,
	outerRate = 70,
	lightBrightness = 4,
}

EffectsConfig.Streak = {
	enabled = false, -- 꺼둠 (개발자 요청)
	lifetime = 0.3,
	color = Color3.fromRGB(120, 210, 255),
	transparency = 0.35,
}

-- 드리프트 진입 순간 한 번에 터지는 양 (타격감)
EffectsConfig.Burst = {
	smoke = 12,
	sparks = 24,
	embers = 10,
}

EffectsConfig.Impact = {
	count = 40, -- 세게 박을 때 튀는 불똥 수 (세기에 비례)
}

-- 충돌 판정 (운전자 화면): 속도 변화가 이 가속도를 넘으면 "박았다"
EffectsConfig.impactAccel = 900
EffectsConfig.impactMinSpeed = 35

return EffectsConfig
