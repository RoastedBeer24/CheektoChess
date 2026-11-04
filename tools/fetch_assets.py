#!/usr/bin/env python3
"""lootandwaifus.com 에서 아티팩트 아이콘과 사도 초상화를 받아 게임 폴더에 맞춰 저장한다.

사용법: python3 tools/fetch_assets.py [--cache 임시폴더]
  - assets/artifacts/<아티팩트 id>.png
  - assets/portraits/<사도 id>.png
  - docs/ASSETS.md (있는 것 / 없는 것 목록) 갱신
Pillow 필요 (pip install pillow)
"""
import argparse
import io
import json
import os
import ssl
import sys
import time
import urllib.request

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_apostles import NAME_FIX, slug  # noqa: E402

BASE = "https://lootandwaifus.com/"

# 사이트 아이콘 파일 이름 -> 게임 아티팩트 id
# (추정) 표시는 이름이 달라 그림을 보고 맞춘 것
ARTIFACT_MAP = {
    "30kg-kettlebell": "kettlebell",
    "assassins-scroll": "assassin_book",
    "barongs-cursed-doll": "barong_doll",
    "blanchets-bouquet": "blanchet_bouquet",
    "blessed-pauldrons": "blessed_pauldron",
    "butters-yellow-card": "butter_card",
    "cardboard-armor": "cardboard_armor",
    "chalice-of-origins": "origin_grail",
    "chloes-all-purpose-sewing-chest": "chloe_sewing",
    "combat-manual": "combat_manual",
    "cotton-cloak": "bojagi_robe",          # (추정) 파란 천 두건
    "crown-of-thorns": "thorn_crown",
    "dragonlight-sword": "dragonlight_sword",
    "eldyne-lamp": "eldyne_lamp",
    "elenas-enhanced-drone": "elena_drone",
    "elven-wand": "elf_wand",
    "erpins-ice-cream-cake": "erpin_cake",
    "fanatic-mask": "madness_mask",
    "fluffy-vest": "soft_vest",
    "gemstone-ring": "gem_ring",
    "grail-of-origins": "priest_censer",    # (추정) 향로 모양
    "head-wrap": "towel_headband",
    "healing-pendant": "healing_pendant",
    "jade-codex": "jade_codex",
    "kyarots-sugarcane": "kyarot_sugarcane",
    "leets-worn-whetstone": "reet_whetstone",
    "life-gem": "life_gem",
    "mithril-knife": "mithril_knife",
    "naias-dolphin-water-gun": "naia_watergun",
    "obsidian-shuriken": "obsidian_shuriken",
    "old-wooden-dagger": "oldwood_dagger",
    "picoras-fashion-pouch": "picora_pouch",
    "ring-of-greed": "greed_ring",
    "ristys-replica-glove": "risty_glove",
    "rolletts-magic-hat": "rollett_hat",
    "ruds-exercise-manual": "rudd_manual",
    "rusty-awl": "rusty_awl",
    "safety-harness": "emergency_belt",
    "scale-armor": "scale_armor",
    "selenes-midnight-mirage": "selene_mirage",
    "shining-tiara": "shining_tiara",
    "shoupans-magical-backpack": "shoupan_backpack",
    "snorkys-fedora": "snorky_fedora",
    "sword-and-staff": "sharp_staff",
    "tigs-blazing-sword": "tig_sword",
    "vivis-silver-staff": "vivi_staff",
    "weathered-arrow": "old_arrow",
    "xions-black-cape": "xion_cape",
    "yomis-moonflower": "yomi_moonflower",
}
GUESSED = {"cotton-cloak", "grail-of-origins"}
# 성격·종족·열·역할·공격 타입 아이콘: 게임 키 -> 사이트 파일
ICON_MAP = {
    "pers_innocence": "icons/trickcal-innocence.png", "pers_composed": "icons/trickcal-composed.png",
    "pers_madness": "icons/trickcal-madness.png", "pers_vivacious": "icons/trickcal-vivacious.png",
    "pers_depressed": "icons/trickcal-depressed.png", "pers_resonance": "icons/trickcal-resonance.png",
    "race_werebeasts": "icons/trickcal-werebeast.webp", "race_elves": "icons/trickcal-elves.webp",
    "race_elementals": "icons/trickcal-elementals.webp", "race_sprites": "icons/trickcal-sprites.webp",
    "race_phantoms": "icons/trickcal-phantoms.webp", "race_dragons": "icons/trickcal-dragons.webp",
    "race_witches": "icons/trickcal-witches.webp", "race_mystic": "icons/trickcal-mystic.webp",
    "row_front": "icons/trickcal-front.png", "row_mid": "icons/trickcal-middle.png",
    "row_back": "icons/trickcal-back.png", "row_all": "icons/trickcal-all.png",
    "role_dealer": "icons/trickcal-dps.png", "role_tank": "icons/trickcal-tank.png", "role_support": "icons/trickcal-support.png",
    "dmg_physical": "icons/trickcal-physical.png", "dmg_magic": "icons/trickcal-magic.png",
}
# 사이트에는 있지만 게임(트릭컬 리바이브 한국 서버 목록)에 없는 아티팩트
NOT_IN_GAME = {"guins-tiny-penguin-friends", "sherums-parchment-scroll", "piras-gleaming-business-card", "icy-charm"}


