/// Каталог отделочных материалов для модуля планировки.
///
/// Включает: напольные покрытия, настенные покрытия, потолки,
/// плитку, сантехнику, освещение и фурнитуру. Все цены ориентировочные
/// (₽, средний ценовой сегмент, 2024–2025).
library;

// ---------------------------------------------------------------------------
// Напольные покрытия
// ---------------------------------------------------------------------------

/// Категория напольного покрытия.
enum FlooringCategory {
  laminate,
  engineeredWood,
  hardwood,
  tile,
  porcelainTile,
  vinyl,
  linoleum,
  carpet,
  concrete,
  cork,
  marble,
  granite,
}

/// Один вариант напольного покрытия.
class FlooringOption {
  final String id;
  final FlooringCategory category;
  final String name;
  final String description;
  final double pricePerM2;
  final double thicknessMm;
  final bool waterResistant;
  final bool underfloorHeatingCompatible;
  final int wearClass; // 21–34 по EN 13329 (для ламината)
  final Set<String> suitableRooms;

  const FlooringOption({
    required this.id,
    required this.category,
    required this.name,
    required this.description,
    required this.pricePerM2,
    required this.thicknessMm,
    required this.waterResistant,
    required this.underfloorHeatingCompatible,
    this.wearClass = 0,
    required this.suitableRooms,
  });
}

const List<FlooringOption> kFlooringCatalog = [
  FlooringOption(
    id: 'lam_32',
    category: FlooringCategory.laminate,
    name: 'Ламинат 32 класс',
    description: 'Ламинат средней износостойкости, толщина 8 мм',
    pricePerM2: 800,
    thicknessMm: 8,
    waterResistant: false,
    underfloorHeatingCompatible: true,
    wearClass: 32,
    suitableRooms: {'bedroom', 'livingRoom', 'study', 'kidsRoom', 'corridor'},
  ),
  FlooringOption(
    id: 'lam_33',
    category: FlooringCategory.laminate,
    name: 'Ламинат 33 класс',
    description: 'Ламинат повышенной износостойкости, толщина 12 мм',
    pricePerM2: 1200,
    thicknessMm: 12,
    waterResistant: false,
    underfloorHeatingCompatible: true,
    wearClass: 33,
    suitableRooms: {
      'bedroom',
      'livingRoom',
      'study',
      'kidsRoom',
      'corridor',
      'hallway',
    },
  ),
  FlooringOption(
    id: 'tile_ceramic',
    category: FlooringCategory.tile,
    name: 'Керамическая плитка',
    description: 'Напольная керамика, матовая, 30×30 см',
    pricePerM2: 1000,
    thicknessMm: 9,
    waterResistant: true,
    underfloorHeatingCompatible: true,
    suitableRooms: {
      'bathroom',
      'toilet',
      'kitchen',
      'hallway',
      'boilerRoom',
      'laundry',
      'terrace',
    },
  ),
  FlooringOption(
    id: 'tile_porcelain',
    category: FlooringCategory.porcelainTile,
    name: 'Керамогранит',
    description: 'Полированный керамогранит 60×60 см',
    pricePerM2: 1800,
    thicknessMm: 10,
    waterResistant: true,
    underfloorHeatingCompatible: true,
    suitableRooms: {
      'bathroom',
      'toilet',
      'kitchen',
      'hallway',
      'livingRoom',
      'corridor',
      'terrace',
    },
  ),
  FlooringOption(
    id: 'engineered_oak',
    category: FlooringCategory.engineeredWood,
    name: 'Инженерная доска (дуб)',
    description: 'Трёхслойная инженерная доска, дуб, лак',
    pricePerM2: 3500,
    thicknessMm: 14,
    waterResistant: false,
    underfloorHeatingCompatible: true,
    suitableRooms: {'bedroom', 'livingRoom', 'study', 'dining'},
  ),
  FlooringOption(
    id: 'vinyl_spc',
    category: FlooringCategory.vinyl,
    name: 'SPC ламинат (кварцвинил)',
    description: 'Кварцвиниловая плитка с жёстким основанием',
    pricePerM2: 1500,
    thicknessMm: 5,
    waterResistant: true,
    underfloorHeatingCompatible: true,
    wearClass: 34,
    suitableRooms: {
      'bedroom',
      'livingRoom',
      'kitchen',
      'hallway',
      'bathroom',
      'corridor',
    },
  ),
  FlooringOption(
    id: 'linoleum',
    category: FlooringCategory.linoleum,
    name: 'Линолеум полукоммерческий',
    description: 'ПВХ-линолеум на вспененной основе',
    pricePerM2: 500,
    thicknessMm: 3,
    waterResistant: true,
    underfloorHeatingCompatible: false,
    suitableRooms: {
      'kitchen',
      'hallway',
      'corridor',
      'storage',
      'laundry',
    },
  ),
];

