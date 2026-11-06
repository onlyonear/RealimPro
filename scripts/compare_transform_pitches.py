#!/usr/bin/env python3
"""
Impro-Visor vs Real imPro: Transform Pitch Selection 1:1 对比脚本

策略: 取相同输入(固定和弦进行+固定GuideTone线), 逐阶段追踪Transform规则匹配与替换,
对比Swift端(算术表达式→raw MIDI)与Java端(算术表达式→NoteChooser概率选音)的输出差异。

使用方法:
    python3 compare_transform_pitches.py

输出:
    - 每步规则匹配 → 输入音符/和弦 → 替换表达式 → Swift输出 vs Java预期输出
    - 最后一节: 汇总所有音高偏差, 按严重程度分级
"""

import random
from typing import List, Dict, Tuple, Optional, Set
from dataclasses import dataclass, field
from enum import Enum
import sys

# ── 确定性种子 ──
SEED = 42
random.seed(SEED)

# ── 常量 ──
SLOTS_PER_BEAT = 120
MIDI_MIN = 48
MIDI_MAX = 84

# ═══════════════════════════════════════════════════════════════
# §1 数据结构 (映射 Swift TransformEngine + Java LickGen)
# ═══════════════════════════════════════════════════════════════

@dataclass
class PhysicalNote:
    midi: int  # -1 = rest
    slots: int

@dataclass
class ChordBlock:
    name: str          # "Cmaj7", "Dm7", "G7", etc.
    duration_beats: float

@dataclass
class NoteChordPair:
    note: PhysicalNote
    chord: ChordBlock
    slot: int
    var: int = 0

    def copy(self) -> 'NoteChordPair':
        return NoteChordPair(
            PhysicalNote(self.note.midi, self.note.slots),
            self.chord, self.slot, self.var
        )

# ═══════════════════════════════════════════════════════════════
# §2 和弦音程映射 (对齐 ChordQuality + getChordTones)
# ═══════════════════════════════════════════════════════════════

def parse_root_pc(name: str) -> int:
    """解析和弦根音→0-11"""
    pc_map = {"C":0,"C#":1,"Db":1,"D":2,"Eb":3,"E":4,"F":5,
              "F#":6,"G":7,"Ab":8,"A":9,"Bb":10,"B":11}
    chars = list(name.strip())
    if not chars: return 0
    root = chars[0].upper()
    if len(chars) > 1 and chars[1] in ('#','b'):
        root += chars[1]
    return pc_map.get(root, 0)

def get_chord_pitch_classes(chord_name: str) -> Set[int]:
    """返回和弦音(根三五七)的音高类集合 0-11"""
    root_pc = parse_root_pc(chord_name)
    name = chord_name.strip()
    is_minor = ('m' in name and 'maj' not in name and 'M7' not in name) or 'dim' in name
    is_maj7 = 'maj' in name or 'M7' in name
    is_dim7 = 'dim7' in name or 'o7' in name
    is_halfdim = 'm7b5' in name or '\u00f8' in name
    is_aug = 'aug' in name or '+' in name
    is_sus = 'sus' in name

    if is_dim7: intervals = [0,3,6,9]
    elif is_halfdim: intervals = [0,3,6,10]
    elif is_aug: intervals = [0,4,8,10]
    elif is_sus: intervals = [0,5,7,10] if 'sus2' not in name else [0,2,7,10]
    elif is_maj7: intervals = [0,4,7,11]
    elif is_minor: intervals = [0,3,7,10]
    else: intervals = [0,4,7,10]  # dominant7

    return {(root_pc + iv) % 12 for iv in intervals}

def get_color_pitch_classes(chord_name: str) -> Set[int]:
    """返回色彩音(9,11,13)的音高类集合"""
    root_pc = parse_root_pc(chord_name)
    name = chord_name.strip()
    if 'alt' in name: intervals = [1,3,8]
    elif 'dim' in name: intervals = [2,5,8,11]
    elif 'm7b5' in name: intervals = [2,5,8]
    elif 'aug' in name: intervals = [2,6]
    elif 'maj' in name: intervals = [2,5,9]
    elif 'm' in name: intervals = [2,5,9]
    else: intervals = [2,6,9]  # dominant
    return {(root_pc + iv) % 12 for iv in intervals}