def fetch(path, cache, ctx):
    out = os.path.join(cache, path.replace("/", "_"))
    if os.path.exists(out) and os.path.getsize(out) > 0:
        return open(out, "rb").read()
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "Mozilla/5.0 (fan-game asset fetch)"})
    data = urllib.request.urlopen(req, timeout=30, context=ctx).read()
    with open(out, "wb") as f:
        f.write(data)
    time.sleep(0.15)
    return data


def save_image(data, out, max_size):
    im = Image.open(io.BytesIO(data)).convert("RGBA")
    im.thumbnail((max_size, max_size), Image.LANCZOS)
    if out.endswith(".webp"):
        im.save(out, "WEBP", quality=90, method=6)
    else:
        im.save(out, "PNG", optimize=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=os.path.join(ROOT, ".asset_cache"))
    args = ap.parse_args()
    os.makedirs(args.cache, exist_ok=True)
    ca = "/root/.ccr/ca-bundle.crt"
    ctx = ssl.create_default_context(cafile=ca) if os.path.exists(ca) else ssl.create_default_context()

    arts = json.load(open(os.path.join(ROOT, "data", "artifacts.json"), encoding="utf-8"))["list"]
    art_by_id = {a["id"]: a for a in arts}
    raw_arts = json.load(open(os.path.join(ROOT, "data", "raw", "lootandwaifus_artifacts.json"), encoding="utf-8"))
    out_dir = os.path.join(ROOT, "assets", "artifacts")
    os.makedirs(out_dir, exist_ok=True)
    have_art = {}
    for a in raw_arts:
        key = os.path.splitext(os.path.basename(a["icon"]))[0]
        gid = ARTIFACT_MAP.get(key)
        if gid is None:
            continue
        assert gid in art_by_id, gid
        save_image(fetch(a["icon"], args.cache, ctx), os.path.join(out_dir, gid + ".png"), 128)
        have_art[gid] = key

    apostles = json.load(open(os.path.join(ROOT, "data", "apostles.json"), encoding="utf-8"))
    raw_chars = json.load(open(os.path.join(ROOT, "data", "raw", "lootandwaifus_characters.json"), encoding="utf-8"))
    pdir = os.path.join(ROOT, "assets", "portraits")
    os.makedirs(pdir, exist_ok=True)
    have_portrait = set()
    for c in raw_chars:
        aid = slug(c["name"].strip())
        if aid not in apostles:
            continue
        save_image(fetch(c["icon"], args.cache, ctx), os.path.join(pdir, aid + ".webp"), 256)
        have_portrait.add(aid)

    idir = os.path.join(ROOT, "assets", "icons")
    os.makedirs(idir, exist_ok=True)
    for key, path in ICON_MAP.items():
        save_image(fetch(path, args.cache, ctx), os.path.join(idir, key + ".png"), 96)
    make_eldyne_icon(os.path.join(idir, "eldyne.png"))

    write_report(arts, have_art, apostles, have_portrait)
    print(f"아티팩트 아이콘 {len(have_art)}/{len(arts)}, 초상화 {len(have_portrait)}/{len(apostles)}")


