# 무기 모델 (보조수 총)

`ReplicatedStorage.WeaponModels` 에 무기 id 이름으로 (`AR`, `Sniper`, `Revolver`, `ColaCannon`). Tool 이든 Model 이든 됨. 없으면 상자 총.

| 이름 | 종류 | 설명 |
|---|---|---|
| `Muzzle` | 총구 끝의 Attachment (또는 작은 파트) | 총알/섬광이 여기서 나감. 이쪽이 총의 "앞" |
| `Grip` | Attachment | 오른손(방아쇠 손)이 쥐는 곳. 없으면 총 길이의 32% 지점 |
| `Foregrip` | Attachment | 왼손이 받치는 곳 (총열 아래/손잡이). 없으면 68% 지점 아래 |
| `Eject` | Attachment | 탄피 배출구. 탄피가 여기서 튀어나감 (오른쪽으로). 없으면 총구 뒤쪽 대충 |
| `Aim` | Attachment | 조준(우클릭) 때 눈앞 정중앙에 올 점 = 가늠자/도트사이트 가운데. 없으면 대충 가운데 (스나는 조준경 화면이라 필요 없음) |
| `Mag` | 파트, 또는 그 이름의 Model/Folder | 탄창. 1인칭 장전 때 실제로 빠졌다 꽂힘 |
| `Bolt` | 파트, 또는 그 이름의 Model/Folder | 볼트 손잡이. 1인칭 볼트 때 들고 당겼다 밀림, 연사 총은 쏠 때마다 철컥 |
| `Cylinder` | 파트, 또는 그 이름의 Model/Folder | 리볼버 실린더. 쏠 때마다 한 칸(60°) 돌고, 장전 때 왼쪽으로 열림. **회전축 = 총열 방향, 실린더 가운데** |
| `Hammer` | 파트, 또는 그 이름의 Model/Folder | 리볼버 공이치기. 쏘면 앞으로 떨어졌다 다시 젖혀짐 |

- 방향: 총의 **가장 긴 쪽 = 총열**. 크기는 아무렇게나 만들어도 됨 → 코드가 `WeaponConfig` 의 `viewLength`(1인칭), `worldLength`(남이 보는 손) 길이에 맞춰 줄이고 키움
- 움직이는 정도: `src/client/ViewModel.luau` 의 `VM` (`boltTravel`, `boltLift`, `shotSlide`, `magDrop`)

# 아레나 스나이퍼 모델 (선택)

막 위 스나이퍼를 직접 만든 걸로 쓰려면 `ServerStorage.ArenaModels.Sniper` (Model) 에 두고 ArenaBuilder 를 다시 실행.
없으면 블록 스나이퍼가 자동으로 나온다.

**제일 쉬운 방법 (R6, 자세는 코드가 잡음)**
1. 아바타 탭 → 리그 빌더 → **R6** 리그 생성. 자세는 건드리지 말고 기본으로 서 있는 그대로 (옷/모자 입혀도 됨)
2. 이름 `Sniper` 로 `ServerStorage.ArenaModels` 에 넣기
3. 총 모델(Model 또는 Tool)은 이름 `SniperRifle` 로 **같은 폴더**에 따로 넣기 → 코드가 "서서 쏴" 자세로 꺾고 총을 손에 쥐어줌
   - 총 방향: 총의 가장 긴 쪽 = 총열. 총구 끝에 `Muzzle` Attachment 가 있으면 그쪽이 앞 (없으면 자동으로 만듦)
   - 거꾸로 쥐면 `A.sniperPose.rifleFlip = true`, 뒤집히면 `rifleUpsideDown = true`, 쥐는 위치 `rifleGrip`
   - 자세 각도/손발 위치도 `A.sniperPose` 에서 조절

**자세 손으로 다듬기**
1. 위 방법으로 맵을 한 번 만든 뒤, `Workspace.Map.Curtain` 안의 스나이퍼 하나(`Sniper1` 등)를 회전/이동 도구로 직접 다듬음 (관절이 없고 고정돼 있어서 파트를 그냥 돌리면 됨)
2. 다듬은 걸 복사 → `ServerStorage.ArenaModels` 에 붙여넣고, 원래 `Sniper` 는 지우거나 이름 바꾸고, 붙여넣은 걸 `Sniper` 로 이름 변경
3. 맵 다시 만들기 → 다듬은 자세 그대로 8명 모두 적용 (Attribute `SniperBaked` 가 붙어 있어서 자세/총/크기를 다시 건드리지 않음)

아래 표는 직접 자세를 잡아서 넣을 때 (R15 등):

