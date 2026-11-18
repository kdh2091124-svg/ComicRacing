# Studio 테스트 방법

## 처음 한 번
1. Studio에서 새 Baseplate 플레이스를 연다. 저장 이름 예: `ComicRacing.rbxl`, 이 폴더 바깥에 저장해도 된다.
2. 기본 **Baseplate 파트를 지운다.** 맵과 겹치기 때문이다.
3. 터미널에서 이 폴더로 이동해 `rojo serve` 를 실행한다. Studio의 Rojo 플러그인에서 **Connect** 를 누른다.
4. Studio 명령줄(View → Command Bar)에 아래를 입력한다:
   ```lua
   require(game.ServerStorage.Tools.MapBuilder:Clone()).Build()
   ```
   그러면 `Workspace.Map` 이 생긴다. 이제 직접 고쳐도 되고, Rojo는 맵을 건드리지 않는다.
5. 꼭 **저장하거나 게시**한다. 맵은 Git이 아니라 플레이스 파일에 저장되기 때문이다.

## 보조수 총 (2명 테스트)
Studio 테스트 탭 → 클라이언트 및 서버 → 플레이어 2명 → 시작. 한 명은 차를 꺼내 운전, 다른 한 명은 그 차 동승석에 탑승 (차가 2인승 이상이어야 함, 예: ShoppingCart)
- 동승석에 앉으면 보조수 모드: 어깨 너머 카메라, 화면 가운데 조준점
- 좌클릭 쏘기(AR 꾹 = 연사) · 우클릭 꾹 조준 · R 장전 · 1~4 무기 바꾸기(테스트용) · F 내리기
- 사람을 맞히면 그 사람 체력, 차를 맞히면 차 HP. 머리 맞히면 노란 표시, 죽이면 빨간 표시 + KILL
- 콜라캐논 = 날아가는 탄, 터지면 범위 피해 + 차를 밀어냄 (장외로 날리기)
- 스나: 조준 안 하면 탄 크게 튐, 우클릭 후 0.25초 동안 조준점 모임, 한 발 쏘면 조준 풀리고 볼트 1초(탄피는 이때), 조준 중엔 상대 화면에 머리 위 조준경 반짝임
- 보조석에선 마우스 커서 숨김 (조준점만)
- 죽으면 5초 뒤 부활 → 자기 차가 살아 있으면 원래 좌석으로 (가운데 "다운! N초 뒤 부활")
- 맞으면: 화면 가장자리 빨갛게(내 차가 맞으면 주황) + 맞은 방향 화살표
- 맞히면: 데미지 숫자(머리 노랑, 차 주황, 킬 빨강) + 맞은 대상 하얗게 번쩍
- 왼쪽 아래 내 체력, 다른 차 위에 차 HP + 탄 사람(운전/보조) 체력
- 우리 차 운전수/보조수가 죽으면 위에 "운전수 다운! 차가 멈춰요 (N초)" 알림. 운전수 없는 차는 서서히 멈춤 (`GameplayConfig.Vehicle.driverlessBrake`)
- 차가 터진 뒤 운전수뿐 아니라 동승자도 새 차 같은 자리에 다시 탐
- 무기 모델: `ReplicatedStorage.WeaponModels` 에 `AR`, `Sniper`, `Revolver`, `ColaCannon` 이름으로 (Tool 또는 Model, 총구 끝에 `Muzzle` Attachment). 없으면 검은 상자 총
- 수치: `src/shared/Config/WeaponConfig.luau`

