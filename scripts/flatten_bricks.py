#!/usr/bin/env python3
"""
flatten_bricks.py — 解析 My.dictionary，展开层级 brick 引用为扁平化和弦序列

用法:
  python3 flatten_bricks.py [--all]     # 展开全部 brick
  python3 flatten_bricks.py --grammar   # 仅展开 grammar 引用的 brick
  python3 flatten_bricks.py --list      # 列出所有 brick 名
"""

import re
import sys
import json

# ── 常量 ──────────────────────────────────────────────
DICT_PATH = "/Users/onlyonear/Desktop/Improlyze/imp/vocab/My.dictionary"
NOTE_NAMES = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B",
              "C","Db","D","Eb","E","F","Gb","G","Ab","A","Bb","B"]
# 根音名 → 半音数
ROOT_TO_SEMITONE = {}
for i, n in enumerate(NOTE_NAMES[:12]):
    ROOT_TO_SEMITONE[n] = i
# 别名
ROOT_TO_SEMITONE["Db"] = 1; ROOT_TO_SEMITONE["Eb"] = 3
ROOT_TO_SEMITONE["Gb"] = 6; ROOT_TO_SEMITONE["Ab"] = 8; ROOT_TO_SEMITONE["Bb"] = 10

SEMITONE_TO_NOTE = {
    0:"C",1:"C#",2:"D",3:"D#",4:"E",5:"F",6:"F#",7:"G",8:"G#",9:"A",10:"A#",11:"B"
}

# ── S-表达式解析 ──────────────────────────────────────

def tokenize(text):
    """将 S-表达式文本拆分为 token 列表"""
    text = text.replace("(", " ( ").replace(")", " ) ")
    tokens = []
    for t in text.split():
        t = t.strip()
        if t:
            tokens.append(t)
    return tokens

def parse_sexp(tokens, pos=0):
    """递归解析单个 S-表达式，返回 (parsed, next_pos)
    parsed: 字符串 或 列表 [head, item1, item2, ...]
    """
    if pos >= len(tokens):
        return None, pos
    token = tokens[pos]
    if token != "(":
        return token, pos + 1
    pos += 1  # skip '('
    items = []
    while pos < len(tokens) and tokens[pos] != ")":
        item, pos = parse_sexp(tokens, pos)
        items.append(item)
    if pos < len(tokens):
        pos += 1  # skip ')'
    return items, pos

def parse_all_sexps(text):
    """解析文本中所有 S-表达式"""
    tokens = tokenize(text)
    results = []
    pos = 0
    while pos < len(tokens):
        item, pos = parse_sexp(tokens, pos)
        if item is not None:
            results.append(item)
    return results

# ── 和弦名处理 ────────────────────────────────────────

def extract_root(chord_name: str) -> str:
    """从和弦名中提取根音名"""
    m = re.match(r"([A-G][#b]?)", chord_name)
    return m.group(1) if m else "C"

def transpose_chord(chord_name: str, semitones: int) -> str:
    """将和弦名按半音数移调"""
    root = extract_root(chord_name)
    if root not in ROOT_TO_SEMITONE:
        return chord_name
    old_root = ROOT_TO_SEMITONE[root]
    new_root_i = (old_root + semitones) % 12
    new_root = SEMITONE_TO_NOTE[new_root_i]
    # 替换根音部分，保留后缀
    rest = chord_name[len(root):]
    return new_root + rest

def semitone_diff(from_key: str, to_key: str) -> int:
    """计算两个调之间的半音差"""
    f = ROOT_TO_SEMITONE.get(from_key, 0)
    t = ROOT_TO_SEMITONE.get(to_key, 0)
    return (t - f + 12) % 12

# ── Brick 数据结构 ────────────────────────────────────

class BrickDef:
    """解析后的 brick 定义"""
    def __init__(self, name, qualifier, mode, btype, key, subblocks):
        self.name = name
        self.qualifier = qualifier  # e.g. "main", "var 1"
        self.mode = mode
        self.btype = btype
        self.key = key
        self.subblocks = subblocks  # list of (type, content)
        # type: "chord" → ("chord", name, duration)
        #       "brick" → ("brick", name, key, duration)

    @property
    def full_name(self):
        if self.qualifier:
            return f"{self.name}({self.qualifier})"
        return self.name

def parse_duration(val):
    """解析 duration: 数字返回整数, '*' 返回 -1"""
    if isinstance(val, (int, float)):
        return int(val)
    s = str(val)
    if s == "*" or s == "_":
        return -1
    try:
        return int(s)
    except ValueError:
        return 1  # default

