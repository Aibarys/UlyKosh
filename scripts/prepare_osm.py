"""
Населённые пункты, области и дороги Казахстана из OpenStreetMap.

    pip install osmium
    curl -L -o kazakhstan-latest.osm.pbf https://download.geofabrik.de/asia/kazakhstan-latest.osm.pbf
    python3 scripts/prepare_osm.py kazakhstan-latest.osm.pbf

Пишет UlyKosh/Resources/kz-places.json и kz-roads.bin.
Данные © участники OpenStreetMap, лицензия ODbL.
"""
import json, math, os, re, struct, sys, collections, time
import osmium

PBF = sys.argv[1]
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "UlyKosh", "Resources") + "/"
ROAD_CLASSES = {
    "motorway": 1, "trunk": 1, "motorway_link": 1, "trunk_link": 1,
    "primary": 2, "primary_link": 2,
    "secondary": 3, "secondary_link": 3,
    "tertiary": 4, "tertiary_link": 4,
    "unclassified": 5, "residential": 6, "track": 7,
}
PLACE_KINDS = {"city": 1, "town": 3, "village": 4, "hamlet": 5}
CYR = re.compile(r"[А-Яа-яЁёӘәҒғҚқҢңӨөҰұҮүҺһІі]")

def hav(a, b):
    lon1, lat1 = a; lon2, lat2 = b; p = math.pi / 180
    d = 0.5 - math.cos((lat2 - lat1) * p) / 2 + math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2
    return 12742 * math.asin(math.sqrt(max(0, d)))

t0 = time.time()

# ---------- 1. Населённые пункты и области
class PlacesAndRegions(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.places = []
        self.regions = []   # (osm_id, ru, kk, [rings])

    def node(self, n):
        kind = n.tags.get("place")
        if kind not in PLACE_KINDS:
            return
        name = n.tags.get("name", "")
        ru = n.tags.get("name:ru") or (name if CYR.search(name) else "")
        kk = n.tags.get("name:kk") or (name if CYR.search(name) else "") or ru
        ru = ru or kk
        if not ru:
            return
        try:
            pop = int(re.sub(r"[^\d]", "", n.tags.get("population", "0")) or 0)
        except ValueError:
            pop = 0
        self.places.append({
            "osm": n.id, "ru": ru.strip(), "kk": kk.strip(), "lon": n.location.lon, "lat": n.location.lat,
            "kind": kind, "pop": pop, "capital": n.tags.get("capital") in ("yes", "2"),
            "admin": n.tags.get("capital") in ("4",),
        })

    def area(self, a):
        if a.tags.get("boundary") != "administrative" or a.tags.get("admin_level") != "4":
            return
        name = a.tags.get("name", "")
        ru = a.tags.get("name:ru") or name
        kk = a.tags.get("name:kk") or name
        rings = []
        for outer in a.outer_rings():
            rings.append([(nd.lon, nd.lat) for nd in outer])
        if rings:
            self.regions.append((a.orig_id(), ru, kk, rings))

h = PlacesAndRegions()
h.apply_file(PBF, locations=True, idx="flex_mem")
print(f"places {len(h.places)}, regions {len(h.regions)}  [{time.time()-t0:.0f}s]")
for _, ru, kk, rings in h.regions:
    print("  region:", ru, "|", kk, "| rings", len(rings), sum(len(r) for r in rings))

# ---------- 2. Дороги
class Roads(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.ways = []   # (class, [(lon,lat,nodeid)])
        self.node_use = collections.Counter()

    def way(self, w):
        cls = ROAD_CLASSES.get(w.tags.get("highway"))
        if cls is None:
            return
        if w.tags.get("area") == "yes":
            return
        pts = []
        for nd in w.nodes:
            if not nd.location.valid():
                continue
            pts.append((nd.location.lon, nd.location.lat, nd.ref))
        if len(pts) < 2:
            return
        self.ways.append((cls, pts))
        for p in pts:
            self.node_use[p[2]] += 1

r = Roads()
r.apply_file(PBF, locations=True, idx="flex_mem")
print(f"road ways {len(r.ways)} [{time.time()-t0:.0f}s]")
cls_km = collections.Counter()
for cls, pts in r.ways:
    cls_km[cls] += sum(hav(pts[i][:2], pts[i+1][:2]) for i in range(len(pts)-1))
print("km by class:", {k: int(v) for k, v in sorted(cls_km.items())})

import pickle
pickle.dump({"places": h.places, "regions": h.regions, "ways": r.ways, "node_use": r.node_use}, open("osm_raw.pkl", "wb"))
print(f"saved raw [{time.time()-t0:.0f}s]")

# ---------- 3. Граф дорог
MAX_CLASS = int(os.environ.get("MAX_CLASS", "5"))  # без грунтовок: последний отрезок до села путник идёт напрямик
TOL = float(os.environ.get("TOL", "0.0006"))   # упрощение геометрии, градусы (~60 м)

def simplify(pts, tol):
    if len(pts) < 3: return pts
    keep = [False] * len(pts); keep[0] = keep[-1] = True; stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1: continue
        ax, ay = pts[i]; bx, by = pts[j]; dx, dy = bx - ax, by - ay; L = dx * dx + dy * dy
        best, bk = -1, -1
        for k in range(i + 1, j):
            px, py = pts[k]
            t = 0 if L == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / L))
            dd = math.hypot(px - (ax + t * dx), py - (ay + t * dy))
            if dd > best: best, bk = dd, k
        if best > tol: keep[bk] = True; stack += [(i, bk), (bk, j)]
    return [p for p, k in zip(pts, keep) if k]

