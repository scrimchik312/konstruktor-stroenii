# HANDOFF v68 — «Конструктор строений»

**Версия**: v68.1
**Дата**: 2026-05-09
**Базовая версия**: v67 (см. HANDOFF_v67.md от прошлой сессии)
**Прод**: https://konstruktor-stroenii.ru/

---

## 1. Краткое резюме изменений

Сессия закрыла бэклог §24.7 из v67 (CSG, split-events, snap drag-vertex,
auto-rollback мебели, аксонометрия), добавила правки UI каталога шаблонов,
синхронизировала лист «Схема ПОЗУ» с реальным полигоном пятна и провела
полный аудит кода на безопасность, заглушки и несостыковки.

### Что вошло
1. **§25.1-5** — закрытие бэклога v67 (auto-rollback, snap drag, split-events,
   CSG/Sutherland-Hodgman polygon clipping, аксонометрия 3D code-review).
2. **§26.1-5** — правки страницы каталога шаблонов: видимость карточек,
   кнопка «Назад», hero-renders реалистичных домов, борьба с серым scrim
   (HintAutoShow race-condition + grayscale-фильтр у пользователя).
3. **§27.1** — Лист «Схема ПОЗУ» (АР-0а): рисуется реальный
   `BuildingFootprint.outline` (L/T/U/+ формы), а не bbox-rect. Размер
   участка адаптивный к размеру пятна.
4. **§27.2** — Унификация высоты этажа: pdf_additional_plans использовало
   2.7 м, остальные модули — 2.8 м. Сведено к единому `walls.height ??
   staircase.floorHeight ?? 2.8`.
5. **§27.3** — Клампы на ввод пользователя в брифе и редакторе пятна
   (защита от значений 99999 м, ломавших масштабирование).
6. **§27.4** — Аудит безопасности и качества кода: убран dead-code,
   проверены секреты, eval/innerHTML, catch-блоки, валидация ввода.

---

## 2. Качество

| Метрика                           | Результат |
|-----------------------------------|-----------|
| `flutter analyze` (lib)           | 0 errors / 0 warnings |
| `flutter analyze` (lib + test + cc_engine) | 0 errors / 0 warnings |
| `flutter test` (Flutter unit)     | 133 / 133 passed |
| `dart test` (packages/cc_engine)  | 5 / 5 passed |
| `flutter build web --release`     | ~45 с, success |
| `curl https://konstruktor-stroenii.ru/` | HTTP 200 |

---

## 3. Изменения по файлам

### lib/services/pdf_site_plan.dart (§27.1)
- Импортирован `building_footprint.dart`.
- Параметры пятна берутся из `project.effectiveArchitectureFootprint.bbox`
  вместо `brief.footprintWidth/Length`.
- Размер участка адаптивный: при пятне ≤ 14 м — 20×20 м, иначе
  `max(W,L) + 16` м (СНиП 30-102: 3 м до забора + 5 м красная линия +
  место под подъезд).
- Painter получает `footprint` параметром и рисует полигон
  через `moveTo`/`lineTo`/`closePath` вместо `drawRect`. Координаты
  outline-а конвертируются из плановой системы (Y вниз) в PDF (Y вверх).
- Диагональ «крыша на плане» рисуется только для прямоугольных пятен
  (4 вершины); для L/T/U/+ её рисовать бессмысленно.

### lib/services/pdf_additional_plans.dart (§27.2)
- Строка 1750 (расшивка стропил, КД-2 «Расчёт»): `wallHeightM` теперь
  `walls.height ?? staircase.floorHeight ?? 2.8` (унифицировано с
  pdf_builder, pdf_catalog_card, pdf_a1_placard, pdf_engineering_specs).
- Строка 2820 (план кровли «Условия»): отметка пола чердака теперь
  `walls.height × floors`, а не хардкод `2.7 × floors`.

### lib/pages/floor_plan_templates_page.dart (§26.1-5)
- Полностью переписан под home_page стиль: pure white карточки, светлый
  фон, без BoxShadow, светлые бордеры (`0xFFD3D6DC` idle / `0xFF3D2D6E`
  selected). AppBar без явного цвета (M3 default).