## PVP 깔때기 아레나 (최신 맵)
Studio 명령줄 (기존 Workspace.Map 은 ServerStorage 로 백업, 지형은 비움):
```lua
require(game.ServerStorage.Tools.ArenaBuilder:Clone()).Build()
```
- 고리 3층(바깥 높음 → 안쪽 낮음) + 층 사이 경사면 + 넓은 나선 경사로 8개(폭 100) + 구멍 가로지르는 다리 + 가운데 장외 구멍
- 난간 없음 (경사로에서도 언제든 박아서 아래로 떨굴 수 있음). 다시 켜려면 `A.rampRails = true`
- 크기/높이/경사로 위치/기울기는 `src/tools/ArenaBuilder.luau` 맨 위 `A` 표에서만 고치면 됨
- 하늘색 공(BuffSpawn) = 나중에 버프 아이템이 나올 자리 표시 (아직 먹어도 아무 일 없음)
- 빨간 네모 막 + 막 위 스나이퍼 8명: 장외로 나가면 빨간 레이저 조준 + 락온 괄호(내 화면은 가장자리 빨갛게 + 경고) → 떨어지다가 바닥 직전 "탕" (총알 줄기) → 바로 폭발. 연출은 `LockOnClient`. 막은 통과 가능(보기용). 판정/사격은 서버 `ArenaService`, 수치는 `GameplayConfig.Arena`
  - 막 크기/높이/스나이퍼 수: `A.curtainMargin`, `A.curtainAbove`, `A.snipersPerSide`
- 바깥 가장자리는 벽 없이 전부 뚫림(빨강/흰 연석) = 밀려나면 바깥으로 떨어져 장외. 벽을 다시 세우려면 `A.outerOpen = false` (그때는 `A.gaps` 자리만 뚫림)
- 노랑/검정 회전 쟁기 = 캠핑 방지. 바깥 고리는 바깥쪽으로, 중간/안쪽 고리는 구멍 쪽으로 밀어냄. 개수/속도/방향: `A.plows`
  - 쟁기는 플레이(Play)를 눌러야 돌아감 (편집 화면에선 멈춰 있음). 물리는 서버가 맡음 (`ArenaService`)
- 출력창에 경사로 최대 기울기가 나오고, 경사로끼리 겹치면 경고가 뜸

## 섬 월드 (이전 맵)
Studio 명령줄 (기존 Workspace.Map 은 ServerStorage 로 백업, 지형은 새로 만듦):
```lua
require(game.ServerStorage.Tools.IslandBuilder:Clone()).Build()
```
- 남쪽 해안 바둑판 도심(대로, 해변 도로, 부두, 딜러샵 옆 스폰) / 강 + 다리 / 북동 설산 고갯길 / 북서 서킷 / 서쪽 긴 다리 + 해안도로 + 공항 + 숲 / 동쪽 사막 협곡
- 길 모양: `src/tools/IslandBuilder.luau` 의 `buildRoutes()`, 땅 모양: `LAND`, 도심 특별 블록: `SPECIAL`
- 길 까는 공통 기술은 `src/tools/RoadEngine.luau` (RoadBuilder 와 같은 방식: 자동 다리/입구, 경사 상한, 지형 채우기/깎기)
- 끝나면 출력창에 길별 경사/다리 리포트가 나옴 (경고 뜨면 알려주세요)

## 오픈월드 도로 (이전 맵)
Studio 명령줄 (기존 Workspace.Map 은 ServerStorage 로 백업됨):
```lua
require(game.ServerStorage.Tools.RoadBuilder:Clone()).Build()
```
- 길 모양은 `src/tools/RoadBuilder.luau` 의 `ROUTES` 점만 고치면 됨 (다시 Build 하면 반영)
- 바깥 월드 크기: `WORLD` (도시는 그대로). 고갯길 모양: `TOUGE_PROGRAM` ({"s", 길이, 경사} 직선 / {"t", 각도, 반지름, 경사} 회전 / {"mark", 이름} 지름길 위치)
- 가드레일: 보이는 난간은 충돌 없음, 뒤에 투명 벽(높이 `railWallHeight`)이 막음
- Build 할 때 지형(Terrain)을 새로 만듦 (지형 직접 손본 게 있으면 `Build({ keepTerrain = true })`)
- 끝나면 Output 에 "길 점검" (길마다 최대 경사, 자동 다리, 입구 수)
- 직접 손볼 땐 Workspace.Map.Roads 안의 조각을 움직이면 됨

