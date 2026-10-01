import json, math, heapq, collections
def hav(a, b):
    lon1, lat1 = a; lon2, lat2 = b
    p = math.pi/180
    d = 0.5 - math.cos((lat2-lat1)*p)/2 + math.cos(lat1*p)*math.cos(lat2*p)*(1-math.cos((lon2-lon1)*p))/2
    return 12742 * math.asin(math.sqrt(d))

# граница KZ из подготовленной карты
import os
kz = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'UlyKosh', 'Resources', 'kazakhstan-map.json')))['border']
# Запускать из папки с ne_10m_roads.geojson (Natural Earth)
def inside(pt, ring):
    x, y = pt; n=len(ring); j=n-1; res=False
    for i in range(n):
        xi, yi = ring[i]; xj, yj = ring[j]
        if (yi>y)!=(yj>y) and x < (xj-xi)*(y-yi)/((yj-yi) or 1e-12)+xi: res = not res
        j=i
    return res
def in_kz(p): return any(inside(p, r) for r in kz)

r = json.load(open('ne_10m_roads.geojson'))
lines=[]
for ft in r['features']:
    if ft['properties'].get('type') == 'Ferry Route': continue
    g=ft['geometry']; parts = [g['coordinates']] if g['type']=='LineString' else g['coordinates']
    for part in parts:
        if not any(46<=x<=88 and 40<=y<=56 for x,y in part): continue
        share = sum(1 for p in part if in_kz(p)) / len(part)
        if share >= 0.3: lines.append([tuple(p) for p in part])
print("lines kept:", len(lines))

# узлы: квантование до ~1.5 км, затем склейка концов в радиусе 4 км
Q = 0.015
def key(p): return (round(p[0]/Q), round(p[1]/Q))
node_id = {}; coords = []
def nid(p):
    k = key(p)
    if k not in node_id:
        node_id[k] = len(coords); coords.append(p)
    return node_id[k]
adj = collections.defaultdict(dict)
for line in lines:
    prev = None
    for p in line:
        cur = nid(p)
        if prev is not None and prev != cur:
            d = hav(coords[prev], coords[cur])
            adj[prev][cur] = min(adj[prev].get(cur, 1e9), d); adj[cur][prev] = adj[prev][cur]
        prev = cur
deg = {n: len(adj[n]) for n in adj}
ends = [n for n in adj if deg[n] == 1]
# склейка висячих концов с ближайшим узлом другой компоненты/линии
grid = collections.defaultdict(list)
for n in adj: grid[(int(coords[n][0]/0.1), int(coords[n][1]/0.1))].append(n)
joined = 0
for e in ends:
    gx, gy = int(coords[e][0]/0.1), int(coords[e][1]/0.1)
    best=None; bd=4.0
    for dx in (-1,0,1):
        for dy in (-1,0,1):
            for n in grid[(gx+dx, gy+dy)]:
                if n==e or n in adj[e]: continue
                d = hav(coords[e], coords[n])
                if d < bd: bd, best = d, n
    if best is not None:
        adj[e][best] = bd; adj[best][e] = bd; joined += 1
print("nodes:", len(adj), "dangling joined:", joined)

# компоненты
comp = {}; sizes = collections.Counter()
for n in adj:
    if n in comp: continue
    stack=[n]; comp[n]=n
    while stack:
        u=stack.pop()
        for v in adj[u]:
            if v not in comp: comp[v]=n; stack.append(v)
for n,c in comp.items(): sizes[c]+=1
print("components:", len(sizes), "largest:", sizes.most_common(5))

def nearest(p):
    return min(adj, key=lambda n: hav(coords[n], p))
def route(a, b):
    s, t = nearest(a), nearest(b)
    dist={s:0}; prev={}; pq=[(0,s)]
    while pq:
        d,u=heapq.heappop(pq)
        if u==t: break
        if d>dist[u]: continue
        for v,w in adj[u].items():
            nd=d+w
            if nd<dist.get(v,1e18): dist[v]=nd; prev[v]=u; heapq.heappush(pq,(nd,v))
    return dist.get(t), hav(coords[s], a), hav(coords[t], b)
tests = {
 "Алматы→Астана (≈1210)": ((76.95,43.24),(71.45,51.17)),
 "Шымкент→Түркістан (≈160)": ((69.60,42.32),(68.25,43.30)),
 "Атырау→Ақтау (≈880)": ((51.92,47.11),(51.17,43.65)),
 "Алматы→Өскемен (≈1050)": ((76.95,43.24),(82.61,49.95)),
 "Қызылорда→Жезқазған (≈450)": ((65.51,44.85),(67.71,47.80)),
 "Орал→Ақтөбе (≈470)": ((51.37,51.23),(57.17,50.28)),
 "Астана→Петропавл (≈450)": ((71.45,51.17),(69.15,54.87)),
}
for name,(a,b) in tests.items():
    d, sa, sb = route(a,b)
    print(f"{name}: {d and round(d)} km (snap {sa:.1f}/{sb:.1f})")
json.dump({"coords": coords, "adj": {str(k): v for k,v in adj.items()}}, open('graph_raw.json','w'))