- Hero-render 180 px на pure white фоне — реалистичный дом с цветами
  материалов: кирпич терракотовый, газобетон серый, керамзит жёлтый,
  брус медовый, каркас бежевый. Кровля серо-коричневая металлочерепица
  с разделением скатов по освещению. Окна, гараж-пристройка, тень земли.
- Кнопка «Назад» в AppBar (явный IconButton + Navigator.maybePop).
- Toggle 2D/3D (план сверху vs аксонометрия).
- Бейджи «PRO» / «L/T/U», галочка выбранного шаблона.

### lib/widgets/hints.dart (§26.3)
- В `_HintAutoShowState.didChangeDependencies` добавлена защита от
  race-condition: `addPostFrameCallback` теперь проверяет
  `ModalRoute.of(context)?.isCurrent` перед `showHintDialog`. Раньше при
  быстром переходе с экрана-источника подсказка показывалась поверх
  каталога шаблонов и её ModalBarrier оставлял серую полупрозрачную
  плёнку.

### lib/pages/brief/brief_wizard_page.dart (§27.3)
- `_NumField._parse` (используется для footprintWidth/Length): после
  `tryParse` добавлен `clamp(0.0, 60.0)` — защита от 99999 м.
- `_AttachmentForm._setW`/`_setL`: `clamp(0.5, 30.0)`.
- `_AttachmentForm._setH`: `clamp(1.5, 6.0)`.

### lib/pages/footprint_editor_page.dart (§27.3)
- `_editVertex`: координаты `Vec2(x, y)` клампятся в `0..60 м`.

### Удалено как dead-code (§27.4)
- `lib/services/link_opener.dart`
- `lib/services/link_opener_stub.dart`
- `lib/services/link_opener_web.dart`
  (никогда не вызывались — `LinkOpener.open` нет ни одного caller-а).
- В `lib/services/pdf_builder.dart`: статические поля `_roomFill`,
  `_staircaseFill`, переменные `eaveLabelW`, `axesXPos`, методы
  `_estimateRidgeElevation`, `_estimateEaveElevation`.
- В `lib/services/pdf_catalog_card.dart`: метод `_articleNumber`.
- В `lib/services/material_volumes.dart`: переменная `floors`.
- В `lib/services/building3d_generator.dart`: `hasGarage`,
  `basementCeilingH`.

### Новые файлы / правки v68 backlog (§25)
- `lib/utils/polygon_helpers.dart` — Sutherland-Hodgman polygon clipping
  для CSG-операций (subject — любой simple-полигон, clip — convex).
- `lib/services/floor_plan_generator.dart` — `regenerateDrawings(autoFix:
  true)` теперь молчаливо откатывает мебель, перекрывающую дверные зоны.
- `lib/widgets/floor_plan_view.dart` — live-snap drag-vertex (CAD-стандарт).
- `lib/services/roof_skeleton.dart` — split-events: reflex-биссектриса
  клиппируется по противоположным рёбрам outline-а (Aichholzer 1995).

---

## 4. Согласованность данных по чертежам

Подтверждено, что параметры берутся из проекта (а не хардкод):

| Параметр                | Источник                 | Где используется |
|-------------------------|--------------------------|------------------|
| `brief.footprintWidth/Length` | `ClientBrief`        | АР-1, ПОЗУ, планы, ТЭП, фасады, разрезы |
| `brief.floors`          | `ClientBrief`            | placard, plans, sections, facades, engineering |
| `brief.wallMaterial`    | `ClientBrief`            | штриховка плана, заливка фасада, спец, КЖ-1 |
| `walls.height`          | `WallsDesign`            | facade, section, stairs, roof, attic |
| `walls.thickness`       | `WallsDesign`            | section, foundation plan, foundation section |
| `roof.type/slopeAngle/roofingMaterial` | `RoofDesign` | КД-2, фасад, кровля план, расчёт стропил |
| `foundation.type`       | `FoundationDesign`       | КЖ план, КЖ-2 сечение, ПЗ-ТР |
| `attachments` (гараж/терраса/балкон) | `FloorPlan.attachments` | ПОЗУ, план этажа, аксонометрия |
| `architectureFootprint.outline` | `HouseProject`   | план этажа, фасад, аксонометрия, ПОЗУ |