ways = [(c, pts) for c, pts in r.ways if c <= MAX_CLASS and c != 6]
use = collections.Counter()
for c, pts in ways:
    for p in pts: use[p[2]] += 1
    use[pts[0][2]] += 1; use[pts[-1][2]] += 1
loc = {}
for c, pts in ways:
    for lon, lat, nid in pts: loc[nid] = (lon, lat)
# рёбра между узлами-развилками
adj = collections.defaultdict(list)   # node -> [(edge_index)]
edges = []                            # [a, b, km, cls, [inner pts]]
for c, pts in ways:
    start = 0
    for i in range(1, len(pts)):
        if use[pts[i][2]] >= 2 or i == len(pts) - 1:
            seg = pts[start:i + 1]
            a, b = seg[0][2], seg[-1][2]
            if a != b or len(seg) > 2:
                km = sum(hav(seg[k][:2], seg[k + 1][:2]) for k in range(len(seg) - 1))
                edges.append([a, b, km, c, [(p[0], p[1]) for p in seg[1:-1]]])
            start = i
print(f"raw edges {len(edges)}")
# самая большая связная компонента
nbr = collections.defaultdict(set)
for a, b, *_ in edges: nbr[a].add(b); nbr[b].add(a)
seen = {}; best_root = None; best_size = 0
for n in nbr:
    if n in seen: continue
    stack = [n]; seen[n] = n; size = 0
    while stack:
        u = stack.pop(); size += 1
        for v in nbr[u]:
            if v not in seen: seen[v] = n; stack.append(v)
    if size > best_size: best_size, best_root = size, n
edges = [e for e in edges if seen.get(e[0]) == best_root]
print(f"largest component nodes {best_size}, edges {len(edges)}")
# сжатие цепочек: проходим от каждой развилки по рёбрам, пока не встретим следующую развилку
inc = collections.defaultdict(list)
for i, e in enumerate(edges):
    inc[e[0]].append(i)
    if e[1] != e[0]: inc[e[1]].append(i)
def is_junction(n):
    lst = inc[n]
    if len(lst) != 2: return True
    e1, e2 = edges[lst[0]], edges[lst[1]]
    return abs(e1[3] - e2[3]) > 1
used = [False] * len(edges)
merged = []
for j in list(inc.keys()):
    if not is_junction(j): continue
    for start_edge in inc[j]:
        if used[start_edge]: continue
        cur, ei = j, start_edge
        pts = [loc[j]]; km = 0.0; cls = 9
        while True:
            used[ei] = True
            a_, b_, ekm, ecls, inner = edges[ei]
            nxt = b_ if a_ == cur else a_
            seg = inner if a_ == cur else inner[::-1]
            pts += seg + [loc[nxt]]; km += ekm; cls = min(cls, ecls)
            cur = nxt
            if is_junction(cur): break
            others = [x for x in inc[cur] if x != ei]
            if not others or used[others[0]]: break
            ei = others[0]
        merged.append([j, cur, km, cls, pts[1:-1]])
edges = merged
node_ids = sorted({e[0] for e in edges} | {e[1] for e in edges})
idx = {n: i for i, n in enumerate(node_ids)}
print(f"contracted: nodes {len(node_ids)}, edges {len(edges)}")