def get_scale_pitch_classes(chord_name: str) -> Set[int]:
    """返回音阶音的音高类集合"""
    root_pc = parse_root_pc(chord_name)
    name = chord_name.strip()
    if 'maj' in name: intervals = [0,2,4,5,7,9,11]      # Ionian
    elif 'm' in name: intervals = [0,2,3,5,7,9,10]       # Dorian
    elif 'dim' in name: intervals = [0,1,3,4,6,7,9,10]   # HW-dim
    elif 'm7b5' in name: intervals = [0,1,3,5,6,8,10]    # Locrian
    elif 'aug' in name: intervals = [0,2,4,6,8,10]       # Whole-tone
    elif 'alt' in name: intervals = [0,1,3,4,6,8,10]     # Super-Locrian
    else: intervals = [0,2,4,5,7,9,10]                   # Mixolydian
    return {(root_pc + iv) % 12 for iv in intervals}


# ═══════════════════════════════════════════════════════════════
# §3 Java NoteChooser 概率表模拟 (28条规则, 对齐 NoteChooser.java)
# ═══════════════════════════════════════════════════════════════

# NoteChooser type constants
CHORD_TYPE = 1001; COLOR_TYPE = 1003; RANDOM_TYPE = 1005; SCALE_TYPE = 1002
TYPE_MAP = [CHORD_TYPE, COLOR_TYPE, RANDOM_TYPE, SCALE_TYPE]

# 28条概率查表规则: (target_type, has_chord, has_color, has_random, p_chord%, p_color%, p_random%, p_scale%)
PROB_TABLE = [
    # type=0 → looking for CHORD (L62-68)
    (0, 1,1,1, 100,0,0,0), (0, 1,1,0, 100,0,0,0), (0, 1,0,1, 100,0,0,0),
    (0, 1,0,0, 100,0,0,0), (0, 0,1,1, 0,100,0,0), (0, 0,1,0, 0,100,0,0),
    (0, 0,0,1, 0,0,100,0),
    # type=1 → looking for COLOR (L70-76)
    (1, 1,1,1, 0,100,0,0), (1, 1,1,0, 10,90,0,0), (1, 1,0,1, 85,0,15,0),
    (1, 1,0,0, 100,0,0,0), (1, 0,1,1, 0,100,0,0), (1, 0,1,0, 0,100,0,0),
    (1, 0,0,1, 0,0,100,0),
    # type=3 → looking for SCALE (L78-84)
    (3, 1,1,1, 0,0,0,100), (3, 1,1,0, 0,0,0,100), (3, 1,0,1, 0,0,0,100),
    (3, 1,0,0, 0,0,0,100), (3, 0,1,1, 0,0,0,100), (3, 0,1,0, 0,0,0,100),
    (3, 0,0,1, 0,0,100,0),
    # type=2 → looking for RANDOM (L87-93)
    (2, 1,1,1, 50,25,25,0), (2, 1,1,0, 80,20,0,0), (2, 1,0,1, 50,0,50,0),
    (2, 1,0,0, 100,0,0,0), (2, 0,1,1, 0,50,50,0), (2, 0,1,0, 0,100,0,0),
    (2, 0,0,1, 0,0,100,0),
]