| 할 것 | 설명 |
|---|---|
| 기본 Rig (R6/R15 아무거나) | 아바타 탭 → 리그 빌더. 자세는 마음대로 (팔/다리 돌려서 저격 자세) |
| 무기 | 무기 모델을 손에 맞춰 놓고 **스나이퍼 Model 안에 넣기** (용접 필요 없음, 전부 고정됨) |
| `Muzzle` | 총구 끝에 **Attachment 또는 작은 파트**, 이름 `Muzzle`. 레이저/총알이 여기서 나감. 총 모델 안에 있어도 됨 |
| 앞 방향 | 캐릭터가 **정면(HumanoidRootPart 앞)으로 총을 겨누게**. 생성기가 정면을 아레나 가운데로 돌림 |
| 크기 | 보통 크기로 만들면 됨. 생성기가 `A.sniperScale`(기본 3)배로 키움 |

자동 처리: 모든 파트 Anchored + 충돌 끔 (잡은 자세 그대로 고정), 이름/체력바 숨김, 안에 든 스크립트(Animate 등) 삭제, 발바닥을 막 위에 맞춤.

# 차 모델 만드는 규칙

새 차 = `VehicleConfig.Vehicles` 에 한 줄 추가 + 아래 규칙대로 만든 모델을 `ReplicatedStorage.VehicleModels` 에 넣기.
모델이 없으면 config 의 `placeholder`(크기/색)로 **임시 상자 차**가 자동으로 나온다. 그래서 모델 없이도 테스트할 수 있다.

## 필수
| 이름 | 종류 | 설명 |
|---|---|---|
| 모델 이름 | Model | VehicleConfig 의 `id` 와 똑같이 (예: `RocketToilet`) |
| `Chassis` | Part | 차체 충돌 상자 겸 기준점. **앞쪽 = 파트의 앞면(-Z, LookVector)**. 유일하게 충돌하는 파트 |
| `DriverSeat` | Seat | 운전석 (VehicleSeat 아님, 그냥 Seat) |

## 선택
| 이름 | 종류 | 설명 |
|---|---|---|
| `Wheel_XX` | Part | **보이는 바퀴 (그림 전용)**. 이름이 `Wheel_` 로 시작하면 됨. 생김새대로 아무 위치·개수로 둬도 주행에 영향 없음. 가장 가까운 물리 바퀴의 출렁임을 따라 움직이고, 앞쪽(Z<0) 바퀴는 조향 때 꺾임. 굴러가는 축 = 차의 좌우(X) 방향. 주차 상태에서 땅에 닿는 높이에 두면 됨 |
| `Susp_FL/FR/RL/RR` | Chassis 안의 Attachment | **보통 만들지 않음.** 물리 바퀴 위치는 `VehicleConfig.BaseLayout` 공통 배치로 자동 생성된다. 아주 특별한 차만 직접 넣거나, config 의 `layout = { track = , wheelbase = }` 로 조정 |
| `PassengerSeat1`, `PassengerSeat2`… | Seat | 동승석. 개수 = config `seats - 1` 권장 |
| `Headlight…` | Part + 안에 SpotLight/PointLight | 이름이 `Headlight` 로 시작. L 키로 켜고 끔 |
| `DriverCamera` | DriverSeat 안의 Attachment | 1인칭 시점 위치. 없으면 좌석 위 2.6 |

## 자동 처리 (직접 할 필요 없음)
- 모든 파트를 Chassis 에 용접하고, Anchored 를 끄고, Massless 를 켠다.
- Chassis 를 뺀 모든 파트는 충돌을 끈다. 충돌을 살리려면 파트에 Attribute `KeepCollision = true` 를 넣는다.
- 운전석은 닿기만 해선 안 앉고 E 프롬프트로만 탄다 (운전 권한 검사). 동승석은 가까이 가서 닿으면 바로 앉고, 권한이 없으면 차 옆으로 내려놓는다.
- 서스펜션 길이와 바퀴 반지름은 config 의 `suspensionRest`, `wheelRadius` 를 쓴다. 바퀴 그림 크기도 여기에 맞춘다.

## 조작감 원칙
- **모든 차가 같은 물리 바퀴 배치를 쓴다** (`BaseLayout`: 좌우 5.5, 앞뒤 7.5, 차체 바닥에서 1 위). 그래서 생김새와 상관없이 기본 조작감이 거의 같다.
- 차 크기에 따라 배치가 **조금만** 바뀐다 (`sizeInfluence = 0.25`, 0.85~1.3배). 큰 버스는 조금 더 안정적이고, 작은 의자는 조금 더 휙휙 돈다.
- 차마다 다른 맛은 `stats` (grip, steerAngle, maxSpeed 등) 몇 개로 낸다.

## 팁
- Chassis 바닥 높이가 차고 기준이다. 모든 차가 바닥에서 약 1.6 떠 있다.
- 하이퍼가미 카의 차트 그림은 **Decal 하나로만** 붙여서 이미지 ID만 바꾸면 교체되게 한다 (심사에서 거부될 때 대비).
