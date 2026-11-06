#!/usr/bin/env python3
"""逐事件对比 Swift 导入器输出与 build_79 参考 JSON（仅对通过 App 闸门、有 swift 输出的文件）。"""
import os, json, glob

REF='/Users/onlyonear/Desktop/Improlyze/importer_m1/ref'
SW ='/Users/onlyonear/Desktop/Improlyze/importer_m1/swift'

NOTE_KEYS=['pitch','isRest','duration','isTriplet','isTieStart','isTieEnd']

def norm_note(n):
    return tuple(n[k] for k in NOTE_KEYS)
def norm_slot(s):
    return (s['chord'], s['startSlot'])
def norm_ann(a):
    return (a['chord'], a['noteIndex'])

def measure_sig(m):
    return (m['chord'], m['slotsPerMeasure'],
            [norm_slot(s) for s in m['chordSlots']],
            [norm_ann(a) for a in m['chordAnnotations']],
            [norm_note(n) for n in m['notes']])

def main():
    sw={os.path.basename(p).replace('.swift.json',''):p for p in glob.glob(SW+'/*.swift.json')}
    total=0; fullmatch=0
    summary={'bars':0,'meta':0,'chord':0,'slots':0,'ann':0,'notes':0,'noteCount':0}
    details=[]
    for base,path in sorted(sw.items()):
        rp=os.path.join(REF,base+'.ref.json')
        if not os.path.exists(rp): continue
        total+=1
        ref=json.load(open(rp)); out=json.load(open(path))
        song=out['song']
        problems=[]; examples=[]
        # meta
        for k in ('key','timeSignature','tempo'):
            rv=ref[k]; sv=song.get(k)
            if rv!=sv:
                problems.append('meta'); examples.append(f"  meta {k}: ref={rv!r} swift={sv!r}")
        rm=ref['measures']; sm=song['measures']
        if len(rm)!=len(sm):
            problems.append('bars'); examples.append(f"  bars ref={len(rm)} swift={len(sm)}")
        nbar=min(len(rm),len(sm))
        noteDiffBars=0; slotDiff=0; annDiff=0; chordDiff=0; noteCountDiff=0
        for i in range(nbar):
            a=measure_sig(rm[i]); b=measure_sig(sm[i])
            if a[0]!=b[0]: chordDiff+=1
            if a[1]!=b[1]:
                noteDiffBars+=1; examples.append(f"  m{i+1} spm ref={a[1]} swift={b[1]}")
            if a[2]!=b[2]:
                slotDiff+=1
                if len(examples)<12: examples.append(f"  m{i+1} slots\n    ref={a[2]}\n    sw ={b[2]}")
            if a[3]!=b[3]:
                annDiff+=1
                if len(examples)<12: examples.append(f"  m{i+1} ann\n    ref={a[3]}\n    sw ={b[3]}")
            if a[4]!=b[4]:
                noteDiffBars+=1; noteCountDiff+= 0 if len(a[4])==len(b[4]) else 1
                if len(examples)<12:
                    # find first differing note
                    for j in range(max(len(a[4]),len(b[4]))):
                        x=a[4][j] if j<len(a[4]) else None
                        y=b[4][j] if j<len(b[4]) else None
                        if x!=y:
                            examples.append(f"  m{i+1} note#{j}\n    ref={x}\n    sw ={y}")
                            break
        if chordDiff: summary['chord']+=1
        if slotDiff: summary['slots']+=1
        if annDiff: summary['ann']+=1
        if noteDiffBars: summary['notes']+=1
        if noteCountDiff: summary['noteCount']+=1
        if problems: summary['meta']+=1
        if len(rm)!=len(sm): summary['bars']+=1
        if not problems and not slotDiff and not annDiff and not noteDiffBars and not chordDiff and len(rm)==len(sm):
            fullmatch+=1
        else:
            details.append((ref['file'],examples))
    print(f"swift outputs compared={total} FULL_MATCH={fullmatch}")
    print("files with ->",{k:v for k,v in summary.items() if v})
    print("\n==== per-file details (first 25 files) ====")
    for f,ex in details[:25]:
        print("\n###",f)
        for e in ex[:10]: print(e)
    if len(details)>25: print(f"\n... and {len(details)-25} more files with diffs")

if __name__=='__main__': main()
