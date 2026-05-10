// Phase-3b §17.2.2: каталог из 12 типовых архетипов планировок частного
// дома. Каждый архетип — это пресет полей `ClientBrief` (этажность,
// габариты, состав комнат, доп-флаги, материал стен и т.д.) плюс
// опциональный полигональный footprint (для L/T/U-форм).
//
// Пользователь выбирает шаблон ИЗ КАТАЛОГА на старте проекта; пресет
// разворачивается в брифе, который дальше можно подкручивать в
// 6-шаговом мастере «Этап 1». Каталог намеренно фиксирован — это
// галерея «частых» архетипов, а не редактор: на L/T/U-формы мы
// выходим только через пресеты или (в следующем слайсе) UI-редактор
// контура.
//
// Все 12 шаблонов соответствуют сценариям, регулярно встречающимся в
// российской частной застройке (СП 55.13330.2017): эконом, типовой,
// семейный, 2-этажный, с мансардой, с подвалом, с гаражом, L-форма,
// для пенсионеров и т.д.

import '../models/building_footprint.dart' show BuildingFootprint, Vec2;
import '../models/client_brief.dart';
import 'rooms_catalog.dart';
import 'wall_materials.dart';

/// Один архетип планировки.
///
/// Поля, помеченные `null`, не переопределяют значения брифа при
/// применении пресета (`applyTo`). Пресет «не знает» все возможные
/// настройки — только базовые целевые параметры.
class FloorPlanTemplate {
  /// Стабильный идентификатор шаблона (используется как ключ в UI и
  /// сериализации). Изменять нельзя — сломает сохранённые проекты,
  /// у которых лежит ссылка на шаблон.
  final String id;

  /// Короткое название для карточки каталога (~ 30 символов).
  final String title;

  /// Подзаголовок: целевая аудитория или сценарий («Эконом для дачи»,
  /// «Семья 4 + кабинет», «Усадьба с гаражом» и т.п.).
  final String tagline;

  /// 1–2 строки описания, что внутри (для tooltip / детальной карточки).
  final String description;

  /// Целевая ширина и длина пятна, м.
  final double footprintWidth;
  final double footprintLength;

  /// Этажность: 1, 2 или 3.
  final int floors;

  /// Доп-конструкции.
  final bool hasMansard;
  final bool hasBasement;
  final bool hasGarage;
  final bool hasTerrace;

  /// Состав комнат, ключ — `RoomKind.name`, значение — количество.
  final Map<RoomKind, int> rooms;

  /// Базовый материал стен (можно переопределить в Этапе 2).
  final WallMaterial wallMaterial;

  /// Опциональный полигональный footprint. Если задан, проект
  /// открывается с L/T/U-формой; иначе — прямоугольник
  /// `footprintWidth × footprintLength`.
  final BuildingFootprint? footprint;

  /// Целевая общая площадь, м² (приблизительно — ориентировочное
  /// значение для подбора состава комнат).
  final double? targetArea;

  const FloorPlanTemplate({
    required this.id,
    required this.title,
    required this.tagline,
    required this.description,
    required this.footprintWidth,
    required this.footprintLength,
    required this.floors,
    required this.rooms,
    this.hasMansard = false,
    this.hasBasement = false,
    this.hasGarage = false,
    this.hasTerrace = false,
    this.wallMaterial = WallMaterial.aerated,
    this.footprint,
    this.targetArea,
  });

  /// Применяет пресет к существующему [ClientBrief]. Перезаписывает
  /// только те поля, которые шаблон явно задаёт; всё остальное
  /// (грунты, регион, особые пожелания) сохраняется.
  void applyTo(ClientBrief brief) {
    brief.floors = floors;
    brief.hasMansard = hasMansard;
    brief.hasBasement = hasBasement;
    brief.hasGarage = hasGarage;
    brief.hasTerrace = hasTerrace;
    brief.footprintWidth = footprintWidth;
    brief.footprintLength = footprintLength;
    brief.targetArea = targetArea;
    brief.wallMaterial = wallMaterial;
    brief.rooms.clear();
    rooms.forEach((kind, n) => brief.rooms[kind.name] = n);
  }
}

