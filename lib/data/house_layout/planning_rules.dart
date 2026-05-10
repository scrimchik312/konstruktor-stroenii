/// Правила планировки частных домов — самодостаточная копия модуля.
library;

import 'dart:math' as math;

// ---------------------------------------------------------------------------
// §1. Площади комнат
// ---------------------------------------------------------------------------

class RoomAreaStandard {
  final double minArea;
  final double recommendedArea;
  final double maxArea;
  final double minWidth;
  final double minHeight;

  const RoomAreaStandard({
    required this.minArea,
    required this.recommendedArea,
    required this.maxArea,
    required this.minWidth,
    this.minHeight = 2.5,
  });
}

const Map<String, RoomAreaStandard> kRoomAreaStandards = {
  'bedroom': RoomAreaStandard(minArea: 8, recommendedArea: 14, maxArea: 25, minWidth: 2.4),
  'masterBedroom': RoomAreaStandard(minArea: 12, recommendedArea: 18, maxArea: 35, minWidth: 3.0),
  'kidsRoom': RoomAreaStandard(minArea: 8, recommendedArea: 12, maxArea: 20, minWidth: 2.4),
  'bathroom': RoomAreaStandard(minArea: 2.5, recommendedArea: 5, maxArea: 15, minWidth: 1.5),
  'masterBathroom': RoomAreaStandard(minArea: 5, recommendedArea: 8, maxArea: 20, minWidth: 2.0),
  'toilet': RoomAreaStandard(minArea: 1.2, recommendedArea: 2, maxArea: 4, minWidth: 0.8),
  'kitchen': RoomAreaStandard(minArea: 6, recommendedArea: 12, maxArea: 25, minWidth: 2.1),
  'kitchenDining': RoomAreaStandard(minArea: 12, recommendedArea: 20, maxArea: 40, minWidth: 3.0),
  'livingRoom': RoomAreaStandard(minArea: 12, recommendedArea: 25, maxArea: 60, minWidth: 3.0),
  'dining': RoomAreaStandard(minArea: 8, recommendedArea: 14, maxArea: 30, minWidth: 2.4),
  'study': RoomAreaStandard(minArea: 6, recommendedArea: 12, maxArea: 25, minWidth: 2.1),
  'hallway': RoomAreaStandard(minArea: 3, recommendedArea: 8, maxArea: 20, minWidth: 1.4),
  'boilerRoom': RoomAreaStandard(minArea: 4, recommendedArea: 6, maxArea: 15, minWidth: 1.5),
  'storage': RoomAreaStandard(minArea: 1.5, recommendedArea: 4, maxArea: 10, minWidth: 1.0),
  'wardrobe': RoomAreaStandard(minArea: 2, recommendedArea: 4, maxArea: 10, minWidth: 1.2),
  'laundry': RoomAreaStandard(minArea: 3, recommendedArea: 5, maxArea: 10, minWidth: 1.5),
  'garage': RoomAreaStandard(minArea: 18, recommendedArea: 24, maxArea: 60, minWidth: 3.0),
  'terrace': RoomAreaStandard(minArea: 6, recommendedArea: 15, maxArea: 50, minWidth: 2.0),
  'balcony': RoomAreaStandard(minArea: 2, recommendedArea: 5, maxArea: 15, minWidth: 1.0),
  'pantry': RoomAreaStandard(minArea: 1, recommendedArea: 3, maxArea: 8, minWidth: 0.9),
  'technical': RoomAreaStandard(minArea: 3, recommendedArea: 5, maxArea: 12, minWidth: 1.5),
  'corridor': RoomAreaStandard(minArea: 3, recommendedArea: 6, maxArea: 15, minWidth: 0.9),
};

// ---------------------------------------------------------------------------
// §2. Смежность
// ---------------------------------------------------------------------------

enum AdjacencyType { required, recommended, forbidden, undesirable }

class AdjacencyRule {
  final String roomA;
  final String roomB;
  final AdjacencyType type;
  final String reason;
  const AdjacencyRule({required this.roomA, required this.roomB, required this.type, required this.reason});
}