# ---------- 4. Двоичный файл дорог
def q(v): return int(round(v * 1e5))
buf = bytearray(b"KZRD") + struct.pack("<HII", 1, len(node_ids), len(edges))
for n in node_ids:
    lon, lat = loc[n]; buf += struct.pack("<ii", q(lon), q(lat))
total_pts = 0
for a, b, km, c, inner in edges:
    pts = simplify([loc[a]] + inner + [loc[b]], TOL)[1:-1]
    # дельты в 1e-5°, длинные шаги дробим
    out = []; px, py = q(loc[a][0]), q(loc[a][1])
    for lon, lat in pts:
        tx, ty = q(lon), q(lat)
        steps = max(1, math.ceil(max(abs(tx - px), abs(ty - py)) / 32000))
        for s in range(1, steps + 1):
            nx = px + (tx - px) * s // steps; ny = py + (ty - py) * s // steps
            out.append((nx - px, ny - py)); px, py = nx, ny
    total_pts += len(out)
    buf += struct.pack("<IIfBH", idx[a], idx[b], km, c, len(out))
    for dx, dy in out: buf += struct.pack("<hh", dx, dy)
open(OUT + "kz-roads.bin", "wb").write(buf)
print(f"roads bin {len(buf)//1024} KB, geometry points {total_pts} [{time.time()-t0:.0f}s]")

# ---------- 5. Населённые пункты
def inside(pt, ring):
    x, y = pt; n = len(ring); j = n - 1; res = False
    for i in range(n):
        xi, yi = ring[i]; xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-12) + xi: res = not res
        j = i
    return res
regions = sorted(h.regions, key=lambda r_: r_[1])
reg_names = {str(i): [ru, kk] for i, (_, ru, kk, _) in enumerate(regions)}
bboxes = []
for _, _, _, rings in regions:
    xs = [p[0] for rg in rings for p in rg]; ys = [p[1] for rg in rings for p in rg]
    bboxes.append((min(xs), min(ys), max(xs), max(ys)))
def region_of(lon, lat):
    # города республиканского значения проверяем первыми: они лежат внутри областей
    order = sorted(range(len(regions)), key=lambda i: (bboxes[i][2] - bboxes[i][0]) * (bboxes[i][3] - bboxes[i][1]))
    for i in order:
        x0, y0, x1, y1 = bboxes[i]
        if not (x0 <= lon <= x1 and y0 <= lat <= y1): continue
        if any(inside((lon, lat), rg) for rg in regions[i][3]): return str(i)
    return ""
out_places = []
for p in h.places:
    if re.search(r"упраздн|бывш|снесен|нежил", p["ru"], re.I): continue
    ru = re.sub(r"\s*\(.*?\)\s*", " ", p["ru"]).strip(); kk = re.sub(r"\s*\(.*?\)\s*", " ", p["kk"]).strip()
    pop = p["pop"]
    if p["capital"] or (p["kind"] == "city" and pop >= 200_000): rank = 1
    elif p["kind"] == "city": rank = 2
    elif p["kind"] == "town": rank = 3
    elif pop >= 1000: rank = 4
    else: rank = 5
    item = {"id": p["osm"], "ru": ru, "kk": kk, "at": [round(p["lon"], 5), round(p["lat"], 5)], "pop": pop, "rank": rank,
            "region": region_of(p["lon"], p["lat"])}
    if p["capital"]: item["cap"] = True
    out_places.append(item)
# Пункты на границе, не попавшие ни в один контур, получают область ближайшего соседа.
with_region = [x for x in out_places if x["region"]]
for x in out_places:
    if not x["region"]:
        near = min(with_region, key=lambda y: (y["at"][0] - x["at"][0]) ** 2 + (y["at"][1] - x["at"][1]) ** 2)
        x["region"] = near["region"]
out_places.sort(key=lambda x: (x["rank"], -x["pop"], x["ru"]))
json.dump({"regions": reg_names, "places": out_places, "source": "© OpenStreetMap contributors, ODbL"},
          open(OUT + "kz-places.json", "w"), ensure_ascii=False, separators=(",", ":"))
print(f"places {len(out_places)}, no region {sum(1 for x in out_places if not x['region'])}, "
      f"json {os.path.getsize(OUT + 'kz-places.json')//1024} KB [{time.time()-t0:.0f}s]")
