# Construction Calculator (konstruktor-stroenii) — Project State

> Snapshot for handing off to another LLM/agent. Captures repo layout, what's
> implemented, what's stubbed, deployment, and the open task (3D / axonometry
> engine).
>
> Updated: 2026-04-30 (после доводки разреза 1-1/2-2 до полностью расчётного; архив `v29`).

---

## 1. TL;DR

- **Что это**: Flutter Web/Desktop приложение для проектирования зданий по
  параметрическому ТЗ. Генерирует комплект АР/КР чертежей и расчётных PDF.
- **Stack**: Flutter 3.35.4, Dart 3, `pdf` (Marc/PdfDocument), внутренний пакет
  `packages/cc_engine` для всех расчётов по СП.
- **Прод**: https://konstruktor-stroenii.ru (S3 бакет `konstruktor-stroenii` +
  Yandex CDN, ресурс `bc8rh3v5e5cz2p6phawl`). Билд деплоится скриптом
  `/home/ubuntu/scripts/deploy.sh` (`flutter build web` → `aws s3 sync` →
  `cdn.api.cloud.yandex.net/.../$ID:purge`).
- **Целевая аудитория**: проектировщики строительных организаций (ИЖС, дальше
  МКД и металлоконструкции). Продукт собираются продавать.
- **Текущая задача**: написать новый движок «3D-модель дома / аксонометрия»
  на основе плана этажа + расчётных значений (фундамент, стены, кровля).

---

## 2. Repo layout

```
construction_calculator/
├── pubspec.yaml                 # Flutter app + зависимости (pdf, provider, uuid…)
├── analysis_options.yaml
├── README.md
├── assets/
│   ├── fonts/                   # DejaVuSans, DejaVuSans-Bold (кириллица в PDF)
│   └── images/types/            # 6 jpg типов сооружений
├── web/                         # web shell (index.html, manifest, icons)
├── lib/
│   ├── main.dart                # AppState provider, MaterialApp, темы
│   ├── data/                    # справочники: regions, soil_types, wall_materials, room_catalog…
│   ├── models/                  # доменные модели (см. ниже)
│   ├── services/                # генераторы / PDF / DXF / cc_engine bridge
│   ├── widgets/                 # FloorPlanView, FoundationPlanView, calc_steps_card, hints…
│   ├── pages/                   # экраны (мастер ТЗ → планировка → фундамент → кровля → ТЗ-doc → чертежи)
│   ├── state/app_state.dart     # ChangeNotifier с проектами, организацией, хинтами
│   └── storage/                 # SharedPreferences-backed JSON store
└── packages/cc_engine/          # внутренний пакет — расчёты по СП
    ├── pubspec.yaml
    └── lib/src/
        ├── enums.dart           # FoundationSoilType, RoofShape, ConcreteClass, RebarClass, TerrainType, …
        ├── regions.dart         # SnowRegion, WindRegion (СП 20, прил. Е/Ж)
        ├── weight_component.dart
        ├── permanent_load.dart  # каталог типовых постоянных нагрузок (стены/перекрытия/кровля)
        ├── foundation_loads.dart # FoundationLoadsCalculator.compute(...) — снег+ветер+постоянная по СП 20
        ├── strip_footing.dart   # StripFootingDesigner.design(...) — лента по СП 22
        ├── rafters.dart         # расчёт стропил
        ├── thermal.dart         # СП 50 — сопротивление теплопередаче
        └── calc_step.dart       # CalcStep / CalcInput — пошаговая трассировка для UI/PDF
```

---

## 3. Доменные модели (lib/models)

| Модель | Назначение |
|---|---|
| `HouseProject` | главный агрегат: id/name + brief + composition + foundation + roof + walls + slabs + staircase + drawings + stages |
| `ClientBrief` | ТЗ заказчика: регион, footprintWidth/Length, floors, ceilingHeight, snowZone (int), windZone (String), wallMaterial, roofShape (через roof.type), мастер-список soilLayers, и пр. |
| `FloorPlan` | план одного этажа: width × height (в метрах), список `PlanRoom` (rect: mx, my, mw, mh + kind), список `PlanOpening` (окна/двери/арки), `PlanAttachment` (террасы/крыльцо). JSON-сериализуем. |
| `FoundationDesign` | выбранный тип фундамента + расчётные параметры |
| `RoofDesign` | тип кровли, уклон, материал, элементы |
| `WallsDesign`, `FloorSlabsDesign`, `StaircaseDesign` | соответствующие подсистемы |
| `Drawing` | один лист в комплекте: id, kind (DrawingKind), title, createdAt, payload (String, чаще всего JSON) |
| `DrawingsCollection` | хранит листы, группирует по «версиям» (одна генерация = одна партия) |
| `FoundationPlanModel` *(новый)* | геометрия плана фундамента (см. §6) |
| `OrganizationSettings` | реквизиты компании для штампа PDF |

