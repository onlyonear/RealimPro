#!/usr/bin/env python3
"""M1 参考生成器：在黄金集上复用 build_79 的已验证函数，圈定"无反复线性子集"，
产出与未来 Swift 导入器同构的逐小节参考 JSON，供机器逐事件对比。
不写 effendi 正式数据，只写 importer_m1/ref/。"""
import os, sys, re, json, glob
import music21

EFF = '/Users/onlyonear/Desktop/video_shoot/jazz_songs/effendi'
MXL = os.path.join(EFF, 'mxl_all')
OUT = '/Users/onlyonear/Desktop/Improlyze/importer_m1/ref'
sys.path.insert(0, EFF)
import build_79 as B

MAJOR = ['Cb','Gb','Db','Ab','Eb','Bb','F','C','G','D','A','E','B','F#','C#']
MINOR = ['Abm','Ebm','Bbm','Fm','Cm','Gm','Dm','Am','Em','Bm','F#m','C#m','G#m','D#m','A#m']

NAV_RE = re.compile(r'D\.\s*[SC]\.|Dal\s*Segno|Da\s*Capo|al\s*Coda|al\s*Fine|To\s*Coda|segno|coda|(^|[^a-z])fine([^a-z]|$)', re.I)

def classify(raw):
    has_rep = '<repeat' in raw
    has_end = '<ending' in raw
    nav = False
    for m in re.finditer(r'<(words|sound|rehearsal|barline)\b[^>]*?(?:/>)?>([^<]*)?', raw):
        blob = (m.group(0) or '')
        if NAV_RE.search(blob):
            nav = True; break
    return has_rep, has_end, nav

def key_of(sc):
    ks = None
    for el in sc.recurse().getElementsByClass(music21.key.KeySignature):
        ks = el; break
    if ks is None: return 'C'
    fif = int(ks.sharps)
    mode = (getattr(ks, 'mode', None) or 'major')
    table = MINOR if mode == 'minor' else MAJOR
    i = fif + 7
    if 0 <= i < 15: return table[i]
    return 'C'

def time_of(sc):
    for ts in sc.recurse().getElementsByClass(music21.meter.TimeSignature):
        return ts.ratioString
    return '4/4'

def tempo_of(sc):
    for mm in sc.recurse().getElementsByClass(music21.tempo.MetronomeMark):
        try:
            if mm.number is not None: return int(round(float(mm.number)))
        except Exception: pass
    return 120

def title_of(sc, path):
    try:
        if sc.metadata and sc.metadata.title: return sc.metadata.title
        mt = getattr(sc.metadata, 'movementTitle', None) if sc.metadata else None
        if mt: return mt
    except Exception: pass
    return os.path.splitext(os.path.basename(path))[0]

def main():
    os.makedirs(OUT, exist_ok=True)
    files = sorted(glob.glob(os.path.join(MXL, '*.xml')) + glob.glob(os.path.join(MXL, '*.musicxml')))
    manifest = []
    n_lin = 0
    for f in files:
        raw = open(f, encoding='utf-8', errors='ignore').read()
        has_rep, has_end, nav = classify(raw)
        base = os.path.basename(f)
        if has_rep or has_end or nav:
            manifest.append({'file': base, 'linear': False,
                             'repeat': has_rep, 'ending': has_end, 'nav': nav})
            continue
        try:
            sc = music21.converter.parse(f)
            out, g, coll, expanded, mism, repaired = B.convert_song(f)
            measures, bad = B.finalize(out)
            dang = B.repair_dangling_ties(measures, title='')
            ref = {
                'file': base,
                'title': title_of(sc, f),
                'composer': (sc.metadata.composer if (sc.metadata and sc.metadata.composer) else '') or '',
                'key': key_of(sc),
                'timeSignature': time_of(sc),
                'tempo': tempo_of(sc),
                'gridQl': g,
                'bars': len(measures),
                'measures': measures,
                '_diag': {'collapsed': coll, 'orphanRepaired': repaired,
                          'danglingFixed': len(dang), 'mism': mism[:8], 'bad': bad},
            }
            with open(os.path.join(OUT, base.rsplit('.', 1)[0] + '.ref.json'), 'w', encoding='utf-8') as w:
                json.dump(ref, w, ensure_ascii=False)
            manifest.append({'file': base, 'linear': True, 'bars': len(measures),
                             'key': ref['key'], 'ts': ref['timeSignature'], 'tempo': ref['tempo'],
                             'diag': ref['_diag']})
            n_lin += 1
        except Exception as e:
            import traceback; traceback.print_exc()
            manifest.append({'file': base, 'linear': True, 'error': str(e)[:120]})
    with open(os.path.join(OUT, '_manifest.json'), 'w', encoding='utf-8') as w:
        json.dump(manifest, w, ensure_ascii=False, indent=1)
    errs = [m for m in manifest if m.get('error')]
    print(f'total={len(files)} linear={n_lin} errors={len(errs)}')
    for m in errs: print('  ERR', m['file'], m['error'])

if __name__ == '__main__':
    main()
