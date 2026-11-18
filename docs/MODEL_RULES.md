# 아레나 스나이퍼 모델 (선택)

막 위 스나이퍼를 직접 만든 걸로 쓰려면 `ServerStorage.ArenaModels.Sniper` (Model) 에 두고 ArenaBuilder 를 다시 실행.
없으면 블록 스나이퍼가 자동으로 나온다.

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
