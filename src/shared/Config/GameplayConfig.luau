-- 게임 규칙 수치. TEMP = 개발자 확인 전 임시값.

local GameplayConfig = {}

-- 아케이드 보정 (문서 2-1). 구현하면서 조율.
GameplayConfig.Physics = {
	highSpeedSteerFactor = 0.5, -- 최고속일 때 조향각 = 최대의 50%
	steerSpeed = 7, -- 핸들 꺾이는 속도
	steerReturnSpeed = 10, -- 핸들 놓으면 가운데로 돌아오는 속도 (빠를수록 손 떼면 바로 직진)
	antiPitchRoll = 1.0, -- 바퀴 힘(가속/코너)이 차를 들어올리는 효과 제거 (1 = 윌리/옆 들림 없음, 낮추면 기울어짐 생김)
	uprightGround = 12, -- 땅에서 수평 유지 힘
	-- 공중 보정 (떨어질 때 수평 + 직진 유지, A/D 로 방향 돌리기)
	airLevelSpeed = 6, -- 수평으로 돌아오는 빠르기 (클수록 빨리 평평해짐)
	airLevelDampingRatio = 0.9, -- 1 근처면 출렁임 없이 딱 멈춤
	airYawSpeed = 2.5, -- A/D 누를 때 공중 회전 속도 (라디안/초, 2.5 ≈ 초당 145°)
	airYawResponse = 8, -- 회전 반응 속도
	airHeadingAlign = 2, -- A/D 안 누르면 날아가는 방향으로 차 머리 맞추는 세기 (0 = 안 맞춤)
	-- 드리프트 (누르고 있는 동안 도는 방식)
	--   Space + A/D 로 시작 → 누르는 순간 바로 그립을 놓고 돎. Space 떼면 끝.
	--   꾹 = 계속 돌아서 깊어짐, 톡톡 = 짧게 돌고 얕음 (뗀 사이엔 tapYaw 로 느슨하게 유지)
	--   드리프트 중 안쪽 키 = 더 깊게, 바깥 키 = 얕게, 바깥 키를 switchHoldTime 이상 = 반대쪽으로 전환
	--   각도 ≈ asin(회전속도 × (1 - carve) / traction)
	--     기본: 1.7×0.4/1.2 → 약 35°   안쪽 꾹: 2.9×0.4/1.2 → 약 75° (스핀 방지 한계)   바깥: 0.5×0.4/1.2 → 약 10°
	Drift = {
		minSpeed = 18, -- 이 속도 이상에서 시작
		inputBuffer = 0.2, -- Space 와 방향키를 이 초 안에만 누르면 순서 상관없이 시작
		tapYaw = 0.6, -- Space 를 뗀 사이(톡톡 사이) 회전 속도 → 느슨한 각도 유지 (약 11°)
		holdRampTime = 0, -- 꾹 누른 뒤 baseYaw 까지 걸리는 시간 (0 = 즉시)
		entryBlend = 0.85, -- 누르는 순간 바로 그립을 이만큼 놓음
		blendIn = 10, -- 드리프트 들어가는 빠르기
		blendOut = 2.0, -- Space 떼면 드리프트 힘이 빠지는 빠르기 (높을수록 떼자마자 내 조작대로)
		tireLatCut = 0.97, -- 드리프트 중 타이어 옆 힘 97% 줄임 (남으면 회전을 막음)
		baseYaw = 1.7, -- Space 누르고 있을 때 회전 속도 (라디안/초)
		steerYaw = 1.2, -- 안쪽 키 = 더 깊게 (+1.2)
		outwardYaw = 2.6, -- 바깥 키 = 반대로 돌려서 "펴기" (1.7-2.6 = -0.9 → 차가 실제로 펴짐). 전엔 덜 돌기만 해서 못 펴고 박았음
		spinGuardAngle = 75, -- 이 각도 넘을 때만 스핀 방지
		yawResponse = 8, -- 회전 반응 (낮을수록 스윽, 높을수록 탁)
		carve = 0.6, -- 차가 도는 만큼 진행 방향도 바로 휘는 비율
		traction = 1.2, -- 진행 방향이 차 머리를 따라 휘는 세기 (낮을수록 길게 미끄러짐)
		engineCut = 0.75, -- 드리프트 중 엔진 힘 75% 줄임
		speedKeep = 0, -- 엑셀 밟을 때 추가 속도 보충 (가속도)
		drag = 22, -- 드리프트 중 감속 (가속도). 오래 끌수록 느려짐
		switchHoldTime = 0.45, -- 바깥 키를 이 초 이상 계속 누르면 반대쪽 드리프트로 전환 (짧게 누르면 펴기만)
		recoverTime = 0.3, -- 드리프트 끝난 뒤 옆 그립이 완전히 돌아오기까지 (짧게 → 떼면 바로 원하는 방향으로)
		recoverMinGrip = 0.7, -- 끝난 직후 옆 그립 (70% 에서 바로 시작)
		recoverSteerBoost = 4, -- 회복 중 방향키를 누르면 회복이 이 배수만큼 빨라짐 (반대로 바로 꺾기)
	},
	-- 평소 주행: 저속은 착 붙고, 빠를수록 점점 밀림
	-- 고속에서 덜 도는 건 "조향각이 줄어서" 자연스럽게 (타이어를 억지로 미끄럽게 하지 않음)
	highSpeedGrip = 1.0, -- 최고속일 때 타이어 접지 배율 (1 = 안 줄어듦. 고속 한계는 조향각으로만)
	gripFalloffCurve = 2, -- 접지가 줄어드는 곡선
	-- 평소(A/D) 코너 한계: 옆 가속도 = base + perSpeed × 속도 (studs/s²). 회전 한계 = 옆 가속도 / 속도
	--   속도 40 → 초당 2.9   속도 100 → 초당 1.5   부스터 160 → 초당 1.2 (+부스터 접지 보너스)
	--   드리프트는 속도 상관없이 초당 1.2 ~ 2.2 + 미끄러지며 도는 각도 → 급커브/U턴은 드리프트가 확실히 유리
	normalLatAccelBase = 130,
	normalLatAccelPerSpeed = 0.8,
	-- 드리프트 탈출 부스트 (각도 유지하며 오래 미끄러질수록 단계 ↑, Space 떼면 발동)
	DriftBoost = {
		enabled = false, -- 개발자 요청으로 끔 (부스트 중 방향 잡기 어려움). 켜면 탈출 부스트 + 단계 표시 부활
		minAngle = 10, -- 이 각도 이상 미끄러져야 충전 (불똥 색 단계에도 쓰임)
		spinOutAngle = 100, -- 이 각도 넘으면 스핀으로 보고 충전 초기화 (깊게 판 드리프트는 OK)
		tierTimes = { 0.6, 1.4, 2.4 }, -- 1/2/3단계 필요 시간 (초)
		tierPower = { 0.15, 0.28, 0.42 }, -- 단계별 속도/가속 +15% / +28% / +42%
		duration = 1.2, -- 부스트 지속 (초)
	},
	-- 스핀 방지: 핸들 꺾은 것보다 차가 더 돌면 잡아줌 (차 크기 상관없이 같은 느낌)
	yawStability = 3, -- 차가 핸들 꺾은 만큼 정확히 따라 돌게 잡아줌 (클수록 칼같음, 0 = 보정 없음)
	counterSteerAssist = 0.3, -- 평소 자동 카운터 스티어 (살짝 미끄러질 때 알아서 잡음)
	yawTargetSmooth = 4, -- A↔D 전환 때 목표 회전이 바뀌는 빠르기 (낮을수록 스윽, 높을수록 탁)
	-- 타이어 모델 (A/D 꾹 누르면 접지 한계 넘어서 자연스럽게 미끄러짐)
	frontGrip = 1.0, -- 앞바퀴 접지 배율
	rearGrip = 1.0, -- 뒷바퀴 접지 배율 (앞보다 낮으면 꼬리가 잘 나감 = 오버스티어)
	rearDriveBias = 0.55, -- 가속 힘의 55%를 뒷바퀴로 (높을수록 코너에서 밟으면 꼬리 미끄러짐)
	slipPeak = math.rad(8), -- 이 각도까지 미끄러질 땐 접지가 점점 세짐
	slipFull = math.rad(28), -- 이 각도 넘으면 완전히 미끄러지는 상태
	slideRatio = 1.0, -- 한계 넘어 미끄러질 때 접지 = 최대의 100% (1 = 한계에서 갑자기 놓치지 않음)
	-- 벽 긁기 (비스듬히 박으면 속도 유지하며 벽 따라 미끄러짐)
	WallScrape = {
		minSpeed = 25, -- 이 속도 이상일 때만
		minDeltaV = 10, -- 한 프레임에 이만큼 이상 속도가 꺾이면 "벽에 닿음"
		minSpeedLoss = 5, -- 그리고 속력이 이만큼 이상 줄었을 때
		headOnCos = 0.75, -- 정면 기준. 벽에 약 50° 이상 각도로 꽂으면 "정면 충돌" → 그냥 멈춤
		keep = 0.93, -- 벽 따라 남는 속도 비율 (1 = 전혀 안 줄어듦)
		bounce = 0.15, -- 벽에서 살짝 튕겨 나오는 정도
		yawKeep = 0.4, -- 충격으로 생긴 회전 중 남기는 비율 (낮을수록 박아도 방향이 안 틀어짐)
		alignTime = 0.4, -- 긁은 뒤 이 초 동안 차 머리를 벽 따라 가는 방향으로 맞춰줌
		alignStrength = 25, -- 맞춰주는 세기
		alignDamping = 8, -- 그동안 회전 죽이기 (벽 쪽으로 휙 도는 것 방지)
	},
	groundGraceTime = 0.3, -- 바퀴가 잠깐 떠도 이 초까지는 땅에 있는 걸로 봐줌 (고속 드리프트 시작용)
	frictionCircle = 0.35, -- 가속/브레이크가 옆 접지를 얼마나 깎는지 (1 = 실제 물리, 낮을수록 밟으면서 꺾어도 안 밀림)
	boostGrip = 1.25, -- 부스터(Shift, 드리프트 탈출 부스트) 중 접지 +25%
	gripLoadSmoothing = 0.9, -- 접지 계산 시 출렁임 무시 비율 (높을수록 고속에서 안정, 0 = 실제 물리)
	slipLowSpeed = 6, -- 저속 떨림 방지용
	holdSpeed = 4, -- 페달 안 밟고 이 속도 미만이면 제자리 버팀
	holdGrip = 8, -- 버티는 힘
	downforce = 0.1, -- 고속 접지 보조 (g 배율)
	pedalRise = 3, -- 가속/브레이크 페달 밟히는 속도 (초당). 낮을수록 부드럽게 출발
	pedalFall = 6, -- 페달 놓는 속도
	powerCurve = 2.5, -- 최고속 근처 힘 감소 곡선 (클수록 끝까지 힘 유지)
	bumpStopStart = 0.8, -- 서스펜션 80% 눌리면 범프 스톱 시작
	bumpStopStrength = 4, -- 범프 스톱 세기 (스프링의 배수)
	maxSpringG = 4, -- 바퀴 하나가 낼 수 있는 최대 힘 (무게의 배수) → 착지 튐 방지
	airDrag = 0.02,
	-- 통제 불능: 크게 틀어지면(세게 맞아 기울거나 빙글빙글 돌면) 수평 맞춤 같은 보정을 끄고 진짜 물리에 맡김
	-- → 운 좋으면 바퀴로 떨어져 살고, 아니면 굴러서 떨어짐. 바퀴로 똑바로 서면 보정이 다시 켜짐
	Chaos = {
		enabled = false, -- 꺼둠: 켜면 차가 혼자 자빠짐 (개발자 요청으로 예전 물리로 복귀)
		tiltDeg = 55, -- 이 각도 넘게 기울면 통제 불능
		spinRate = 5, -- 앞뒤/좌우로 이 속도(라디안/초) 넘게 돌면 통제 불능
		recoverDeg = 25, -- 바퀴 3개 이상 땅에 닿고 이 각도 안으로 서면
		calmTime = 0.4, -- 이 시간 동안 버티면 보정 복귀 시작
		returnTime = 0.5, -- 보정이 다시 100% 로 돌아오는 시간
	},
	-- 범퍼 (Attribute "Bumper" 붙은 파트, 예: 아레나 회전 쟁기): 닿으면 "통" 하고 진행 방향 반대로 살짝 튕김, 데미지 없음
	Bumper = {
		back = 30, -- TEMP 뒤로 튕기는 기본 속도
		backPerSpeed = 0.25, -- 빠르게 박을수록 더 튕김 (박은 속도 × 이 값 추가)
		up = 18, -- 살짝 뜨는 속도
		carryHit = 1, -- 범퍼가 움직이는 속도도 얹어줌 (쟁기에 밀려나는 느낌)
		spinKeep = 0.3, -- 튕길 때 남기는 회전 (낮을수록 안 돌아감)
		minTravelSpeed = 8, -- 이보다 느리면 "진행 방향" 대신 범퍼 반대쪽으로 튕김
		cooldown = 0.4, -- 연속으로 튕기지 않게
		noDamageTime = 0.3, -- 튕긴 직후 이 시간 동안 충돌 데미지 없음
		fxStrength = 0.6,
		cameraPunch = 0.6,
	},
	autoFlip = true, -- TEMP 뒤집혀 멈추면 자동 복구 (문서 7장 16번)
	autoFlipDelay = 2, -- 뒤집힌 채 이 초 지나면 복구
}