`DrawingKind` сейчас:
```
schematicPlan, workingPlan, foundationPlan
```
Раньше `план фундамента` был `workingPlan` с текстовым payload. Новый
`foundationPlan` использует JSON-encoded `FoundationPlanModel`.

---

## 4. Текущая фича-карта

### 4.1 Что работает «для пользователя»
- Многоэтапный мастер: ТЗ → Планировка → Фундамент → Стены → Перекрытия →
  Лестница → Кровля → Технические условия → Чертежи.
- Реальный генератор плана этажа (slice-and-dice) с дверьми/окнами,
  редактор плана (drag/resize/добавить помещение).
- Выгрузка в PDF (A3 landscape, многостраничный комплект) и DXF (R12).
- Штамп ГОСТ Р 21.101-2020 (форма 3) с реквизитами организации.
- Регионы, грунты, материалы стен, кровли — с привязкой к СП.

### 4.2 cc_engine (расчёты)
- `FoundationLoadsCalculator.compute(...)` — снег по СП 20 (μ от формы и
  α), ветер по терррейн+регион, постоянная нагрузка как сумма
  `WeightComponent`-ов (стены × этажи + перекрытия × этажи + кровля).
  Возвращает `FoundationLoadsResult` с `LoadsGroupResult` (список
  `CalcStep`-ов с формулой/подстановкой/origin/reference) и
  `totalVerticalKnPerM2`.
- `StripFootingDesigner.design(...)` — лента: ширина подошвы из
  `R0(soilType)` и линейной нагрузки на 1 пог. м несущих стен; высота
  ленты = max(0.4, 2·b); глубина = max(df+0.1, 1.0); подбор `ConcreteClass` /
  `RebarClass` по нагрузке.
- `FoundationByTypeDesigner.design(...)` *(в lib/services/foundation_designer.dart)*
  — плита (толщина по нагрузке), сваи (Ø + длина + шаг), столбы,
  свайно-ростверк.
- `RafterDesigner` (cc_engine.rafters) — стропилка.
- `ThermalCalculator` (cc_engine.thermal) — СП 50, сопротивление R.

### 4.3 Какие чертежи реально рисуются
- **План этажа** (`schematicPlan` / `workingPlan`): полностью реальный
  (FloorPlanView + `_paintPlan` в pdf_builder.dart). Стены, проёмы,
  лестница со ступенями, осевая сетка, размерные цепи (3 уровня),
  ведомость окон/дверей, экспликация — всё из FloorPlan.
- **План кровли** (`_roofPage` + `_paintRoofPlan`): из
  `roof_plan_geometry.dart` — скаты, конёк, накосы, водостоки,
  снегозадержатели, дымоходы.
- **Фасады С/Ю/В/З** (`_facadePage` + `_paintFacade`): полностью реальные.
  Все размеры — из расчётов (см. §8). Окна/двери из `plan.openings`,
  материал стен из `brief.wallMaterial`, материал кровли из
  `project.roof.roofingMaterial` (цвет → `_facadeRoofFill`), уклон в %/°
  из `roof.slopeAngle`, высота цоколя — по типу фундамента
  (`StripFootingDesigner`/`FoundationByTypeDesigner`), вертикальная цепь
  размеров справа, легенда материалов слева, маркировка осей и общая
  длина внизу.
