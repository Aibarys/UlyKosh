import json, math, collections, re
import os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'UlyKosh', 'Resources') + '/'
# Запускать из папки с KZ.txt, alt/KZ.txt (GeoNames) и graph_raw.json (scripts/prepare_roads.py)
def hav(a, b):
    lon1, lat1 = a; lon2, lat2 = b; p = math.pi/180
    d = 0.5 - math.cos((lat2-lat1)*p)/2 + math.cos(lat1*p)*math.cos(lat2*p)*(1-math.cos((lon2-lon1)*p))/2
    return 12742 * math.asin(math.sqrt(d))

# ---------- граф: только крупная компонента, сжатие цепочек степени 2
g = json.load(open('graph_raw.json'))
coords = g['coords']; adj = {int(k): {int(a): b for a, b in v.items()} for k, v in g['adj'].items()}
start = max(adj, key=lambda n: len(adj[n]))
comp=set([start]); st=[start]
while st:
    u=st.pop()
    for v in adj[u]:
        if v not in comp: comp.add(v); st.append(v)
adj = {u: {v:w for v,w in adj[u].items() if v in comp} for u in comp}
junction = {u for u in adj if len(adj[u]) != 2}
edges = []; seen = set()
for j in junction:
    for nb in adj[j]:
        if (j, nb) in seen: continue
        path=[j]; prev=j; cur=nb; length=adj[j][nb]
        while cur not in junction:
            path.append(cur)
            nxt = [v for v in adj[cur] if v != prev]
            if not nxt: break
            prev, cur = cur, nxt[0]; length += adj[prev][cur]
            if cur == j: break
        path.append(cur)
        seen.add((j, path[1])); seen.add((cur, path[-2]))
        edges.append((j, cur, length, path))
# циклы без перекрёстков не нужны
jlist = sorted(junction); jidx = {n:i for i,n in enumerate(jlist)}
def rnd(p): return [round(p[0], 4), round(p[1], 4)]
def simplify(pts, tol=0.004):
    if len(pts) < 3: return pts
    def d(p,a,b):
        ax,ay=a; bx,by=b; px,py=p; dx,dy=bx-ax,by-ay
        if dx==dy==0: return math.hypot(px-ax,py-ay)
        t=max(0,min(1,((px-ax)*dx+(py-ay)*dy)/(dx*dx+dy*dy))); return math.hypot(px-(ax+t*dx),py-(ay+t*dy))
    keep=[False]*len(pts); keep[0]=keep[-1]=True; stack=[(0,len(pts)-1)]
    while stack:
        i,j=stack.pop()
        if j<=i+1: continue
        k=max(range(i+1,j), key=lambda k: d(pts[k],pts[i],pts[j]))
        if d(pts[k],pts[i],pts[j])>tol: keep[k]=True; stack+=[(i,k),(k,j)]
    return [p for p,k in zip(pts,keep) if k]
out_edges=[]
for a,b,length,path in edges:
    geom = simplify([coords[n] for n in path])
    out_edges.append([jidx[a], jidx[b], round(length,2), [rnd(p) for p in geom[1:-1]]])
roads = {"nodes": [rnd(coords[n]) for n in jlist], "edges": out_edges}
json.dump(roads, open(OUT+"kz-roads.json","w"), separators=(",",":"))
road_pts = [coords[n] for n in comp]
print("roads: nodes", len(jlist), "edges", len(out_edges))

# ---------- населённые пункты
CYR = re.compile(r'^[А-Яа-яЁёӘәҒғҚқҢңӨөҰұҮүҺһІі \-\.0-9]+$')
cands = collections.defaultdict(lambda: collections.defaultdict(list))
for line in open('alt/KZ.txt', encoding='utf-8'):
    f = line.rstrip('\n').split('\t')
    gid, lang, name = int(f[1]), f[2], f[3]
    if lang not in ('ru','kk'): continue
    if f[7] == '1' or f[6] == '1': continue  # исторические и разговорные
    if not CYR.match(name): continue
    cands[gid][lang].append((0 if f[4] == '1' else 1, len(name), name))
alt = collections.defaultdict(dict)
for gid, langs in cands.items():
    for lang, lst in langs.items():
        alt[gid][lang] = (True, sorted(lst)[0][2])
# Знаковые места без кириллицы в GeoNames
OVERRIDES = {1520295: ("Отрар", "Отырар")}
admin = {}
rows = []
for line in open('KZ.txt', encoding='utf-8'):
    f = line.rstrip('\n').split('\t')
    if f[6] == 'A' and f[7] == 'ADM1': admin[f[10]] = int(f[0])
    if f[6] == 'P' and f[7] not in ('PPLX','PPLQ','PPLH','PPLW','PPLF'): rows.append(f)
def names(gid, fallback):
    if gid in OVERRIDES: return OVERRIDES[gid]
    ru = alt[gid].get('ru', (None, None))[1]; kk = alt[gid].get('kk', (None, None))[1]
    return ru or kk or fallback, kk or ru or fallback
# сетка дорожных точек для отбора сёл возле дорог
grid = collections.defaultdict(list)
for p in road_pts: grid[(int(p[0]/0.2), int(p[1]/0.2))].append(p)
def road_dist(p):
    gx, gy = int(p[0]/0.2), int(p[1]/0.2); best = 1e9
    for dx in (-1,0,1):
        for dy in (-1,0,1):
            for q in grid[(gx+dx,gy+dy)]:
                best = min(best, hav(p, q))
    return best
regions = {}
for code, gid in admin.items():
    ru, kk = names(gid, code)
    ru = re.sub(r'\s*[Оо]бласть$', ' область', ru).strip()
    kk = re.sub(r'\s*[Оо]блысы$', ' облысы', kk).strip()
    regions[code] = [ru, kk]
places = []; skipped_latin = 0
for f in rows:
    gid = int(f[0]); lat, lon = float(f[4]), float(f[5]); pop = int(f[14] or 0); code = f[7]
    ru, kk = names(gid, f[1])
    if re.search(r'[A-Za-z]', ru) and pop < 10000: skipped_latin += 1; continue
    rd = road_dist((lon, lat))
    important = pop >= 5000 or code in ('PPLA','PPLA2','PPLC') or gid in OVERRIDES
    if not important and rd > 12: continue
    rank = 1 if pop >= 200000 or code in ('PPLC',) else 2 if pop >= 50000 or code == 'PPLA' else 3 if pop >= 10000 or code == 'PPLA2' else 4 if pop >= 1000 else 5
    item = {"id": gid, "ru": ru, "kk": kk, "at": [round(lon,4), round(lat,4)], "pop": pop, "rank": rank, "region": f[10]}
    if code == 'PPLC': item["cap"] = True
    places.append(item)
places.sort(key=lambda p: (p["rank"], -p["pop"], p["ru"]))
json.dump({"regions": regions, "places": places}, open(OUT+"kz-places.json","w"), ensure_ascii=False, separators=(",",":"))
c = collections.Counter(p["rank"] for p in places)
print("places:", len(places), dict(sorted(c.items())), "skipped latin:", skipped_latin)
for nm in ["Алматы","Астана","Шымкент","Түркістан","Жезқазған","Сарыағаш","Отырар","Шолаққорған","Қызылорда","Ақтау"]:
    hits = [p for p in places if p["kk"] == nm or p["ru"] == nm]
    print(nm, "->", [(h["ru"], h["kk"], h["rank"], h["pop"]) for h in hits[:2]])
print("regions sample:", list(regions.items())[:4])
import os
for fn in ["kz-roads.json","kz-places.json"]: print(fn, os.path.getsize(OUT+fn)//1024, "KB")
