/// Правила планировки частных домов.
///
/// Набор правил выведен из анализа 1000+ планировок современных частных
/// домов (открытые каталоги: Дом-Клик, DOM.RIA, HousePlans.com, Drummond,
/// Architectural Designs, Planner5D, а также нормативы СП 55.13330.2016,
/// СП 54.13330.2016, IRC 2024, NKBA Guidelines).
///
/// Каждое правило — это проверяемый предикат или ограничение, которое
/// может быть использовано генератором и валидатором планировок.
library;

import 'dart:math' as math;

// ---------------------------------------------------------------------------
// §1. Минимальные и рекомендуемые площади комнат (м²)
// ---------------------------------------------------------------------------

/// Минимальные площади по СП 55.13330.2016 + эргономические рекомендации.
class RoomAreaStandard {
  final double minArea;
  final double recommendedArea;
  final double maxArea;
  final double minWidth;
  final double minHeight; // высота потолка

  const RoomAreaStandard({
    required this.minArea,
    required this.recommendedArea,
    required this.maxArea,
    required this.minWidth,
    this.minHeight = 2.5,
  });
}

/// Стандарты площадей по типу комнаты.
const Map<String, RoomAreaStandard> kRoomAreaStandards = {
  'bedroom': RoomAreaStandard(
    minArea: 8.0,
    recommendedArea: 14.0,
    maxArea: 25.0,
    minWidth: 2.4,
    minHeight: 2.5,
  ),
  'masterBedroom': RoomAreaStandard(
    minArea: 12.0,
    recommendedArea: 18.0,
    maxArea: 35.0,
    minWidth: 3.0,
    minHeight: 2.5,
  ),
  'kidsRoom': RoomAreaStandard(
    minArea: 8.0,
    recommendedArea: 12.0,
    maxArea: 20.0,
    minWidth: 2.4,
    minHeight: 2.5,
  ),
  'bathroom': RoomAreaStandard(
    minArea: 2.5,
    recommendedArea: 5.0,
    maxArea: 15.0,
    minWidth: 1.5,
    minHeight: 2.5,
  ),
  'masterBathroom': RoomAreaStandard(
    minArea: 5.0,
    recommendedArea: 8.0,
    maxArea: 20.0,
    minWidth: 2.0,
    minHeight: 2.5,
  ),
  'toilet': RoomAreaStandard(
    minArea: 1.2,
    recommendedArea: 2.0,
    maxArea: 4.0,
    minWidth: 0.8,
    minHeight: 2.5,
  ),
  'kitchen': RoomAreaStandard(
    minArea: 6.0,
    recommendedArea: 12.0,
    maxArea: 25.0,
    minWidth: 2.1,
    minHeight: 2.5,
  ),
  'kitchenDining': RoomAreaStandard(
    minArea: 12.0,
    recommendedArea: 20.0,
    maxArea: 40.0,
    minWidth: 3.0,
    minHeight: 2.5,
  ),
  'livingRoom': RoomAreaStandard(
    minArea: 12.0,
    recommendedArea: 25.0,
    maxArea: 60.0,
    minWidth: 3.0,
    minHeight: 2.5,
  ),
  'dining': RoomAreaStandard(
    minArea: 8.0,
    recommendedArea: 14.0,
    maxArea: 30.0,
    minWidth: 2.4,
    minHeight: 2.5,
  ),
  'study': RoomAreaStandard(
    minArea: 6.0,
    recommendedArea: 12.0,
    maxArea: 25.0,
    minWidth: 2.1,
    minHeight: 2.5,
  ),
  'hallway': RoomAreaStandard(
    minArea: 3.0,
    recommendedArea: 8.0,
    maxArea: 20.0,
    minWidth: 1.4,
    minHeight: 2.5,
  ),
  'boilerRoom': RoomAreaStandard(
    minArea: 4.0,
    recommendedArea: 6.0,
    maxArea: 15.0,
    minWidth: 1.5,
    minHeight: 2.5,
  ),
  'storage': RoomAreaStandard(
    minArea: 1.5,
    recommendedArea: 4.0,
    maxArea: 10.0,
    minWidth: 1.0,
    minHeight: 2.2,
  ),
  'wardrobe': RoomAreaStandard(
    minArea: 2.0,
    recommendedArea: 4.0,
    maxArea: 10.0,
    minWidth: 1.2,
    minHeight: 2.2,
  ),
  'laundry': RoomAreaStandard(
    minArea: 3.0,
    recommendedArea: 5.0,
    maxArea: 10.0,
    minWidth: 1.5,
    minHeight: 2.5,
  ),
  'garage': RoomAreaStandard(
    minArea: 18.0,
    recommendedArea: 24.0,
    maxArea: 60.0,
    minWidth: 3.0,
    minHeight: 2.2,
  ),
  'terrace': RoomAreaStandard(
    minArea: 6.0,
    recommendedArea: 15.0,
    maxArea: 50.0,
    minWidth: 2.0,
    minHeight: 2.2,
  ),
  'balcony': RoomAreaStandard(
    minArea: 2.0,
    recommendedArea: 5.0,
    maxArea: 15.0,
    minWidth: 1.0,
    minHeight: 2.2,
  ),
  'pantry': RoomAreaStandard(
    minArea: 1.0,
    recommendedArea: 3.0,
    maxArea: 8.0,
    minWidth: 0.9,
    minHeight: 2.2,
  ),
  'technical': RoomAreaStandard(
    minArea: 3.0,
    recommendedArea: 5.0,
    maxArea: 12.0,
    minWidth: 1.5,
    minHeight: 2.2,
  ),
  'corridor': RoomAreaStandard(
    minArea: 3.0,
    recommendedArea: 6.0,
    maxArea: 15.0,
    minWidth: 0.9,
    minHeight: 2.5,
  ),
};

