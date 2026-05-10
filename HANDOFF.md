# Konstruktor Stroenii — Handoff v66 (Phase-3b: full straight-skeleton + zero-overhang miter)

**Дата:** 2026-05-02
**Прод:** https://konstruktor-stroenii.ru (этот build залит через `deploy.sh` → S3)
**Staging / демо:** https://web-cwgifkra.devinapps.com (тот же build, для быстрой проверки без CDN-кеша)
**База:** v65 (A1-планшет в UI, ReachabilityReport.warnings → Project.warnings, векторные текстуры кровли в аксонометрии; §22)
**Архив:** `konstruktor_stroenii_v66.tar.gz` (текущий) (без `.dart_tool` / `build` / `.git`)

> **ВАЖНО для следующей нейросети.** Этот handoff — **кумулятивная дельта v65 + v66 поверх v64.20**. Все исторические разделы и архитектура (стек, деплой, ключевые файлы, ограничения, тесты v64.x) — без изменений. Новые разделы — **§22 (v65) и §23 (v66) ниже**. Текущая база — **`konstruktor_stroenii_v66.tar.gz`**.
> Состояние: `flutter analyze lib` — **0 ошибок** (181 info baseline), `flutter test` — **124 / 124 зелёный** (+2 теста к v65), `flutter build web --release` — собирается за ~70 c.

---

## §22. v65 — что добавлено поверх v64.20

Поверх v64.20 закрыт открытый бэклог §21 + §17.2.x из HANDOFF_v64_20:

### §22.1 — §21.3 / §21.4 (унаследовано из текущей итерации, до начала v65)

В каталоге планировок (`lib/pages/floor_plan_templates_page.dart` + `lib/data/floor_plan_templates.dart`) появились:

* **3D-предпросмотр (`_Iso3DThumbPainter`).** Каждая карточка шаблона рисует не только 2D-силуэт, но и изометрическую аксонометрию (`px = (x − y)·cos30°`, `py = −z + (x + y)·sin30°`) с цоколем (если `hasBasement`), стенами высотой `floors · 3.0 + (hasMansard ? 2.5 : 0)` м и упрощённой кровлей (30° скат, 2 ската с коньком). Toggle `2D / 3D` через `ToggleButtons`; размер 44 px (2D) / 64 px (3D). Без WebGL — чистая 2D-Canvas-математика.
* **Расширенный VIP-каталог.** В `FloorPlanTemplateLibrary.extended` (отдельный список, **не превышает запрет §17.3 «12 архетипов в `.all`»**) появилось **7 спец-шаблонов:**
  T-shape 12×10, U-shape с атриумом 4×4, +-shape (cross / flagship 14×14), narrow lot 6×14, wide lot 16×8, two-storey estate 12×12, bungalow + mansard + garage. Все footprints — реальные `BuildingFootprint` (через фабрики `tShape()` / `uShape()` или явный `Vec2`-список в CCW-порядке).
* `findById(id)` теперь ищет в обоих списках; UI разводит каталог по `TabBar` (`Базовый (12)` / `VIP / расширенный (7)`).

### §22.2 — A1-планшет в Export-диалоге (§17.2.4)

`PdfA1Placard.buildDocument(...)` существовал с v64.16, но не был подключён к UI. Теперь:

* **`lib/pages/drawings_page.dart`:** в `_showExportDialog()` появилась третья кнопка — **«А1»** (рядом с PDF и DXF). Метод `_exportA1Placard()` декодирует `widget.drawings → FloorPlan` через `FloorPlan.tryDecode(d.payload)`, вызывает `PdfA1Placard.buildDocument(project, plans, versionNumber, organization)`, скачивает результат `<name>_A1_v<n>.pdf`.
* Никакой миграции `Project` / `ExportSettings` не потребовалось — A1 идёт отдельным экспортом, по той же кнопке-меню. Backward-compat 100 %.

### §22.3 — ReachabilityReport.warnings → Project.warnings (§17.2.3)

BFS-валидатор `lib/services/furniture/reachability_validator.dart` существовал с v64.18, но его отчёт никуда не сохранялся. Теперь:

* **`lib/models/house_project.dart`:** новое поле `final List<String> warnings`; сериализуется как ключ `'warnings'` в JSON; **backward-compat fallback** — отсутствующий ключ → `<String>[]` (старые проекты загружаются без потерь, см. §22.4 ниже).
* **`lib/services/drawing_generator.dart`:** после генерации `plans` из `FloorPlanGenerator.generate(...)` для каждого этажа вызывается `ReachabilityValidator.validate(plan)`. Если валидатор нашёл хотя бы одну входную дверь и хотя бы одну недостижимую комнату — в `project.warnings` добавляется строка вида `Этаж 1: «Спальня 1» недоступна — ширина прохода < 0.9 м`. Старые предупреждения «Этаж …» удаляются перед каждой генерацией (idempotent re-generation), остальные пользовательские строки в `warnings` сохраняются.
* **UI:** `DrawingsPage` для текущей версии проекта (`isLatest`) рисует красную карточку «Предупреждения (N)» сверху списка чертежей; внутри — список предупреждений из `project.warnings`.
* **PDF:** `PdfGeneralData._secondPage` — раздел «6. Предупреждения проектировщика» (только если `warnings.isNotEmpty`), сразу после «Инженерное оборудование», перед сноской «Настоящий комплект…».