/// Библиотека из 12 готовых архетипов.
class FloorPlanTemplateLibrary {
  /// Шаблоны, отсортированные по «возрастанию сложности» — от эконом
  /// до усадьбы. Порядок важен для UI-каталога.
  static final List<FloorPlanTemplate> all = [
    // ── 1. ЭКОНОМ ────────────────────────────────────────────────
    FloorPlanTemplate(
      id: 'econom-6x8',
      title: 'Эконом 6×8',
      tagline: 'Дача / летний дом',
      description: '1 этаж, 1 спальня, кухня-столовая, санузел. '
          'Минимальный комплект для сезонного проживания.',
      footprintWidth: 6,
      footprintLength: 8,
      floors: 1,
      targetArea: 48,
      rooms: {
        RoomKind.bedroom: 1,
        RoomKind.kitchen: 1,
        RoomKind.bathroom: 1,
        RoomKind.livingRoom: 1,
        RoomKind.hallway: 1,
      },
      wallMaterial: WallMaterial.timber,
    ),
    // ── 2. ТИПОВОЙ ОДНОЭТАЖНЫЙ ───────────────────────────────────
    FloorPlanTemplate(
      id: 'typical-8x10',
      title: 'Типовой 8×10',
      tagline: 'Семья 3–4 чел., один уровень',
      description: '1 этаж, 2 спальни, гостиная, кухня, санузел, '
          'котельная. Пятно ~80 м² — самый частый вариант для ИЖС.',
      footprintWidth: 8,
      footprintLength: 10,
      floors: 1,
      targetArea: 80,
      rooms: {
        RoomKind.bedroom: 2,
        RoomKind.kitchen: 1,
        RoomKind.livingRoom: 1,
        RoomKind.bathroom: 1,
        RoomKind.boilerRoom: 1,
        RoomKind.hallway: 1,
      },
    ),
    // ── 3. СЕМЕЙНЫЙ ОДНОЭТАЖНЫЙ ──────────────────────────────────
    FloorPlanTemplate(
      id: 'family-10x10',
      title: 'Семейный 10×10',
      tagline: 'Семья 4–5 чел. + кабинет',
      description: '1 этаж, 3 спальни (включая детскую), 2 санузла, '
          'просторная гостиная, кабинет, котельная.',
      footprintWidth: 10,
      footprintLength: 10,
      floors: 1,
      targetArea: 100,
      rooms: {
        RoomKind.bedroom: 2,
        RoomKind.kidsRoom: 1,
        RoomKind.kitchen: 1,
        RoomKind.livingRoom: 1,
        RoomKind.study: 1,
        RoomKind.bathroom: 2,
        RoomKind.boilerRoom: 1,
        RoomKind.hallway: 1,
      },
    ),
    // ── 4. ДВУХЭТАЖНЫЙ КОМПАКТНЫЙ ───────────────────────────────
    FloorPlanTemplate(
      id: 'compact-2-storey-7x9',
      title: 'Компактный 2-эт. 7×9',
      tagline: 'Молодая семья, узкий участок',
      description: '2 этажа, кухня-гостиная и санузел внизу, '
          '2 спальни и санузел наверху.',
      footprintWidth: 7,
      footprintLength: 9,
      floors: 2,
      targetArea: 110,
      rooms: {
        RoomKind.bedroom: 2,
        RoomKind.kitchenDining: 1,
        RoomKind.livingRoom: 1,
        RoomKind.bathroom: 2,
        RoomKind.boilerRoom: 1,
        RoomKind.hallway: 1,
      },
    ),
    // ── 5. ТИПОВОЙ ДВУХЭТАЖНЫЙ ──────────────────────────────────
    FloorPlanTemplate(
      id: 'typical-2-storey-8x10',
      title: 'Типовой 2-эт. 8×10',
      tagline: 'Семья 4–5 чел. на двух уровнях',
      description: '2 этажа: гостиная + кухня + санузел внизу, '
          '3 спальни + санузел + гардеробная наверху.',
      footprintWidth: 8,
      footprintLength: 10,
      floors: 2,
      targetArea: 150,
      rooms: {
        RoomKind.bedroom: 2,
        RoomKind.kidsRoom: 1,
        RoomKind.kitchen: 1,
        RoomKind.livingRoom: 1,
        RoomKind.bathroom: 2,
        RoomKind.wardrobe: 1,
        RoomKind.boilerRoom: 1,
        RoomKind.hallway: 1,
      },
    ),
    // ── 6. УСАДЬБА С ГАРАЖОМ ─────────────────────────────────────
    FloorPlanTemplate(
      id: 'estate-with-garage-10x12',
      title: 'Усадьба 10×12 с гаражом',
      tagline: 'Семья 5 + 1 машина',
      description: '2 этажа + встроенный гараж, 4 спальни, кабинет, '
          '3 санузла, гостиная, кухня-столовая.',
      footprintWidth: 10,
      footprintLength: 12,
      floors: 2,
      hasGarage: true,
      targetArea: 200,
      rooms: {
        RoomKind.bedroom: 3,
        RoomKind.kidsRoom: 1,
        RoomKind.kitchenDining: 1,
        RoomKind.livingRoom: 1,
        RoomKind.study: 1,
        RoomKind.bathroom: 3,
        RoomKind.wardrobe: 1,
        RoomKind.boilerRoom: 1,
        RoomKind.hallway: 1,
      },
      wallMaterial: WallMaterial.brick,
    ),
    // ── 7. С МАНСАРДОЙ ───────────────────────────────────────────
    FloorPlanTemplate(
      id: 'mansard-8x10',
      title: 'С мансардой 8×10',
      tagline: '1 этаж + жилой чердак',
      description: '1 этаж: гостиная + кухня + санузел; мансарда: '
          '2 спальни и санузел. Экономит фундамент.',
      footprintWidth: 8,
      footprintLength: 10,
      floors: 1,
      hasMansard: true,
      targetArea: 130,
      rooms: {
        RoomKind.bedroom: 2,
        RoomKind.kitchen: 1,
        RoomKind.livingRoom: 1,
        RoomKind.bathroom: 2,
        RoomKind.boilerRoom: 1,
        RoomKind.hallway: 1,
      },
    ),
    // ── 8. С ПОДВАЛОМ ────────────────────────────────────────────
    FloorPlanTemplate(
      id: 'basement-8x10',
      title: 'С подвалом 8×10',
      tagline: '1 эт. + подвал (мастерская/котельная)',
      description: 'Подвал для котельной/кладовой, 1 этаж жилой: '
          '2 спальни + гостиная + кухня + санузел.',
      footprintWidth: 8,
      footprintLength: 10,
      floors: 1,
      hasBasement: true,
      targetArea: 80,
      rooms: {
        RoomKind.bedroom: 2,
        RoomKind.kitchen: 1,
        RoomKind.livingRoom: 1,
        RoomKind.bathroom: 1,
        RoomKind.boilerRoom: 1,
        RoomKind.storage: 1,
        RoomKind.hallway: 1,
      },
    ),
    // ── 9. ОДНОЭТАЖНЫЙ С ГАРАЖОМ ─────────────────────────────────
    FloorPlanTemplate(
      id: 'one-storey-garage-10x8',
      title: 'Одноэтажный с гаражом 10×8',
      tagline: 'Без лестницы + 1 машина',
      description: '1 этаж + встроенный гараж, 2 спальни, кухня-'
          'гостиная, санузел, котельная.',
      footprintWidth: 10,
      footprintLength: 8,
      floors: 1,
      hasGarage: true,
      targetArea: 80,
      rooms: {
        RoomKind.bedroom: 2,
        RoomKind.kitchenDining: 1,
        RoomKind.livingRoom: 1,
        RoomKind.bathroom: 1,
        RoomKind.boilerRoom: 1,
        RoomKind.hallway: 1,
      },
    ),
    // ── 10. L-ФОРМА 1 ЭТ. ────────────────────────────────────────
    _lShape1Storey,
    // ── 11. L-ФОРМА 2 ЭТ. С ГАРАЖОМ ──────────────────────────────
    _lShape2StoreyGarage,
    // ── 12. ДЛЯ ПЕНСИОНЕРОВ ──────────────────────────────────────
    FloorPlanTemplate(
      id: 'seniors-12x8',
      title: 'Для пенсионеров 12×8',
      tagline: '1 эт., низкий порог, без лестниц',
      description: 'Один уровень, широкие проходы, минимум порогов; '
          '1 спальня, большая гостиная-столовая, кухня, 2 санузла, '
          'постирочная.',
      footprintWidth: 12,
      footprintLength: 8,
      floors: 1,
      targetArea: 96,
      rooms: {
        RoomKind.bedroom: 1,
        RoomKind.kitchen: 1,
        RoomKind.livingRoom: 1,
        RoomKind.dining: 1,
        RoomKind.bathroom: 2,
        RoomKind.laundry: 1,
        RoomKind.boilerRoom: 1,
        RoomKind.hallway: 1,
      },
    ),
  ];