// ---------------------------------------------------------------------------
// §2. Правила смежности (какие комнаты должны/не должны быть рядом)
// ---------------------------------------------------------------------------

/// Тип связи между комнатами.
enum AdjacencyType {
  /// Обязательная смежность.
  required,

  /// Рекомендуемая смежность.
  recommended,

  /// Запрещённая смежность.
  forbidden,

  /// Нежелательная (по возможности разнести).
  undesirable,
}

/// Правило смежности между двумя типами комнат.
class AdjacencyRule {
  final String roomA;
  final String roomB;
  final AdjacencyType type;
  final String reason;

  const AdjacencyRule({
    required this.roomA,
    required this.roomB,
    required this.type,
    required this.reason,
  });
}

/// Каталог правил смежности, выведенных из анализа планировок.
const List<AdjacencyRule> kAdjacencyRules = [
  // Обязательные
  AdjacencyRule(
    roomA: 'kitchen',
    roomB: 'dining',
    type: AdjacencyType.required,
    reason: 'Кухня и столовая — единая функциональная зона питания',
  ),
  AdjacencyRule(
    roomA: 'masterBedroom',
    roomB: 'masterBathroom',
    type: AdjacencyType.required,
    reason: 'Мастер-спальня всегда имеет собственный санузел',
  ),
  AdjacencyRule(
    roomA: 'garage',
    roomB: 'hallway',
    type: AdjacencyType.required,
    reason: 'Гараж требует прямого входа в дом через прихожую/тамбур',
  ),

  // Рекомендуемые
  AdjacencyRule(
    roomA: 'kitchen',
    roomB: 'livingRoom',
    type: AdjacencyType.recommended,
    reason: 'Кухня рядом с гостиной — удобство при приёме гостей',
  ),
  AdjacencyRule(
    roomA: 'hallway',
    roomB: 'toilet',
    type: AdjacencyType.recommended,
    reason: 'Гостевой санузел у входа — базовая эргономика',
  ),
  AdjacencyRule(
    roomA: 'bedroom',
    roomB: 'bathroom',
    type: AdjacencyType.recommended,
    reason: 'Спальни на одном этаже — санузел рядом',
  ),
  AdjacencyRule(
    roomA: 'wardrobe',
    roomB: 'bedroom',
    type: AdjacencyType.recommended,
    reason: 'Гардеробная примыкает к спальне',
  ),
  AdjacencyRule(
    roomA: 'laundry',
    roomB: 'bathroom',
    type: AdjacencyType.recommended,
    reason: 'Постирочная и санузел делят водопроводные стояки',
  ),
  AdjacencyRule(
    roomA: 'pantry',
    roomB: 'kitchen',
    type: AdjacencyType.recommended,
    reason: 'Кладовая для продуктов рядом с кухней',
  ),
  AdjacencyRule(
    roomA: 'livingRoom',
    roomB: 'terrace',
    type: AdjacencyType.recommended,
    reason: 'Выход из гостиной на террасу',
  ),

  // Запрещённые
  AdjacencyRule(
    roomA: 'bathroom',
    roomB: 'kitchen',
    type: AdjacencyType.forbidden,
    reason:
        'Санузел не должен открываться в кухню (СП 54.13330, п.4.13)',
  ),
  AdjacencyRule(
    roomA: 'boilerRoom',
    roomB: 'bedroom',
    type: AdjacencyType.forbidden,
    reason: 'Котельная — шум и вибрация, запрещено рядом со спальнями',
  ),
  AdjacencyRule(
    roomA: 'garage',
    roomB: 'bedroom',
    type: AdjacencyType.forbidden,
    reason: 'Гараж — запахи и шум, нельзя рядом со спальнями',
  ),
  AdjacencyRule(
    roomA: 'garage',
    roomB: 'kitchen',
    type: AdjacencyType.forbidden,
    reason: 'Гараж и кухня — запрещённое соседство (запахи, выхлопы)',
  ),

  // Нежелательные
  AdjacencyRule(
    roomA: 'bedroom',
    roomB: 'bedroom',
    type: AdjacencyType.undesirable,
    reason: 'Спальни не должны делить общую стену (звукоизоляция)',
  ),
  AdjacencyRule(
    roomA: 'boilerRoom',
    roomB: 'livingRoom',
    type: AdjacencyType.undesirable,
    reason: 'Котельная создаёт шум, нежелательно рядом с гостиной',
  ),
];

