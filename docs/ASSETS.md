# 에셋 현황

`python3 tools/fetch_assets.py` 로 자동 생성되는 문서입니다.

## 넣는 방법

- 아티팩트 아이콘: `assets/artifacts/<아티팩트 id>.png` (정사각형 권장, 128px 이상)
- 사도 초상화: `assets/portraits/<사도 id>.webp` (또는 .png)
- 사도 모션(전투용): 아직 형식 미정 — 받으면 `assets/motions/<사도 id>/` 로 정리할 예정
- 파일 이름이 달라도 괜찮습니다. 아티팩트·사도 이름만 알 수 있으면 제가 맞춰 넣습니다.
- 위 경로에 파일이 없으면 게임은 등급 색상(아티팩트) / 성격 색상(사도) 칸으로 대신 표시합니다.

## 아티팩트 아이콘: 105/105종 확보

- 49종: lootandwaifus.com
- 56종: 공개 팬 사이트 저장소 github.com/mediate1082/Trickal-Revive-Skill-Guide-Beta-0.8 (`assets/icons/artifacts`, 비상업 팬 작품 · 이미지 권리는 Epid Games) — 한글 이름·등급으로 대조
- 확인 필요: `sharp_staff`(날카로운 지팡이) 아이콘이 두 출처에서 다름 (지금은 lootandwaifus 쪽: 검과 파란 구슬 지팡이)

## 사도 초상화: 125/125명 확보

모든 사도의 초상화가 있습니다.

## 사도 모션

아직 없음. 전투에서는 초상화를 임시로 사용하고, 간단한 움직임(공격 시 돌진, 피격 시 깜빡임, 스킬 시 확대)을 코드로 넣어 두었습니다.

### 현재 사도 풀(임시 24명)의 사도 id

| 이름 | id |
|---|---|
| Ronnie | `ronnie` |
| 가비아 | `gabia` |
| 그윈 | `guin` |
| 나이아 | `naia` |
| 네르 | `ner` |
| 네르(빡침) | `ner_rage` |
| 네티 | `neti` |
| 니콜 | `nicole` |
| 다야 | `daya` |
| 다야(퓨어샤인) | `daya_pure_shine` |
| 델리아 | `delia` |
| 디아나 | `diana` |
| 디아나(왕년) | `diana_yester` |
| 라이카 | `raika` |
| 란 | `ran` |
| 레비 | `levi` |
| 레비(졸업) | `levi_graduate` |
| 레테 | `lethe` |
| 로네 | `rohne` |
| 로네(시장) | `rohne_mayor` |
| 롤렛 | `rollett` |
| 루드 | `rudd` |
| 루포 | `rufo` |
| 리뉴아 | `renewa` |
| 리스티 | `risty` |
| 리온 | `leone` |
| 리츠 | `leets` |
| 리코타 | `ricotta` |
| 림 | `rim` |
| 림(혼돈) | `rim_chaos` |
| 마고 | `mago` |
| 마리 | `marie` |
| 마에스트로 2호 | `maestromk2` |
| 마요 | `mayo` |
| 마요(멋짐) | `mayo_cool` |
| 마카샤 | `makasha` |
| 멜루나 | `meluna` |
| 모모 | `momo` |
| 뮤트 | `mute` |
| 미로 | `miro` |
| 바나 | `bana` |
| 바롱 | `barong` |
| 바리에 | `barie` |
| 버터 | `butter` |
| 베니 | `beni` |
| 베니 (베니) | `beni_beni` |
| 벨라 | `vela` |
| 벨리타 | `belita` |
| 벨벳 | `velvet` |
| 블랑셰 | `blanchet` |
| 비비 | `vivi` |
| 비비(신성) | `vivi_divine` |
| 빅우드 | `bigwood` |
| 샤샤 | `shasha` |
| 셀리네 | `selene` |
| 셰럼 | `sherum` |
| 셰이디 | `shaydi` |
| 셰이디(역전) | `shaydi_twisted` |
| 슈로 | `shuro` |
| 슈팡 | `shoupan` |
| 스노키 | `snorky` |
| 스키아 | `skea` |
| 스패럿 | `sparrot` |
| 스피키 | `speaki` |
| 스피키(메이드) | `speaki_maid` |
| 시스트 | `sist` |
| 시온 더 다크불릿 | `xxionx` |
| 시저 | `caesar` |
| 실라 | `sylla` |
| 실비아 | `silvia` |
| 실피르 | `silphir` |
| 아네트 | `annette` |
| 아라그니아 | `aragnia` |
| 아르코 | `arco` |
| 아멜리아 | `amelia` |
| 아멜리아(R41) | `amelia_r41` |
| 아사나 | `asana` |
| 아야 | `aya` |
| 아이시아 | `asia` |
| 아일라 | `ayla` |
| 알레트 | `allet` |
| 앨리스 | `alice` |
| 에르핀 | `erpin` |
| 에르핀(왕도) | `erpin_royale` |
| 에슈르 | `ashur` |
| 에슈르(마도) | `ashur_magi` |
| 에스피 | `espi` |
| 에피카 | `epica` |
| 엘레나 | `elena` |
| 오로라 | `aurora` |
| 오르 | `orr` |
| 오팔 | `opal` |
| 요미 | `yomi` |
| 우로스 | `uros` |
| 우이 | `ui` |
| 우이(기억) | `ui_memory` |
| 이드 | `ed` |
| 이드(재활) | `ed_rehab` |
| 이프리트 | `ifrit` |
| 잉클 | `inkle` |
| 제이드 | `jade` |
| 죠안 | `joanne` |
| 쥬비 | `jubee` |
| 칸나 | `canna` |
| 칸타 | `canta` |
| 캐시 | `kathy` |
| 캬롯 | `kyarot` |
| 코미 | `kommy` |
| 코미(수영복) | `swimsuit_kommy` |
| 코페 | `coffe` |
| 클로에 | `chloe` |
| 키디언 | `kidian` |
| 키샤 | `kishya` |
| 티그 | `tig` |
| 티그(영웅) | `tig_hero` |
| 페스타 | `festa` |
| 포셔 | `posher` |
| 폴랑 | `polan` |
| 프리클 | `fricle` |
| 피라 | `pira` |
| 피코라 | `picora` |
| 하이디 | `heidi` |
| 헤일리 | `haley` |
| 헤일리(멀쩡) | `haley_sane` |
| 힐데 | `hilde` |
