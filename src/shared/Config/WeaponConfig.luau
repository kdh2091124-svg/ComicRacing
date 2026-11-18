-- 무기 목록/수치 (보조수 = 동승석에 탄 사람이 씀)
-- 새 무기 = 아래 Weapons 에 한 줄 추가 + (선택) ReplicatedStorage.WeaponModels 에 같은 id 이름의 모델
--   모델 = Tool(손잡이 Handle) 또는 Model. 총구 끝에 "Muzzle" Attachment 를 두면 총알이 거기서 나감
--   모델이 없으면 임시 상자 총이 나옴
-- 모든 수치 TEMP (개발자 확인 전)
--
-- kind:
--   "hitscan"    쏘는 즉시 맞음 (AR, 스나이퍼, 리볼버)
--   "projectile" 날아가는 탄 + 터지면 범위 피해 + 차를 밀어냄 (콜라캐논)
-- auto: 꾹 누르면 연사 / false 면 한 번 클릭에 한 발

local WeaponConfig = {}

WeaponConfig.Weapons = {
	{
		id = "AR",
		name = "AR",
		viewLength = 4.6, -- 1인칭에서 보이는 총 길이 (스터드)
		worldLength = 5.2, -- 다른 사람이 보는 내 손의 총 길이
		kind = "hitscan",
		auto = true,
		fireRate = 13, -- 초당 발사 수
		damage = 9, -- 사람 피해
		headMultiplier = 1.6,
		carDamage = 3, -- 차 HP 피해
		range = 700,
		spread = 0.8, -- 탄 퍼짐 (도). 조준(우클릭)하면 40%
		magazine = 30,
		reloadTime = 2.0,
		zoomFov = 55, -- 우클릭 조준 시 시야
		recoil = 0.9, -- 한 발 쏠 때 화면이 위로 튀는 각도 (도). 쏜 뒤 원래 조준으로 돌아옴
		vmKick = 0.16, -- 1인칭 총이 쏠 때 튀는 세기 (1 = 한 발 크게). 총알도 총이 튄 방향을 따라감
		adsDistance = 1.9, -- 조준할 때 가늠자가 눈에서 떨어진 거리 (작을수록 얼굴에 붙음)
		shake = 0.18, -- 쏠 때 화면 흔들림 (스터드)
		fovKick = 1.5, -- 쏠 때 시야가 순간 넓어지는 정도 (도)
		recoilSide = 0.45, -- 좌우로 흔들리는 최대 각도 (도)
	},
	{
		id = "Sniper",
		name = "스나이퍼",
		viewLength = 6.6,
		worldLength = 7.6,
		kind = "hitscan",
		auto = false,
		fireRate = 0.8,
		damage = 70,
		headMultiplier = 2, -- 머리 = 한 방
		carDamage = 22,
		range = 2000,
		spread = 0, -- 조준(우클릭) 중 퍼짐
		hipSpread = 12, -- 조준 안 하고 쏘면 이만큼 크게 튐 (도). 없으면 spread 그대로 (조준 시 40%)
		scopeTime = 0.25, -- 우클릭 후 이 시간 동안은 아직 튐 (점점 모임) → 퀵스코프 방지
		boltTime = 1.0, -- 한 발 쏘면 조준 풀리고 볼트 당김. 이 시간 동안 다시 조준 못 함 (탄피는 이때 튐)
		scopeGlint = true, -- 조준하는 동안 상대 화면에 조준경 반짝임
		scopeOverlay = true, -- 조준하면 조준경 화면 (O 안에 +, 바깥은 어둡게). 흐릿한 동안은 탄이 튐
		magazine = 5,
		reloadTime = 3.4, -- 탄창 빼기 → 꽂기 → 볼트 한 바퀴까지 여유 있게
		zoomFov = 20,
		recoil = 10,
		vmKick = 1,
		shake = 0.8,
		fovKick = 7,
		recoilSide = 1,
	},
	{
		id = "Revolver",
		name = "리볼버",
		viewLength = 2.6,
		worldLength = 2.9,
		kind = "hitscan",
		auto = false,
		fireRate = 2.5,
		damage = 32,
		headMultiplier = 1.5,
		carDamage = 9,
		range = 600,
		spread = 0.4,
		magazine = 6,
		reloadTime = 2.4,
		zoomFov = 50,
		recoil = 6,
		vmKick = 0.8,
		adsDistance = 2.9, -- 리볼버는 팔을 쭉 뻗고 조준
		shake = 0.45,
		fovKick = 4,
		recoilSide = 0.8,
	},
	{
		id = "ColaCannon",
		name = "콜라캐논",
		viewLength = 5.2,
		worldLength = 5.9,
		kind = "projectile",
		auto = false,
		fireRate = 1.1,
		damage = 45, -- 터진 자리 한가운데 사람 피해 (멀수록 줄어듦)
		headMultiplier = 1,
		carDamage = 28, -- 한가운데 차 피해
		splashRadius = 16,
		knockback = 90, -- 맞은 차를 밀어내는 속도 (장외로 날리기!)
		projectileSpeed = 260,
		projectileGravity = 0.35, -- 1 = 실제 중력. 낮을수록 곧게 날아감
		range = 900,
		spread = 0,
		magazine = 1, -- 한 발 쏘고 → 캔 뽑아서 장전 → 반복
		reloadTime = 1.6,
		zoomFov = 60,
		recoil = 8,
		vmKick = 1,
		adsDistance = 2.3,
		shake = 0.7,
		fovKick = 6,
		recoilSide = 1.2,
		projectileColor = Color3.fromRGB(120, 60, 30),
	},
}