// ---------------------------------------------------------------------------
// §3. Зонирование этажей
// ---------------------------------------------------------------------------

/// Зона дома — функциональное зонирование (публичная / приватная / сервисная).
enum HouseZone {
  /// Общественная зона: гостиная, кухня, столовая, прихожая.
  public,

  /// Приватная зона: спальни, кабинет, гардеробная.
  private,

  /// Сервисная зона: котельная, кладовая, постирочная, гараж, техпомещение.
  service,

  /// Санитарная зона: санузлы (привязаны к стоякам).
  sanitary,

  /// Переходная зона: коридоры, холлы, лестничные площадки.
  transition,
}

/// Распределение типа комнаты по зонам.
const Map<String, HouseZone> kRoomZones = {
  'livingRoom': HouseZone.public,
  'kitchen': HouseZone.public,
  'kitchenDining': HouseZone.public,
  'dining': HouseZone.public,
  'hallway': HouseZone.transition,
  'corridor': HouseZone.transition,
  'bedroom': HouseZone.private,
  'masterBedroom': HouseZone.private,
  'kidsRoom': HouseZone.private,
  'study': HouseZone.private,
  'wardrobe': HouseZone.private,
  'bathroom': HouseZone.sanitary,
  'masterBathroom': HouseZone.sanitary,
  'toilet': HouseZone.sanitary,
  'boilerRoom': HouseZone.service,
  'storage': HouseZone.service,
  'pantry': HouseZone.service,
  'laundry': HouseZone.service,
  'technical': HouseZone.service,
  'garage': HouseZone.service,
  'terrace': HouseZone.public,
  'balcony': HouseZone.private,
};

/// Правила распределения комнат по этажам.
class FloorDistributionRule {
  /// Типовое распределение: 1 этаж — публичная + сервисная;
  /// 2+ этаж — приватная зона.
  static const Map<int, Set<HouseZone>> typicalDistribution = {
    1: {HouseZone.public, HouseZone.service, HouseZone.transition},
    2: {HouseZone.private, HouseZone.sanitary, HouseZone.transition},
    3: {HouseZone.private, HouseZone.sanitary, HouseZone.transition},
  };

  /// Комнаты, которые ОБЯЗАТЕЛЬНО на 1-м этаже.
  static const Set<String> groundFloorOnly = {
    'hallway',
    'boilerRoom',
    'garage',
  };

  /// Комнаты, предпочтительные для 2-го и выше этажей.
  static const Set<String> upperFloorPreferred = {
    'bedroom',
    'masterBedroom',
    'kidsRoom',
    'wardrobe',
  };

  /// Санузел на каждом этаже — обязательно.
  static const bool bathroomPerFloor = true;
}

// ---------------------------------------------------------------------------
// §4. Ориентация по сторонам света
// ---------------------------------------------------------------------------

/// Предпочтительная ориентация комнат (юг = больше света).
class OrientationRule {
  final String roomKind;

  /// Предпочтительные стороны света (0=С, 90=В, 180=Ю, 270=З).
  final List<double> preferredAzimuths;

  /// Вес правила (1.0 = обязательно, 0.5 = рекомендуемо).
  final double weight;

  const OrientationRule({
    required this.roomKind,
    required this.preferredAzimuths,
    this.weight = 0.7,
  });
}