def java_choose_note(
    low_midi: int, high_midi: int,
    chord_name: str,
    note_type: int,    # CHORD_TYPE / COLOR_TYPE / SCALE_TYPE / RANDOM_TYPE
    last_pitch: int,
    min_pitch: int, max_pitch: int,
    attempt: int
) -> int:
    """
    完整复刻 Java LickGen.chooseNote() → NoteChooser.getNote():
    1. [low,high]区间每个整数音按和弦分类 → CHORD/COLOR/RANDOM
    2. 统计各类型数量 → numTypes[]
    3. 28条概率查表→掷骰选输出类型
    4. 从该类型候选音中随机取一个音高差
    5. 八度修正 → 返回最终MIDI
    """
    chord_pcs = get_chord_pitch_classes(chord_name)
    color_pcs = get_color_pitch_classes(chord_name)

    # 构建 noteTypes[] 数组: [low, high] 每个音的分类
    note_types = []
    for midi in range(low_midi, high_midi + 1):
        pc = midi % 12
        if pc in chord_pcs:
            note_types.append(CHORD_TYPE)
        elif pc in color_pcs:
            note_types.append(COLOR_TYPE)
        else:
            note_types.append(RANDOM_TYPE)

    # 统计 numTypes[0]=chord_count, [1]=color_count, [2]=random_count, [3]=scale_count
    # Java L3183-3197: chord→numTypes[0]++ & numTypes[3]++; color→numTypes[1]++ & numTypes[3]++; random→numTypes[2]++
    num_types = [0, 0, 0, 0]
    for nt in note_types:
        if nt == CHORD_TYPE:
            num_types[0] += 1; num_types[3] += 1
        elif nt == COLOR_TYPE:
            num_types[1] += 1; num_types[3] += 1
        else:
            num_types[2] += 1

    # 扩张区间: CHORD类型找不到音时最多扩张3次
    if note_type == CHORD_TYPE and num_types[0] == 0:
        # 不在本脚本内扩张，简化处理
        pass

    # 映射目标类型
    target_type = note_type
    if target_type == CHORD_TYPE: target_type = 0
    elif target_type == COLOR_TYPE: target_type = 1
    elif target_type == RANDOM_TYPE: target_type = 2
    elif target_type == SCALE_TYPE: target_type = 3

    have_chord = 1 if num_types[0] != 0 else 0
    have_color = 1 if num_types[1] != 0 else 0
    have_random = 1 if num_types[2] != 0 else 0

    # 查表匹配
    match_idx = None
    for idx, rule in enumerate(PROB_TABLE):
        if (rule[0] == target_type and rule[1] == have_chord
            and rule[2] == have_color and rule[3] == have_random):
            match_idx = idx
            break

    if match_idx is None:
        # 兜底: 如果有chord音用chord，否则用random
        match_idx = 3  # (0,1,0,0, 100,0,0,0) → all chord

    rule = PROB_TABLE[match_idx]
    probs = [rule[4], rule[5], rule[6], rule[7]]

    # 掷骰选输出类型
    rand_val = random.randint(1, 100)
    new_type = 0
    for i in range(4):
        rand_val -= probs[i]
        if rand_val <= 0:
            new_type = i
            break

    target_output_type = TYPE_MAP[new_type]

    # 从对应类型候选音中随机选
    # num_types[new_type] 是候选总数
    candidate_count = num_types[new_type]
    if candidate_count == 0:
        # 兜底: 返回 low
        return low_midi

    rand_idx = random.randint(1, candidate_count)
    pitch_diff = 0
    for i, nt in enumerate(note_types):
        if nt == target_output_type or (new_type == 3 and nt in (CHORD_TYPE, COLOR_TYPE)):
            rand_idx -= 1
        if rand_idx <= 0:
            pitch_diff = i
            break

    final_pitch = low_midi + pitch_diff

    # 八度修正
    if attempt >= 14:  # melodyGenLimit-1 (15-1)
        while final_pitch > max_pitch: final_pitch -= 12
        while final_pitch < min_pitch: final_pitch += 12

    return final_pitch


# ═══════════════════════════════════════════════════════════════
# §4 Transform规则定义 (对齐 Transform+Defaults.swift)
# ═══════════════════════════════════════════════════════════════

