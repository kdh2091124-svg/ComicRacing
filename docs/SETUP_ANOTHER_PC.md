# 다른 컴퓨터 / 다른 플레이스에서 이어서 작업하기

이 프로젝트는 **두 군데**에 나뉘어 있어요.

| 무엇 | 어디에 저장됨 | 옮기는 법 |
|---|---|---|
| 코드 (`src/`, `docs/`, 설정) | 이 폴더 (Git) | GitHub 에 올리고 다른 컴퓨터에서 받기 |
| 맵, 차 모델, 무기 모델, 스나이퍼 템플릿 | Roblox 플레이스 파일 (Studio) | 플레이스를 Roblox 에 게시하거나 `.rbxl` 파일로 저장해서 옮기기 |

Studio 에서만 관리하는 것들 (Git 에 없음):
- `Workspace.Map` (ArenaBuilder 로 만든 아레나)
- `ReplicatedStorage.VehicleModels` (차 모델)
- `ReplicatedStorage.WeaponModels` (AR, Sniper, Revolver, ColaCannon)
- `ServerStorage.ArenaModels` (스나이퍼 템플릿, 있으면)

---

## 1. 지금 컴퓨터에서 (한 번만)

### 코드 올리기
1. GitHub 에서 새 저장소를 만들어요 (예: `ComicRacing`, **Private 추천**). README 같은 건 추가하지 말고 빈 저장소로.
2. 저장소 주소(`https://github.com/<아이디>/ComicRacing.git`)를 Claude 에게 주면 연결해서 올려줘요.
   직접 하려면 이 폴더에서:
   ```bash
   git remote add origin https://github.com/<아이디>/ComicRacing.git
   git push -u origin master
   ```
   처음 올릴 때 브라우저로 GitHub 로그인 창이 뜨면 로그인하면 돼요.

### 플레이스(맵/모델) 올리기 — 둘 중 하나
- **Roblox 에 게시 (추천):** Studio → 파일 → Roblox 에 게시. 다른 컴퓨터 Studio 에서 같은 계정으로 "내 게임"에서 열면 돼요.
- **파일로 저장:** Studio → 파일 → 다른 이름으로 파일에 저장 → `ComicRacing.rbxl` 을 USB/클라우드로 옮기기.

---

## 2. 다른 컴퓨터에서 (처음 한 번)

1. 설치
   - Roblox Studio
   - Git (https://git-scm.com)
   - Rokit (https://github.com/rojo-rbx/rokit) — Rojo 를 설치해 주는 도구
2. 코드 받기
   ```bash
   git clone https://github.com/<아이디>/ComicRacing.git
   ```
3. 받은 폴더에서 Rojo 설치 (rokit.toml 에 적힌 7.7.1 버전으로 깔림)
   ```bash
   rokit install
   ```
4. Studio 에 Rojo 플러그인 설치
   ```bash
   rojo plugin install
   ```
5. Studio 에서 플레이스 열기 (Roblox 에 게시한 것 또는 `.rbxl` 파일)

## 3. 매번 작업할 때

1. 최신 코드 받기
   ```bash
   git pull
   ```
2. Rojo 켜기 (폴더에서, 작업하는 동안 켜두기)
   ```bash
   rojo serve
   ```
3. Studio → 플러그인 탭 → Rojo → **Connect** → 코드가 Studio 에 들어감
4. 작업 끝나면 코드 올리기
   ```bash
   git add -A
   git commit -m "무슨 작업"
   git push
   ```
5. 맵/모델을 바꿨으면 플레이스도 다시 게시(또는 `.rbxl` 저장)

> 두 컴퓨터에서 번갈아 할 때: **시작 전 `git pull`, 끝나면 `git push`** 만 지키면 코드가 꼬이지 않아요.
> Claude Code 를 다른 컴퓨터에서 쓰면 이 폴더를 열고 시작하면 돼요 (`CLAUDE.md`, `docs/` 를 읽고 이어감).

---

## 4. 다른 플레이스(새 게임)에 이 코드 넣기

1. 새 플레이스를 Studio 에서 열기
2. 이 폴더에서 `rojo serve` → Studio 에서 Rojo **Connect** → 코드가 들어감
3. Studio 에서만 관리하는 것들 옮기기:
   - 원래 플레이스에서 `WeaponModels`, `VehicleModels`, `ArenaModels` 폴더를 각각 오른쪽 클릭 → **파일에 저장** (`.rbxm`)
   - 새 플레이스에서 같은 위치에 오른쪽 클릭 → **파일에서 삽입**
4. 맵은 새로 만들기 (명령줄):
   ```lua
   require(game.ServerStorage.Tools.ArenaBuilder:Clone()).Build()
   ```
5. 게임 설정 → 보안 → **Studio 의 API 서비스 접근 허용**은 필요 없음 (저장 기능은 아직 없음)