// ---------------------------------------------------------------------------
// Настенные покрытия
// ---------------------------------------------------------------------------

enum WallFinishCategory {
  paint,
  wallpaper,
  decorativePlaster,
  ceramicTile,
  panels,
  stone,
  brick,
  wood,
}

class WallFinishOption {
  final String id;
  final WallFinishCategory category;
  final String name;
  final String description;
  final double pricePerM2;
  final bool moistureResistant;
  final Set<String> suitableRooms;

  const WallFinishOption({
    required this.id,
    required this.category,
    required this.name,
    required this.description,
    required this.pricePerM2,
    required this.moistureResistant,
    required this.suitableRooms,
  });
}

const List<WallFinishOption> kWallFinishCatalog = [
  WallFinishOption(
    id: 'paint_latex',
    category: WallFinishCategory.paint,
    name: 'Краска латексная',
    description: 'Интерьерная латексная краска, моющаяся',
    pricePerM2: 250,
    moistureResistant: true,
    suitableRooms: {
      'bedroom',
      'livingRoom',
      'study',
      'hallway',
      'corridor',
      'kidsRoom',
      'kitchen',
    },
  ),
  WallFinishOption(
    id: 'wallpaper_vinyl',
    category: WallFinishCategory.wallpaper,
    name: 'Обои виниловые',
    description: 'Виниловые обои на флизелиновой основе',
    pricePerM2: 400,
    moistureResistant: false,
    suitableRooms: {
      'bedroom',
      'livingRoom',
      'study',
      'kidsRoom',
      'dining',
    },
  ),
  WallFinishOption(
    id: 'tile_wall',
    category: WallFinishCategory.ceramicTile,
    name: 'Плитка настенная',
    description: 'Керамическая настенная плитка 20×30 см',
    pricePerM2: 900,
    moistureResistant: true,
    suitableRooms: {
      'bathroom',
      'toilet',
      'kitchen',
      'laundry',
      'boilerRoom',
    },
  ),
  WallFinishOption(
    id: 'plaster_decorative',
    category: WallFinishCategory.decorativePlaster,
    name: 'Декоративная штукатурка',
    description: 'Структурная / венецианская штукатурка',
    pricePerM2: 1200,
    moistureResistant: true,
    suitableRooms: {
      'livingRoom',
      'hallway',
      'dining',
      'corridor',
    },
  ),
  WallFinishOption(
    id: 'panels_mdf',
    category: WallFinishCategory.panels,
    name: 'Стеновые МДФ-панели',
    description: 'Ламинированные МДФ-панели под дерево',
    pricePerM2: 700,
    moistureResistant: false,
    suitableRooms: {'study', 'livingRoom', 'corridor', 'wardrobe'},
  ),
];

// ---------------------------------------------------------------------------
// Потолки
// ---------------------------------------------------------------------------

enum CeilingCategory {
  paint,
  stretch,
  suspended,
  panels,
  plasterboard,
  wood,
}