### §22.4 — JSON-сериализация `Project.warnings` с backward-compat

```dart
toJson():    if (warnings.isNotEmpty) 'warnings': warnings,
fromJson():  warnings: json['warnings'] is List
              ? <String>[
                  for (final w in json['warnings'] as List)
                    if (w != null) w.toString(),
                ]
              : <String>[],
```

Проверка: тесты `floor_plan_template_serialization_test.dart` и существующие интеграционные → **122 / 122 зелёный**.

### §22.5 — Векторные текстуры кровли на аксонометрии (§16 / §8 пункт 6)

Стены на 3D-аксонометрии уже имели векторные текстуры с v64.16 (`_drawWallTexturesAxono` в `pdf_builder_materials.dart`: кирпичная кладка, газоблочная сетка, брус, ОСП). Теперь добавлены **текстуры кровли** — `_drawRoofTexturesAxono`:

* Для каждого ската (`Building3D.roof.slopes[i]`) проектируем 4 угла в экран; если скат обращён к камере (`dot(normal, camDir) > 0.05`), в локальных uv-координатах (`u` — вдоль карниза, `v` — вдоль ската) рисуются линии раскладки выбранного материала.
* Поддерживаются 5 паттернов из `MaterialTextureLibrary.roof(...)`:
  - **`metalTile` / `ceramicTile`** — горизонтальные ряды + вертикальные швы со сдвигом (шахматка) на каждом нечётном ряду.
  - **`slate`** — только горизонтальные волны через 0.6·tile.
  - **`seam` / `profileSheet`** — вертикальные швы вдоль ската через `tile`.
  - **`bitumen`** — крестовая сетка через 0.5 м (мелкая зернистость).
* Цвет — `roofTex.mortarColor` (тёмная линия), толщина 0.25 pt. Совпадает по визуальной плотности с настенными текстурами.

После правки PDF-дамп тестового U-shape вырос с 299 КБ до 356 КБ — это и есть сетка из векторных линий.

### §22.6 — Что НЕ делалось

Из бэклога v64.20 §21 принципиально остались для следующей итерации:

* **§21.1 п. 3 — Полная straight-skeleton (Aichholzer/Aurenhammer).** Текущая 45° trim + pairwise valley intersection достаточна для L/T/U/+ и большинства outline-форм. Узкие участки (две 45°-линии встречаются друг с другом, не дойдя до конька) ещё не обрабатываются.
* **§21.1 п. 4 (zero-overhang в reflex-углах ендов)** — пока в reflex-вершинах overhang `o·√2`. Геометрически это безвредно (карниз поднимается над ендовой), но визуально на крупных L-формах виден маленький «уголок».
* **§17.2.3 deep-deep — auto-rollback мебели.** Сейчас валидатор только формирует предупреждение в `project.warnings`. Автоматический откат мебели для недостижимых комнат (с применением `RoomFurnitureManager`) отложен — требует продумать UX (молчаливый откат vs подтверждение пользователем).
* **§21.7 п. 8 — Snap drag-vertex по сетке + кнопка «Сделать axis-aligned».** В `FootprintEditorPage` есть drag-and-drop вершин и подсветка convex/reflex, но автоматического snap к 0.5/0.1 м пока нет.

### §22.7 — Ключевые файлы, изменённые в v65

```
lib/data/floor_plan_templates.dart                    # +7 VIP-шаблонов
lib/pages/floor_plan_templates_page.dart              # +TabBar, +_Iso3DThumbPainter
lib/pages/drawings_page.dart                          # +кнопка А1, +панель warnings
lib/models/house_project.dart                         # +warnings field, +JSON
lib/services/drawing_generator.dart                   # +reachability validation
lib/services/pdf_general_data.dart                    # +раздел "6. Предупреждения"
lib/services/pdf_builder_materials.dart               # +_drawRoofTexturesAxono
```

Тесты — все из v64.20 продолжают работать без правок (122 / 122). Новых тестов под v65 НЕ добавлено (правки additive по существующему контракту).

### §22.8 — Команды для следующей нейросети

