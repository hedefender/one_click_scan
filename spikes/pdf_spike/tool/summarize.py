"""Aggregates analysis.json into the tables of docs/PDF_SPIKE_RESULTS.md."""
import json, os, statistics, sys
rows = json.load(open(os.path.join(sys.argv[1], 'analysis.json')))
sheets = sys.argv[2].split(',') if len(sys.argv) > 2 else None
def agg(sel):
    r = [x for x in rows if (sheets is None or x['sheet'] in sheets) and sel(x)]
    return r
print('writer mode  n  valid  clean  textEqual  errMean%  errMed%  errP95%  errMax%   exact@0  exact@.25  miss  extra  wrong (of total@.25)')
for w in ('type3', 'glyphless', 'lib'):
    for m in 'ABC':
        r = agg(lambda x: x['writer'] == w and x['mode'] == m)
        if not r: continue
        def tot(k, j): return sum(x[j][k] for x in r)
        t0, t25 = tot('total', 'sel0'), tot('total', 'sel25')
        em = [x['err_mean'] for x in r if x['err_mean'] is not None]
        emed = [x['err_median'] for x in r if x['err_median'] is not None]
        e95 = [x['err_p95'] for x in r if x['err_p95'] is not None]
        emax = [x['err_max'] for x in r if x['err_max'] is not None]
        print(f"{w:9} {m}  {len(r):2}  {sum(x['valid'] for x in r)}/{len(r)}  {sum(x['clean'] for x in r)}/{len(r)}  {sum(x['text_equal'] for x in r)}/{len(r)}  "
              f"{100*statistics.mean(em):6.1f}  {100*statistics.mean(emed):6.1f}  {100*statistics.mean(e95):6.1f}  {100*max(emax):6.1f}   "
              f"{100*tot('exact','sel0')/max(t0,1):5.1f}%  {100*tot('exact','sel25')/max(t25,1):5.1f}%  "
              f"{100*tot('missing','sel25')/max(t25,1):4.1f}% {100*tot('extra','sel25')/max(t25,1):4.1f}% {100*tot('wrong','sel25')/max(t25,1):4.1f}%  ({t25})")
print()
print('per sheet OCR exact lines:', {x['sheet']: f"{x['ocr_exact_lines']}/{x['lines']}" for x in rows if x['writer']=='lib' and x['mode']=='A'})