@dataclass
class Transformation:
    name: str
    weight: float
    match_len: int                              # 匹配音符数
    template_pitches: List[int]                 # 模板音高(相对)
    template_durs: List[int]                    # 模板时值
    guard_cond: Optional[str] = None            # "= (- n2 n1) 2"
    replace_exprs: List[str] = field(default_factory=list)  # ["n1","(+ n1 1)","n2"]

    def matches(self, segment: List[NoteChordPair]) -> bool:
        """与 Swift Transformation.matches() 对齐"""
        if len(segment) != self.match_len:
            return False
        # 步骤1: 休止对齐
        for i in range(self.match_len):
            s_rest = segment[i].note.midi == -1
            t_rest = self.template_pitches[0] == -1 if i == 0 else self.template_pitches[i] == -1
            if s_rest != t_rest:
                return False
        # 步骤2: 相对音高轮廓
        t_first = self.template_pitches[0]
        s_first = segment[0].note.midi
        for i in range(self.match_len):
            if t_first == -1 or s_first == -1:
                continue
            t_off = self.template_pitches[i] - t_first
            s_off = segment[i].note.midi - s_first
            if t_off != s_off:
                return False
        # 步骤3: 时值检查
        for i in range(self.match_len):
            if segment[i].note.slots < self.template_durs[i]:
                return False
        # 步骤4: guard条件
        if self.guard_cond:
            n1 = segment[0].note.midi
            n2 = segment[1].note.midi if len(segment) > 1 else 0
            if self.guard_cond == "(= (- n2 n1) 2)":
                if n2 - n1 != 2:
                    return False
            elif self.guard_cond == "(= (- n1 n2) 2)":
                if n1 - n2 != 2:
                    return False
        return True


# ── 默认规则集(对齐Transform+Defaults.swift makeDefault()) ──
def make_default_rules() -> List[Tuple[str, List[Transformation]]]:
    """返回 [(subName, [transformations]), ...] 按Motif→Embellishment分组"""
    motif_rules = []
    emb_rules = []

    # --- Motif ---
    # identity-motif (wt=1): 任何单音原样保留
    motif_rules.append(("identity-motif", [
        Transformation("identity-motif", 1, 1, [60], [30], replace_exprs=["n1"])
    ]))

    # passing-tone chromaticUp (wt=5): n1,n2距2半音→插入半音经过
    motif_rules.append(("passing-tone-up", [
        Transformation("passing-up", 5, 2, [60, 62], [60, 60],
                       guard_cond="(= (- n2 n1) 2)",
                       replace_exprs=["n1", "(+ n1 1)", "n2"])
    ]))
    motif_rules.append(("passing-tone-down", [
        Transformation("passing-down", 5, 2, [62, 60], [60, 60],
                       guard_cond="(= (- n1 n2) 2)",
                       replace_exprs=["n1", "(- n1 1)", "n2"])
    ]))

    # split-half-to-eighths (wt=1): 二分→4个八分
    motif_rules.append(("split-half-eighths", [
        Transformation("split-h-e", 1, 1, [60], [240],
                       replace_exprs=["n1", "n1", "n1", "n1"])
    ]))

    # triplet-arpeggio (wt=4): 三分连音琶音
    motif_rules.append(("triplet-arpeggio", [
        Transformation("triplet-arp", 4, 1, [60], [240],
                       replace_exprs=["n1", "(+ n1 2)", "(+ n1 4)"])
    ]))

    # --- Embellishment ---
    # identity-embellishment (wt=10)
    emb_rules.append(("identity-embellishment", [
        Transformation("identity-emb", 10, 1, [60], [30], replace_exprs=["n1"])
    ]))

    # mordent/neighbors (wt=1)
    emb_rules.append(("mordent", [
        Transformation("mordent", 1, 1, [60], [60],
                       replace_exprs=["n1", "(- n1 1)", "n1"])
    ]))

    # neighbor-upper (wt=2)
    emb_rules.append(("neighbor-upper", [
        Transformation("neighbor-up", 2, 1, [60], [60],
                       replace_exprs=["n1", "(+ n1 2)", "n1"])
    ]))

    # neighbor-lower (wt=2)
    emb_rules.append(("neighbor-lower", [
        Transformation("neighbor-low", 2, 1, [60], [60],
                       replace_exprs=["n1", "(- n1 1)", "n1"])
    ]))

    # approach-chromatic (wt=2)
    emb_rules.append(("approach-chromatic", [
        Transformation("approach-chromatic", 2, 2, [60, 64], [60, 60],
                       guard_cond="(= (- n2 n1) 4)",
                       replace_exprs=["(- n2 1)", "n2"])
    ]))

    return [("motif", motif_rules), ("embellishment", emb_rules)]