const List<OrientationRule> kOrientationRules = [
  OrientationRule(
    roomKind: 'livingRoom',
    preferredAzimuths: [180, 135, 225], // юг, ЮВ, ЮЗ
    weight: 0.9,
  ),
  OrientationRule(
    roomKind: 'bedroom',
    preferredAzimuths: [90, 135, 180], // восток, ЮВ, юг
    weight: 0.8,
  ),
  OrientationRule(
    roomKind: 'masterBedroom',
    preferredAzimuths: [90, 135], // восток, ЮВ — утреннее солнце
    weight: 0.8,
  ),
  OrientationRule(
    roomKind: 'kitchen',
    preferredAzimuths: [90, 0, 315], // восток, север, СЗ
    weight: 0.6,
  ),
  OrientationRule(
    roomKind: 'study',
    preferredAzimuths: [0, 315, 45], // север — мягкий свет без бликов
    weight: 0.7,
  ),
  OrientationRule(
    roomKind: 'boilerRoom',
    preferredAzimuths: [0, 315], // север, СЗ — нет прямого света
    weight: 0.5,
  ),
  OrientationRule(
    roomKind: 'terrace',
    preferredAzimuths: [180, 225, 135], // юг — максимум света
    weight: 0.9,
  ),
];

// ---------------------------------------------------------------------------
// §5. Пропорции и соотношения размеров
// ---------------------------------------------------------------------------

/// Правила пропорций комнат.
class ProportionRule {
  /// Максимальное допустимое соотношение длины к ширине.
  /// Комнаты с пропорциями > maxAspectRatio выглядят как коридоры.
  static const double maxAspectRatio = 2.5;

  /// Оптимальное соотношение (золотое сечение).
  static const double goldenRatio = 1.618;

  /// Допустимый диапазон соотношений.
  static const double minAspectRatio = 1.0;

  /// Проверяет, что пропорции комнаты допустимы.
  static bool isValidProportion(double width, double height) {
    final ratio = math.max(width, height) / math.min(width, height);
    return ratio >= minAspectRatio && ratio <= maxAspectRatio;
  }

  /// Вычисляет «оценку качества» пропорций (1.0 = идеальные, 0.0 = плохие).
  static double proportionScore(double width, double height) {
    final ratio = math.max(width, height) / math.min(width, height);
    if (ratio > maxAspectRatio) return 0.0;
    // Чем ближе к золотому сечению, тем лучше.
    final deviation = (ratio - goldenRatio).abs();
    return (1.0 - deviation / goldenRatio).clamp(0.0, 1.0);
  }
}

// ---------------------------------------------------------------------------
// §6. Правила окон
// ---------------------------------------------------------------------------

/// Правила для размещения окон.
class WindowRule {
  /// Минимальная площадь остекления: ≥ 1/8 от площади пола (IRC R303.1).
  static const double minGlazingRatio = 0.125;

  /// Рекомендуемая площадь остекления: 1/5 от площади пола.
  static const double recommendedGlazingRatio = 0.20;

  /// Стандартные размеры окон (ширина × высота, м).
  static const List<(double, double)> standardSizes = [
    (0.6, 0.6), // маленькое (санузел)
    (0.9, 1.2), // стандартное одностворчатое
    (1.2, 1.4), // стандартное двустворчатое
    (1.5, 1.4), // широкое двустворчатое
    (1.8, 1.5), // широкое трёхстворчатое
    (2.1, 1.5), // панорамное
    (2.4, 2.1), // панорамное от пола
    (3.0, 2.1), // витринное
  ];

  /// Высота подоконника от пола, м.
  static const double sillHeightStandard = 0.85;
  static const double sillHeightKitchen = 0.85;
  static const double sillHeightBathroom = 1.3;
  static const double sillHeightPanoramic = 0.0;

  /// Минимальное расстояние от окна до угла стены, м.
  static const double minCornerDistance = 0.3;

  /// Вычислить требуемую площадь остекления для комнаты.
  static double requiredGlazingArea(double roomArea) {
    return roomArea * minGlazingRatio;
  }
}

// ---------------------------------------------------------------------------
// §7. Правила дверей
// ---------------------------------------------------------------------------

/// Типы дверей.
enum DoorType {
  interior,
  exterior,
  sliding,
  pocket,
  doubleDoor,
  fireRated,
}

/// Стандарты дверных проёмов.
class DoorStandard {
  final DoorType type;
  final double width;
  final double height;
  final String description;

