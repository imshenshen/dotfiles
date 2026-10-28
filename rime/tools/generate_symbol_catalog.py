#!/usr/bin/env python3
"""Generate the checked-in /fh symbol catalog for the Squirrel slash palette.

The Rime preset is the source of truth for the glyph set. Names, categories and
search aliases are maintained here so the palette can search by English,
Chinese/pinyin, hex code and category without a second input composition.
Run without arguments to rewrite the Swift file; pass --check to verify it.
"""
from __future__ import annotations

import argparse
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SYMBOLS = ROOT / "rime/distribution/data/symbols.yaml"
OUTPUT = ROOT / "rime/native/voice/SlashSymbolData.swift"

CATEGORY_PINYIN = {
    "商标与版权": "shangbiao banquan",
    "警示与标志": "jingshi biaozhi",
    "自然与地点": "ziran didian",
    "体育与娱乐": "tiyu yule",
    "方向与手势": "fangxiang shoushi",
    "工具与科学": "gongju kexue",
    "其他": "qita",
}

# Curated names and search aliases for the symbols users are most likely to
# look up by meaning. The category name is the fallback for the rest.
ALIASES = {
    "©": ("版权", "banquan", "copyright copy banquan ©"),
    "®": ("注册商标", "zhuce shangbiao", "registered trademark zhuce ®"),
    "℗": ("录音版权", "luyin banquan", "sound recording copyright luyin ℗"),
    "℠": ("服务标记", "fuwu biaoji", "service mark fuwu ℠"),
    "™": ("商标", "shangbiao", "trademark tm shangbiao ™"),
    "℡": ("电话", "dianhua", "telephone tel dianhua ℡"),
    "℻": ("传真", "chuanzhen", "fax facsimile chuanzhen ℻"),
    "☎": ("电话", "dianhua", "telephone phone dianhua ☎"),
    "☏": ("电话", "dianhua", "telephone phone dianhua ☏"),
    "☐": ("空方框", "kong fangkuang", "ballot box empty checkbox kong fangkuang ☐"),
    "☑": ("勾选", "gouxuan", "ballot box check checkbox gou xuan ☑"),
    "☒": ("叉选", "chaxuan", "ballot box x checkbox cha xuan ☒"),
    "☓": ("叉", "cha", "saltire cross x cha ☓"),
    "☕": ("咖啡", "kafei", "hot beverage coffee tea kafei ☕"),
    "☘": ("三叶草", "sanyecao", "shamrock clover sanyecao ☘"),
    "☙": ("花饰", "huashi", "reversed rotated floral heart bullet huashi ☙"),
    "☚": ("左指", "zuozhi", "pointing left hand zuo zhi ☚"),
    "☛": ("右指", "youzhi", "pointing right hand you zhi ☛"),
    "☜": ("左指", "zuozhi", "pointing left hand zuo zhi ☜"),
    "☝": ("上指", "shangzhi", "pointing up hand shang zhi ☝"),
    "☞": ("右指", "youzhi", "pointing right hand you zhi ☞"),
    "☟": ("下指", "xiazhi", "pointing down hand xia zhi ☟"),
    "☠": ("骷髅", "kulou", "skull crossbones danger death kulou ☠"),
    "☡": ("警示", "jingshi", "caution sign warning jingshi ☡"),
    "☢": ("辐射", "fushe", "radioactive radiation fushe ☢"),
    "☣": ("生物危害", "shengwu weihai", "biohazard shengwu weihai ☣"),
    "☮": ("和平", "heping", "peace symbol heping ☮"),
    "☯": ("阴阳", "yinyang", "yin yang yinyang ☯"),
    "☸": ("法轮", "falun", "wheel of dharma falun ☸"),
    "♨": ("温泉", "wenquan", "hot springs onsen wenquan ♨"),
    "♻": ("回收", "huishou", "recycling recycle huishou ♻"),
    "♿": ("无障碍", "wuzhangai", "wheelchair accessibility wuzhangai ♿"),
    "⚐": ("白旗", "baiqi", "white flag baiqi ⚐"),
    "⚑": ("黑旗", "heiqi", "black flag heiqi ⚑"),
    "⚒": ("锤子", "chuizi", "hammer and pick tool chuizi ⚒"),
    "⚓": ("锚", "mao", "anchor mao ⚓"),
    "⚔": ("剑", "jian", "crossed swords jian ⚔"),
    "⚕": ("医疗", "yiliao", "staff of aesculapius medical yiliao ⚕"),
    "⚖": ("天平", "tianping", "scales balance justice tianping ⚖"),
    "⚗": ("蒸馏", "zhengliu", "alembic distillation zhengliu ⚗"),
    "⚘": ("花", "hua", "flower hua ⚘"),
    "⚙": ("齿轮", "chilun", "gear settings chilun ⚙"),
    "⚛": ("原子", "yuanzi", "atom symbol yuanzi ⚛"),
    "⚜": ("鸢尾", "yuanwei", "fleur de lis yuanwei ⚜"),
    "⚠": ("警告", "jinggao", "warning jinggao ⚠"),
    "⚡": ("闪电", "shandian", "high voltage lightning shandian ⚡"),
    "⚽": ("足球", "zuqiu", "soccer football zuqiu ⚽"),
    "⚾": ("棒球", "bangqiu", "baseball bangqiu ⚾"),
    "⛳": ("高尔夫", "gaoerfu", "golf gaoerfu ⛳"),
    "⛷": ("滑雪", "huaxue", "skier ski huaxue ⛷"),
    "⛸": ("滑冰", "huabing", "ice skate huabing ⛸"),
    "⛹": ("篮球", "lanqiu", "basketball lanqiu ⛹"),
    "⛺": ("帐篷", "zhangpeng", "tent camping zhangpeng ⛺"),
    "⛽": ("加油站", "jiayouzhan", "fuel pump gas station jiayouzhan ⛽"),
    "⛰": ("山", "shan", "mountain shan ⛰"),
    "⛱": ("遮阳伞", "zheyangsan", "umbrella on ground beach zheyangsan ⛱"),
    "⛲": ("喷泉", "penquan", "fountain penquan ⛲"),
    "⛴": ("渡轮", "dulun", "ferry boat dulun ⛴"),
    "⛵": ("帆船", "fanchuan", "sailboat fanchuan ⛵"),
    "⛪": ("教堂", "jiaotang", "church jiaotang ⛪"),
    "⛩": ("神社", "shenshe", "shinto shrine shenshe ⛩"),
    "⛔": ("禁止", "jinzhi", "no entry prohibited jinzhi ⛔"),
    "⛎": ("蛇夫座", "shefuzuo", "ophiuchus serpent shefuzuo ⛎"),
    "⛏": ("镐", "gao", "pick tool mining gao ⛏"),
    "⛑": ("头盔", "toukui", "rescue worker helmet toukui ⛑"),
    "⛓": ("链", "lian", "chains lian ⛓"),
    "⛲": ("喷泉", "penquan", "fountain penquan ⛲"),
    "⛳": ("高尔夫", "gaoerfu", "golf gaoerfu ⛳"),
    "⛵": ("帆船", "fanchuan", "sailboat fanchuan ⛵"),
    "⛺": ("帐篷", "zhangpeng", "tent camping zhangpeng ⛺"),
    "⛽": ("加油站", "jiayouzhan", "fuel pump gas station jiayouzhan ⛽"),
}