def parse_brick(sexp):
    """解析单个 defbrick S-表达式 → BrickDef"""
    if not isinstance(sexp, list) or len(sexp) < 6:
        return None
    head = str(sexp[0])
    if head != "defbrick":
        return None

    idx = 1
    # name [optional (qualifier)]
    name_str = str(sexp[idx])
    qualifier = None
    idx += 1
    if idx < len(sexp) and isinstance(sexp[idx], list):
        # qualifier like (var 1) or (main)
        qualifier = " ".join(str(x) for x in sexp[idx])
        idx += 1

    # mode, type, key
    if idx >= len(sexp): return None
    mode = str(sexp[idx]); idx += 1
    if idx >= len(sexp): return None
    btype = str(sexp[idx]); idx += 1
    if idx >= len(sexp): return None
    key = str(sexp[idx]); idx += 1

    # subblocks
    subblocks = []
    while idx < len(sexp):
        sb = sexp[idx]
        if isinstance(sb, list) and len(sb) >= 2:
            sb_type = str(sb[0])
            if sb_type == "chord" and len(sb) >= 2:
                chord_name = str(sb[1])
                duration = parse_duration(sb[2]) if len(sb) >= 3 else 1
                subblocks.append(("chord", chord_name, duration))
            elif sb_type == "brick" and len(sb) >= 3:
                brick_name = str(sb[1])
                brick_key = str(sb[2])
                duration = parse_duration(sb[3]) if len(sb) >= 4 else 1
                subblocks.append(("brick", brick_name, brick_key, duration))
        idx += 1

    return BrickDef(name_str, qualifier, mode, btype, key, subblocks)

# ── 展开逻辑 ──────────────────────────────────────────

def flatten_brick(brick_def, brick_map, visited=None, depth=0, parent_key="C"):
    """
    递归展开 brick 为扁平和弦序列
    返回 [(chord_name, duration), ...]
    """
    if visited is None:
        visited = set()
    full = brick_def.full_name
    if full in visited:
        print(f"WARNING: circular reference detected: {full}", file=sys.stderr)
        return []
    if depth > 20:
        print(f"WARNING: max depth exceeded for {full}", file=sys.stderr)
        return []

    visited.add(full)
    result = []
    key_offset = semitone_diff(parent_key, brick_def.key)

    for sb in brick_def.subblocks:
        if sb[0] == "chord":
            _, chord_name, duration = sb
            # 如果 parent key ≠ brick key，需要移调
            if key_offset != 0:
                chord_name = transpose_chord(chord_name, key_offset)
            result.append((chord_name, duration))
        elif sb[0] == "brick":
            _, brick_name, brick_key, duration = sb
            # 子 brick 的 key 需要加上当前 brick 的 key 偏移
            effective_key = brick_key
            # 递归展开
            resolved = resolve_and_flatten(brick_name, brick_map, visited.copy(),
                                           depth + 1, effective_key)
            result.extend(resolved)
    return result

def resolve_and_flatten(name, brick_map, visited, depth, parent_key):
    """按名查找 brick 并展开，优先 (main) qualifier"""
    # 先查找 (main) 版本
    main_name = f"{name}(main)"
    if main_name in brick_map:
        return flatten_brick(brick_map[main_name], brick_map, visited, depth, parent_key)

    # 再找无 qualifier 版本
    if name in brick_map:
        return flatten_brick(brick_map[name], brick_map, visited, depth, parent_key)

    # 最后模糊匹配 (任意 qualifier)
    prefix = f"{name}("
    for fname, brick_def in brick_map.items():
        if fname.startswith(prefix):
            return flatten_brick(brick_def, brick_map, visited, depth, parent_key)

    print(f"WARNING: brick '{name}' not found in map", file=sys.stderr)
    return []

# ── 主流程 ────────────────────────────────────────────

def load_all_bricks(dict_path=DICT_PATH):
    """加载并解析所有 brick 定义"""
    with open(dict_path) as f:
        content = f.read()

    sexps = parse_all_sexps(content)
    brick_map = {}

    for sexp in sexps:
        brick_def = parse_brick(sexp)
        if brick_def:
            # 存储：用 full_name (含 qualifier) 作为 key
            brick_map[brick_def.full_name] = brick_def

    return brick_map

def bricks_for_grammar():
    """返回 CharlieParker grammar 引用的 brick 名列表"""
    return [
        "Sad-Cadence", "Straight-Cadence", "Dizzy-Cadence", "Long-Cadence",
        "Tension-Cadence", "Surprise-Major-Cadence", "Body-&-Soul-Cadence",
        "Starlight-Cadence", "Supertension-Ending", "Suprise-Major-Tension-Cadence",
        "Dominant-Cycle-Cadence", "Two-Goes-Straight-Cadence",
        "Straight-Approach", "Dizzy-Approach",
        "Straight-Launcher",
        "Dropback", "Minor-Chromatic-Walkdown",
        "Happenstance-Turnaround", "POT", "SPOT",
        "Dominant-Cycle", "Giant-Steps",
        "Donna-Lee-Opening", "Rhythm-Bridge",
        "To-IV-n-Yak", "IV-n-Back", "IV-n-Bird-SPOT",
        "II-n-Bird-POT", "Yardbird-Cadence", "Yardbird-Approach",
        "Major-On", "Minor-On", "Surge",
        "On-Off-On-Minor-V", "On-Off-On-To-V",
    ]