GameplayConfig.Camera = {
	distance = 1.6, -- 차 길이 배율
	minDistance = 12,
	height = 0.55, -- 거리 대비 높이
	followSharpness = 8,
	fov = 70, -- 멈춰 있을 때 시야
	speedFov = 84, -- 최고속일 때 시야 (속도감)
	boostFovAdd = 10, -- 부스터 중 추가 시야
	speedPullBack = 0.18, -- 최고속일 때 카메라가 18% 뒤로 빠짐
	shake = 0.35, -- 고속/부스터 흔들림 세기 (0 = 끔)
	-- 드리프트 타격감
	-- 둘러보기 (운전 중 우클릭 드래그 / 게임패드 오른쪽 스틱)
	orbitSensitivity = 0.008, -- 마우스 감도
	orbitStickSpeed = 3, -- 스틱 회전 속도 (라디안/초)
	orbitReturnSpeed = 4, -- 손 떼면 차 뒤로 돌아오는 빠르기
	orbitPitchMin = -0.3, -- 아래로 내려볼 수 있는 한계 (라디안)
	orbitPitchMax = 1.1, -- 위에서 내려다볼 수 있는 한계 (라디안)
	driftFollowVelocity = 0.55, -- 드리프트 중 카메라가 차 머리 대신 진행 방향을 따르는 비율 (차가 옆으로 미끄러지는 게 보임)
	driftRoll = 4, -- 드리프트 중 화면 기울기 (도)
	driftFovAdd = 5, -- 드리프트 중 시야 추가
	driftEntryPunch = 0.6, -- 드리프트 들어가는 순간 흔들림
	firstPersonOffset = Vector3.new(0, 2.6, 0), -- 운전석 기준 (DriverCamera 어태치먼트 있으면 그걸 사용)
}

