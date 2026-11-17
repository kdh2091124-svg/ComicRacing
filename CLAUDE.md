# ComicRacing (가제) — Claude Code 작업 안내

- 설계 문서: `docs/RACING_GAME_DESIGN.md` (0장 작업 규칙을 반드시 따른다)
- 개발자 확정 사항: `docs/DECISIONS.md` (설계 문서보다 우선)
- 차 모델 규칙: `docs/MODEL_RULES.md`
- 테스트 방법: `docs/TESTING.md`

## 구조
- Rojo는 **코드만** 관리한다 (`src/`). Workspace(맵), `ReplicatedStorage.VehicleModels`(차 모델)는 Studio에서 직접 관리 → Rojo 프로젝트 파일에 Workspace를 절대 넣지 않는다.
- `src/shared/Config/*` : 모든 게임 수치/목록. `-- TEMP` 표시는 개발자 확인 전 임시값.
- `src/shared/StatCalculator.luau` : 최종 능력치 계산은 여기서만.
- `src/tools/MapBuilder.luau` : 그레이박스 맵 생성기 (Studio 명령줄에서 1회 실행). 이미 맵이 있으면 덮어쓰지 않는다.
- 차 이름/코스 이름을 코드에 하드코딩하지 않는다.
- 설명은 한국어.