const List<AdjacencyRule> kAdjacencyRules = [
  AdjacencyRule(roomA: 'kitchen', roomB: 'dining', type: AdjacencyType.required, reason: 'Кухня и столовая — единая зона'),
  AdjacencyRule(roomA: 'masterBedroom', roomB: 'masterBathroom', type: AdjacencyType.required, reason: 'Мастер-спальня + свой санузел'),
  AdjacencyRule(roomA: 'garage', roomB: 'hallway', type: AdjacencyType.required, reason: 'Гараж — вход через прихожую'),
  AdjacencyRule(roomA: 'kitchen', roomB: 'livingRoom', type: AdjacencyType.recommended, reason: 'Удобство при приёме гостей'),
  AdjacencyRule(roomA: 'hallway', roomB: 'toilet', type: AdjacencyType.recommended, reason: 'Гостевой санузел у входа'),
  AdjacencyRule(roomA: 'wardrobe', roomB: 'bedroom', type: AdjacencyType.recommended, reason: 'Гардеробная рядом со спальней'),
  AdjacencyRule(roomA: 'pantry', roomB: 'kitchen', type: AdjacencyType.recommended, reason: 'Кладовая рядом с кухней'),
  AdjacencyRule(roomA: 'livingRoom', roomB: 'terrace', type: AdjacencyType.recommended, reason: 'Выход на террасу'),
  AdjacencyRule(roomA: 'bathroom', roomB: 'kitchen', type: AdjacencyType.forbidden, reason: 'СП 54.13330: запрет'),
  AdjacencyRule(roomA: 'boilerRoom', roomB: 'bedroom', type: AdjacencyType.forbidden, reason: 'Шум и вибрация'),
  AdjacencyRule(roomA: 'garage', roomB: 'bedroom', type: AdjacencyType.forbidden, reason: 'Запахи и шум'),
  AdjacencyRule(roomA: 'garage', roomB: 'kitchen', type: AdjacencyType.forbidden, reason: 'Выхлопные газы'),
  AdjacencyRule(roomA: 'bedroom', roomB: 'bedroom', type: AdjacencyType.undesirable, reason: 'Звукоизоляция'),
  AdjacencyRule(roomA: 'boilerRoom', roomB: 'livingRoom', type: AdjacencyType.undesirable, reason: 'Шум котельной'),
];

// ---------------------------------------------------------------------------
// §3. Зонирование
// ---------------------------------------------------------------------------

enum HouseZone { public, private, service, sanitary, transition }

const Map<String, HouseZone> kRoomZones = {
  'livingRoom': HouseZone.public, 'kitchen': HouseZone.public,
  'kitchenDining': HouseZone.public, 'dining': HouseZone.public,
  'hallway': HouseZone.transition, 'corridor': HouseZone.transition,
  'bedroom': HouseZone.private, 'masterBedroom': HouseZone.private,
  'kidsRoom': HouseZone.private, 'study': HouseZone.private,
  'wardrobe': HouseZone.private,
  'bathroom': HouseZone.sanitary, 'masterBathroom': HouseZone.sanitary,
  'toilet': HouseZone.sanitary,
  'boilerRoom': HouseZone.service, 'storage': HouseZone.service,
  'pantry': HouseZone.service, 'laundry': HouseZone.service,
  'technical': HouseZone.service, 'garage': HouseZone.service,
  'terrace': HouseZone.public, 'balcony': HouseZone.private,
};

// ---------------------------------------------------------------------------
// §4. Категории домов
// ---------------------------------------------------------------------------

enum HouseSizeCategory { micro, compact, standard, comfort, large, estate }

HouseSizeCategory houseSizeCategory(double totalAreaM2) {
  if (totalAreaM2 < 60) return HouseSizeCategory.micro;
  if (totalAreaM2 < 100) return HouseSizeCategory.compact;
  if (totalAreaM2 < 150) return HouseSizeCategory.standard;
  if (totalAreaM2 < 250) return HouseSizeCategory.comfort;
  if (totalAreaM2 < 400) return HouseSizeCategory.large;
  return HouseSizeCategory.estate;
}

const Map<HouseSizeCategory, Map<String, int>> kRecommendedRoomsBySize = {
  HouseSizeCategory.micro: {'livingRoom': 1, 'bedroom': 1, 'kitchen': 1, 'bathroom': 1, 'hallway': 1},
  HouseSizeCategory.compact: {'livingRoom': 1, 'bedroom': 2, 'kitchen': 1, 'bathroom': 1, 'hallway': 1, 'boilerRoom': 1},
  HouseSizeCategory.standard: {'livingRoom': 1, 'bedroom': 3, 'kitchen': 1, 'bathroom': 2, 'hallway': 1, 'boilerRoom': 1, 'storage': 1},
  HouseSizeCategory.comfort: {'livingRoom': 1, 'bedroom': 3, 'masterBedroom': 1, 'kitchen': 1, 'dining': 1, 'bathroom': 2, 'masterBathroom': 1, 'study': 1, 'hallway': 1, 'boilerRoom': 1, 'wardrobe': 1, 'storage': 1, 'laundry': 1},
  HouseSizeCategory.large: {'livingRoom': 1, 'bedroom': 3, 'masterBedroom': 1, 'kidsRoom': 2, 'kitchenDining': 1, 'dining': 1, 'bathroom': 3, 'masterBathroom': 1, 'study': 1, 'hallway': 1, 'boilerRoom': 1, 'wardrobe': 2, 'storage': 2, 'laundry': 1, 'pantry': 1, 'garage': 1, 'terrace': 1},
  HouseSizeCategory.estate: {'livingRoom': 2, 'bedroom': 4, 'masterBedroom': 1, 'kidsRoom': 2, 'kitchenDining': 1, 'dining': 1, 'bathroom': 4, 'masterBathroom': 1, 'study': 2, 'hallway': 1, 'boilerRoom': 1, 'wardrobe': 3, 'storage': 2, 'laundry': 1, 'pantry': 1, 'garage': 1, 'terrace': 1, 'balcony': 2},
};