### Известные жёсткие значения (по дизайну, не баги)
- На планах этажей толщина наружной стены `_outerWall = 0.40 м`,
  внутренняя несущая `_innerWall = 0.25 м`. Это стандарт стадии АС
  (рабочие чертежи), не зависит от материала. На разрезах используется
  реальная `walls.thickness`.
- Условный размер участка по умолчанию 20 м: пользователю негде задать
  кадастровые габариты в брифе. При появлении такого поля — план будет
  автоматически использовать его.

---

## 5. Аудит безопасности (§27.4)

### Проверено и чисто
- **TODO/FIXME/XXX/HACK** — 0 совпадений в lib/.
- **UnimplementedError** — 0 случаев. `UnsupportedError` только в
  `file_download_stub.dart` для не-вебовых платформ (intentional).
- **API-ключи / пароли / OAuth-секреты в коде** — не найдены.
- **eval / Function.apply / js.context.callMethod** — не используются.
- **innerHTML / document.write** — не используются.
- **HTTP (insecure)** — все URL HTTPS.
- **Парсы пользовательского ввода** — везде `tryParse` (null-safe), не
  `parse` (throws).
- **`catch (_) {}`** — только 2 случая в `tryDecode` (FloorPlan,
  OrganizationSettings) — intentional swallowing JSON-parse errors.

### Auth
- Auth API base URL: `https://89-169-141-69.sslip.io` через
  `--dart-define=AUTH_API_BASE_URL` (можно переопределить при билде).
  Сертификат через Caddy + sslip.io валидный.
- JWT хранится в SharedPreferences (web → localStorage). Известный
  trade-off SPA: уязвимо к XSS, но XSS у нас нет (Flutter рендерит через
  canvas без HTML-инъекций).
- Пароль: минимум 8 символов, подтверждение в отдельном поле.
- 401 → автоматический logout. Оптимистичный кеш только если сеть
  недоступна.

### Validation hardening (§27.3)
- Все числовые поля в брифе имеют `FilteringTextInputFormatter` (только
  цифры/запятая/точка/минус) + новые клампы на физически осмысленные
  диапазоны.

### Известные ограничения
- **CSP-заголовок не установлен** в index.html. Flutter Web использует
  CanvasKit + WASM с inline-скриптами — строгая CSP ломает рантайм.
- **Service worker** автогенерится Flutter, без кастомных fetch-перехватов.
- **Optimistic offline auth** в bootstrap() — если сервер не отвечает,
  юзер остаётся залогиненным из локального кеша. UX-фича, требует XSS
  для эксплойта.

---

## 6. Бэклог (что не закрыто)

### Низкий приоритет
- **CSP-заголовок** для index.html (нужен careful-список разрешённых
  script-src/connect-src + тестирование, что Flutter не сломается).
- **Миграция JWT в httpOnly-cookie** (требует cookie-based auth на
  бэкенде, средние правки).
- **Шифрование local storage** (через `flutter_secure_storage` —
  mobile-only пока что; web-аналог пишет в IndexedDB без real шифрования).

### Большие инициативы (см. §В из v67-сессии)
- **№5** — Версионирование проектов (история изменений).
- **№9** — Дальнейшая декомпозиция `pdf_builder.dart` (8911 строк → пока
  вынесли pdf_builder_materials.dart на 704 строки; следом на очереди
  разделы фундамент/кровля/фасад).
- **№12** — Смета (КС-2/КС-3) с реальными ценами ФССЦ-2020.
- **№13** — Геопривязка участка через Росреестр API.