# Name-keyword categories. The order decides ties; specific rules first.
RULES = [
    ("体育与娱乐", ("SOCCER", "BASEBALL", "GOLF", "SKI", "SKIER", "SNOWBOARD",
                    "BASKETBALL", "TENNIS", "BOWLING", "SWIMMER", "SURFER",
                    "FISHING", "HORSE RACING", "RUNNING SHIRT", "BILLIARDS",
                    "CHESS", "DICE", "PLAYING CARD", "TENT")),
    ("方向与手势", ("POINTING", "ARROW", "HAND")),
    ("警示与标志", ("SKULL", "RADIOACTIVE", "BIOHAZARD", "WARNING", "CAUTION",
                    "NO ENTRY", "PROHIBITED", "RECYCL", "PEACE", "YIN YANG",
                    "WHEEL OF DHARMA", "WHEELCHAIR", "ATOM", "CROSS", "CRESCENT",
                    "STAR AND", "HAMMER AND SICKLE", "FLAG")),
    ("自然与地点", ("MOUNTAIN", "FOUNTAIN", "TENT", "CHURCH", "MOSQUE", "SHINTO",
                    "SYNAGOGUE", "UMBRELLA", "SHAMROCK", "COMET", "SUN", "CLOUD",
                    "SNOW", "UMBRELLA")),
    ("工具与科学", ("TELEPHONE", "FAX", "BALLOT", "CHECK", "SALT", "PENCIL",
                    "SCISSORS", "ANCHOR", "SWORDS", "STAFF", "SCALES", "ALEMBIC",
                    "GEAR", "HAMMER", "PICK", "HELMET", "CHAINS", "FLOWER",
                    "FLEUR", "COFFEE", "HOT BEVERAGE", "MICROSCOPE", "TELESCOPE")),
    ("商标与版权", ("COPYRIGHT", "REGISTERED", "TRADE MARK", "SOUND RECORDING",
                    "SERVICE MARK", "TELEPHONE RECORDER")),
]