def make_eldyne_icon(out):
    """엘다인 아이콘은 사이트에 없어서 직접 그린다 (금색 잎 모양 마름모)."""
    from PIL import ImageDraw
    S = 96
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(48, 4), (90, 48), (48, 92), (6, 48)], fill=(224, 184, 79, 255), outline=(255, 240, 190, 255), width=5)
    d.polygon([(48, 22), (72, 48), (48, 74), (24, 48)], fill=(255, 236, 160, 255))
    d.line([(48, 26), (48, 70)], fill=(176, 128, 32, 255), width=4)
    im.save(out, "PNG")


def write_report(arts, have_art, apostles, have_portrait):
    grade_name = {"legend": "전설", "rare": "희귀", "advanced": "고급", "common": "일반"}
    roster = {u["id"] for g in json.load(open(os.path.join(ROOT, "data", "groups.json"), encoding="utf-8"))["groups"] for u in g["units"]}
    lines = [
        "# 에셋 현황",
        "",
        "`python3 tools/fetch_assets.py` 로 자동 생성되는 문서입니다.",
        "",
        "## 넣는 방법",
        "",
        "- 아티팩트 아이콘: `assets/artifacts/<아티팩트 id>.png` (정사각형 권장, 128px 이상)",
        "- 사도 초상화: `assets/portraits/<사도 id>.webp` (또는 .png)",
        "- 사도 모션(전투용): 아직 형식 미정 — 받으면 `assets/motions/<사도 id>/` 로 정리할 예정",
        "- 파일 이름이 달라도 괜찮습니다. 아티팩트·사도 이름만 알 수 있으면 제가 맞춰 넣습니다.",
        "- 위 경로에 파일이 없으면 게임은 등급 색상(아티팩트) / 성격 색상(사도) 칸으로 대신 표시합니다.",
        "",
        f"## 아티팩트 아이콘: {len(have_art)}/{len(arts)}종 확보",
        "",
    ]
    missing = [a for a in arts if a["id"] not in have_art]
    lines += [f"### 없는 아이콘 ({len(missing)}종) — 제공 필요", "", "| 등급 | 이름 | 파일 이름 | 애착 사도 |", "|---|---|---|---|"]
    order = ["legend", "rare", "advanced", "common"]
    for a in sorted(missing, key=lambda a: (order.index(a["grade"]), a["name"])):
        lines.append(f"| {grade_name[a['grade']]} | {a['name']} | `{a['id']}.png` | {a.get('owner', '')} |")
    lines += ["", "### 받은 아이콘 (사이트 이름과 맞춘 결과)", "", "| 이름 | 사이트 파일 | 비고 |", "|---|---|---|"]
    for a in sorted([a for a in arts if a["id"] in have_art], key=lambda a: (order.index(a["grade"]), a["name"])):
        key = have_art[a["id"]]
        lines.append(f"| {a['name']} | {key} | {'그림을 보고 추정 — 틀리면 알려 주세요' if key in GUESSED else ''} |")
    lines += ["", "사이트에만 있고 게임 목록에 없어서 쓰지 않은 아이콘: " + ", ".join(sorted(NOT_IN_GAME)), ""]
    miss_p = [a for a in apostles.values() if a["id"] not in have_portrait]
    lines += [f"## 사도 초상화: {len(have_portrait)}/{len(apostles)}명 확보", ""]
    if miss_p:
        lines += ["| 이름 | 파일 이름 |", "|---|---|"] + [f"| {a['name']} | `{a['id']}.webp` |" for a in miss_p]
    else:
        lines.append("모든 사도의 초상화가 있습니다.")
    lines += ["", "## 사도 모션", "", "아직 없음. 전투에서는 초상화를 임시로 사용하고, 간단한 움직임(공격 시 돌진, 피격 시 깜빡임, 스킬 시 확대)을 코드로 넣어 두었습니다.", ""]
    lines += ["### 현재 사도 풀(임시 24명)의 사도 id", "", "| 이름 | id |", "|---|---|"]
    for aid in sorted(roster, key=lambda i: apostles[i]["name"]):
        lines.append(f"| {apostles[aid]['name']} | `{aid}` |")
    with open(os.path.join(ROOT, "docs", "ASSETS.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