// ---------------------------------------------------------------------------
// §4a. Правила генерации по категориям домов (из анализа 1000+ проектов)
// ---------------------------------------------------------------------------

class CategoryLayoutRules {
  final String nameRu;
  final String description;
  final int recommendedFloors;
  final int maxFloors;
  final double corridorWidthM;
  final double hallwayDepthM;
  final double minCeilingHeight;
  final double recommendedCeilingHeight;
  final bool openPlanKitchenLiving;
  final bool separateDining;
  final bool requiresCorridor;
  final bool requiresEntryHall;
  final double corridorAreaPercent; // % от общей площади на коридоры
  final double serviceAreaPercent; // % от общей площади на хоз. помещения
  final List<String> requiredRooms;
  final List<String> optionalRooms;
  final List<String> layoutNotes;
  final Map<String, double> roomAreaOverrides; // рекомендуемые площади для данной категории

  const CategoryLayoutRules({
    required this.nameRu,
    required this.description,
    this.recommendedFloors = 1,
    this.maxFloors = 2,
    this.corridorWidthM = 1.4,
    this.hallwayDepthM = 2.5,
    this.minCeilingHeight = 2.5,
    this.recommendedCeilingHeight = 2.7,
    this.openPlanKitchenLiving = false,
    this.separateDining = false,
    this.requiresCorridor = true,
    this.requiresEntryHall = true,
    this.corridorAreaPercent = 12,
    this.serviceAreaPercent = 10,
    this.requiredRooms = const [],
    this.optionalRooms = const [],
    this.layoutNotes = const [],
    this.roomAreaOverrides = const {},
  });
}