def parse_fh() -> list[str]:
    text = SYMBOLS.read_text(encoding="utf-8")
    match = re.search(r"^[ \t]*['\"]/fh['\"]\s*:\s*\[(.*?)\]\s*$", text, re.M | re.S)
    if not match:
        raise SystemExit("/fh entry not found in symbols.yaml")
    raw = [part.strip().strip("'\"") for part in match.group(1).split(",")]
    symbols = []
    for value in raw:
        if not value:
            continue
        if len(value) != 1:
            raise SystemExit(f"unexpected multi-character /fh token: {value!r}")
        code = ord(value)
        if 0x20 <= code <= 0x7E:
            continue
        symbols.append(value)
    if len(symbols) != len(set(symbols)):
        raise SystemExit("duplicate /fh symbols")
    if len(symbols) != 158:
        raise SystemExit(f"expected 158 non-ASCII /fh symbols, got {len(symbols)}")
    return symbols


def classify(glyph: str, name: str) -> str:
    # "Gear With Handles"/"Gear Without Hub" otherwise match the broad HAND
    # rule for direction and land in the wrong category.
    if "GEAR" in name:
        return "工具与科学"
    for category, words in RULES:
        if any(word in name for word in words):
            return category
    return "其他"


def swift_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "") + '"'


def build() -> str:
    rows = []
    for glyph in parse_fh():
        name = unicodedata.name(glyph, "")
        if not name:
            name = f"Symbol U+{ord(glyph):04X}"
        title = name.title()
        category = classify(glyph, name)
        alias = ALIASES.get(glyph)
        if alias:
            name_zh, pinyin, keywords = alias
        else:
            name_zh = category
            pinyin = CATEGORY_PINYIN[category]
            keywords = ""
        keyword_text = " ".join(filter(None, [keywords, title.lower(), name.lower(),
                                               category, pinyin, CATEGORY_PINYIN[category]]))
        hex_code = f"U+{ord(glyph):04X}"
        rows.append(
            "    .init(glyph: %s, nameEN: %s, nameZH: %s, pinyin: %s, category: %s, keywords: %s, hex: %s),"
            % (swift_string(glyph), swift_string(title), swift_string(name_zh),
               swift_string(pinyin), swift_string(category), swift_string(keyword_text),
               swift_string(hex_code)))
    body = "\n".join(rows)
    return f"""// Generated by rime/tools/generate_symbol_catalog.py. Do not edit by hand.
// Source: rime/distribution/data/symbols.yaml, /fh (158 non-ASCII symbols).
extension SlashSymbolData {{
  static let all: [SlashSymbol] = [
{body}
  ]
}}
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = build()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != expected:
            print(f"{OUTPUT} is out of date; run {Path(__file__).name}", file=sys.stderr)
            return 1
        print("PASS: slash symbol catalog is current")
        return 0
    OUTPUT.write_text(expected, encoding="utf-8")
    print(f"Wrote {OUTPUT} ({expected.count('.init(')} symbols)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