- **Разрезы 1-1 / 2-2** (`_sectionPage` + `_paintSection`): полностью
  реальный разрез. Все размеры — из расчётов (см. §9). Цоколь = высота
  по типу фундамента, толщина наружной стены = `walls.thickness` мм,
  материал стены штрихуется по ГОСТ 2.306-68 (кирпич — диагональная,
  газобетон — клеточная, брус — горизонтальные слои, каркас —
  вертикальные стойки), стропилка с шагом 600 мм по СП 64.13330,
  кровельный цвет = выбранный `roofingMaterial`, мауэрлат на углах,
  проёмы из `plan.openings` пересекающие сечение, внутренние перегородки
  150 мм по `plan.rooms`, легенда материалов справа, вертикальная
  цепь высот в мм.
- **Аксонометрия** (`_axonometricPage`): простая 2.5D проекция дома,
  кубики этажей со скатной кровлей. **Это то, что сейчас планируется
  заменить на полноценный 3D-движок.**
- **Спецификация материалов** (`_materialsSpecPage`): таблица бетон/
  арматура/двутавр/стены/кровля/утеплители — **только то, что
  фактически выбрано** в проекте (АР-12, нормировано в v25.1).
- **План фундамента** (`foundationPlan`, **новое в этой сессии**) —
  реальный чертёж со всей геометрией из расчётов. См. §6.

### 4.4 Что осталось «коротко» (не в этой сессии)
- Реальный фасад с реальной отделкой/высотами (сейчас упрощённый).
- Реальный разрез 1-1 с уровнями из расчёта фундамента+этажей+кровли.
- Узлы (мауэрлат, цокольный, опирание плиты).
- Генплан / ситуационный план / схема расположения скважин.
- Облако / аккаунты / совместная работа.
- IFC-экспорт.
- Расчётные ПЗ для теплотехники, стропил, перекрытий (по аналогии с
  `foundation_explanation_pdf.dart`).

---

## 5. Деплой

```
/home/ubuntu/scripts/deploy.sh
```
делает:
1. `flutter build web --base-href /` (в `/home/ubuntu/repos/construction_calculator`).
2. `aws s3 sync build/web/ s3://konstruktor-stroenii/ --delete` через
   `--endpoint-url=https://storage.yandexcloud.net`.
3. Обмен `YC_OAUTH_TOKEN` → IAM-токен.
4. `POST /cdn/v1/cache/$YC_CDN_RESOURCE_ID:purge` с `{"paths":["/*"]}`.

### Секреты
| Имя | Значение |
|---|---|
| `YC_S3_ACCESS_KEY_ID` | *(хранить в `~/.aws/credentials` профиль `yc`)* |
| `YC_S3_SECRET_ACCESS_KEY` | *(хранить там же)* |
| `YC_OAUTH_TOKEN` | env-переменная; перевыпуск: https://oauth.yandex.ru/authorize?response_type=token&client_id=1a6990aa636648e9b2ef855fa7bec2fb |
| `YC_CDN_RESOURCE_ID` | YC Console → CDN → Ресурсы → ID ресурса |
| Бакет | `konstruktor-stroenii` (без `.ru`) |
| Endpoint | `https://storage.yandexcloud.net` |
| Регион | `ru-central1` |

> ⚠️ В репозитории секреты **не хранятся**. Они подставляются из
> локального `~/.aws/credentials` (профиль `yc`) и env-переменных
> `YC_OAUTH_TOKEN` / `YC_CDN_RESOURCE_ID`. См. `deploy.sh`.

---

## 6. Что добавлено в текущей сессии: «#1 План фундамента»

> Контекст: пользователь попросил «полностью генерировать чертежи на основе
> расчётов, а не от себя. пускай генерит всё так, чтобы не было заглушек, а
> только реальные цифры».

### 6.1 Новые файлы

