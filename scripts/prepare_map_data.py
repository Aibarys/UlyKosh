import json, math, random
random.seed(7)
OUT = "/Users/aiba/Documents/projects/UlyKosh/UlyKosh/Resources/kazakhstan-map.json"
BBOX = (45.5, 39.5, 88.5, 56.5)

def load(n): return json.load(open(n))['features']

# ---------- геометрия ----------
def rings_of(geom):
    t = geom['type']; c = geom['coordinates']
    if t == 'Polygon': return [c[0]]
    if t == 'MultiPolygon': return [poly[0] for poly in c]
    return []
def lines_of(geom):
    t = geom['type']; c = geom['coordinates']
    if t == 'LineString': return [c]
    if t == 'MultiLineString': return list(c)
    return []
def simplify(pts, tol):
    # Douglas-Peucker
    if len(pts) < 3: return pts
    def d(p, a, b):
        ax, ay = a; bx, by = b; px, py = p
        dx, dy = bx-ax, by-ay
        if dx == dy == 0: return math.hypot(px-ax, py-ay)
        t = max(0, min(1, ((px-ax)*dx + (py-ay)*dy) / (dx*dx+dy*dy)))
        return math.hypot(px-(ax+t*dx), py-(ay+t*dy))
    stack = [(0, len(pts)-1)]; keep = [False]*len(pts); keep[0] = keep[-1] = True
    while stack:
        i, j = stack.pop()
        if j <= i+1: continue
        idx, dm = i, 0
        for k in range(i+1, j):
            dk = d(pts[k], pts[i], pts[j])
            if dk > dm: idx, dm = k, dk
        if dm > tol:
            keep[idx] = True; stack += [(i, idx), (idx, j)]
    return [p for p, k in zip(pts, keep) if k]
def inside(pt, ring):
    x, y = pt; n = len(ring); j = n-1; res = False
    for i in range(n):
        xi, yi = ring[i]; xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj-xi)*(y-yi)/((yj-yi) or 1e-12) + xi: res = not res
        j = i
    return res
def inside_any(pt, rings): return any(inside(pt, r) for r in rings)
def bbox(rings):
    xs = [p[0] for r in rings for p in r]; ys = [p[1] for r in rings for p in r]
    return min(xs), min(ys), max(xs), max(ys)
def rnd(pts, n=3): return [[round(x, n), round(y, n)] for x, y in pts]
def in_bbox(pts): return any(BBOX[0] <= x <= BBOX[2] and BBOX[1] <= y <= BBOX[3] for x, y in pts)

# ---------- граница ----------
kaz = next(f for f in load('ne_50m_admin_0_countries.geojson') if f['properties'].get('ADM0_A3') == 'KAZ')
kaz_rings = [simplify(r, 0.02) for r in rings_of(kaz['geometry'])]
kaz_rings = [r for r in kaz_rings if len(r) > 20]
print("border rings", [len(r) for r in kaz_rings])

# ---------- вода ----------
water = []
marine = load('ne_10m_geography_marine_polys.geojson')
for f in marine:
    if f['properties'].get('name') == 'Caspian Sea':
        rings = [simplify(r, 0.03) for r in rings_of(f['geometry'])]
        rings = [[p for p in r if p[1] > 39.5] for r in rings]
        water.append({"name": "Каспий теңізі", "label": [51.0, 44.8], "rings": [rnd(r) for r in rings if len(r) > 3]})