class CeilingOption {
  final String id;
  final CeilingCategory category;
  final String name;
  final String description;
  final double pricePerM2;
  final bool moistureResistant;
  final double dropMm; // понижение от перекрытия
  final Set<String> suitableRooms;

  const CeilingOption({
    required this.id,
    required this.category,
    required this.name,
    required this.description,
    required this.pricePerM2,
    required this.moistureResistant,
    required this.dropMm,
    required this.suitableRooms,
  });
}

const List<CeilingOption> kCeilingCatalog = [
  CeilingOption(
    id: 'stretch_matt',
    category: CeilingCategory.stretch,
    name: 'Натяжной матовый',
    description: 'ПВХ-полотно, белый мат',
    pricePerM2: 600,
    moistureResistant: true,
    dropMm: 40,
    suitableRooms: {
      'bedroom',
      'livingRoom',
      'study',
      'kitchen',
      'hallway',
      'corridor',
      'kidsRoom',
      'dining',
    },
  ),
  CeilingOption(
    id: 'stretch_gloss',
    category: CeilingCategory.stretch,
    name: 'Натяжной глянцевый',
    description: 'ПВХ-полотно, глянец — визуально увеличивает высоту',
    pricePerM2: 700,
    moistureResistant: true,
    dropMm: 40,
    suitableRooms: {'bathroom', 'toilet', 'kitchen', 'hallway'},
  ),
  CeilingOption(
    id: 'plasterboard',
    category: CeilingCategory.plasterboard,
    name: 'ГКЛ (гипсокартон)',
    description: 'Подвесной потолок из влагостойкого ГКЛ',
    pricePerM2: 900,
    moistureResistant: true,
    dropMm: 100,
    suitableRooms: {
      'bedroom',
      'livingRoom',
      'study',
      'kitchen',
      'hallway',
      'corridor',
      'bathroom',
    },
  ),
  CeilingOption(
    id: 'paint_ceiling',
    category: CeilingCategory.paint,
    name: 'Окраска по штукатурке',
    description: 'Выравнивание + покраска потолка',
    pricePerM2: 450,
    moistureResistant: false,
    dropMm: 0,
    suitableRooms: {
      'bedroom',
      'livingRoom',
      'study',
      'corridor',
      'storage',
    },
  ),
];

// ---------------------------------------------------------------------------
// Сантехника
// ---------------------------------------------------------------------------

enum PlumbingCategory {
  toilet,
  sink,
  bathtub,
  shower,
  bidet,
  washingMachine,
  kitchenSink,
  waterHeater,
}

class PlumbingFixture {
  final String id;
  final PlumbingCategory category;
  final String name;
  final double widthM;
  final double depthM;
  final double heightM;
  final double priceRub;
  final Set<String> suitableRooms;

  const PlumbingFixture({
    required this.id,
    required this.category,
    required this.name,
    required this.widthM,
    required this.depthM,
    required this.heightM,
    required this.priceRub,
    required this.suitableRooms,
  });
}

