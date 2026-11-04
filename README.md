# CheektoChess

트릭컬 리바이브 **비공식 팬게임** · 오토체스 장르 (Godot 4.7)

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
- 사도를 누른 뒤 빈칸/다른 사도를 누르면 이동·교체. 사도를 고르면 놓을 수 있는 칸이 빛납니다.
- 사도를 고르고 **판매**.
- 보관함 아티팩트를 누르고 사도를 누르면 장착.
- 아티팩트를 고르고 **합성** → 같은 등급의 다른 아티팩트를 누르면 합성.

## 폴더 구조

```
data/                게임 데이터 (JSON)
  apostles.json      사도 125명 (tools/build_apostles.py 로 생성)
  roster.json        상점에 나오는 사도 목록과 코스트 ← 사도 풀은 여기서 바꿈
  artifacts.json     아티팩트 105종 (효과 구조 포함)
  synergies.json     시너지 단계/효과
  balance.json       경제·전투·확률 수치
  raw/               원본 참고 데이터
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
tests/               자동 테스트
tools/               데이터 변환 / 에셋 받기 스크립트 (fetch_assets.py)
```

## 테스트

```bash
godot --headless --path . res://tests/tests.tscn
```

전투 결정론, 합성, 열 제한, 아티팩트 합성, 봇 8명 한 판, 화면을 띄운 오프라인 진행을 확인합니다.

LAN 테스트 (같은 기기에서 두 프로세스):

```bash
godot --headless --path . res://tests/lan_test.tscn -- host &
godot --headless --path . res://tests/lan_test.tscn -- client
```

## 데이터 출처 / 라이선스

- 사도·아티팩트 정보, 초상화·아이콘 이미지: [lootandwaifus.com](https://lootandwaifus.com), 나무위키 「트릭컬 리바이브/카드/아티팩트」 (CC BY-NC-SA 2.0 KR)
- 트릭컬 리바이브의 캐릭터와 설정의 권리는 원저작자(에피드게임즈)에게 있습니다. 비상업적 팬게임입니다.
- 폰트: Noto Sans KR — SIL Open Font License 1.1 (`assets/fonts/OFL.txt`)