def category_from_type(btype: str) -> str:
    """brick-type → BrickCategory 枚举映射"""
    mapping = {
        "Cadence": ".cadence",
        "Approach": ".passing",
        "Turnaround": ".turnaround",
        "Dropback": ".passing",
        "CESH": ".modal",
        "Ending": ".cadence",
        "Opening": ".extended",
        "Misc": ".extended",
        "On": ".passing",
        "On-Off": ".modal",
        "On-Off+": ".modal",
        "Off-On": ".modal",
        "Overrun": ".passing",
        "Pullback": ".passing",
        "Invisible": ".cadence",
        "Deceptive-Cadence": ".cadence",
    }
    return mapping.get(btype, ".cadence")

def generate_swift(brick_map, target_names):
    """生成 Swift BrickTemplate 数组代码"""
    lines = []
    lines.append("    // ── 自动生成: My.dictionary 展开的 BrickTemplate (CharlieParker) ──")
    lines.append("")

    for name in target_names:
        brick_def = resolve_best_match(name, brick_map)
        if brick_def is None:
            # 手工补缺
            if name == "Straight-Launcher":
                chords = ["Dm7", "G7"]
                cat = ".cadence"
                beats = 2
            elif name == "Straight-Cadence-+-Dropback":
                if "Straight-Cadence(main)" in brick_map:
                    chords = [c for c, _ in flatten_brick(brick_map["Straight-Cadence(main)"], brick_map)]
                else:
                    chords = ["Dm7", "G7", "Cmaj7"]
                cat = ".cadence"; beats = 4
            elif name == "Tension-Cadence-+-Overrun":
                if "Tension-Cadence(main)" in brick_map:
                    chords = [c for c, _ in flatten_brick(brick_map["Tension-Cadence(main)"], brick_map)]
                else:
                    chords = ["Dm7", "G7", "Cmaj7"]
                cat = ".cadence"; beats = 4
            else:
                print(f"SKIP: {name} not found", file=sys.stderr)
                continue
        else:
            flattened = flatten_brick(brick_def, brick_map)
            chords = [c for c, _ in flattened]
            beats = sum(d for _, d in flattened)
            cat = category_from_type(brick_def.btype)

        # 格式化输出
        chord_str = ", ".join(f'"{c}"' for c in chords)
        lines.append(
            f'        BrickTemplate(name: "{name}",')
        lines.append(
            f'                      chords: [{chord_str}],')
        lines.append(
            f'                      category: {cat},')
        lines.append(
            f'                      style: ["swing","bebop","ballad","bossa"],')
        lines.append(
            f'                      beats: {float(beats)},')
        lines.append(
            f'                      substitutions: []),')
        lines.append("")

    return "\n".join(lines)

def resolve_best_match(name, brick_map):
    """按名查找最佳 brick 定义"""
    main_name = f"{name}(main)"
    if main_name in brick_map:
        return brick_map[main_name]
    if name in brick_map:
        return brick_map[name]
    prefix = f"{name}("
    for fname, bdef in brick_map.items():
        if fname.startswith(prefix):
            return bdef
    return None


# ── CLI ────────────────────────────────────────────────

if __name__ == "__main__":
    brick_map = load_all_bricks()
    print(f"Loaded {len(brick_map)} brick definitions")

    if "--list" in sys.argv:
        for name in sorted(brick_map.keys()):
            bd = brick_map[name]
            print(f"  {name}  [{bd.btype}]  key={bd.key}")
        sys.exit(0)

    if "--all" in sys.argv:
        targets = sorted(set(bd.name for bd in brick_map.values()))
    else:
        targets = bricks_for_grammar()

    print(f"\nFlattening {len(targets)} target bricks...")
    swift_code = generate_swift(brick_map, targets)
    print(swift_code)

    # 同时输出 JSON 用于调试
    if "--json" in sys.argv:
        result = {}
        for name in targets:
            bd = resolve_best_match(name, brick_map)
            if bd:
                flattened = flatten_brick(bd, brick_map)
                result[name] = {
                    "chords": [c for c, _ in flattened],
                    "type": bd.btype,
                    "key": bd.key,
                    "beats": sum(d for _, d in flattened)
                }
        with open("/tmp/bricks_flattened.json", "w") as f:
            json.dump(result, f, indent=2)
        print(f"\n// JSON debug output → /tmp/bricks_flattened.json")