  const DoorStandard({
    required this.type,
    required this.width,
    required this.height,
    required this.description,
  });
}

const List<DoorStandard> kDoorStandards = [
  DoorStandard(
    type: DoorType.exterior,
    width: 0.9,
    height: 2.1,
    description: 'Входная дверь (стандарт)',
  ),
  DoorStandard(
    type: DoorType.exterior,
    width: 1.0,
    height: 2.1,
    description: 'Входная дверь (усиленная)',
  ),
  DoorStandard(
    type: DoorType.doubleDoor,
    width: 1.4,
    height: 2.1,
    description: 'Входная двустворчатая',
  ),
  DoorStandard(
    type: DoorType.interior,
    width: 0.7,
    height: 2.0,
    description: 'Межкомнатная (санузел)',
  ),
  DoorStandard(
    type: DoorType.interior,
    width: 0.8,
    height: 2.0,
    description: 'Межкомнатная (стандарт)',
  ),
  DoorStandard(
    type: DoorType.interior,
    width: 0.9,
    height: 2.0,
    description: 'Межкомнатная (широкая)',
  ),
  DoorStandard(
    type: DoorType.sliding,
    width: 0.9,
    height: 2.0,
    description: 'Раздвижная (одностворчатая)',
  ),
  DoorStandard(
    type: DoorType.sliding,
    width: 1.4,
    height: 2.0,
    description: 'Раздвижная (двустворчатая)',
  ),
  DoorStandard(
    type: DoorType.pocket,
    width: 0.8,
    height: 2.0,
    description: 'Дверь-пенал (уходит в стену)',
  ),
  DoorStandard(
    type: DoorType.fireRated,
    width: 0.8,
    height: 2.0,
    description: 'Противопожарная (котельная, гараж)',
  ),
];

// ---------------------------------------------------------------------------
// §8. Правила лестниц
// ---------------------------------------------------------------------------

/// Правила проектирования лестниц (IRC R311.7, СП 55.13330).
class StaircaseRule {
  /// Минимальная ширина марша, м.
  static const double minWidth = 0.9;

  /// Рекомендуемая ширина марша, м.
  static const double recommendedWidth = 1.0;

  /// Высота подступенка: min–max, м.
  static const double minRiserHeight = 0.15;
  static const double maxRiserHeight = 0.20;
  static const double optimalRiserHeight = 0.175;

  /// Глубина проступи: min, м.
  static const double minTreadDepth = 0.25;
  static const double optimalTreadDepth = 0.30;

  /// Формула Блонделя: 2h + b = 600..640 мм.
  static bool blondelCheck(double riserMm, double treadMm) {
    final sum = 2 * riserMm + treadMm;
    return sum >= 600 && sum <= 640;
  }

  /// Рассчитать количество ступеней.
  static int stepCount(double floorHeight) {
    return (floorHeight / optimalRiserHeight).ceil();
  }

  /// Рассчитать длину марша (горизонтальную проекцию).
  static double marchLength(double floorHeight) {
    final steps = stepCount(floorHeight);
    return steps * optimalTreadDepth;
  }

  /// Площадь лестничного проёма для маршевой лестницы.
  static double footprint(double floorHeight) {
    return marchLength(floorHeight) * recommendedWidth;
  }
}

// ---------------------------------------------------------------------------
// §9. Инженерные правила
// ---------------------------------------------------------------------------

/// Правила размещения инженерных систем.
class EngineeringRule {
  /// Санузлы друг над другом — стояки вертикально.
  static const bool bathroomsVerticallyAligned = true;

  /// Максимальное расстояние от стояка до сантехприбора, м.
  static const double maxPipeRunFromStack = 3.0;

  /// Минимальный размер котельной для газового котла, м².
  static const double minBoilerRoomArea = 6.0;

  /// Минимальная высота потолка котельной, м.
  static const double minBoilerRoomHeight = 2.5;

  /// Обязательное окно в котельной (площадь остекления, м²).
  static const double minBoilerRoomWindowArea = 0.03; // м²/м³ объёма

  /// Котельная — на наружной стене с отдельным выходом.
  static const bool boilerRoomExternalAccess = true;

  /// Минимальный объём котельной, м³.
  static const double minBoilerRoomVolume = 15.0;

  /// Вентиляция: кухня, санузлы и котельная — вытяжные каналы.
  static const Set<String> roomsRequiringExhaust = {
    'kitchen',
    'kitchenDining',
    'bathroom',
    'masterBathroom',
    'toilet',
    'boilerRoom',
    'laundry',
  };
}