```bash
# Распаковка
tar xzf konstruktor_stroenii_v65.tar.gz
cd construction_calculator

# Установка (Flutter 3.32+ / Dart 3.5+)
flutter pub get

# Линт + тесты
flutter analyze lib    # ожидаем 0 errors / 0 warnings (есть info-хинты)
flutter test           # ожидаем 122 / 122 passed

# Сборка веб
flutter build web --release   # ~63 c, выход в build/web/

# Локальный preview
cd build/web && python3 -m http.server 8080
# → http://localhost:8080
```

### §22.9 — Что не положено в архив

* `build/`, `.dart_tool/`, `.flutter-plugins-cache`, `.git/`
* Любые `.env`, `.env.local`, `auth_backend/.env` (бэкенд в архиве не лежит — он не входил в v64.20)
* Папки платформ: `ios/`, `android/`, `macos/`, `windows/`, `linux/` (web-only сборка)

### §22.10 — Известные предостережения

* **Ключи Yandex Cloud** в чате в начале сессии v52 — давно скомпрометированы. Если они до сих пор используются в S3/CDN, обязательно перевыпусти.
* **`use_build_context_synchronously`** info-warning в `drawings_page.dart:421` — унаследован из v64.x, не относится к новому коду v65, не блокирует.

---

## §23. v66 — что добавлено поверх v65

Закрыты два пункта бэклога §21.1 из HANDOFF v65 §22.6: **п. 3 «full straight-skeleton continuation»** и **п. 4 «zero-overhang miter в reflex-углах»**. Обе правки — в одном файле `lib/services/roof_plan_geometry.dart` и сопровождающих тестах, без изменения публичного API `RoofPlanGeometry` и без миграций сериализации.

### §23.1 — §21.1 п. 3 — Straight-skeleton continuation (Aichholzer/Aurenhammer, упрощённая)

В алгоритме `computePolygonal(...)` уже была **двухпроходная** генерация hip/valley биссектрис (Pass 1 — лучи до ближайшего конька, Pass 2 — взаимное обрезание встречных лучей). Этого достаточно для большинства L/T/U-форм, но в **узких** участках, где две биссектрисы встречаются раньше, чем одна из них доходит до конька, между точкой встречи и коньком оставался **визуальный разрыв** — недостающий отрезок «merged wavefront».

**Что добавлено:**

* Класс `_MergeEvent` (точка встречи + усреднённое направление + флаги convex/reflex).
* В Pass 2 при обрезании пары лучей сохраняется такой ивент.
* Новый **Pass 4** в `computePolygonal`: для каждого `_MergeEvent` строится продолжение от точки встречи в усреднённом направлении до ближайшего конька. Дедупликация по сетке 0.2 м (одна точка = один merge-сегмент).
* Сегмент-продолжение классифицируется как `valley` (если оба исходных луча были reflex), `hip` (если оба convex и `wantHips`) или, для смешанного случая, как `hip` на hip-кровле.

Это аналог **edge-event** в полной straight-skeleton геометрии Aichholzer/Aurenhammer (1995), но без обработки split-events и без приоритетной очереди — разовый проход с дедупликацией. Для типовых жилых L/T/U/+-форм этого достаточно; для **сильно изогнутых** контуров с несколькими «ступенями» требуется доработка (см. §23.4).

### §23.2 — §21.1 п. 4 — Zero-overhang miter в reflex-вершинах

В v65 reflex-вершина outerOutline-а кровли эмитировалась как **одна точка** на координате исходной вершины (curr.x, curr.y). Это убирало o·√2 «горн» во внешнем углу карниза (правильно), но связывало карниз двумя **сложыми отрезками** длины ≈ √(L² + o²) — визуально это давало 45°-чамфер, который при крупных L-формах смотрелся «срезанным».

**Что добавлено:**

В `_offsetPolygonOutward(outline, o)` для каждой reflex-вершины теперь эмитируется **три точки подряд**:

1. `(curr + nIn · o)` — конец карниза предыдущего ребра, остановленный в точке, где он встречает линию следующего ребра (на стене).
2. `curr` — сама reflex-вершина (внутренний угол стены).
3. `(curr + nOut · o)` — начало карниза следующего ребра.

Между точкой 1 → 2 контур идёт **строго вдоль предыдущего ребра** на длину `o`; между 2 → 3 — **строго вдоль следующего ребра** на длину `o`. Это даёт **правильный L-образный внутренний угол** карниза без чамфера и без horn-а — то, как выглядит реальный карниз в строительстве (карниз доходит до стены, делает 90°, продолжается по следующей стене).

Для axis-aligned 270°-reflex (L/T/U/+) это идеальный результат. Для не-axis-aligned reflex (например, эркер под 60°) — корректный обобщённый miter (точки 1 и 3 лежат на корректных линиях, угол между ними равен внешнему углу полигона).

