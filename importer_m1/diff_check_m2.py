#!/usr/bin/env python3
"""M2 逐事件对拍：swift2/<base>.swift.json 与 ref2/<base>.m2.json（展开后 measures）。
仅比对逐小节（chord/spm/chordSlots/chordAnnotations/notes）；meta 在 M1 已验证。"""
import os, json, glob

REF='/Users/onlyonear/Desktop/Improlyze/importer_m1/ref2'
SW ='/Users/onlyonear/Desktop/Improlyze/importer_m1/swift2'
NOTE_KEYS=['pitch','isRest','duration','isTriplet','isTieStart','isTieEnd']
def nn(n): return tuple(n[k] for k in NOTE_KEYS)
def ns(s): return (s['chord'], s['startSlot'])
def na(a): return (a['chord'], a['noteIndex'])
def sig(m):
    return (m['chord'], m['slotsPerMeasure'],
            [ns(s) for s in m['chordSlots']],
            [na(a) for a in m['chordAnnotations']],
            [nn(x) for x in m['notes']])

def main():
    sw={os.path.basename(p).replace('.swift.json',''):p for p in glob.glob(SW+'/*.swift.json')}
    total=0; full=0; details=[]
    cat={'bars':0,'chord':0,'slots':0,'ann':0,'notes':0}
    for base,path in sorted(sw.items()):
        rp=os.path.join(REF,base+'.m2.json')
        if not os.path.exists(rp): continue
        total+=1
        ref=json.load(open(rp)); out=json.load(open(path))
        rm=ref['measures']; sm=out['song']['measures']
        ex=[]; bad=False
        if len(rm)!=len(sm):
            cat['bars']+=1; bad=True; ex.append(f"bars ref={len(rm)} swift={len(sm)} (mapLen={len(ref['map'])})")
        nb=min(len(rm),len(sm))
        cd=sd=ad=nd=0
        for i in range(nb):
            a=sig(rm[i]); b=sig(sm[i])
            if a[0]!=b[0]: cd+=1
            if a[2]!=b[2]:
                sd+=1
                if len(ex)<10: ex.append(f"m{i+1} slots\n ref={a[2]}\n sw ={b[2]}")
            if a[3]!=b[3]:
                ad+=1
                if len(ex)<10: ex.append(f"m{i+1} ann\n ref={a[3]}\n sw ={b[3]}")
            if a[4]!=b[4]:
                nd+=1; bad=True
                if len(ex)<10:
                    for j in range(max(len(a[4]),len(b[4]))):
                        x=a[4][j] if j<len(a[4]) else None
                        y=b[4][j] if j<len(b[4]) else None
                        if x!=y: ex.append(f"m{i+1} note#{j}\n ref={x}\n sw ={y}"); break
            if a[1]!=b[1]:
                nd+=1; bad=True
                if len(ex)<10: ex.append(f"m{i+1} spm ref={a[1]} sw={b[1]}")
        if cd: cat['chord']+=1; bad=True
        if sd: cat['slots']+=1; bad=True
        if ad: cat['ann']+=1; bad=True
        if nd: cat['notes']+=1
        if not bad and len(rm)==len(sm): full+=1
        else: details.append((base,ex))
    print(f"M2 measures compared={total} FULL_MATCH={full}")
    print("files with ->",{k:v for k,v in cat.items() if v})
    for f,ex in details[:20]:
        print("\n###",f)
        for e in ex[:8]: print(e)
    if len(details)>20: print(f"\n... and {len(details)-20} more")

if __name__=='__main__': main()
