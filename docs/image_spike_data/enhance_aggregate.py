import sys,re,collections,statistics as st
rows=[]
for l in open(sys.argv[1],encoding='utf8',errors='ignore'):
    m=re.search(r'ENHEVAL csv (.*)',l)
    if m:
        p=m.group(1).strip().split(',')
        rows.append(dict(id=p[0],cat=p[1],opt=p[2],em=int(p[3]),om=int(p[4]),cer=float(p[5]),wr=float(p[6]),kr=float(p[7])))
opts=['color','gray','flat','clahe','flat+clahe','binary']
groups={'ALL':None,'hard (light,low_contrast,combined,crumple)':{'light','low_contrast','combined','crumple'},'light':{'light'},'low_contrast':{'low_contrast'},'combined':{'combined'},'crumple':{'crumple'}}
by=collections.defaultdict(dict)
for r in rows: by[r['id']][r['opt']]=r
for g,cats in groups.items():
    ids=[i for i,v in by.items() if cats is None or v['color']['cat'] in cats]
    print(f'\n{g}: {len(ids)} pages')
    print('option | CER | wordRecall | keyRecall | worse>2pts vs color | better>2pts | enhanceMs | ocrMs')
    for o in opts:
        rs=[by[i][o] for i in ids]
        base=[by[i]['color'] for i in ids]
        worse=sum(1 for a,b in zip(rs,base) if a['wr']<b['wr']-0.02)
        better=sum(1 for a,b in zip(rs,base) if a['wr']>b['wr']+0.02)
        print(f"{o} | {st.mean(r['cer'] for r in rs):.4f} | {st.mean(r['wr'] for r in rs):.4f} | {st.mean(r['kr'] for r in rs):.4f} | {worse} | {better} | {st.median(r['em'] for r in rs):.0f} | {st.median(r['om'] for r in rs):.0f}")
# per page worst for each option
for o in opts[1:]:
    d=sorted(((by[i][o]['wr']-by[i]['color']['wr'],i) for i in by))[:3]
    print(o,'worst',[(i,round(x,3)) for x,i in d])