### Косметика (§24.7 из v67 не до конца закрыто)
- **Аксонометрия 3D**: пользователь жаловался на «прозрачные текстуры»
  в v67. Code-review показал alpha=1 везде; гипотеза — у пользователя
  активен grayscale-фильтр (Win+Ctrl+C / macOS Accessibility / Chrome
  extension), который десатурирует текстуры. После выключения фильтра
  материалы должны быть видны корректно.

---

## 7. Команды для следующей сессии

```bash
# Распаковать и поставить зависимости
tar -xzf konstruktor_stroenii_v68.tar.gz
cd konstruktor_stroenii_v68
flutter pub get
(cd packages/cc_engine && dart pub get)

# Качество
flutter analyze                                # 0 issues
flutter test                                   # 133 / 133 passed
(cd packages/cc_engine && dart test)           # 5 / 5 passed
flutter build web --release --no-tree-shake-icons --base-href /

# Деплой (нужны S3 credentials, см. yc-secrets)
PROJECT_DIR="$PWD" SKIP_BUILD=1 bash ~/scripts/deploy.sh

# Проверка
curl -sI https://konstruktor-stroenii.ru/      # HTTP 200
```

---

## 8. Карта файлов (что важно для следующей сессии)

```
lib/
├── data/
│   └── floor_plan_templates.dart       # библиотека шаблонов (basic + extended)
├── models/
│   ├── building_footprint.dart         # L/T/U/+ полигоны пятна
│   ├── client_brief.dart               # бриф (footprint, floors, material, ...)
│   ├── floor_plan.dart                 # план этажа (комнаты, проёмы, attachments)
│   ├── house_project.dart              # корневая модель + architectureFootprint
│   ├── foundation/walls/roof/...       # инженерные модели
│   └── auth.dart                       # auth модели (User, LoginResult, ...)
├── pages/
│   ├── home_page.dart                  # стартовая (типы строений)
│   ├── floor_plan_templates_page.dart  # каталог шаблонов (§26)
│   ├── footprint_editor_page.dart      # редактор пятна (live-snap, vertex)
│   ├── brief/brief_wizard_page.dart    # бриф-визард (5 шагов)
│   ├── login_page.dart                 # экран логина
│   ├── change_password_page.dart       # принудительная смена пароля
│   ├── admin_users_page.dart           # админка пользователей
│   └── ...                             # walls/roof/foundation/staircase/...
├── services/
│   ├── pdf_builder.dart                # 8911 строк, главный PDF-сборщик
│   ├── pdf_builder_materials.dart      # текстуры стен/кровли (§9 v43)
│   ├── pdf_site_plan.dart              # АР-0а Схема ПОЗУ (§27.1)
│   ├── pdf_general_data.dart           # АР-1..АР-4 общие данные
│   ├── pdf_additional_plans.dart       # перегородки, полы, кровля
│   ├── pdf_a1_placard.dart             # А1-плакат с метриками
│   ├── pdf_catalog_card.dart           # АР-0 каталожная карточка
│   ├── building3d_generator.dart       # 3D рендер для аксонометрии
│   ├── floor_plan_generator.dart       # генератор планов комнат
│   ├── roof_skeleton.dart              # straight-skeleton (§25.3)
│   ├── auth_api.dart                   # HTTP-клиент Auth
│   └── ...
├── state/
│   ├── app_state.dart                  # ChangeNotifier (проекты, hints, ...)
│   └── auth_state.dart                 # JWT, user, signedIn
├── storage/
│   ├── project_repository.dart         # SharedPreferences + миграции
│   ├── project_migrations.dart         # схема v1 → v2 → ...
│   └── settings_repository.dart        # тёмная/светлая тема, организация
├── utils/
│   └── polygon_helpers.dart            # Sutherland-Hodgman CSG (§25.4)
└── widgets/
    ├── floor_plan_view.dart            # FloorPlanView с live-drag (§25.2)
    ├── hints.dart                      # HintAutoShow + ModalRoute guard (§26.3)
    └── synced_slider_field.dart        # числовое поле + слайдер
packages/cc_engine/                     # pure Dart расчётный движок
```
