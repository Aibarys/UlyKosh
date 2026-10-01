# Жаяу · Jaiau

Фитнес-путешествие для iOS: шаги из «Здоровья» превращаются в километры пешего пути по реальным дорогам Казахстана, из любого города в любой. Четыре сезонных «великих кочевья» остались как готовые маршруты.

Проект и бандл исторически называются UlyKosh (`kz.ulykosh.UlyKosh`), бренд приложения — «Жаяу».

## Сборка

Проект описан в `project.yml` и генерируется XcodeGen:

```bash
xcodegen generate
open UlyKosh.xcodeproj
```

Требования: Xcode 16+, iOS 17+. HealthKit работает в симуляторе, но шагов там нет, поэтому во вкладке «Ещё» есть раздел «Отладка» с кнопками добавления шагов (только в Debug-сборке).

## Структура

- `UlyKosh/Data/SpringRoute.swift` — контент маршрута: стоянки, фауна, персонажи, испытания.
- `UlyKosh/Services/GameEngine.swift` — игровая логика: шаги → км, стадо, события, стоянки.
- `UlyKosh/Services/HealthKitStepSource.swift` — чтение шагов по дням.
- `UlyKosh/Views/` — экраны: онбординг, «Дорога», «Маршрут», «Аул», «Ещё».

## Выпуск в TestFlight

```bash
./scripts/test.sh            # тесты
./scripts/archive.sh upload  # +1 к номеру сборки, коммит, Release-архив, выгрузка в App Store Connect
```

Сборки для симулятора и устройства кладутся в `~/Library/Caches/UlyKosh/build`, вне папки проекта, потому что она синхронизируется iCloud и его атрибуты ломают подпись.

Раздел «Отладка» в настройках виден в Debug- и TestFlight-сборках и скрыт в App Store.
Политика конфиденциальности публикуется из `docs/` через GitHub Pages.

## Данные карты

Населённые пункты, границы областей и дороги взяты из OpenStreetMap (© участники OpenStreetMap, лицензия ODbL).
Пересобрать `kz-places.json` и `kz-roads.bin`:

```bash
pip install osmium
curl -L -o kazakhstan-latest.osm.pbf https://download.geofabrik.de/asia/kazakhstan-latest.osm.pbf
python3 scripts/prepare_osm.py kazakhstan-latest.osm.pbf
```

Контур страны, реки, озёра и рельеф — Natural Earth (`scripts/prepare_map_data.py`).