want = {
 "Балхаш": "Балқаш", "Зайсан": "Зайсан", "Алаколь": "Алакөл", "Сасыкколь": None, "Тенгиз": "Теңіз",
 "Кушмурун": None, "Селетытениз": None, "Шардаринское водохранилище": None, "Капчагайское водохранилище": None,
 "Большое Аральское море": "Арал теңізі", "Малое Аральское море": None, "Маркаколь": None, "Теке": None,
 "озеро Кызылкак": None, "Сарыкопа": None, "озеро Шалкар": None, "озеро Улькен Ажиболат": None, "Койбагар": None,
 "озеро Шаглытеныз": None, "Имантау": None, "Айке": None,
}
seen = set()
for f in load('ne_10m_lakes.geojson'):
    ru = f['properties'].get('name_ru')
    if ru in want and ru not in seen:
        seen.add(ru)
        rings = [simplify(r, 0.01) for r in rings_of(f['geometry'])]
        rings = [r for r in rings if len(r) > 3]
        if not rings: continue
        x0, y0, x1, y1 = bbox(rings)
        water.append({"name": want[ru], "label": [round((x0+x1)/2, 2), round((y0+y1)/2, 2)] if want[ru] else None, "rings": [rnd(r) for r in rings]})
print("water", len(water))

# ---------- реки ----------
river_names = {"Syr  Darya": ("Сырдария", 3), "Ertis": ("Ертіс", 3), "Irtysh": (None, 3), "Esil": ("Есіл", 2), "Ishim": (None, 2),
               "Ile": ("Іле", 2), "Tobol": ("Тобыл", 2), "Ural": ("Жайық", 3), "Aksu": (None, 1)}
rivers = {}
for f in load('ne_10m_rivers_lake_centerlines.geojson'):
    nm = f['properties'].get('name')
    if nm not in river_names: continue
    for line in lines_of(f['geometry']):
        # оставляем только участки внутри Казахстана (с небольшим запасом у Арала и Каспия)
        run = []
        for p in line:
            if inside_any(p, kaz_rings) or (nm == "Syr  Darya" and 44 < p[1] < 46.5 and p[0] < 62.5):
                run.append(p)
            else:
                if len(run) > 2: rivers.setdefault(nm, []).append(run)
                run = []
        if len(run) > 2: rivers.setdefault(nm, []).append(run)