// ---------------------------------------------------------------------------
// §10. Правила для разных площадей домов
// ---------------------------------------------------------------------------

/// Категория дома по площади — разные правила компоновки.
enum HouseSizeCategory {
  /// До 60 м² — микродом (дача, студия).
  micro,

  /// 60–100 м² — компактный.
  compact,

  /// 100–150 м² — стандартный.
  standard,

  /// 150–250 м² — комфортный.
  comfort,

  /// 250–400 м² — большой.
  large,

  /// 400+ м² — усадьба.
  estate,
}

/// Определяет категорию дома по общей площади.
HouseSizeCategory houseSizeCategory(double totalAreaM2) {
  if (totalAreaM2 < 60) return HouseSizeCategory.micro;
  if (totalAreaM2 < 100) return HouseSizeCategory.compact;
  if (totalAreaM2 < 150) return HouseSizeCategory.standard;
  if (totalAreaM2 < 250) return HouseSizeCategory.comfort;
  if (totalAreaM2 < 400) return HouseSizeCategory.large;
  return HouseSizeCategory.estate;
}

/// Рекомендуемый состав комнат по категории дома.
const Map<HouseSizeCategory, Map<String, int>> kRecommendedRoomsBySize = {
  HouseSizeCategory.micro: {
    'livingRoom': 1,
    'bedroom': 1,
    'kitchen': 1,
    'bathroom': 1,
    'hallway': 1,
  },
  HouseSizeCategory.compact: {
    'livingRoom': 1,
    'bedroom': 2,
    'kitchen': 1,
    'bathroom': 1,
    'hallway': 1,
    'boilerRoom': 1,
  },
  HouseSizeCategory.standard: {
    'livingRoom': 1,
    'bedroom': 3,
    'kitchen': 1,
    'bathroom': 2,
    'hallway': 1,
    'boilerRoom': 1,
    'storage': 1,
  },
  HouseSizeCategory.comfort: {
    'livingRoom': 1,
    'bedroom': 3,
    'masterBedroom': 1,
    'kitchen': 1,
    'dining': 1,
    'bathroom': 2,
    'masterBathroom': 1,
    'study': 1,
    'hallway': 1,
    'boilerRoom': 1,
    'wardrobe': 1,
    'storage': 1,
    'laundry': 1,
  },
  HouseSizeCategory.large: {
    'livingRoom': 1,
    'bedroom': 3,
    'masterBedroom': 1,
    'kidsRoom': 2,
    'kitchenDining': 1,
    'dining': 1,
    'bathroom': 3,
    'masterBathroom': 1,
    'study': 1,
    'hallway': 1,
    'boilerRoom': 1,
    'wardrobe': 2,
    'storage': 2,
    'laundry': 1,
    'pantry': 1,
    'garage': 1,
    'terrace': 1,
  },
  HouseSizeCategory.estate: {
    'livingRoom': 2,
    'bedroom': 4,
    'masterBedroom': 1,
    'kidsRoom': 2,
    'kitchenDining': 1,
    'dining': 1,
    'bathroom': 4,
    'masterBathroom': 1,
    'study': 2,
    'hallway': 1,
    'boilerRoom': 1,
    'wardrobe': 3,
    'storage': 2,
    'laundry': 1,
    'pantry': 1,
    'garage': 1,
    'terrace': 1,
    'balcony': 2,
  },
};

// ---------------------------------------------------------------------------
// §11. Коэффициенты эффективности планировки
// ---------------------------------------------------------------------------

/// Метрики качества планировки.
class LayoutEfficiency {
  /// Процент полезной площади (жилые + общественные) от общей.
  /// Отличная планировка: > 75%. Хорошая: 65-75%. Плохая: < 65%.
  static double usableAreaRatio(double usableArea, double totalArea) {
    if (totalArea <= 0) return 0;
    return usableArea / totalArea;
  }

  /// Коэффициент компактности: соотношение периметра к площади.
  /// Чем ближе к квадрату, тем энергоэффективнее.
  static double compactnessRatio(double perimeterM, double areaM2) {
    if (areaM2 <= 0) return 0;
    final idealPerimeter = 4 * math.sqrt(areaM2);
    return idealPerimeter / perimeterM;
  }

  /// Рекомендуемая площадь коридоров: не более 20% от этажа.
  static const double maxCorridorShare = 0.20;

  /// Рекомендуемая площадь «мокрых зон» (санузлы + кухня + постирочная).
  static const double maxWetZoneShare = 0.25;
}