GameplayConfig.Vehicle = {
	spawnCooldown = 3,
	exitMaxSpeed = 12, -- 이 속도보다 빠르면 못 내림 (운전자/동승자 모두)
	-- 내 차 권한 (개발자 확정: 모두 / 친구만 / 나만). 기본값 TEMP.
	permissionLevels = { "Everyone", "Friends", "OwnerOnly" },
	permissionLabels = { Everyone = "모두", Friends = "친구만", OwnerOnly = "나만" },
	defaultPermissions = { Drive = "OwnerOnly", Ride = "Everyone" }, -- TEMP
	devFreeVehicles = true, -- 개발용: 모든 차 무료로 꺼내기 (구매 시스템 생기면 false)
}

-- 차량 HP / 폭발 / 부활. 차마다 최대 HP 는 VehicleConfig stats.hp. 수치 TEMP
GameplayConfig.Health = {
	regenDelay = 3, -- 데미지 받으면 이 초 동안 회복 멈춤 (문서 확정)
	regenPerSecond = 8, -- 그 후 초당 회복량
	-- 충돌 데미지 = (속도 변화 - minImpactSpeed) × damagePerSpeed
	-- 비스듬히 긁으면 속도가 거의 유지돼서 데미지 적고, 정면으로 꽈앙 박을수록 큼
	minImpactSpeed = 35, -- 이보다 작은 충격은 데미지 없음
	damagePerSpeed = 0.8, -- 예: 시속 110 정면 충돌 → (110-35)×0.8 = 60 데미지
	maxPerHit = 90, -- 한 번에 최대 데미지 (서버 검사용)
	-- 착지: 차가 똑바로 선 채(이 각도 안) 바퀴로 떨어지면 위아래 충격은 데미지 없음
	-- 코박기/옆으로/뒤집혀 떨어지면 충격이 차 위아래 방향과 어긋나서 그만큼 데미지
	landingUprightDeg = 35, -- TEMP
	lavaDps = 60, -- 용암 위에 있으면 초당 데미지
	drownY = -8, -- 이 높이 아래로 빠지면 (바다 등) 바로 폭발
	-- 폭발
	tickDelay = 0.4, -- 박은 순간 차+사람 정지(히트스톱) 후 "콰앙" 까지 시간 (초). 이 동안 못 내림
	respawnDelay = 3, -- 오픈월드: 폭발 후 이 초 뒤 그 근처에서 차와 함께 부활 (개발자 확정)
	flingUp = 90, -- 탄 사람이 날아가는 위쪽 속도 (90 ≈ 20스터드 높이. 140 은 너무 높았음)
	flingSide = 8, -- 옆으로 살짝 랜덤 (작을수록 똑바로 뒤로)
	flingBack = 70, -- 달리던 방향의 "반대(뒤쪽)" 로 날아가는 속도
	debrisSpeed = 90, -- 차 조각 옆으로 흩어지는 속도
	debrisUp = 100, -- 차 조각 위로 튀는 속도
	chassisLaunch = 100,
	-- 날아가는 동안 팔다리 땡깡 휘적휘적
	limbKick = 45, -- 날아가는 순간 팔다리를 랜덤 방향으로 한 번 촥 돌리는 세기 (라디안/초)
	flailEnabled = false, -- 땡깡 휘적거리기 (false = 순수 래그돌만). 다시 켜려면 true
	flailTime = 2.5, -- 휘적거리는 시간 (초)
	flailSpeed = 50, -- 팔다리 휘두르는 세기 (우스꽝스럽게 세게)
	flailRate = 13, -- 초당 휘두르는 횟수 (땡깡 박자, 미친듯이 빠르게)
	-- 날아갈 때 뒤로 도는(공중제비) 세기. 처음 한 번만 주고 나머진 물리에 맡김 → 자연스러운 포물선
	bodySpin = 6, -- 몸 전체 공중제비 회전 속도 (라디안/초)
	debrisTime = 4, -- 차 조각 남는 시간 (초)
	safeSpotInterval = 0.5, -- 부활 위치 기록 간격 (땅에 똑바로 있을 때만)
}