## 1단계 확인할 것
- [ ] Play → 왼쪽 위 **차 꺼내기** → 마트 카트 → 앞에 임시 상자 차가 나오는지
- [ ] 차에 다가가 **E(운전하기)** → 카메라가 차 뒤로 붙는지
- [ ] W/S/A/D, Space(드리프트), Shift(부스터, 아래 게이지 줄어듦)
- [ ] C: 1인칭 ↔ 3인칭 / L: 헤드라이트 / F: 내리기
- [ ] Space를 눌러도 차에서 튕겨 나가지 않는지
- [ ] 다운힐 오르막(도심 북쪽)과 설산 경사를 올라갈 수 있는지
- [ ] 뒤집힌 채 2초 → 자동으로 세워지는지
- [ ] 모바일: Studio 상단 **Test → Device** 에서 폰 선택 → 운전 중 버튼이 나오는지
- [ ] 권한: Test → **Clients and Servers** 에서 플레이어 2명 → 내 차 권한 "나만"일 때 상대가 운전하기를 누르면 거부 메시지가 나오는지

## 트라이얼 확인할 것
이미 맵을 만들었다면 명령줄에서 한 번 실행 (게이트, 구간 이름, 코너 표지판만 덧붙임. 기존 맵은 안 건드림):
```lua
require(game.ServerStorage.Tools.MapBuilder:Clone()).AddTrialExtras()
```
- [ ] 코스 출발선 노란 게이트 "TIME TRIAL · 코스이름" 이 보이는지 (도심 블록 서킷: 도심 남쪽 블록 길)
- [ ] 차 타고 게이트를 앞 방향으로 지나가면 화면 위에 타이머가 시작되는지
- [ ] 체크포인트(초록 반투명 벽) 지날 때마다 구간 이름 + CP 숫자가 오르는지
- [ ] 두 번째 판부터 구간마다 +/- (초록 = 빨라짐, 빨강 = 느려짐)
- [ ] 완주 → 신기록이면 다음 판에 반투명 고스트가 같이 달리는지
- [ ] Backspace → 출발선 뒤로 이동, 다시 지나가면 새로 시작
- [ ] R → 마지막 체크포인트로 복귀 / 트라이얼 밖에서는 그 자리에서 차 세우기
- [ ] 차에서 내리면 트라이얼 취소

## HP / 폭발 확인할 것
- [ ] 운전 패널 아래 HP 바 (초록 → 빨강). 박으면 줄고 하얗게 번쩍
- [ ] 정면으로 세게 박으면 많이, 비스듬히 긁으면 조금 깎이는지
- [ ] 3초 동안 안 박으면 다시 차오르는지
- [ ] HP 0 → 큰 불덩이 + 연기 + 불똥, 차가 조각나서 흩어지고 나는 흐물흐물 날아감
- [ ] 3초 뒤 근처에서 새 차에 탄 채로 부활
- [ ] 화산 용암(빨간 네온) 위를 달리면 HP 가 빠르게 깎이는지 / 바다에 빠지면 바로 폭발
- [ ] 달리는 중 F → "속도를 줄여야 내릴 수 있어요", 멈추면 운전석 왼쪽으로 내려짐
- [ ] 동승석에 걸어가서 닿으면 앉아지고, Space 로 안 튕겨나가고 F/버튼으로 내림
- [ ] 벽에 붙어 달리면 계속 불똥 + 벽에 검은 줄 + 차 옆에 하얀 긁힌 자국

## 조작감 조절
주행감은 대부분 `src/shared/Config/GameplayConfig.luau` 의 `Physics` 와 `VehicleConfig.BaseStats` 숫자로 조절한다.
- 너무 미끄러움 → `grip` ↑
- 잘 뒤집힘 → `antiPitchRoll` ↑ (최대 1), `uprightGround` ↑
- 출렁임이 심함 → `suspensionDamping` ↑
- 드리프트 조절은 `GameplayConfig.Physics.Drift` 한 곳 (각 줄 주석 참고)
- 고속에서 너무/덜 밀림 → `highSpeedGrip`
- 멈춰 있을 때 혼자 굴러감 → `holdGrip` ↑

## 알려진 한계 (지금 단계)
- 바퀴가 굴러가고 꺾이는 모습은 **운전자 화면에서만** 보인다. 다른 사람에게는 바퀴가 고정돼 보인다 (나중에 개선).
- 서버의 속도·순간이동 검사, HP, 폭발, 레이스, 저장 기능은 아직 없다 (2~6단계).
- 권한 설정은 서버를 나가면 초기화된다 (3단계 저장 시스템에서 연결).