#### `lib/models/foundation_plan.dart` (366 строк)
JSON-сериализуемая структура `FoundationPlanModel`:
```dart
class FoundationPlanModel {
  final FoundationType type;          // strip / slab / pile / columnar / pileWithGrillage
  final String typeLabel;             // «Ленточный фундамент»
  final double buildingWidth, buildingLength; // метры (= footprint из ТЗ)
  final double depthM;                // глубина заложения, расчётная
  final double footprintArea;
  final List<FoundationBand> bands;             // ленты под несущие стены / ростверк
  final FoundationSlab? slab;                   // полигон плиты + толщина + арматура
  final List<FoundationPile> piles;             // x, y, diameterM, label
  final List<FoundationAxis> horizontalAxes;    // буквенные (А/Б/В…)
  final List<FoundationAxis> verticalAxes;      // цифровые (1/2/3…)
  final List<FoundationDimChain> dimensionChains; // FoundationDimSide + level + stops
  final List<FoundationAnnotation> annotations;   // x, y, text, opt. targetX/Y
  final List<String> notes;                       // «Бетон В25, Арматура А500…»
  final List<String> codeReferences;              // «СП 22.13330.2016», «СП 63.13330.2018» …
  String encode() => jsonEncode(toJson());
  static FoundationPlanModel? tryDecode(String s);
}
```
Вспомогательные типы: `FoundationBand` (x1,y1→x2,y2 + thicknessM + kind), `FoundationBandKind` (external/internal/grillage), `FoundationSlab` (polygon List\<FoundationPoint\> + thicknessM + reinforcement), `FoundationPile`, `FoundationAxis` (label + position в метрах), `FoundationDimChain` (FoundationDimSide + level + List\<double\> stops), `FoundationAnnotation`, `FoundationPoint`.

#### `lib/services/foundation_plan_generator.dart` (849 строк)
Главный оркестратор. Точка входа: `FoundationPlanGenerator.generate(HouseProject) → FoundationPlanModel?`.

Этапы:
1. Валидация: ТЗ заполнено (footprint), фундамент выбран. Иначе возвращает `null`.
2. **План этажа** генерируется через `FloorPlanGenerator.generate(brief)` для
   детекции внутренних несущих стен.
3. **Расчёты** через `_computeFoundationParams`:
   - `FoundationLoadsCalculator.compute(...)` (снег/ветер/постоянная по СП 20).
   - `StripFootingDesigner.design(...)` или `FoundationByTypeDesigner.design(...)`.
4. **Геометрия фундамента** в зависимости от типа:
   - `strip` — внешний контур + ленты под внутренние несущие стены.
   - `slab` — полигон плиты на всё пятно + ленты по периметру (опционально).
   - `pile` / `columnar` — массив свай по углам + по периметру с шагом из расчёта.
   - `pileWithGrillage` — сваи + ростверк (FoundationBand kind=grillage) над ними.
5. **Внутренние несущие стены** определяет `_detectInternalLoadBearingWalls`:
   парсит `FloorPlan.rooms`, ищет Y-координаты, где есть комнаты и сверху, и
   снизу (горизонтальные стены), и X-координаты с комнатами слева и справа
   (вертикальные стены). Только стены, проходящие через всё пятно. Допуск 0.02 м.
6. **Осевая сетка**: уникальные Y-координаты несущих стен + 0 и
   `buildingLength` → буквенные оси (А/Б/В/...). Уникальные X-координаты →
   цифровые оси (1/2/3/...).
7. **Размерные цепи**: уровень 1 — расстояния между соседними осями (мм);
   уровень 2 — общий габарит. Для каждого борта (top/bottom/left/right).
8. **Аннотации** и **notes**: глубина заложения, класс бетона/арматуры (из
   `design.concreteClass.title`, `design.rebarClass.title`), грунт, нагрузка,
   рекомендации (подушка, гидроизоляция).

Ключевые helper-функции:
- `_parseWindZone(String?)` — парсит метку «II»/«4»/«iv» в индекс WindRegion.
- `_soilFromBrief(List<SoilLayer>)` — маппинг `SoilType` → `FoundationSoilType` (в cc_engine).
- `freezingDepthForRegion(String?)` — табличная глубина промерзания по региону (соответствует функции в `foundation_design_page.dart`).
- `_wallsComponents` / `_floorComponents` / `_roofComponents` — берут
  `WeightComponent` из `PermanentLoadCalculator.defaults`.

#### `lib/widgets/foundation_plan_view.dart` (566 строк)
`FoundationPlanView extends StatelessWidget` + `_FoundationPlanPainter` (CustomPainter).

Рисует на Canvas:
- внешний контур (толстая чёрная линия);
- плиту (если slab) — заливка серым + 45° штриховка;
- ленты — четырёхугольники с заливкой и штриховкой;
- сваи — кружки;
- осевые линии (пунктир) с кружками-метками;
- размерные цепи — линии + засечки + текст в мм;
- аннотации — текст + leader-линия;
- блок «Технические указания» внизу (опционально, через `showNotes`).