def evaluate_expr(expr: str, n_vars: Dict[str, int]) -> int:
    """简单的Lisp表达式求值器 (模拟Evaluate.shared.evaluate)"""
    expr = expr.strip()
    if expr.startswith('('):
        # 简单的 S表达式: (+ n1 1), (- n1 1), (= (- n2 n1) 2)
        inner = expr[1:-1]
        parts = inner.split()
        if parts[0] == '+':
            return evaluate_val(parts[1], n_vars) + evaluate_val(parts[2], n_vars)
        elif parts[0] == '-':
            return evaluate_val(parts[1], n_vars) - evaluate_val(parts[2], n_vars)
        elif parts[0] == '=':
            return 1 if evaluate_val(parts[1], n_vars) == evaluate_val(parts[2], n_vars) else 0
    # 纯变量: n1, n2...
    return evaluate_val(expr, n_vars)


def evaluate_val(val: str, n_vars: Dict[str, int]) -> int:
    val = val.strip()
    if val.startswith('('):
        return evaluate_expr(val, n_vars)
    if val in n_vars:
        return n_vars[val]
    try:
        return int(val)
    except ValueError:
        return 0


# ═══════════════════════════════════════════════════════════════
# §5 Java vs Swift 差异诊断核心
# ═══════════════════════════════════════════════════════════════

@dataclass
class PitchVerdict:
    """单个音符的 Java vs Swift 对比诊断"""
    slot: int
    swift_midi: int
    chord_name: str
    is_chord_tone: bool
    is_color_tone: bool
    is_scale_tone: bool
    is_approach: bool        # ±1 from chord tone
    rule_that_generated: str
    expression_used: str
    expected_java_midi: int  # Java NoteChooser会选择什么
    severity: str            # "OK" | "WARNING" | "CRITICAL"


def diagnose_note(
    midi: int, chord_name: str, rule_name: str, expr: str,
    n_vars: Dict[str, int], attempt: int = 15
) -> PitchVerdict:
    """诊断单个变换生成的音符: Swift raw MIDI vs Java NoteChooser预期"""
    chord_pcs = get_chord_pitch_classes(chord_name)
    color_pcs = get_color_pitch_classes(chord_name)
    scale_pcs = get_scale_pitch_classes(chord_name)
    pc = midi % 12

    is_chord = pc in chord_pcs
    is_color = pc in color_pcs
    is_scale = pc in scale_pcs
    is_approach = any(pc == (c + 1) % 12 or pc == (c + 11) % 12 for c in chord_pcs)

    # Java NoteChooser: 根据和弦在lastPitch±12半音区间选音
    last_pitch = n_vars.get('n1', 60)
    low = max(MIDI_MIN, last_pitch - 12)
    high = min(MIDI_MAX, last_pitch + 12)

    java_midi = java_choose_note(
        low, high, chord_name, CHORD_TYPE, last_pitch, MIDI_MIN, MIDI_MAX, attempt
    )

    # 严重程度判定
    if is_chord:
        severity = "OK"
    elif is_color:
        severity = "OK"
    elif is_approach:
        severity = "OK"  # rectifyMelody会保留
    elif is_scale:
        severity = "WARNING"  # 音阶音但不是和弦/色彩/趋近音
    else:
        severity = "CRITICAL"  # 完全不在音阶内!

    return PitchVerdict(
        slot=0, swift_midi=midi, chord_name=chord_name,
        is_chord_tone=is_chord, is_color_tone=is_color,
        is_scale_tone=is_scale, is_approach=is_approach,
        rule_that_generated=rule_name, expression_used=expr,
        expected_java_midi=java_midi, severity=severity
    )