  /// L-форма 10×10 с вырезом 4×4. Один этаж, 3 спальни.
  static final FloorPlanTemplate _lShape1Storey = FloorPlanTemplate(
    id: 'l-shape-1-storey-10x10',
    title: 'L-форма 10×10',
    tagline: 'Уступ для террасы / двора',
    description: '1 этаж в форме буквы Г: вырез 4×4 формирует '
        'террасу или защищённый внутренний двор. 3 спальни, '
        'гостиная, кухня, 2 санузла.',
    footprintWidth: 10,
    footprintLength: 10,
    floors: 1,
    targetArea: 84,
    rooms: const {
      RoomKind.bedroom: 2,
      RoomKind.kidsRoom: 1,
      RoomKind.kitchen: 1,
      RoomKind.livingRoom: 1,
      RoomKind.bathroom: 2,
      RoomKind.boilerRoom: 1,
      RoomKind.hallway: 1,
    },
    footprint: BuildingFootprint.lShape(
      width: 10,
      height: 10,
      cutWidth: 4,
      cutHeight: 4,
    ),
  );

  /// L-форма 12×10 с вырезом 5×4. Два этажа, гараж в выступе.
  static final FloorPlanTemplate _lShape2StoreyGarage = FloorPlanTemplate(
    id: 'l-shape-2-storey-12x10',
    title: 'L-форма 12×10 с гаражом',
    tagline: '2 эт., гараж в выступе',
    description: '2 этажа в форме буквы Г: гараж в коротком крыле, '
        'жилая часть — в длинном. 4 спальни, кабинет.',
    footprintWidth: 12,
    footprintLength: 10,
    floors: 2,
    hasGarage: true,
    targetArea: 180,
    rooms: const {
      RoomKind.bedroom: 3,
      RoomKind.kidsRoom: 1,
      RoomKind.kitchenDining: 1,
      RoomKind.livingRoom: 1,
      RoomKind.study: 1,
      RoomKind.bathroom: 2,
      RoomKind.boilerRoom: 1,
      RoomKind.hallway: 1,
    },
    footprint: BuildingFootprint.lShape(
      width: 12,
      height: 10,
      cutWidth: 5,
      cutHeight: 4,
    ),
    wallMaterial: WallMaterial.brick,
  );