### 6.2 Обновлённые файлы
- `lib/models/drawing.dart` — добавлен `DrawingKind.foundationPlan` + title `«План фундамента»`.
- `lib/services/drawing_generator.dart` — был текстовый stub:
  ```dart
  payload: 'Фундамент: ${project.foundation.summary}'
  ```
  Стало:
  ```dart
  final foundationModel = FoundationPlanGenerator.generate(project);
  if (foundationModel != null) {
    drawings.add(Drawing(
      id: _uuid.v4(),
      title: 'План фундамента',
      kind: DrawingKind.foundationPlan,
      createdAt: now,
      payload: foundationModel.encode(),
    ));
  }
  ```
- `lib/pages/drawings_page.dart` — добавлен рендер `FoundationPlanView` + полноэкранный режим (InteractiveViewer).
- `lib/services/pdf_builder.dart` — новая страница КР-1 «План фундамента»:
  - вставка в комплект между планами этажей и планом кровли;
  - метод `_foundationPlanPage(...)` (рамка, штамп, header);
  - painter `_paintFoundationPlan(canvas, size, model, font)` ~600 строк:
    - заливка/контур пятна, плита, ленты с косой штриховкой ГОСТ 2.306-68
      (бетон), сваи, оси (пунктир + белые кружки с лейблом), 2 размерные
      цепи, аннотации с leader-линиями, блок «Технические указания»;
    - все цифры на чертеже — из переданной `FoundationPlanModel`;
  - hatch-функция `_foundationHatchPolygon` использует `saveContext`/`clipPath`
    для клиппинга косых линий внутри полигона.

### 6.3 Где это видно
- В UI: вкладка «Чертежи» → лист «План фундамента».
- В PDF: лист **КР-1** в комплекте, раздел «Конструктивные решения».
- На проде https://konstruktor-stroenii.ru (CDN purged 2026-04-30).

---

## 7. 3D-движок здания / аксонометрия — РЕАЛИЗОВАНО

> Реализовано в этой сессии (архив `v27`). Заменяет нынешний упрощённый
> лист «Общий вид» в PDF и добавляет интерактивный 3D-вид на экран
> «Чертежи».

### 7.1 Файлы