river_out = []
for nm, lines in rivers.items():
    label, width = river_names[nm]
    lines = [simplify(l, 0.015) for l in lines]
    longest = max(lines, key=len)
    mid = longest[len(longest)//2]
    river_out.append({"name": label, "width": width, "label": [round(mid[0], 2), round(mid[1], 2)] if label else None, "lines": [rnd(l) for l in lines]})
# Дорисованные вручную реки, которых нет в Natural Earth (приближённо).
hand = {
 "Сарысу": (2, [[72.0, 49.3], [70.6, 48.7], [69.2, 48.1], [68.1, 47.5], [67.6, 46.8], [67.1, 46.1], [66.5, 45.5], [66.2, 45.2]]),
 "Шу": (2, [[74.6, 42.9], [73.8, 43.5], [72.6, 44.1], [71.4, 44.4], [70.2, 44.8], [69.2, 45.0], [68.3, 44.9]]),
 "Нұра": (1, [[74.6, 49.2], [73.6, 49.7], [72.6, 50.1], [71.5, 50.4], [70.4, 50.5], [69.4, 50.4]]),
 "Торғай": (1, [[64.2, 50.7], [63.8, 49.9], [63.4, 49.1], [63.0, 48.5], [62.5, 48.1]]),
 "Ырғыз": (1, [[61.9, 49.6], [61.3, 48.9], [61.6, 48.4], [62.2, 48.1]]),
 "Жем": (1, [[58.6, 49.1], [57.4, 48.5], [56.3, 47.8], [55.0, 47.1], [53.8, 46.5]]),
 "Талас": (1, [[72.4, 42.6], [71.4, 42.9], [70.7, 43.5], [70.3, 44.1], [70.1, 44.5]]),
 "Ойыл": (1, [[56.2, 49.6], [55.0, 49.2], [53.8, 48.9], [52.9, 49.1]]),
 "Есіл (верх)": (1, [[70.5, 51.1], [71.3, 51.3], [71.9, 51.7], [71.6, 52.3]]),
}
for nm, (w, pts) in hand.items():
    label = None if "верх" in nm else nm
    mid = pts[len(pts)//2]
    river_out.append({"name": label, "width": w, "label": [mid[0], mid[1]] if label else None, "lines": [rnd(pts)]})
print("rivers", len(river_out))

# ---------- регионы: штриховка и подписи ----------
regions = load('ne_10m_geography_regions_polys.geojson')
def region_rings(name):
    for f in regions:
        if f['properties'].get('NAME') == name:
            return [simplify(r, 0.02) for r in rings_of(f['geometry'])]
    return []
def scatter(rings, dx, dy, jitter, limit_to_kaz=True, extra=None):
    x0, y0, x1, y1 = bbox(rings); pts = []
    y = y0
    row = 0
    while y <= y1:
        x = x0 + (dx/2 if row % 2 else 0)
        while x <= x1:
            p = (x + random.uniform(-jitter, jitter)*dx, y + random.uniform(-jitter, jitter)*dy)
            if inside_any(p, rings) and (not limit_to_kaz or inside_any(p, kaz_rings)) and (extra is None or extra(p)):
                pts.append(p)
            x += dx
        y += dy; row += 1
    return pts
def poly(points): return [points]
symbols = []; labels = []
def add(kind, rings, dx, dy, label=None, at=None, angle=0, jitter=0.35, extra=None):
    pts = scatter(rings, dx, dy, jitter, extra=extra)
    if pts: symbols.append({"kind": kind, "points": rnd(pts, 2)})
    if label:
        if at is None:
            x0, y0, x1, y1 = bbox(rings); at = [(x0+x1)/2, (y0+y1)/2]
        labels.append({"text": label, "kind": kind, "at": [round(at[0], 2), round(at[1], 2)], "angle": angle})

# Хребты
add("range", region_rings("Karatau Range"), 0.26, 0.19, "Қаратау", angle=-35)
add("range", region_rings("Tarbagatay Ra."), 0.26, 0.19, "Тарбағатай", angle=-8)
add("range", region_rings("ALTAY MOUNTAINS"), 0.3, 0.22, "Алтай", at=[84.6, 49.6])
add("range", region_rings("TIAN SHAN"), 0.3, 0.22, "Тянь-Шань", at=[78.6, 42.55])
add("range", region_rings("Alataw Mts."), 0.26, 0.19, "Жоңғар Алатауы", at=[80.3, 45.15], angle=-12)
add("range", region_rings("URAL MOUNTAINS"), 0.28, 0.2, "Мұғалжар", at=[58.4, 48.6], angle=80)
add("range", poly([[66.4, 48.4], [67.2, 48.3], [67.8, 48.9], [67.4, 49.3], [66.6, 49.1]]), 0.24, 0.17, "Ұлытау", at=[67.1, 49.45])
add("range", poly([[76.2, 43.05], [78.2, 43.0], [78.2, 43.35], [76.2, 43.4]]), 0.24, 0.15, "Іле Алатауы", at=[77.2, 43.55], angle=-4)
add("range", poly([[51.5, 43.9], [52.8, 43.7], [53.3, 44.2], [52.0, 44.5]]), 0.24, 0.17, "Маңғыстау", at=[52.4, 44.75])
# Мелкосопочник
add("hills", region_rings("KAZAKH UPLAND"), 0.55, 0.42, "Сарыарқа", at=[73.5, 48.6], jitter=0.45)
# Плато
add("plateau", region_rings("Ustyurt Plateau"), 0.5, 0.4, "Үстірт", at=[55.5, 44.3], jitter=0.4)
# Пустыни
add("desert", region_rings("BETPAQDALA DESERT"), 0.3, 0.24, "Бетпақдала", at=[70.2, 45.9])
add("desert", region_rings("QIZILQUM DESERT"), 0.3, 0.24, "Қызылқұм", at=[63.3, 43.6])
add("desert", poly([[68.0, 43.5], [72.6, 43.6], [73.0, 44.4], [69.5, 44.7], [68.0, 44.4]]), 0.28, 0.22, "Мойынқұм", at=[70.6, 44.15])
add("desert", poly([[74.8, 44.6], [78.2, 45.2], [78.0, 46.0], [75.0, 45.6]]), 0.28, 0.22, "Сарыесік-Атырау", at=[76.4, 45.85])
add("desert", poly([[60.0, 46.3], [63.0, 46.6], [63.2, 47.6], [60.4, 47.4]]), 0.25, 0.2, "Арал Қарақұмы", at=[61.6, 47.85])
add("desert", poly([[47.2, 48.2], [49.6, 48.4], [49.9, 49.6], [47.6, 49.9]]), 0.28, 0.2, "Нарын құмы", at=[48.6, 50.1])
add("desert", poly([[53.5, 43.9], [56.0, 43.6], [57.2, 44.4], [54.5, 45.1]]), 0.28, 0.2, None)
# Степь: подписи без штриховки
labels.append({"text": "Тұран ойпаты", "kind": "plain", "at": [60.0, 45.2], "angle": 0})
labels.append({"text": "Каспий маңы ойпаты", "kind": "plain", "at": [50.5, 47.6], "angle": 0})
labels.append({"text": "Торғай үстірті", "kind": "plain", "at": [63.6, 51.2], "angle": 0})
labels.append({"text": "Есіл даласы", "kind": "plain", "at": [67.5, 53.2], "angle": 0})
print("symbols", [(s["kind"], len(s["points"])) for s in symbols])

cities = [
 ("Астана", 51.17, 71.45, True, 1), ("Алматы", 43.24, 76.95, False, 1), ("Шымкент", 42.32, 69.60, False, 1),
 ("Қарағанды", 49.80, 73.10, False, 2), ("Ақтөбе", 50.28, 57.17, False, 2), ("Тараз", 42.90, 71.37, False, 2),
 ("Павлодар", 52.29, 76.95, False, 2), ("Өскемен", 49.95, 82.61, False, 2), ("Семей", 50.41, 80.25, False, 2),
 ("Атырау", 47.11, 51.92, False, 2), ("Ақтау", 43.65, 51.17, False, 2), ("Қызылорда", 44.85, 65.51, False, 2),
 ("Түркістан", 43.30, 68.25, False, 2), ("Жезқазған", 47.80, 67.71, False, 2), ("Қостанай", 53.21, 63.62, False, 2),
 ("Петропавл", 54.87, 69.15, False, 2), ("Орал", 51.23, 51.37, False, 2), ("Талдықорған", 45.02, 78.37, False, 3),
 ("Көкшетау", 53.28, 69.39, False, 3), ("Балқаш", 46.85, 74.98, False, 3), ("Қапшағай", 43.88, 77.07, False, 3),
]
historic = [
 ("Сауран", 43.53, 67.77), ("Сығанақ", 44.28, 66.95), ("Сарайшық", 47.50, 51.75),
 ("Жанкент", 45.85, 62.10), ("Талхиз", 43.30, 77.23), ("Қойлық", 45.60, 80.10),
 ("Ақыртас", 42.82, 71.85), ("Тамғалы", 43.80, 75.53),
]
data = {
 "border": [rnd(r) for r in kaz_rings],
 "water": water,
 "rivers": river_out,
 "symbols": symbols,
 "labels": labels,
 "cities": [{"name": n, "at": [lon, lat], "capital": c, "rank": r} for n, lat, lon, c, r in cities],
 "historic": [{"name": n, "at": [lon, lat]} for n, lat, lon in historic],
}
import os; os.makedirs(os.path.dirname(OUT), exist_ok=True)
json.dump(data, open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
print("written", os.path.getsize(OUT)//1024, "KB")