# ═══════════════════════════════════════════════════════════════
# §6 确定测试用例: ii-V-I 4小节
# ═══════════════════════════════════════════════════════════════

TEST_CHORDS = [
    ChordBlock("Dm7", 4.0),
    ChordBlock("G7", 4.0),
    ChordBlock("Cmaj7", 4.0),
    ChordBlock("Cmaj7", 4.0),
]

# GuideTone: 优先3音和7音 (greedy nearest, direction=noPreference)
# Dm7(3=F,7=C) → pick F; G7(3=B,7=F) → pick F; Cmaj7(3=E,7=B) → pick E (closest to F)
GUIDE_TONE_PITCHES = [65, 65, 64, 64]  # F4, F4, E4, E4
GUIDE_TONE_SLOTS = [480, 480, 480, 480]  # 全音符


def build_test_ncps() -> List[NoteChordPair]:
    ncps = []
    slot = 0
    for i, (midi, dur, chord) in enumerate(
        zip(GUIDE_TONE_PITCHES, GUIDE_TONE_SLOTS, TEST_CHORDS)):
        ncps.append(NoteChordPair(
            PhysicalNote(midi, dur), chord, slot, 0
        ))
        slot += dur
    return ncps


# ═══════════════════════════════════════════════════════════════
# §7 对比引擎
# ═══════════════════════════════════════════════════════════════

