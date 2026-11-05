# 볼토체스

트릭컬 리바이브 **비공식 팬게임** · 오토체스 장르 (Godot 4.7)

저장소 이름은 CheektoChess, 게임 이름은 **볼토체스**입니다.

- 기획서: [docs/DESIGN.md](docs/DESIGN.md)
- 진행 상황 / 남은 작업: [docs/STATUS.md](docs/STATUS.md)
- 에셋 현황 (없는 아이콘 목록): [docs/ASSETS.md](docs/ASSETS.md)

## 실행 방법 (PC)

1. [Godot 4.7](https://godotengine.org/download) 표준판(.NET 아님)을 설치합니다.
2. Godot 프로젝트 관리자에서 **가져오기** → 이 폴더의 `project.godot` 선택.
3. 에디터에서 **F5**(실행).

### 플레이

- **혼자 하기**: 첫 화면에서 봇 수(3~7)를 고르고 시작.
- **LAN**: 한 명이 **방 만들기** → 같은 와이파이의 다른 기기에서 방 목록을 누르거나, 방장 화면에 표시된 IP로 참가 → 방장이 봇으로 인원을 채우고(최소 4명) **게임 시작**.

### 조작 (마우스·터치 공통)

- 상점 카드를 누르면 구매.
- 사도를 **누른 채 끌면** 손가락을 따라오고, 놓을 수 있는 칸(초록)과 없는 칸(어둡게), 놓일 모습이 표시됩니다.
- 상점 카드를 끌어 대기석/보드에 놓으면 그 자리에 바로 구매합니다. 판매 칸에 놓으면 판매.
- 누르기→누르기 방식(사도를 누른 뒤 빈칸을 누름)도 그대로 됩니다.
- 상점 카드 꾹 누르기: 그 칸 잠금. 시너지 꾹 누르기: 상세 정보. 플레이어 이름 누르기: 그 플레이어 보드 보기.
- 도감: 첫 화면·게임 중 상단의 [도감] 버튼. 이름(초성 가능) 검색과 여러 필터.
- 마우스를 올리면(모바일은 꾹 누르면) 설명이 나옵니다. 설명 글의 밑줄 친 용어도 올리거나 눌러 뜻을 볼 수 있고, 도감 '용어' 탭에 모아 두었습니다.
- PC 단축키: D 새로고침 · F 경험치 · E 마우스 아래 사도 판매 · 스페이스 준비/건너뛰기 · F11(또는 Alt+Enter) 전체 화면
- 사도를 고르고 **판매**.
- 보관함 아티팩트를 누르고 사도를 누르면 장착. 아티팩트를 사도 위로 끌어다 놓아도 장착됩니다.
- 아티팩트를 고르고 **합성** → 같은 등급의 다른 아티팩트를 누르면 합성. 같은 등급 아티팩트 위로 끌어다 놓아도 합성됩니다.
- 목록(정보·보관함·도감·플레이어/시너지)은 손가락으로 끌어 스크롤합니다. 보관함에서는 세로로 끌면 스크롤, 옆으로 끌면 아티팩트 끌어다 놓기.
- 사도가 같은 등급 아티팩트를 2개 장착하고 있으면 사도 정보 맨 위의 합성 버튼으로 바로 합성 (결과는 보관함으로).

## 안드로이드 설치 · 자동 업데이트

- APK를 한 번 설치하면, 이후 게임 내용(코드·데이터·그림)은 **실행할 때 자동으로 업데이트**됩니다.
  - 게임은 시작할 때 GitHub 릴리스의 `manifest.json`을 확인하고, **바뀐 묶음만** 받습니다 (core ≈ 0.5MB, art ≈ 2.5MB).
  - 인터넷이 없으면 마지막으로 받은 버전으로 실행합니다.
- **LAN**: 방에 들어갈 때 방장보다 버전이 낮으면, 방장 기기에서 바뀐 묶음만 직접 받습니다 (인터넷 불필요). 받은 뒤 앱을 다시 실행합니다.
- 큰 묶음(모션 ≈ 71MB, 보이스 ≈ 18MB)은 4MB 조각으로 받고, 끊기면 다음 실행 때 받은 곳부터 이어서 받습니다. 게임 코드·그림을 먼저 받아 적용하므로 모션·보이스를 다 못 받아도 게임은 최신 버전으로 시작합니다('지금은 건너뛰기' 버튼).
- 새 APK 가 나오면(시작 화면 버전 `BASE_VERSION` 이 오르면) 실행할 때 [받기]/[나중에]를 묻습니다. 받은 APK 는 덮어 설치합니다.
- **APK 자동 빌드**: 저장소 Settings → Secrets and variables → Actions 에 `ANDROID_KEYSTORE_BASE64`(키 파일을 base64 로), `ANDROID_KEYSTORE_USER`(별칭), `ANDROID_KEYSTORE_PASSWORD` 를 넣어 두면, 업데이트마다 서명된 `CheektoChess.apk` 가 릴리스에 함께 올라갑니다 (버전 코드 = 빌드 번호).
- APK 자체를 다시 설치해야 하는 경우: Godot 엔진 버전 변경, 앱 권한 변경, 시작 화면(`boot/`) 변경. 이때는 `boot/boot.gd`의 `BASE_VERSION`을 올리고, 옛 APK 로는 동작할 수 없는 묶음이면 `min_base`도 맞춥니다.

## PC(Windows) 설치 · 자동 업데이트

- [최신 릴리스](https://github.com/RoastedBeer24/CheektoChess/releases/latest)에서 `CheektoChess-windows.zip`을 받아 압축을 풀고 `CheektoChess.exe`를 실행합니다.
  - 바탕 화면·문서처럼 쓰기 권한이 있는 폴더에 두세요 (Program Files 는 자동 업데이트가 안 될 수 있음).
  - 처음 실행할 때 "Windows의 PC 보호" 창이 뜨면 **추가 정보 → 실행** (코드 서명 인증서가 없어서 뜨는 안내).
  - LAN 방을 만들 때 방화벽 창이 뜨면 **개인 네트워크** 허용.
- 게임 내용은 안드로이드와 같은 묶음으로 실행할 때 자동 업데이트됩니다.
- 실행 파일 자체가 바뀌어야 하는 업데이트(`boot/boot.gd`의 `BASE_VERSION` 상승)는 실행할 때 새 실행 파일을 받아 **스스로 바꾼 뒤 다시 시작**합니다.
  (지금 파일 → `.old` 로 이름 변경, 새 파일을 원래 이름으로. 다음 실행 때 `.old` 삭제. 실패하면 릴리스 페이지를 엽니다.)
- F11 또는 Alt+Enter 전체 화면, 창 크기·위치 기억. 저장 위치: `%APPDATA%\CheektoChess`.

### 업데이트 배포 (자동)

`scripts/`, `scenes/`, `data/`, `assets/`, `boot/` 등이 바뀌어 푸시되면 GitHub Actions(`.github/workflows/content-release.yml`)가
묶음과 Windows 실행 파일(zip)을 만들어 `content-<빌드번호>` 릴리스로 올립니다. 게임은 항상 최신 릴리스를 봅니다.

### 직접 빌드

```bash
# 묶음만
tools/build_release.sh 1
# 묶음 + APK (서명 키 환경 변수 필요)
GODOT_ANDROID_KEYSTORE_RELEASE_PATH=... GODOT_ANDROID_KEYSTORE_RELEASE_USER=cheektochess GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=... tools/build_release.sh 1 android
# 묶음 + Windows 실행 파일
tools/build_release.sh 1 windows
```

필요한 것: Godot 4.7 + 내보내기 템플릿, Android SDK(build-tools), JDK 17 이상. 서명 키는 저장소에 넣지 않습니다.

## 폴더 구조

```
boot/                시작 화면 + 자동 업데이트 (APK 에 들어가는 유일한 게임 스크립트)
data/                게임 데이터 (JSON)
  apostles.json      사도 125명 (tools/build_apostles.py 로 생성)
  groups.json        그룹: 판에 쓰는 사도·코스트·시너지(효과 글 + 게임 동작) ← tools/import_group.py
  artifacts.json     아티팩트 105종 (효과 구조 포함)
  balance.json       경제·전투·확률 수치
  raw/               원본 참고 데이터
scripts/app.gd       게임 시작점 (App.session / App.net)
scripts/core/        규칙 (네트워크·화면과 무관)
  match.gd           게임 진행·명령 처리 (방장에서만 실행)
  battle_sim.gd      결정론적 자동 전투
  rules.gd           시너지/능력치/어사이드 계산
  bot.gd             봇
scripts/net/         LAN (net.gd), 세션·동기화 (session.gd)
scripts/ui/          화면
assets/fonts/        Noto Sans KR (SIL OFL)
assets/portraits/    사도 초상화 (<사도 id>.webp)
assets/artifacts/    아티팩트 아이콘 (<아티팩트 id>.png)
assets/icons/        성격·종족·엘다인·열·역할·공격 타입 아이콘
tests/               자동 테스트
tools/               데이터 변환, 에셋 받기(fetch_assets.py), 묶음 만들기(build_packs.gd), 릴리스 빌드(build_release.sh), 앱 아이콘(make_icons.py)
```

## 테스트

```bash
godot --headless --path . res://tests/tests.tscn
```

전투 결정론, 합성, 열 제한, 아티팩트 합성, 끊김 탈락, 봇 8명 한 판, 화면을 띄운 오프라인 진행을 확인합니다.
LAN 업데이트(방장 기기에서 받기) 테스트는 `tests/lan_update_test.gd` 상단 주석 참고.

LAN 테스트 (같은 기기에서 두 프로세스):

```bash
godot --headless --path . res://tests/lan_test.tscn -- host &
godot --headless --path . res://tests/lan_test.tscn -- client
```

## 데이터 출처 / 라이선스

- 사도·아티팩트 정보, 초상화·아이콘 이미지: [lootandwaifus.com](https://lootandwaifus.com), 아티팩트 아이콘 일부: [Trickal-Revive-Skill-Guide](https://github.com/mediate1082/Trickal-Revive-Skill-Guide-Beta-0.8) (팬 사이트), 전투 모션·보이스: 트릭컬 스파인 뷰어(viewer.dclnslde.com)의 저장 기능, 나무위키 「트릭컬 리바이브/카드/아티팩트」 (CC BY-NC-SA 2.0 KR)
- 트릭컬 리바이브의 캐릭터와 설정의 권리는 원저작자(에피드게임즈)에게 있습니다. 비상업적 팬게임입니다.
- 폰트: Noto Sans KR — SIL Open Font License 1.1 (`assets/fonts/OFL.txt`)