WeaponConfig.DefaultGunnerWeapon = "AR" -- TEMP 동승석에 앉으면 기본으로 쥐는 총 (나중에 상점에서 고름)

WeaponConfig.General = {
	respawnTime = 5, -- 사람이 죽으면 이 초 뒤 부활 (자기 차가 살아 있으면 원래 좌석으로)
	hitTolerance = 18, -- (서버 검사) 맞았다고 한 위치가 맞은 파트에서 이보다 멀면 무효
	originTolerance = 25, -- (서버 검사) 쏜 위치가 보조수 머리에서 이보다 멀면 무효
	tracerTime = 0.06,
	friendlyFire = false, -- 같은 차에 탄 사람끼리는 안 맞음 (팀은 게임 모드 만들 때)
	-- 보조수 카메라
	firstPerson = true, -- true = 1인칭 (눈 위치, 내 몸 안 보임) / false = 어깨 너머 3인칭
	eyeOffset = Vector3.new(0, 0.35, 0), -- 1인칭 눈 위치 (머리 중심 기준)
	cameraOffset = Vector3.new(2.2, 2.4, 9), -- 3인칭일 때 머리 기준 오른쪽, 위, 뒤
	-- 조준경 그림자 (scopeOverlay 무기). 정확도는 줌 켠 직후(scopeTime)만 영향, 돌리는 건 연출만
	scopeTurnShade = 0.012, -- 화면을 돌린 만큼 가장자리 그림자 진해짐 (마우스 1픽셀당)
	scopeSettle = 3.5, -- 돌리기 멈추면 그림자 빠지는 빠르기 (초당)
	scopeShift = 0.15, -- 휙 돌릴 때 렌즈가 반대로 밀리는 양 (마우스 1픽셀당 화면 픽셀)
	scopeShiftMax = 22, -- 렌즈가 밀리는 최대 (픽셀)
	scopeShiftReturn = 20, -- 렌즈가 제자리로 돌아오는 빠르기
	mouseSensitivity = 0.0035,
	zoomSensitivityScale = 0.75, -- 조준 중엔 마우스가 이만큼 느리게 (너무 낮으면 늦게 따라오는 느낌)
	recoilStiffness = 90, -- 반동 스프링: 클수록 빨리 제자리로
	recoilDamping = 0.5, -- 0.4~0.6 = 살짝 튕기며 복귀 (쫄깃), 1 = 튕김 없이
	recoilMax = 16, -- 연사로 쌓이는 반동 최대 (도)
	pitchMin = -70,
	pitchMax = 60,
}

local byId = {}
for _, w in WeaponConfig.Weapons do
	byId[w.id] = w
end

function WeaponConfig.Get(id: string)
	return byId[id]
end

return WeaponConfig
