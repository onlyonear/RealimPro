#!/usr/bin/env python3
"""M2 参考生成器：单 Part、非导航、含反复/volta 的子集。
产出每个文件：
  - map：music21 Expander.measureMap() 展开后的"源小节下标"播放顺序（展开器黄金基准）
  - measures：convert_song(已 expandRepeats)+finalize+dangling(policy a) 的逐小节 JSON（量化黄金基准）
  - structure：music21 看到的左/右反复线与 volta bracket 跨度（校验 Swift 结构解析）
  - expandable / 异常：music21 展不开者标记 block（Swift 必须一并拦截）
只写 importer_m1/ref2/。
"""
import os, sys, re, json, glob, traceback
import music21
from music21 import bar, repeat as m21repeat

EFF = '/Users/onlyonear/Desktop/video_shoot/jazz_songs/effendi'
MXL = os.path.join(EFF, 'mxl_all')
OUT = '/Users/onlyonear/Desktop/Improlyze/importer_m1/ref2'
sys.path.insert(0, EFF)
import build_79 as B

NAV_RE = re.compile(r'D\.\s*[SC]\.|Dal\s*Segno|Da\s*Capo|al\s*Coda|al\s*Fine|To\s*Coda|segno|coda|(^|[^a-z])fine([^a-z]|$)', re.I)

def is_nav(raw):
    for m in re.finditer(r'<(words|sound|rehearsal|barline)\b[^>]*?(?:/>)?>([^<]*)?', raw):
        if NAV_RE.search(m.group(0) or ''): return True
    return '<segno' in raw or '<coda' in raw

def structure_of(sc):
    """未展开 score 的反复结构（按 Part 的 Measure 顺序）。"""
    parts=list(sc.parts)
    part=parts[0]
    meas=list(part.getElementsByClass(music21.stream.Measure))
    bars=[]
    for i,m in enumerate(meas):
        lb=m.leftBarline; rb=m.rightBarline
        l = lb.direction if (lb is not None and 'Repeat' in lb.classSet) else None
        r = rb.direction if (rb is not None and 'Repeat' in rb.classSet) else None
        bars.append({'i':i,'num':m.number,'left':l,'right':r})
    brackets=[]
    for sp in part.spanners:
        if 'RepeatBracket' in sp.classes:
            comps=list(sp.getSpannedElements())
            nums=[mm.measureNumberWithSuffix() for mm in comps if 'Measure' in mm.classes]
            idxs=[meas.index(mm) for mm in comps if 'Measure' in mm.classes and mm in meas]
            brackets.append({'numberRange':list(sp.numberRange),'measures':nums,'idx':idxs})
    return bars, brackets

def main():
    os.makedirs(OUT, exist_ok=True)
    files=sorted(glob.glob(MXL+'/*.xml')+glob.glob(MXL+'/*.musicxml'))
    manifest=[]; n=0; nblock=0
    for f in files:
        raw=open(f,encoding='utf-8',errors='ignore').read()
        if not('<repeat' in raw or '<ending' in raw): continue
        if is_nav(raw):
            manifest.append({'file':os.path.basename(f),'status':'nav_block'}); continue
        if len(re.findall(r'<score-part\b',raw))>1:
            manifest.append({'file':os.path.basename(f),'status':'multipart_block'}); continue
        base=os.path.basename(f)
        rec={'file':base}
        try:
            sc=music21.converter.parse(f)
            bars,brackets=structure_of(sc)
            rec['rawBars']=len(bars); rec['bars']=bars; rec['brackets']=brackets
            part=sc.parts[0]
            # golden map（Expander 必须作用在 Part/小节流上，不能是 Score）
            try:
                ex=m21repeat.Expander(part)
                can=ex.isExpandable()
                if can is False:
                    rec['status']='notexpandable_block'; rec['map']=None
                elif can is None:
                    rec['status']='norepeat'; rec['map']=list(range(len(bars)))
                else:
                    mm=ex.measureMap()
                    rec['status']='expand_ok'; rec['map']=mm
            except Exception as e:
                rec['status']='expandfail_block'; rec['mapError']=str(e)[:120]
            # golden quantized output (convert_song expands internally)
            try:
                out,g,coll,expanded,mism,repaired=B.convert_song(f)
                measures,bad=B.finalize(out)
                dang=B.repair_dangling_ties(measures,title='')
                rec['gridQl']=g; rec['expBars']=len(measures)
                rec['measures']=measures
                rec['diag']={'collapsed':coll,'expanded':expanded,'orphan':repaired,
                             'dangling':len(dang),'mism':[str(x) for x in mism[:8]],'bad':[str(x) for x in bad]}
            except Exception as e:
                rec['quantError']=str(e)[:160]
            with open(os.path.join(OUT, base.rsplit('.',1)[0]+'.m2.json'),'w',encoding='utf-8') as w:
                json.dump(rec,w,ensure_ascii=False)
            n+=1
            if rec['status'].endswith('block'): nblock+=1
            manifest.append({'file':base,'status':rec['status'],'rawBars':rec.get('rawBars'),
                             'expBars':rec.get('expBars'),'mapLen':len(rec['map']) if rec.get('map') is not None else 0,
                             'brackets':len(brackets)})
            print(f"[{n}] {base} {rec['status']} raw={rec.get('rawBars')} exp={rec.get('expBars')} brackets={len(brackets)}",flush=True)
        except Exception:
            traceback.print_exc()
            manifest.append({'file':base,'status':'parsefail_block'})
    with open(os.path.join(OUT,'_manifest.json'),'w',encoding='utf-8') as w:
        json.dump(manifest,w,ensure_ascii=False,indent=1)
    from collections import Counter
    print("DONE",Counter(m['status'] for m in manifest))

if __name__=='__main__': main()