const List<PlumbingFixture> kPlumbingCatalog = [
  PlumbingFixture(
    id: 'toilet_comp',
    category: PlumbingCategory.toilet,
    name: 'Унитаз-компакт',
    widthM: 0.36,
    depthM: 0.65,
    heightM: 0.40,
    priceRub: 8000,
    suitableRooms: {'bathroom', 'toilet', 'masterBathroom'},
  ),
  PlumbingFixture(
    id: 'toilet_wall',
    category: PlumbingCategory.toilet,
    name: 'Подвесной унитаз',
    widthM: 0.36,
    depthM: 0.55,
    heightM: 0.40,
    priceRub: 15000,
    suitableRooms: {'bathroom', 'toilet', 'masterBathroom'},
  ),
  PlumbingFixture(
    id: 'sink_pedestal',
    category: PlumbingCategory.sink,
    name: 'Раковина на пьедестале',
    widthM: 0.55,
    depthM: 0.45,
    heightM: 0.85,
    priceRub: 5000,
    suitableRooms: {'bathroom', 'toilet', 'masterBathroom'},
  ),
  PlumbingFixture(
    id: 'sink_vanity',
    category: PlumbingCategory.sink,
    name: 'Раковина с тумбой',
    widthM: 0.60,
    depthM: 0.50,
    heightM: 0.85,
    priceRub: 12000,
    suitableRooms: {'bathroom', 'masterBathroom'},
  ),
  PlumbingFixture(
    id: 'bathtub_170',
    category: PlumbingCategory.bathtub,
    name: 'Ванна 170×75 см',
    widthM: 0.75,
    depthM: 1.70,
    heightM: 0.60,
    priceRub: 10000,
    suitableRooms: {'bathroom', 'masterBathroom'},
  ),
  PlumbingFixture(
    id: 'shower_90',
    category: PlumbingCategory.shower,
    name: 'Душевой поддон 90×90 см',
    widthM: 0.90,
    depthM: 0.90,
    heightM: 2.0,
    priceRub: 7000,
    suitableRooms: {'bathroom', 'masterBathroom'},
  ),
  PlumbingFixture(
    id: 'kitchen_sink',
    category: PlumbingCategory.kitchenSink,
    name: 'Мойка кухонная врезная',
    widthM: 0.50,
    depthM: 0.60,
    heightM: 0.20,
    priceRub: 5000,
    suitableRooms: {'kitchen', 'kitchenDining'},
  ),
];

// ---------------------------------------------------------------------------
// Окна (каталог стандартных изделий)
// ---------------------------------------------------------------------------

enum WindowProfile {
  pvc60,
  pvc70,
  pvc80,
  aluminum,
  timber,
}

class WindowOption {
  final String id;
  final WindowProfile profile;
  final String name;
  final double widthM;
  final double heightM;
  final int chambers; // камеры стеклопакета
  final double uValue; // Вт/(м²·К)
  final double priceRub;

  const WindowOption({
    required this.id,
    required this.profile,
    required this.name,
    required this.widthM,
    required this.heightM,
    required this.chambers,
    required this.uValue,
    required this.priceRub,
  });
}

const List<WindowOption> kWindowCatalog = [
  WindowOption(
    id: 'pvc60_1200x1400',
    profile: WindowProfile.pvc60,
    name: 'ПВХ 60 мм, 1200×1400',
    widthM: 1.2,
    heightM: 1.4,
    chambers: 2,
    uValue: 1.4,
    priceRub: 12000,
  ),
  WindowOption(
    id: 'pvc70_1500x1400',
    profile: WindowProfile.pvc70,
    name: 'ПВХ 70 мм, 1500×1400',
    widthM: 1.5,
    heightM: 1.4,
    chambers: 3,
    uValue: 1.0,
    priceRub: 18000,
  ),
  WindowOption(
    id: 'pvc70_1800x1500',
    profile: WindowProfile.pvc70,
    name: 'ПВХ 70 мм, 1800×1500',
    widthM: 1.8,
    heightM: 1.5,
    chambers: 3,
    uValue: 1.0,
    priceRub: 24000,
  ),
  WindowOption(
    id: 'pvc80_2100x1500',
    profile: WindowProfile.pvc80,
    name: 'ПВХ 80 мм (панорамное)',
    widthM: 2.1,
    heightM: 1.5,
    chambers: 3,
    uValue: 0.8,
    priceRub: 35000,
  ),
  WindowOption(
    id: 'timber_1200x1400',
    profile: WindowProfile.timber,
    name: 'Деревянное (сосна), 1200×1400',
    widthM: 1.2,
    heightM: 1.4,
    chambers: 2,
    uValue: 1.3,
    priceRub: 22000,
  ),
  WindowOption(
    id: 'bath_600x600',
    profile: WindowProfile.pvc60,
    name: 'ПВХ 60 мм, 600×600 (санузел)',
    widthM: 0.6,
    heightM: 0.6,
    chambers: 2,
    uValue: 1.4,
    priceRub: 6000,
  ),
];
