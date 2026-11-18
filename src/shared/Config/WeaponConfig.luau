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
		kind = "hitscan",
		auto = true,
		fireRate = 13, -- 초당 발사 수
		damage = 9, -- 사람 피해
		headMultiplier = 1.6,
		carDamage = 3, -- 차 HP 피해
		range = 700,
		spread = 1.4, -- 탄 퍼짐 (도)
		magazine = 30,
		reloadTime = 2.0,
		zoomFov = 55, -- 우클릭 조준 시 시야
		recoil = 1.8, -- 한 발 쏠 때 화면이 위로 튀는 각도 (도). 쏜 뒤 원래 조준으로 돌아옴
		shake = 0.18, -- 쏠 때 화면 흔들림 (스터드)
		fovKick = 1.5, -- 쏠 때 시야가 순간 넓어지는 정도 (도)
		recoilSide = 0.7, -- 좌우로 흔들리는 최대 각도 (도)
	},
	{
		id = "Sniper",
		name = "스나이퍼",
		kind = "hitscan",
		auto = false,
		fireRate = 0.8,
		damage = 70,
		headMultiplier = 2, -- 머리 = 한 방
		carDamage = 22,
		range = 2000,
		spread = 0, -- 조준(우클릭) 중 퍼짐
		hipSpread = 12, -- 조준 안 하고 쏘면 이만큼 크게 튐 (도). 없으면 spread 그대로 (조준 시 40%)
		magazine = 5,
		reloadTime = 2.6,
		zoomFov = 20,
		recoil = 10,
		shake = 0.8,
		fovKick = 7,
		recoilSide = 1,
	},
	{
		id = "Revolver",
		name = "리볼버",
		kind = "hitscan",
		auto = false,
		fireRate = 2.5,
		damage = 32,
		headMultiplier = 1.5,
		carDamage = 9,
		range = 600,
		spread = 0.4,
		magazine = 6,
		reloadTime = 2.2,
		zoomFov = 50,
		recoil = 6,
		shake = 0.45,
		fovKick = 4,
		recoilSide = 0.8,
	},
	{
		id = "ColaCannon",
		name = "콜라캐논",
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
		magazine = 3,
		reloadTime = 2.6,
		zoomFov = 60,
		recoil = 8,
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
	-- 보조수 카메라 (어깨 너머)
	cameraOffset = Vector3.new(2.2, 2.4, 9), -- 머리 기준 오른쪽, 위, 뒤
	mouseSensitivity = 0.0035,
	zoomSensitivityScale = 0.4, -- 조준 중엔 마우스가 이만큼 느리게
	recoilRecover = 6, -- 반동이 원래 조준으로 돌아오는 빠르기 (클수록 빨리)
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