### §23.3 — Изменения в тестах

* `test/lshape_integration_test.dart`:
  * Ожидание `outerOutline.length == 6` для L → **8** (5 convex + 1 reflex × 3).
  * Ожидание `outerOutline.length == 8` для T → **12** (6 convex + 2 reflex × 3).
  * Ожидание `outerOutline.length == 8` для U → **12** (6 convex + 2 reflex × 3).
* `test/roof_geometry_advanced_test.dart`: добавлено 2 новых теста (всего 124 / 124):
  * **§21.1.4 (v66) miter-test** для L-shape — проверяет, что reflex-вершина (8, 6) присутствует в `outerOutline` и окружена двумя «walking-along-the-wall» точками на расстоянии ровно `o` друг от друга.
  * **§21.1.3 (v66) skeleton-continuation-test** для hip над L-shape — проверяет, что Pass 4 даёт ненулевые накосы (визуально это та самая «недостающая» 45°-линия от точки встречи до конька).

Существующий test `'L-shape: внешний контур кровли проходит через reflex-вершину'` остаётся зелёным — reflex-вершина по-прежнему лежит в `outerOutline`, просто теперь в окружении двух соседних точек miter-а.

### §23.4 — Что НЕ закрыто (продолжение бэклога)

Открытые пункты §21.1 после v66 (для следующей нейросети):

* **Split-events в straight-skeleton.** Pass 4 обрабатывает только edge-events (две биссектрисы встретились — продолжение в усреднённом направлении). Split-events (reflex-вершина «дотянулась» до edge-а на противоположной стороне полигона и расщепляет его) не реализованы. Влияет только на patологические формы (узкие коридоры с reflex-вершиной, упирающейся в противоположную стену) — для жилых L/T/U/+-проектов не требуется.
* **§17.2.3 deep-deep auto-rollback мебели для недостижимых комнат.** Сейчас warnings-only режим (см. §22.3). Нужно решить UX: молчаливый откат расстановки или модальное подтверждение.
* **§21.7 п. 8 — snap drag-vertex по сетке + кнопка «axis-align»** в `FootprintEditorPage`. Сейчас только текстовый ввод X/Y координат свободного полигона.
* **CSG / boolean operations над footprint-ами** (для добавления выступов / выемок к существующему полигону через UI). Сейчас редактор работает на уровне отдельных вершин.

### §23.5 — Карта изменений v66 (для diff'а)

| Файл                                         | Что изменено                                                                                                  |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `lib/services/roof_plan_geometry.dart`       | + класс `_MergeEvent`; в Pass 2 — запись merge-events; новый Pass 4 — straight-skeleton continuation; в `_offsetPolygonOutward` — 3-вершинный miter в reflex |
| `test/lshape_integration_test.dart`          | Updated `outerOutline.length` ожидания (L: 6→8, T: 8→12, U: 8→12)                                            |
| `test/roof_geometry_advanced_test.dart`      | + 2 теста: «полный miter на reflex» + «straight-skeleton continuation в hip над L»                           |
| `HANDOFF_v66.md`                             | этот файл (новый)                                                                                             |

### §23.6 — Регрессионная проверка

```bash
flutter analyze lib    # 0 errors / 181 info (baseline, без новых)
flutter test           # 124 / 124 passed
flutter build web --release   # ~70 c, build/web/main.dart.js ≈ 6.0 МБ
bash deploy.sh         # S3 sync → konstruktor-stroenii.ru
```

PDF тестовых дампов (`/tmp/lshape_plan.pdf`, `/tmp/tshape_plan.pdf`, `/tmp/ushape_plan.pdf`, `/tmp/full_plan.pdf`) изменились на 30–40 КБ — это новые vertex-события в outerOutline + новые сегменты в hips/valleys. Все три PDF успешно открываются и рендерят план кровли с правильными внутренними углами карниза.

### §23.7 — Деплой v66

```bash
# В корне construction_calculator/
flutter build web --release \
  --dart-define=AUTH_API_BASE_URL="https://89-169-141-69.sslip.io"

aws --profile yc --endpoint-url=https://storage.yandexcloud.net \
    s3 sync build/web s3://konstruktor-stroenii/ \
    --delete --exclude ".DS_Store"

# CDN purge (опционально, нужен YC_OAUTH_TOKEN + YC_CDN_RESOURCE_ID):
# IAM_TOKEN=$(curl ... ); curl -X POST https://cdn.api.cloud.yandex.net/.../$id:purge -d '{"paths":["/*"]}'
```

В этой сессии деплой выполнен, прод по https://konstruktor-stroenii.ru обновлён. CDN purge **не выполнялся** (нет `YC_OAUTH_TOKEN` в окружении) — для немедленного отображения нужен жёсткий reload (Ctrl+F5).