  /// Поиск шаблона по `id` — ищет и в `all`, и в `extended` (§21.4).
  /// Возвращает `null`, если не найден.
  static FloorPlanTemplate? findById(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    for (final t in extended) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// §21.4 — расширенный каталог «VIP / спец-проекты». Эти шаблоны
  /// НЕ показываются в основной странице каталога (там по правилу
  /// §17.3 — ровно 12 базовых архетипов), но доступны через
  /// «Расширенный каталог» в меню. Здесь живут T/U/+ формы, большие
  /// усадьбы, узкие участки и т.п. — экзотика, нужная меньшинству
  /// проектов.
  static final List<FloorPlanTemplate> extended = [
    _tShapeFamily,
    _uShapeAtrium,
    _plusShapeFlagship,
    _narrowLot6x14,
    _wideLot16x8,
    _twoStoreyEstate12x12,
    _bungalowMansardWithGarage,
  ];

  // ── T-форма ─────────────────────────────────────────────────────
  static final FloorPlanTemplate _tShapeFamily = FloorPlanTemplate(
    id: 't-shape-family-12x10',
    title: 'T-форма 12×10',
    tagline: 'Семейный + терраса в крыльях',
    description: '1 этаж в форме буквы T: широкая верхняя часть '
        '(гостиная + кухня) и узкий выступ снизу (спальни). '
        'Естественные террасы в углах буквы.',
    footprintWidth: 12,
    footprintLength: 10,
    floors: 1,
    targetArea: 96,
    rooms: const {
      RoomKind.bedroom: 2,
      RoomKind.kidsRoom: 1,
      RoomKind.kitchen: 1,
      RoomKind.livingRoom: 1,
      RoomKind.bathroom: 2,
      RoomKind.boilerRoom: 1,
      RoomKind.hallway: 1,
    },
    footprint: BuildingFootprint.tShape(
      width: 12,
      height: 10,
      stemWidth: 4,
      stemHeight: 4,
    ),
    wallMaterial: WallMaterial.aerated,
  );

  // ── U-форма с внутренним атриумом ───────────────────────────────
  static final FloorPlanTemplate _uShapeAtrium = FloorPlanTemplate(
    id: 'u-shape-atrium-12x10',
    title: 'U-форма с атриумом 12×10',
    tagline: 'Внутренний двор / зона отдыха',
    description: 'Дом-«подкова»: внутренний двор 4×4 защищён с трёх '
        'сторон. Идея — патио, бассейн, изолированная зона отдыха.',
    footprintWidth: 12,
    footprintLength: 10,
    floors: 1,
    targetArea: 104,
    rooms: const {
      RoomKind.bedroom: 3,
      RoomKind.kitchen: 1,
      RoomKind.livingRoom: 1,
      RoomKind.bathroom: 2,
      RoomKind.boilerRoom: 1,
      RoomKind.hallway: 1,
    },
    footprint: BuildingFootprint.uShape(
      width: 12,
      height: 10,
      cutWidth: 4,
      cutHeight: 4,
    ),
    wallMaterial: WallMaterial.brick,
  );

  // ── +-форма (крест) ─────────────────────────────────────────────
  static final FloorPlanTemplate _plusShapeFlagship = FloorPlanTemplate(
    id: 'plus-shape-flagship-14x14',
    title: '+-форма 14×14 (флагман)',
    tagline: '4 крыла, открытая планировка',
    description: 'Крестовидное пятно с 4 одинаковыми крыльями, '
        'центральная зона — гостиная-кухня-столовая. Лучшая '
        'инсоляция всех комнат, террасы во внутренних углах.',
    footprintWidth: 14,
    footprintLength: 14,
    floors: 2,
    targetArea: 240,
    hasGarage: true,
    rooms: const {
      RoomKind.bedroom: 4,
      RoomKind.kidsRoom: 1,
      RoomKind.kitchen: 1,
      RoomKind.livingRoom: 1,
      RoomKind.dining: 1,
      RoomKind.study: 1,
      RoomKind.bathroom: 3,
      RoomKind.wardrobe: 1,
      RoomKind.boilerRoom: 1,
      RoomKind.hallway: 1,
    },
    footprint: _plusShape14x14,
    wallMaterial: WallMaterial.brick,
  );

  // ── Узкий участок 6×14 ──────────────────────────────────────────
  static final FloorPlanTemplate _narrowLot6x14 = FloorPlanTemplate(
    id: 'narrow-6x14',
    title: 'Узкий 6×14',
    tagline: 'Длинный участок, в линию',
    description: '1 этаж, узкое пятно 6 м, 3 спальни вдоль длинной '
        'стены, гостиная и кухня в торце.',
    footprintWidth: 6,
    footprintLength: 14,
    floors: 1,
    targetArea: 84,
    rooms: const {
      RoomKind.bedroom: 3,
      RoomKind.kitchen: 1,
      RoomKind.livingRoom: 1,
      RoomKind.bathroom: 1,
      RoomKind.boilerRoom: 1,
      RoomKind.hallway: 1,
    },
  );

  // ── Широкий участок 16×8 ────────────────────────────────────────
  static final FloorPlanTemplate _wideLot16x8 = FloorPlanTemplate(
    id: 'wide-16x8',
    title: 'Широкий 16×8',
    tagline: 'Поперёк участка',
    description: '1 этаж, длинный фасад 16 м, удобно для большой '
        'террасы во всю длину дома, 3 спальни.',
    footprintWidth: 16,
    footprintLength: 8,
    floors: 1,
    hasTerrace: true,
    targetArea: 128,
    rooms: const {
      RoomKind.bedroom: 3,
      RoomKind.kitchenDining: 1,
      RoomKind.livingRoom: 1,
      RoomKind.bathroom: 2,
      RoomKind.boilerRoom: 1,
      RoomKind.hallway: 1,
    },
  );

  // ── 2-этажная усадьба 12×12 ─────────────────────────────────────
  static final FloorPlanTemplate _twoStoreyEstate12x12 = FloorPlanTemplate(
    id: 'estate-2-storey-12x12',
    title: 'Усадьба 12×12',
    tagline: 'Большая семья, кабинет, терраса',
    description: '2 этажа, 4 спальни, кабинет, гардеробная, 3 '
        'санузла, кухня-столовая 25 м², гостиная 30 м².',
    footprintWidth: 12,
    footprintLength: 12,
    floors: 2,
    targetArea: 250,
    hasTerrace: true,
    rooms: const {
      RoomKind.bedroom: 3,
      RoomKind.kidsRoom: 1,
      RoomKind.kitchenDining: 1,
      RoomKind.livingRoom: 1,
      RoomKind.study: 1,
      RoomKind.bathroom: 3,
      RoomKind.wardrobe: 1,
      RoomKind.boilerRoom: 1,
      RoomKind.hallway: 1,
    },
    wallMaterial: WallMaterial.brick,
  );

  // ── Бунгало с мансардой и гаражом ───────────────────────────────
  static final FloorPlanTemplate _bungalowMansardWithGarage =
      FloorPlanTemplate(
    id: 'bungalow-mansard-garage-10x10',
    title: 'Бунгало 10×10 + мансарда + гараж',
    tagline: 'Компромисс: дёшевле 2 этажей',
    description: '1 этаж + жилая мансарда + встроенный гараж. '
        'Экономит на фундаменте и стенах по сравнению с 2-этажным.',
    footprintWidth: 10,
    footprintLength: 10,
    floors: 1,
    hasMansard: true,
    hasGarage: true,
    targetArea: 160,
    rooms: const {
      RoomKind.bedroom: 3,
      RoomKind.kidsRoom: 1,
      RoomKind.kitchenDining: 1,
      RoomKind.livingRoom: 1,
      RoomKind.bathroom: 2,
      RoomKind.boilerRoom: 1,
      RoomKind.hallway: 1,
    },
    wallMaterial: WallMaterial.aerated,
  );

  /// Полигон в форме «+» 14×14 с крыльями 4×4 на каждой стороне.
  /// Создаём вручную, потому что в [BuildingFootprint] нет фабрики
  /// `plusShape`; см. также `BuildingFootprint.uShape`/`tShape`.
  static BuildingFootprint get _plusShape14x14 {
    // Центральный квадрат 6×6 (от 4 до 10 по обеим осям) +
    // 4 крыла 4×4: верхнее (4..10, 0..4), нижнее (4..10, 10..14),
    // левое (0..4, 4..10), правое (10..14, 4..10).
    return BuildingFootprint(outline: const [
      Vec2(4, 0),
      Vec2(10, 0),
      Vec2(10, 4),
      Vec2(14, 4),
      Vec2(14, 10),
      Vec2(10, 10),
      Vec2(10, 14),
      Vec2(4, 14),
      Vec2(4, 10),
      Vec2(0, 10),
      Vec2(0, 4),
      Vec2(4, 4),
    ]);
  }
}
