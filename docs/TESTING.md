# Studio 테스트 방법

## 처음 한 번
1. Studio에서 새 Baseplate 플레이스를 연다. 저장 이름 예: `ComicRacing.rbxl`, 이 폴더 바깥에 저장해도 된다.
2. 기본 **Baseplate 파트를 지운다.** 맵과 겹치기 때문이다.
3. 터미널에서 이 폴더로 이동해 `rojo serve` 를 실행한다. Studio의 Rojo 플러그인에서 **Connect** 를 누른다.
4. Studio 명령줄(View → Command Bar)에 아래를 입력한다:
   ```lua
   require(game.ServerStorage.Tools.MapBuilder).Build()
   ```
   그러면 `Workspace.Map` 이 생긴다. 이제 직접 고쳐도 되고, Rojo는 맵을 건드리지 않는다.
5. 꼭 **저장하거나 게시**한다. 맵은 Git이 아니라 플레이스 파일에 저장되기 때문이다.

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
require(game.ServerStorage.Tools.MapBuilder).AddTrialExtras()
```
- [ ] 코스 출발선 노란 게이트 "TIME TRIAL · 코스이름" 이 보이는지 (도심 블록 서킷: 도심 남쪽 블록 길)
- [ ] 차 타고 게이트를 앞 방향으로 지나가면 화면 위에 타이머가 시작되는지
- [ ] 체크포인트(초록 반투명 벽) 지날 때마다 구간 이름 + CP 숫자가 오르는지
- [ ] 두 번째 판부터 구간마다 +/- (초록 = 빨라짐, 빨강 = 느려짐)
- [ ] 완주 → 신기록이면 다음 판에 반투명 고스트가 같이 달리는지
- [ ] Backspace → 출발선 뒤로 이동, 다시 지나가면 새로 시작
- [ ] R → 마지막 체크포인트로 복귀 / 트라이얼 밖에서는 그 자리에서 차 세우기
- [ ] 차에서 내리면 트라이얼 취소

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