/// Правила по категориям размера (из анализа проектов застройщиков:
/// СвойДом, Альфаплан, RuPlans, GroupHE, DeltaPlans, iDomPK, 1house.by и др.)
const Map<HouseSizeCategory, CategoryLayoutRules> kCategoryRules = {
  // ─── Микро-дом (40–60 м²) ──────────────────────────────────────────
  // Источники: проекты 278-60-1 (Планнерс), 263-01 (csr-kaluga), tiny houses
  // Характерно: open plan, минимум перегородок, совмещённый санузел
  HouseSizeCategory.micro: CategoryLayoutRules(
    nameRu: 'Микро-дом',
    description: '40–60 м². Для 1–2 человек, дача или стартовое жильё.',
    recommendedFloors: 1,
    maxFloors: 1,
    corridorWidthM: 1.2,
    hallwayDepthM: 1.8,
    minCeilingHeight: 2.4,
    recommendedCeilingHeight: 2.5,
    openPlanKitchenLiving: true,
    separateDining: false,
    requiresCorridor: false,
    requiresEntryHall: true,
    corridorAreaPercent: 8,
    serviceAreaPercent: 5,
    requiredRooms: ['livingRoom', 'bedroom', 'bathroom', 'hallway'],
    optionalRooms: ['kitchen', 'storage'],
    layoutNotes: [
      'Кухня-гостиная open plan (объединённое пространство)',
      'Совмещённый санузел для экономии площади',
      'Нет отдельного коридора — прихожая ведёт в общую зону',
      'Максимум 2 спальни',
      'Только 1 этаж без лестницы',
      'Котельная не выделяется — электрокотёл в кухне',
      'Габариты фундамента: ~6×8 – 8×10 м',
    ],
    roomAreaOverrides: {
      'livingRoom': 18,  // совмещённая с кухней
      'bedroom': 10,
      'bathroom': 3.5,
      'hallway': 3,
    },
  ),

  // ─── Компактный дом (60–100 м²) ───────────────────────────────────
  // Источники: О-80 (СвойДом), One 80 (Домогацкого), Single 100 (КПД100)
  // Характерно: кухня-гостиная, 2 спальни, 1 санузел, прихожая с гардеробом
  HouseSizeCategory.compact: CategoryLayoutRules(
    nameRu: 'Компактный дом',
    description: '60–100 м². Для семьи из 2–3 чел. Оптимальный баланс цена/комфорт.',
    recommendedFloors: 1,
    maxFloors: 2,
    corridorWidthM: 1.2,
    hallwayDepthM: 2.0,
    minCeilingHeight: 2.5,
    recommendedCeilingHeight: 2.7,
    openPlanKitchenLiving: true,
    separateDining: false,
    requiresCorridor: true,
    requiresEntryHall: true,
    corridorAreaPercent: 10,
    serviceAreaPercent: 8,
    requiredRooms: ['livingRoom', 'bedroom', 'kitchen', 'bathroom', 'hallway', 'corridor'],
    optionalRooms: ['boilerRoom', 'storage', 'terrace', 'wardrobe'],
    layoutNotes: [
      'Кухня-гостиная 25–30 м² — единое пространство для приёма гостей',
      '2 изолированные спальни (12–14 м²)',
      'Один совмещённый санузел (3–5 м²)',
      'Прихожая с гардеробной секцией у входа',
      'Короткий коридор (3–5 м²) к спальням',
      'Котельная: отдельная или электроотопление',
      'Терраса 8–12 м² — летняя столовая',
      'Габариты: 8×10 – 10×12 м',
    ],
    roomAreaOverrides: {
      'livingRoom': 20,
      'bedroom': 12,
      'kitchen': 10,
      'bathroom': 4,
      'hallway': 5,
      'corridor': 4,
      'boilerRoom': 4,
    },
  ),

  // ─── Стандартный дом (100–150 м²) ─────────────────────────────────
  // Источники: 150-001-Л, 150-002-Л (GroupHE), Rg5719/Rg6092 (RuPlans),
  // v-150-2p (postroi.ru)
  // Характерно: 3 спальни, отдельная кухня, 2 санузла, возможен 2-й этаж
  HouseSizeCategory.standard: CategoryLayoutRules(
    nameRu: 'Стандартный дом',
    description: '100–150 м². Для семьи 3–5 чел. Классическая планировка.',
    recommendedFloors: 1,
    maxFloors: 2,
    corridorWidthM: 1.4,
    hallwayDepthM: 2.5,
    minCeilingHeight: 2.7,
    recommendedCeilingHeight: 2.7,
    openPlanKitchenLiving: false,
    separateDining: false,
    requiresCorridor: true,
    requiresEntryHall: true,
    corridorAreaPercent: 12,
    serviceAreaPercent: 10,
    requiredRooms: ['livingRoom', 'bedroom', 'kitchen', 'bathroom', 'hallway', 'corridor', 'boilerRoom'],
    optionalRooms: ['storage', 'pantry', 'terrace', 'wardrobe', 'study', 'toilet'],
    layoutNotes: [
      'Гостиная 18–25 м² — отдельная от кухни',
      'Кухня 10–14 м² или кухня-столовая 15–20 м²',
      '3 спальни: 2 по 12–14 м², 1 мастер 16–18 м²',
      '2 санузла: 1 полный (5 м²), 1 гостевой (2 м²)',
      'Центральный коридор 5–8 м² связывает все помещения',
      'Прихожая 6–10 м² с тамбуром',
      'Котельная обязательна (6–8 м²)',
      'Кладовая/кладовка 3–5 м²',
      '1 этаж: гостиная, кухня, прихожая, котельная, гостевой с/у',
      '2 этаж: спальни, основной с/у, холл',
      'Габариты: 10×12 – 12×14 м',
    ],
    roomAreaOverrides: {
      'livingRoom': 22,
      'bedroom': 14,
      'kitchen': 12,
      'bathroom': 5,
      'hallway': 8,
      'corridor': 6,
      'boilerRoom': 6,
      'storage': 4,
    },
  ),

  // ─── Комфорт-дом (150–250 м²) ─────────────────────────────────────
  // Источники: 200-002-П (GroupHE), Z200 (1house.by), M-250-1K (DeltaPlans)
  // Характерно: 4+ спален, мастер-люкс, кабинет, гардеробные, 2 этажа
  HouseSizeCategory.comfort: CategoryLayoutRules(
    nameRu: 'Комфорт-класс',
    description: '150–250 м². Для семьи 4–6 чел. Все удобства и функциональные зоны.',
    recommendedFloors: 2,
    maxFloors: 2,
    corridorWidthM: 1.5,
    hallwayDepthM: 3.0,
    minCeilingHeight: 2.7,
    recommendedCeilingHeight: 3.0,
    openPlanKitchenLiving: false,
    separateDining: true,
    requiresCorridor: true,
    requiresEntryHall: true,
    corridorAreaPercent: 12,
    serviceAreaPercent: 12,
    requiredRooms: ['livingRoom', 'bedroom', 'masterBedroom', 'kitchen', 'bathroom',
      'masterBathroom', 'hallway', 'corridor', 'boilerRoom', 'study'],
    optionalRooms: ['dining', 'wardrobe', 'storage', 'laundry', 'pantry',
      'terrace', 'balcony', 'garage'],
    layoutNotes: [
      'Гостиная 20–30 м² — парадная зона',
      'Кухня 12–16 м² + отдельная столовая 10–14 м²',
      'Мастер-спальня 18–25 м² с гардеробной (6 м²) и собственным санузлом (8–12 м²)',
      '2–3 дополнительные спальни по 12–16 м²',
      'Кабинет 10–14 м² на 1 или 2 этаже',
      '3 санузла: мастер (8 м²), семейный (5 м²), гостевой (2 м²)',
      'Холл 2 этажа — просторная площадка 8–12 м²',
      'Прачечная отдельная (4–5 м²)',
      'Кладовая + кладовая при кухне (пантри)',
      '1 этаж: публичная зона + мастер-спальня (опц.)',
      '2 этаж: приватная зона (спальни, ванные)',
      'Габариты: 11×14 – 14×16 м',
    ],
    roomAreaOverrides: {
      'livingRoom': 28,
      'masterBedroom': 22,
      'bedroom': 14,
      'kitchen': 14,
      'dining': 12,
      'masterBathroom': 9,
      'bathroom': 5,
      'study': 12,
      'hallway': 10,
      'corridor': 8,
      'boilerRoom': 7,
      'wardrobe': 5,
      'laundry': 5,
    },
  ),

  // ─── Большой дом (250–400 м²) ─────────────────────────────────────
  // Источники: Альфаплан 300–400, iDomPK 300–400, U-300-1K (DeltaPlans)
  // Характерно: 5+ спален, 2-я гостиная, кабинет, 4 с/у, гараж, сауна
  HouseSizeCategory.large: CategoryLayoutRules(
    nameRu: 'Большой дом',
    description: '250–400 м². Для большой семьи. Полный набор зон + доп. удобства.',
    recommendedFloors: 2,
    maxFloors: 3,
    corridorWidthM: 1.6,
    hallwayDepthM: 3.5,
    minCeilingHeight: 2.7,
    recommendedCeilingHeight: 3.0,
    openPlanKitchenLiving: false,
    separateDining: true,
    requiresCorridor: true,
    requiresEntryHall: true,
    corridorAreaPercent: 14,
    serviceAreaPercent: 12,
    requiredRooms: ['livingRoom', 'bedroom', 'masterBedroom', 'kidsRoom',
      'kitchenDining', 'dining', 'bathroom', 'masterBathroom',
      'study', 'hallway', 'corridor', 'boilerRoom', 'laundry'],
    optionalRooms: ['wardrobe', 'storage', 'pantry', 'garage', 'terrace',
      'balcony', 'technical'],
    layoutNotes: [
      'Гостиная 30–40 м² — возможен второй свет',
      'Кухня-столовая 20–30 м² или отдельные кухня + столовая',
      'Мастер-люкс: спальня 25+ м², гардеробная 8+ м², ванная 10+ м²',
      '3–4 дополнительные спальни по 14–18 м²',
      'Детские 12–15 м² с встроенными шкафами',
      'Кабинет 14–18 м² — может быть библиотекой',
      '4 санузла: мастер, семейный, гостевой, хозяйственный',
      'Прачечная-постирочная 6–8 м²',
      'Гараж на 1–2 машины (24–40 м²)',
      'Терраса 15–25 м²',
      '1 этаж: публичная + сервис зоны',
      '2 этаж: приватная + семейная зоны',
      'Габариты: 14×16 – 18×20 м',
    ],
    roomAreaOverrides: {
      'livingRoom': 35,
      'masterBedroom': 25,
      'bedroom': 16,
      'kidsRoom': 14,
      'kitchenDining': 25,
      'dining': 14,
      'masterBathroom': 10,
      'bathroom': 6,
      'study': 15,
      'hallway': 12,
      'corridor': 10,
      'boilerRoom': 8,
      'wardrobe': 6,
      'laundry': 6,
      'garage': 30,
    },
  ),

  // ─── Усадьба / Особняк (400+ м²) ─────────────────────────────────
  // Источники: U-300-1K бассейн (DeltaPlans), элитные проекты Альфаплан
  // Характерно: 2–3 этажа, спортзал/бассейн, библиотека, домашний кинотеатр
  HouseSizeCategory.estate: CategoryLayoutRules(
    nameRu: 'Усадьба / Особняк',
    description: '400+ м². Элитное жильё. Все зоны + премиум-пространства.',
    recommendedFloors: 2,
    maxFloors: 3,
    corridorWidthM: 1.8,
    hallwayDepthM: 4.0,
    minCeilingHeight: 3.0,
    recommendedCeilingHeight: 3.3,
    openPlanKitchenLiving: false,
    separateDining: true,
    requiresCorridor: true,
    requiresEntryHall: true,
    corridorAreaPercent: 15,
    serviceAreaPercent: 14,
    requiredRooms: ['livingRoom', 'bedroom', 'masterBedroom', 'kidsRoom',
      'kitchenDining', 'dining', 'bathroom', 'masterBathroom',
      'study', 'hallway', 'corridor', 'boilerRoom', 'laundry', 'pantry'],
    optionalRooms: ['wardrobe', 'storage', 'garage', 'terrace', 'balcony',
      'technical'],
    layoutNotes: [
      'Парадная гостиная 40–60 м² со вторым светом',
      'Возможна вторая гостиная/семейная комната 25+ м²',
      'Кухня 20+ м² + столовая 16+ м² + пантри',
      'Мастер-люкс: спальня 30+ м², гардеробная 10+ м², ванная 12+ м²',
      '4–5 спален по 16–22 м² с гардеробными',
      'Кабинет/библиотека 18–25 м²',
      '5+ санузлов',
      'Гараж на 2–3 машины (40–60 м²)',
      'Терраса 20–40 м²',
      'Прачечная, гладильная, постирочная (10+ м²)',
      'Возможны: бассейн, сауна, спортзал, бильярдная, зимний сад',
      '1 этаж: представительская + сервис зоны',
      '2 этаж: приватная зона семьи',
      '3 этаж / цоколь: развлекательные зоны',
      'Габариты: 18×20 – 25×25 м и более',
    ],
    roomAreaOverrides: {
      'livingRoom': 50,
      'masterBedroom': 30,
      'bedroom': 18,
      'kidsRoom': 16,
      'kitchenDining': 30,
      'dining': 18,
      'masterBathroom': 12,
      'bathroom': 7,
      'study': 20,
      'hallway': 15,
      'corridor': 12,
      'boilerRoom': 10,
      'wardrobe': 8,
      'laundry': 8,
      'garage': 45,
    },
  ),
};