def run_comparison():
    """主函数: 构建测试用例 → 逐规则匹配对比 → 输出报告"""
    random.seed(SEED)

    ncps = build_test_ncps()
    all_rules = make_default_rules()

    print("=" * 72)
    print("  Impro-Visor vs Real imPro: Transform 音高选择 1:1 对比")
    print("=" * 72)
    print(f"\n输入: {len(ncps)}个GuideTone音符 (ii-V-I in C)")
    for ncp in ncps:
        chord_name = ncp.chord.name
        midi = ncp.note.midi
        pc_names = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]
        note_name = f"{pc_names[midi % 12]}{(midi // 12) - 1}"
        print(f"  slot={ncp.slot:4d}  midi={midi:3d} ({note_name:3s})  dur={ncp.note.slots:3d}  chord={chord_name}")
    print()

    verdicts: List[PitchVerdict] = []

    # 阶段1: Motif
    print("─" * 72)
    print("  [Motif 阶段]")
    print("─" * 72)

    for sub_name, trans_list in all_rules[0][1]:  # motif rules
        for trans in trans_list:
            pos = 0
            while pos <= len(ncps) - trans.match_len:
                segment = ncps[pos:pos + trans.match_len]
                if trans.matches(segment):
                    n_vars = {}
                    for idx, ncp in enumerate(segment):
                        n_vars[f'n{idx+1}'] = ncp.note.midi

                    print(f"\n  规则: {trans.name} (wt={trans.weight})")
                    print(f"  匹配位置: slot={segment[0].slot}")
                    print(f"  输入音高: {[n.note.midi for n in segment]}")
                    print(f"  和弦: {segment[0].chord.name}")

                    for expr in trans.replace_exprs:
                        swift_midi = evaluate_expr(expr, n_vars)
                        if swift_midi <= 0:
                            swift_midi = segment[0].note.midi
                        chord_name = segment[0].chord.name
                        verdict = diagnose_note(
                            swift_midi, chord_name, trans.name, expr, n_vars
                        )
                        verdict.slot = segment[0].slot
                        verdicts.append(verdict)

                        status = "✓" if verdict.severity == "OK" else (
                            "⚠" if verdict.severity == "WARNING" else "✗")
                        print(f"    {status} expr='{expr:20s}' → Swift={swift_midi:3d} | "
                              f"chord={verdict.is_chord_tone} color={verdict.is_color_tone} "
                              f"scale={verdict.is_scale_tone} approach={verdict.is_approach} "
                              f"| Java期望≈{verdict.expected_java_midi:3d} [{verdict.severity}]")

                pos += 1

    # 阶段2: Embellishment
    print("\n" + "─" * 72)
    print("  [Embellishment 阶段]")
    print("─" * 72)

    for sub_name, trans_list in all_rules[1][1]:  # embellishment rules
        for trans in trans_list:
            pos = 0
            while pos <= len(ncps) - trans.match_len:
                segment = ncps[pos:pos + trans.match_len]
                if trans.matches(segment):
                    n_vars = {}
                    for idx, ncp in enumerate(segment):
                        n_vars[f'n{idx+1}'] = ncp.note.midi

                    print(f"\n  规则: {trans.name} (wt={trans.weight})")
                    print(f"  匹配位置: slot={segment[0].slot}")
                    print(f"  输入: midi={[n.note.midi for n in segment]} chord={segment[0].chord.name}")

                    for expr in trans.replace_exprs:
                        swift_midi = evaluate_expr(expr, n_vars)
                        if swift_midi <= 0:
                            swift_midi = segment[0].note.midi
                        chord_name = segment[0].chord.name
                        verdict = diagnose_note(
                            swift_midi, chord_name, trans.name, expr, n_vars
                        )
                        verdict.slot = segment[0].slot
                        verdicts.append(verdict)

                        status = "✓" if verdict.severity == "OK" else (
                            "⚠" if verdict.severity == "WARNING" else "✗")
                        print(f"    {status} expr='{expr:20s}' → Swift={swift_midi:3d} | "
                              f"chord={verdict.is_chord_tone} color={verdict.is_color_tone} "
                              f"scale={verdict.is_scale_tone} approach={verdict.is_approach} "
                              f"| Java期望≈{verdict.expected_java_midi:3d} [{verdict.severity}]")

                pos += 1

    # ── 汇总报告 ──
    print("\n" + "=" * 72)
    print("  汇总诊断报告")
    print("=" * 72)

    ok_count = sum(1 for v in verdicts if v.severity == "OK")
    warn_count = sum(1 for v in verdicts if v.severity == "WARNING")
    crit_count = sum(1 for v in verdicts if v.severity == "CRITICAL")

    print(f"\n  总诊断音符数: {len(verdicts)}")
    print(f"  ✓ OK (和弦/色彩/趋近音): {ok_count}")
    print(f"  ⚠ WARNING (音阶音但非和弦音): {warn_count}")
    print(f"  ✗ CRITICAL (完全不在音阶内): {crit_count}")

    if crit_count > 0:
        print(f"\n  🚨 CRITICAL 音符详情:")
        for v in verdicts:
            if v.severity == "CRITICAL":
                note_names = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]
                name = f"{note_names[v.swift_midi % 12]}{(v.swift_midi // 12) - 1}"
                print(f"    规则={v.rule_that_generated:25s} | "
                      f"expr='{v.expression_used:20s}' | "
                      f"midi={v.swift_midi:3d} ({name:3s}) | "
                      f"chord={v.chord_name:8s}")

    if warn_count > 0:
        print(f"\n  ⚠ WARNING 音符详情 (Scale tones, not chord/color):")
        for v in verdicts:
            if v.severity == "WARNING":
                note_names = ["C","C#","D","Eb","E","F","F#","G","Ab","A","Bb","B"]
                name = f"{note_names[v.swift_midi % 12]}{(v.swift_midi // 12) - 1}"
                print(f"    规则={v.rule_that_generated:25s} | "
                      f"expr='{v.expression_used:20s}' | "
                      f"midi={v.swift_midi:3d} ({name:3s}) | "
                      f"chord={v.chord_name:8s}")

    if crit_count == 0 and warn_count == 0:
        print("\n  结论: ✅ 音高选择完全正确!")
    else:
        err_msg = f"❌ 发现{crit_count}个完全错误音 + {warn_count}个警告音"
        print(f"\n  结论: {err_msg}")


if __name__ == "__main__":
    run_comparison()