-- 트라이얼 (혼자 기록 경쟁)
GameplayConfig.Trial = {
	enabled = false, -- 지금은 꺼둠 (오픈월드 먼저, 레이스는 나중에). 켜면 트라이얼 게이트/구간 기록/고스트 부활
	restartBehindStart = 18, -- Backspace 재시작 시 출발선 뒤 몇 스터드에 놓을지
	respawnHeight = 3, -- 복귀 시 땅 위 높이
	fallY = -30, -- 이 높이 아래로 떨어지면 자동 복귀
	cpMaxDistance = 140, -- (서버 검사) 체크포인트 통과 보고 시 차가 이 거리 안에 있어야 인정
	maxPlausibleSpeed = 450, -- (서버 검사) 체크포인트 사이 평균 속도가 이보다 빠르면 무효
	ghostSampleRate = 15, -- 고스트 녹화 (초당 샘플)
	ghostTransparency = 0.65,
}

GameplayConfig.Race = {
	voteInterval = 300, -- 5분 (문서 확정)
	-- 진행 중인 레이스가 있으면 투표를 미룸 → 레이스 끝나고 이 초 뒤 투표 (개발자: 알아서)
	delayAfterRaceEnd = 60,
	voteDuration = 20,
	voteOptions = 3,
	maxRacers = 8, -- 동승자 포함 사람 수 (관광버스 꽉 채우면 감수 — 개발자 확정)
	-- 8명 초과 시 선착순. 출발 전에 원에서 나가면 자리 잃고 대기자가 채움, 재입장은 맨 뒤 (개발자 확정)
	joinOrder = "FirstCome",
	joinWindow = 30, -- 로비 원 안에서 대기하는 시간
	startGhostSeconds = 5,
	respawnGhostSeconds = 2.5,
	passengerHeadBonkInRace = false, -- 보류 (개발자)
}

return GameplayConfig