// ---------------------------------------------------------------------------
// §4b. Правила генерации по архитектурным стилям
// ---------------------------------------------------------------------------

class StyleLayoutRules {
  final String nameRu;
  final String description;
  final List<String> roofTypes;
  final bool preferOpenPlan;
  final bool preferSymmetry;
  final bool hasPanoramicWindows;
  final bool hasSecondLight;
  final double windowAreaRatio; // % площади фасада
  final bool preferTerrace;
  final bool preferBalcony;
  final String facadeFinish;
  final List<String> characteristicFeatures;
  final List<String> layoutNotes;

  const StyleLayoutRules({
    required this.nameRu,
    required this.description,
    this.roofTypes = const ['gable'],
    this.preferOpenPlan = false,
    this.preferSymmetry = false,
    this.hasPanoramicWindows = false,
    this.hasSecondLight = false,
    this.windowAreaRatio = 15,
    this.preferTerrace = false,
    this.preferBalcony = false,
    this.facadeFinish = 'штукатурка',
    this.characteristicFeatures = const [],
    this.layoutNotes = const [],
  });
}

const Map<String, StyleLayoutRules> kStyleRules = {
  // ─── Современный ──────────────────────────────────────────────────
  'modern': StyleLayoutRules(
    nameRu: 'Современный',
    description: 'Чёткие линии, функциональность, лаконичный дизайн.',
    roofTypes: ['flat', 'shed', 'combined'],
    preferOpenPlan: true,
    preferSymmetry: false,
    hasPanoramicWindows: true,
    hasSecondLight: false,
    windowAreaRatio: 20,
    preferTerrace: true,
    preferBalcony: true,
    facadeFinish: 'штукатурка + HPL панели',
    characteristicFeatures: [
      'Плоская или односкатная крыша',
      'Панорамное остекление',
      'Открытая планировка общей зоны',
      'Минимум декора на фасаде',
    ],
    layoutNotes: [
      'Open plan кухня-гостиная-столовая',
      'Большие окна во всех жилых комнатах',
      'Терраса как продолжение гостиной',
      'Функциональное зонирование без лишних стен',
    ],
  ),

  // ─── Классический ─────────────────────────────────────────────────
  'classic': StyleLayoutRules(
    nameRu: 'Классический',
    description: 'Симметрия, карнизы, пилястры, традиционные пропорции.',
    roofTypes: ['gable', 'hip', 'mansard'],
    preferOpenPlan: false,
    preferSymmetry: true,
    hasPanoramicWindows: false,
    hasSecondLight: false,
    windowAreaRatio: 14,
    preferTerrace: false,
    preferBalcony: true,
    facadeFinish: 'кирпич / штукатурка',
    characteristicFeatures: [
      'Симметричный фасад',
      'Карнизы и пилястры',
      'Высокие потолки (3+ м)',
      'Парадный вход с колоннами',
    ],
    layoutNotes: [
      'Все комнаты изолированные (нет open plan)',
      'Симметричная планировка относительно оси',
      'Парадная прихожая / холл с лестницей',
      'Отдельная столовая обязательна',
      'Кабинет и библиотека на 1 этаже',
    ],
  ),

  // ─── Скандинавский ────────────────────────────────────────────────
  'scandinavian': StyleLayoutRules(
    nameRu: 'Скандинавский',
    description: 'Функциональность, естественные материалы, уют.',
    roofTypes: ['gable', 'shed'],
    preferOpenPlan: true,
    preferSymmetry: false,
    hasPanoramicWindows: true,
    hasSecondLight: false,
    windowAreaRatio: 18,
    preferTerrace: true,
    preferBalcony: false,
    facadeFinish: 'деревянная обшивка',
    characteristicFeatures: [
      'Натуральные материалы (дерево, камень)',
      'Большие окна для естественного света',
      'Простая двускатная крыша',
      'Светлые стены',
    ],
    layoutNotes: [
      'Open plan кухня-гостиная',
      'Максимум естественного света во всех комнатах',
      'Функциональные кладовые и системы хранения',
      'Простые прямоугольные комнаты',
      'Минимум коридоров — комнаты группируются вокруг гостиной',
    ],
  ),

  // ─── Минимализм ──────────────────────────────────────────────────
  'minimalist': StyleLayoutRules(
    nameRu: 'Минимализм',
    description: 'Максимум пространства, минимум перегородок.',
    roofTypes: ['flat'],
    preferOpenPlan: true,
    preferSymmetry: false,
    hasPanoramicWindows: true,
    hasSecondLight: true,
    windowAreaRatio: 22,
    preferTerrace: true,
    preferBalcony: false,
    facadeFinish: 'белая штукатурка',
    characteristicFeatures: [
      'Плоская крыша',
      'Минимум перегородок',
      'Панорамное остекление',
      'Монохромный фасад',
    ],
    layoutNotes: [
      'Общая зона без перегородок (кухня+гостиная+столовая)',
      'Спальни — единственные закрытые комнаты',
      'Встроенные шкафы вместо гардеробных комнат',
      'Скрытые двери и минимум видимых ручек',
    ],
  ),

  // ─── Барнхаус ────────────────────────────────────────────────────
  'barnhouse': StyleLayoutRules(
    nameRu: 'Барнхаус',
    description: 'Амбарный стиль: открытое пространство, высокие потолки.',
    roofTypes: ['gable', 'gambrel'],
    preferOpenPlan: true,
    preferSymmetry: true,
    hasPanoramicWindows: true,
    hasSecondLight: true,
    windowAreaRatio: 16,
    preferTerrace: true,
    preferBalcony: false,
    facadeFinish: 'тёмная деревянная обшивка / металл',
    characteristicFeatures: [
      'Высокая двускатная крыша',
      'Второй свет в гостиной',
      'Тёмный фасад',
      'Простая форма здания',
    ],
    layoutNotes: [
      'Большая open-plan зона с двойной высотой потолка',
      'Спальни на антресольном уровне или в крыле',
      'Минимум внутренних стен',
      'Простая прямоугольная планировка',
    ],
  ),

  // ─── Шале ────────────────────────────────────────────────────────
  'chalet': StyleLayoutRules(
    nameRu: 'Шале',
    description: 'Альпийский стиль: камень + дерево, большие свесы крыши.',
    roofTypes: ['gable', 'hip'],
    preferOpenPlan: false,
    preferSymmetry: false,
    hasPanoramicWindows: true,
    hasSecondLight: true,
    windowAreaRatio: 16,
    preferTerrace: true,
    preferBalcony: true,
    facadeFinish: 'камень + дерево',
    characteristicFeatures: [
      'Каменный 1 этаж + деревянный 2 этаж',
      'Широкие свесы крыши (60+ см)',
      'Балконы с деревянными балясинами',
      'Второй свет в гостиной',
      'Камин в гостиной',
    ],
    layoutNotes: [
      '1 этаж: каменный — гостиная со 2-м светом + камин, кухня, прихожая, хоз. зона',
      '2 этаж: деревянный — спальни, санузлы, открытый холл с видом на гостиную',
      'Балконы и террасы обязательны',
      'Панорамные окна в гостиной с видом на горы/сад',
      'Спальни компактные, комфортные',
    ],
  ),

  // ─── Хай-тек ─────────────────────────────────────────────────────
  'hitech': StyleLayoutRules(
    nameRu: 'Хай-тек',
    description: 'Стекло, металл, бетон. Технологичность и автоматизация.',
    roofTypes: ['flat'],
    preferOpenPlan: true,
    preferSymmetry: false,
    hasPanoramicWindows: true,
    hasSecondLight: true,
    windowAreaRatio: 25,
    preferTerrace: true,
    preferBalcony: true,
    facadeFinish: 'бетон + стекло + металл',
    characteristicFeatures: [
      'Плоская эксплуатируемая крыша',
      'Панорамное остекление до 40% фасада',
      'Кубические формы',
      'Система «умный дом»',
      'Минимум декора',
    ],
    layoutNotes: [
      'Open-plan с зонированием мебелью, а не стенами',
      'Большие безрамные окна (2.5+ м высотой)',
      'Многоуровневые конструкции',
      'Техническое помещение для систем автоматизации',
      'Рекуперация + кондиционирование обязательны',
    ],
  ),

  // ─── Крафтсман ───────────────────────────────────────────────────
  'craftsman': StyleLayoutRules(
    nameRu: 'Крафтсман',
    description: 'Американский ремесленный стиль: крыльцо, натуральные материалы.',
    roofTypes: ['gable', 'hip'],
    preferOpenPlan: false,
    preferSymmetry: false,
    hasPanoramicWindows: false,
    hasSecondLight: false,
    windowAreaRatio: 14,
    preferTerrace: true,
    preferBalcony: false,
    facadeFinish: 'кирпич + штукатурка',
    characteristicFeatures: [
      'Широкое крытое крыльцо',
      'Карниз с выносом',
      'Колонны крыльца',
      'Натуральные материалы',
    ],
    layoutNotes: [
      'Просторная прихожая / веранда',
      'Камин в гостиной',
      'Отдельная кухня с обеденной зоной',
      'Уютные пропорции комнат (не слишком большие)',
      'Встроенные шкафы и ниши',
    ],
  ),

  // ─── Колониальный ────────────────────────────────────────────────
  'colonial': StyleLayoutRules(
    nameRu: 'Колониальный',
    description: 'Симметрия, пилястры, парадный вход, строгие пропорции.',
    roofTypes: ['gable', 'hip'],
    preferOpenPlan: false,
    preferSymmetry: true,
    hasPanoramicWindows: false,
    hasSecondLight: false,
    windowAreaRatio: 12,
    preferTerrace: false,
    preferBalcony: true,
    facadeFinish: 'кирпич',
    characteristicFeatures: [
      'Строгая симметрия фасада',
      'Парадный вход с пилястрами',
      'Высокие окна одинакового размера',
      '2 этажа — стандартная этажность',
    ],
    layoutNotes: [
      'Симметричная планировка с центральным холлом',
      'Парадная лестница в центре',
      'Комнаты одинакового размера по обе стороны',
      'Формальная столовая обязательна',
      'Кабинет на 1 этаже',
    ],
  ),

  // ─── Средиземноморский ───────────────────────────────────────────
  'mediterranean': StyleLayoutRules(
    nameRu: 'Средиземноморский',
    description: 'Тёплые тона, арки, черепица, внутренний дворик.',
    roofTypes: ['hip', 'gable'],
    preferOpenPlan: false,
    preferSymmetry: false,
    hasPanoramicWindows: false,
    hasSecondLight: false,
    windowAreaRatio: 15,
    preferTerrace: true,
    preferBalcony: true,
    facadeFinish: 'штукатурка тёплых тонов',
    characteristicFeatures: [
      'Черепичная крыша',
      'Арочные окна и проёмы',
      'Штукатурка тёплых тонов',
      'Балконы с балюстрадами',
      'Внутренний дворик (патио)',
    ],
    layoutNotes: [
      'Патио или внутренний дворик — центр планировки',
      'Комнаты выходят в галерею / аркаду',
      'Террасы и балконы с выходом из спален',
      'Кухня рядом с патио',
      'Обилие арок во внутренней отделке',
    ],
  ),

  // ─── Рустик ──────────────────────────────────────────────────────
  'rustic': StyleLayoutRules(
    nameRu: 'Рустик / Деревенский',
    description: 'Натуральное дерево, камень, уют, простота.',
    roofTypes: ['gable'],
    preferOpenPlan: false,
    preferSymmetry: false,
    hasPanoramicWindows: false,
    hasSecondLight: false,
    windowAreaRatio: 12,
    preferTerrace: true,
    preferBalcony: false,
    facadeFinish: 'бревно / брус',
    characteristicFeatures: [
      'Деревянный сруб / брус',
      'Камин / печь',
      'Двускатная крыша с большими свесами',
      'Минимум декора',
    ],
    layoutNotes: [
      'Камин или печь — центральный элемент',
      'Гостиная-столовая вокруг камина',
      'Компактные спальни',
      'Кухня рядом с печью/камином',
      'Минимум хозяйственных помещений',
      'Сени / тамбур обязательны (утепление входа)',
    ],
  ),
};

// ---------------------------------------------------------------------------
// §5. Пропорции
// ---------------------------------------------------------------------------

class ProportionRule {
  static const double maxAspectRatio = 2.5;
  static const double goldenRatio = 1.618;

  static double proportionScore(double width, double height) {
    final ratio = math.max(width, height) / math.min(width, height);
    if (ratio > maxAspectRatio) return 0.0;
    final deviation = (ratio - goldenRatio).abs();
    return (1.0 - deviation / goldenRatio).clamp(0.0, 1.0);
  }
}

// ---------------------------------------------------------------------------
// §6. Эффективность
// ---------------------------------------------------------------------------

class LayoutEfficiency {
  static double usableAreaRatio(double usableArea, double totalArea) {
    if (totalArea <= 0) return 0;
    return usableArea / totalArea;
  }

  static double compactnessRatio(double perimeterM, double areaM2) {
    if (areaM2 <= 0) return 0;
    final idealPerimeter = 4 * math.sqrt(areaM2);
    return idealPerimeter / perimeterM;
  }
}