#### `lib/models/building3d.dart` (≈285 строк)
Геометрические доменные модели:
- `Vec3` — 3D-вектор с +/-/* и `cross`/`dot`/`normalized`/`length`.
- `SurfaceKind` — семантика граней (foundationUnderground/Plinth,
  wallExterior/Interior, slab, glazing, door, roofSlope, roofRidge,
  attachmentDeck, ground).
- `Wall3D` — стена со списком прямоугольных проёмов (триангулируется
  рендерером с учётом вырезов). Имеет `start`/`end`/`height`/
  `thickness`/`outwardNormal`/`openings`/`kind`.
- `Opening3D` — прямоугольный проём: offsetAlong + bottom + width + height + kind (window/door/archway).
- `RoofSlope3D`, `RoofEdge3D` — скаты и линии конька/накосов.
- `Slab3D`, `Floor3D`, `Foundation3D`, `Attachment3D` — остальные элементы.
- `Building3D` — корневой агрегат с `projectName`, `footprintWidth/Length`, `totalHeight`, `foundation`, `floors`, `roof`, `attachments`, и геттер `center` для камеры.

#### `lib/services/building3d_generator.dart` (≈565 строк)
Точка входа: `Building3DGenerator.generate(HouseProject) → Building3D?` (null, если пятно ТЗ не задано).

Алгоритм:
1. Берёт глубину фундамента и его лейбл из реального расчёта
   `FoundationPlanGenerator.generate(...)` (которая запускает
   `FoundationLoadsCalculator` + `StripFootingDesigner`/`FoundationByTypeDesigner`).
2. Генерирует/использует `FloorPlan` для каждого этажа, чтобы
   достать `plan.openings` (окна и наружные двери).
3. Строит 4 наружные стены пятна (южная, северная, восточная, западная),
   каждой подсовывает соответствующие openings из `WallSide`.
4. Этажи: высота = `staircase.floorHeight` или 2.8 м; для мансарды — 0.8×.
5. Кровля по `RoofShape` (gable/hip/flat/shed/mansard) + `roof.slopeAngle`
   с правильной 3D-геометрией: двускатная — конёк параллельно длинной
   стороне; вальмовая — 4 ската + укороченный конёк; мансардная — пара
   ломаных скатов на каждой стороне; плоская — горизонтальная плита 0.3 м;
   односкатная — поднимается вдоль X.
6. Пристройки (крыльцо/терраса) — простые блоки из `plan.attachments`.

#### `lib/services/building3d_renderer.dart` (≈463 строки)
Mini-3D-движок без внешних зависимостей.
- `Camera3D` — orbit-камера с yaw/pitch/distance/target и `orthographic` флагом.
  Конструкторы `.iso(target, distance)` (35.264°/45° true-isometric) и
  `.military(target, distance)` (45°/45°).
- `SurfacePalette` — цвета для каждой `SurfaceKind` + функция `shadeFace(base, normal)` с локальным освещением «сверху-юго-запад».
- `RenderTri` — треугольник с вершинами + `kind` + `wireframeOnly` флаг + `normal` геттер.
- `RenderEdge` — линия (для конька / накосов).
- `Building3DRenderer.tessellate(building)` — превращает `Building3D` в
  плоский список `RenderTri`-ов (включая триангуляцию стен с прорезанием
  проёмов). Раздаёт землю, фундамент (подземная + цоколь), этажи,
  перекрытия, скаты, пристройки.
- `Building3DRenderer.collectEdges(building)` — линии конька/накосов из roof.
- `Building3DRenderer.project(p, camera, w, h)` — yaw/pitch матрица +
  ортогональная или перспективная проекция. Возвращает `Projected2D` (x, y, depth).

#### `lib/widgets/building3d_view.dart` (≈230 строк)
Интерактивный 3D-виджет на Flutter Canvas:
- `Building3DView(model, aspectRatio, initialYawDegrees, initialPitchDegrees)`.
- Дрэг — orbit (yaw + pitch); pitch ограничен (-π/2 + 0.05; π/2 − 0.05).
- Колесо мыши — zoom (0.3..5×).
- `_Building3DPainter` — back-face culling по знаковой 2D-площади,
  painter's algorithm (sort по среднему Z), shading через
  `SurfacePalette.shadeFace`.

### 7.2 Интеграция

#### `lib/services/pdf_builder.dart`
- Удалены: старый `_paintAxonometric` (≈400 строк процедурной отрисовки
  кубиков) и `_paintWallTexture3D` (≈90 строк штриховки текстуры).
- Добавлены: компактные `_paintAxonometric` (вызывает Generator + Renderer)
  и `_renderBuilding3DToPdf` (PDF-адаптер для Renderer:
  тесселляция → проекция → back-face cull → sort → рисование на PdfGraphics).
- Линия конька/накосов рисуется поверх граней.
- Подпись `«Общий вид (3D-модель). Изометрия 1:100»`.

#### `lib/pages/drawings_page.dart`
- В `_BatchCard` (для самой свежей версии) добавлен `_Building3DTile`:
  карточка над списком чертежей с превью 3D-вида и подсказкой
  «Тяните для поворота · колесо мыши — масштаб · нажмите, чтобы развернуть».
- По клику — `_Fullscreen3DPage` (full-screen orbit-vью).

### 7.3 Контрольные точки правды
| Что в 3D | Откуда берётся в коде |
|---|---|
| W × L пятна | `brief.footprintWidth/Length` |
| высота этажа | `staircase.floorHeight ?? 2.8` |
| число этажей | `brief.floors`, `+1` если `hasMansard` |
| глубина фундамента | `FoundationPlanGenerator.generate().depthM` |
| класс фундамента (label) | `FoundationPlanGenerator.generate().typeLabel` |
| положение/размер окон/дверей | `FloorPlanGenerator.generate(brief)` → `plan.openings` (filtered by WallSide + kind) |
| углы и форма кровли | `RoofShape.fromTypeId(roof.type)` + `roof.slopeAngle` |
| террасы/крыльцо | `plan.attachments` |

Никаких magic-чисел и хардкода размеров стен/кровли/фундамента в
рендерере нет — всё пришло через модель из проекта.

### 7.4 Дальше (опционально)
- Лестницы в 3D как пакет ступенек.
- Внутренние стены (несущие) — сейчас визуализируется только наружная коробка.
- Текстуры материалов стен (имитация кладки/бруса/штукатурки) поверх граней.
- Тени от здания на ground-плоскость через ортогональную проекцию из направления солнца.

---

## 8. Фасады (АР-2.x) — РЕАЛИЗОВАНО (v28)

Чертёж лежит в `pdf_builder.dart` → `_paintFacade()`. Никаких заглушек,
все размеры/цвета вычисляются из проекта.

### 8.1 Что откуда берётся
- Длина фасада = `plan.width` (для южного/северного) или `plan.height`
  (для западного/восточного). Контур пятна — из `brief.footprintWidth/Length`.
- Высота этажа = `staircase.floorHeight` или (по умолчанию) 2.8 м.
- Высота цоколя над землёй — из типа фундамента (`_BuildingElevation.plinthHeight`):
  - лента / плита / столбчатый — 0.30 м;
  - сваи / свайно-ростверк — 0.45 м (выше для проветриваемого подполья).
- Высота кровли = `(span/2)·tan(slope)` для двускатной/вальмовой,
  `span·tan(slope)` для односкатной, 0.30 м для плоской.
- Окна/двери на фасаде — из `plan.openings`, отфильтрованных по
  соответствующей стороне через `_projectOpeningOnFacade()`. Высоты:
  окно 1.5 м, подоконник 0.9 м (СП 55.13330, типовые); вход 2.1 м.
- Цвет стен — `_facadeWallFill(_wallMaterialCode(project))` по
  `walls.material`/`brief.wallMaterial` (кирпич/газобетон/брус/каркас…).
- Цвет кровли — `_facadeRoofFill(project.roof.roofingMaterial)`:
  металлочерепица — RAL 3005, гибкая черепица — серый, керамика — терракот,
  ПВХ-мембрана — светлый серый.
- Пристройки (терраса/крыльцо/гараж) — из `plan.attachments`, рисуются
  только если они «смотрят» в нужную сторону.

### 8.2 Что отрисовывается
- Земля + штриховка ГОСТ 2.306-68.
- Цоколь со штриховкой «бетон» и подписью типа фундамента.
- Стена + 1.4 пт обводка, цвет по материалу.
- Пунктирные линии межэтажных перекрытий.
- Окна: четверти, стеклопакет, импост, мулионы по ширине, рама,
  подоконник, перемычка. Маркировка ОК-N с размерами в мм.
- Двери: четверти, рама, филёнки, ручка, перемычка. Маркировка Д-N.
- Кровля: силуэт + свес 0.3 м, тень от карниза.
- Дымоход у конька.
- Пристройки на фасаде.
- Левая колонка отметок: −plinth, ±0.000, +этаж, +топ, +конёк (стрелки + текст).
- Нижняя цепь осей (А/Б/В… или 1/2/3…) и общая длина в мм.
- Правая вертикальная цепь высот в мм (цоколь / этажи / кровля).
- Указатель уклона `slopeDeg° / slope%` стрелкой на кровле.
- Легенда материалов слева внизу (стены + кровля цветом-патчем).

### 8.3 Контрольные точки правды
- Никаких magic-чисел кроме типовых СП-значений (1.5/0.9/2.1 м для
  окон/дверей; они задокументированы в коде).
- Все цвета и подписи материалов — функции от выбранных в проекте
  материалов (нет «всегда коричневый»).
- Высоты и проёмы синхронизированы с тем, что рисуется в плане
  этажа и в 3D-движке (используются те же `FloorPlan`/`HouseProject` API).

---

## 9. Разрезы 1-1 / 2-2 (АР-3.1, АР-3.2) — РЕАЛИЗОВАНО (v29)

Чертёж лежит в `pdf_builder.dart` → `_paintSection()`. Никаких заглушек:
все геометрические размеры вычисляются из проекта.

### 9.1 Что откуда берётся
- Длина разреза = `plan.width` (1-1 поперечный) / `plan.height` (2-2
  продольный).
- Положение секущей плоскости — `_findClearAxisPosition()` ищет такую
  ось, которая не пересекает пристройки (терраса/крыльцо/гараж).
- Глубина фундамента = `_FoundationPreview.depthM` (из реального
  `StripFootingDesigner` / `FoundationByTypeDesigner` через
  `_foundationPreview`).
- Высота цоколя над землёй = `_BuildingElevation.plinthHeight` (тот же,
  что на фасадах).
- Толщина наружной стены = `project.walls.thickness` мм
  (по умолчанию 350 мм если не задана).
- Высота этажа = `staircase.floorHeight ?? 2.8` м.
- Высота кровли = из `RoofShape` + угла, как на фасаде.
- Цвет кровли = `_facadeRoofFill(project.roof.roofingMaterial)`.
- Тип стенового материала (для штриховки) = `_wallMaterialCode(project)`.
- Внутренние стены — стороны `plan.rooms`, не совпадающие с внешним
  контуром, проходящие через секущую (`crosses` = секущая в диапазоне
  стороны комнаты).
- Проёмы — из `plan.openings` для соответствующих сторон, фильтруются
  пересечением координаты по секущей.

### 9.2 Что отрисовывается
- Земля + штриховка 45° ниже линии планировки.
- Фундамент — по типу: лента (3 ленты), плита (сплошной слой),
  столбчатый (3 столба + ростверк 0.3 м), сваи (5 свай в видимом
  сечении), свайно-ростверковый (+ ростверк 0.4 м). Все со штриховкой
  бетона.
- Цоколь со штриховкой бетона по ГОСТ 2.306-68.
- Этажи: ж/б перекрытия 0.2 м (чёрные полосы), белый интерьер.
- Наружные стены: толстый контур + штриховка по материалу
  (см. `_drawSectionWallHatch`):
  - кирпич — диагональная (4 пт);
  - газобетон/пенобетон — мелкая клетка (4.5 пт);
  - брус/клееный брус/бревно — горизонтальные слои укладки 200 мм;
  - каркас — вертикальные стойки + горизонтальные обвязки.
- Внутренние перегородки 150 мм со своей штриховкой.
- Окна (1.5×1.2 м, подоконник 0.9 м) и двери (вход 2.1 м, межкомн. 2.0 м)
  — «вырезаются» в толще стены, окна с импостом, двери с косяками.
- Кровля: силуэт с заливкой по реальному цвету материала + стропилка
  (шаг 600 мм по СП 64.13330) — короткие штрихи поперёк ската на каждой
  стропильной ноге; для скатных и мансардной отдельные ветки кода.
- Мауэрлаты — квадратные сечения 100×100 мм над углами стен.
- Левый столбец отметок: ‑foundationDepth / ‑plinthHeight / ±0.000 /
  +этажи / +конёк (стрелки + текст).
- Нижняя цепь общего габарита (мм).
- Маркер «Разрез 1-1 / 2-2» сверху.
- Выноска фундамента слева внизу (тип + габариты + детали армирования).
- Правая вертикальная цепь высот (мм между всеми отметками).
- Легенда материалов: стены / кровля / фундамент с цветными патчами.
- Указатель уклона `slopeDeg° / slope%` стрелкой на скате.

### 9.3 Контрольные точки правды
- Все уровни — функции от `_BuildingElevation` (foundationDepth,
  plinthHeight, floorHeight, roofHeight) и `_FoundationPreview` (depthM).
- Цвета и штриховки — функции от `walls.material` и
  `roof.roofingMaterial`. Никаких magic-чисел кроме типовых СП-значений
  для проёмов (документированы).
- Толщины стен передаются из `walls.thickness`, не зашиты «0.35 м».
- Шаг стропил 600 мм — из СП 64.13330.2017, явно прокомментирован.

---

## 10. Запасные/отложенные задачи

- Узлы (мауэрлат, цокольный, опирание плиты) как отдельные листы.
- Генплан / ситуационный план.
- IFC-экспорт.
- Облако/аккаунты (вместо SharedPreferences).
- Шаблоны проектов / брендирование штампа компании.
- Вкладки проектов, command palette, master-detail каркас (desktop UX).

---

## 11. Команды для бэкапа и деплоя

```bash
# Архив исходников (без build/, без .git/objects):
cd /home/ubuntu/repos
tar -czf /tmp/konstruktor_stroenii.tar.gz \
  --exclude='construction_calculator/build' \
  --exclude='construction_calculator/.dart_tool' \
  --exclude='construction_calculator/.flutter-plugins-dependencies' \
  construction_calculator

# Полный билд+деплой:
bash /home/ubuntu/scripts/deploy.sh
```
