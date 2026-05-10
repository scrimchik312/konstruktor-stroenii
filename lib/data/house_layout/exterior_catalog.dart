/// Каталог элементов экстерьера: крыша, фасад, крыльцо, забор, ландшафт.
///
/// Содержит типовые варианты для каждого элемента с ценами,
/// техническими характеристиками и совместимостью со стилями.
library;

// ---------------------------------------------------------------------------
// Водосточная система
// ---------------------------------------------------------------------------

enum GutterMaterial {
  pvcPlastic,
  galvanizedSteel,
  copper,
  aluminum,
}

class GutterOption {
  final String id;
  final GutterMaterial material;
  final String name;
  final double diameterMm;
  final double pricePerM;

  const GutterOption({
    required this.id,
    required this.material,
    required this.name,
    required this.diameterMm,
    required this.pricePerM,
  });
}

const List<GutterOption> kGutterCatalog = [
  GutterOption(
    id: 'gutter_pvc_125',
    material: GutterMaterial.pvcPlastic,
    name: 'ПВХ 125 мм',
    diameterMm: 125,
    pricePerM: 350,
  ),
  GutterOption(
    id: 'gutter_steel_125',
    material: GutterMaterial.galvanizedSteel,
    name: 'Оцинковка 125 мм',
    diameterMm: 125,
    pricePerM: 500,
  ),
  GutterOption(
    id: 'gutter_alu_150',
    material: GutterMaterial.aluminum,
    name: 'Алюминий 150 мм',
    diameterMm: 150,
    pricePerM: 900,
  ),
];

// ---------------------------------------------------------------------------
// Забор
// ---------------------------------------------------------------------------

enum FenceType {
  metalProfiled,
  metalForged,
  woodBoard,
  woodPicket,
  brickWithMetal,
  stoneWithMetal,
  meshChainLink,
  polycarbonate,
}

class FenceOption {
  final String id;
  final FenceType type;
  final String name;
  final double heightM;
  final double pricePerM;

  const FenceOption({
    required this.id,
    required this.type,
    required this.name,
    required this.heightM,
    required this.pricePerM,
  });
}

const List<FenceOption> kFenceCatalog = [
  FenceOption(
    id: 'fence_prof_18',
    type: FenceType.metalProfiled,
    name: 'Профнастил 1.8 м',
    heightM: 1.8,
    pricePerM: 1800,
  ),
  FenceOption(
    id: 'fence_prof_20',
    type: FenceType.metalProfiled,
    name: 'Профнастил 2.0 м',
    heightM: 2.0,
    pricePerM: 2200,
  ),
  FenceOption(
    id: 'fence_forged',
    type: FenceType.metalForged,
    name: 'Кованый забор',
    heightM: 1.8,
    pricePerM: 5000,
  ),
  FenceOption(
    id: 'fence_wood_board',
    type: FenceType.woodBoard,
    name: 'Деревянный забор (доска)',
    heightM: 1.8,
    pricePerM: 2500,
  ),
  FenceOption(
    id: 'fence_brick_metal',
    type: FenceType.brickWithMetal,
    name: 'Кирпичные столбы + ковка',
    heightM: 2.0,
    pricePerM: 8000,
  ),
  FenceOption(
    id: 'fence_mesh',
    type: FenceType.meshChainLink,
    name: 'Сетка-рабица',
    heightM: 1.5,
    pricePerM: 600,
  ),
];

// ---------------------------------------------------------------------------
// Ворота / калитка
// ---------------------------------------------------------------------------

enum GateType {
  swing,
  sliding,
  sectional,
  rollUp,
}

class GateOption {
  final String id;
  final GateType type;
  final String name;
  final double widthM;
  final double heightM;
  final double priceRub;
  final bool motorized;

  const GateOption({
    required this.id,
    required this.type,
    required this.name,
    required this.widthM,
    required this.heightM,
    required this.priceRub,
    this.motorized = false,
  });
}

const List<GateOption> kGateCatalog = [
  GateOption(
    id: 'gate_swing_3',
    type: GateType.swing,
    name: 'Распашные ворота 3 м',
    widthM: 3.0,
    heightM: 1.8,
    priceRub: 25000,
  ),
  GateOption(
    id: 'gate_sliding_4',
    type: GateType.sliding,
    name: 'Откатные ворота 4 м',
    widthM: 4.0,
    heightM: 2.0,
    priceRub: 45000,
  ),
  GateOption(
    id: 'gate_sliding_motor',
    type: GateType.sliding,
    name: 'Откатные с автоматикой',
    widthM: 4.0,
    heightM: 2.0,
    priceRub: 85000,
    motorized: true,
  ),
  GateOption(
    id: 'gate_sectional',
    type: GateType.sectional,
    name: 'Секционные (гараж)',
    widthM: 3.0,
    heightM: 2.2,
    priceRub: 60000,
    motorized: true,
  ),
];

// ---------------------------------------------------------------------------
// Отмостка
// ---------------------------------------------------------------------------

enum BlindAreaMaterial {
  concrete,
  paving,
  gravel,
  tile,
  asphalt,
}

class BlindAreaOption {
  final String id;
  final BlindAreaMaterial material;
  final String name;
  final double widthM;
  final double pricePerM2;

  const BlindAreaOption({
    required this.id,
    required this.material,
    required this.name,
    required this.widthM,
    required this.pricePerM2,
  });
}

const List<BlindAreaOption> kBlindAreaCatalog = [
  BlindAreaOption(
    id: 'blind_concrete',
    material: BlindAreaMaterial.concrete,
    name: 'Бетонная отмостка',
    widthM: 1.0,
    pricePerM2: 800,
  ),
  BlindAreaOption(
    id: 'blind_paving',
    material: BlindAreaMaterial.paving,
    name: 'Тротуарная плитка',
    widthM: 1.0,
    pricePerM2: 1500,
  ),
  BlindAreaOption(
    id: 'blind_gravel',
    material: BlindAreaMaterial.gravel,
    name: 'Щебень + геотекстиль',
    widthM: 0.8,
    pricePerM2: 400,
  ),
];

// ---------------------------------------------------------------------------
// Крыльцо / входная группа
// ---------------------------------------------------------------------------

enum PorchStyle {
  open,
  covered,
  enclosed,
  withRamp,
}

class PorchOption {
  final String id;
  final PorchStyle style;
  final String name;
  final String material; // 'concrete', 'wood', 'stone', 'metal'
  final double widthM;
  final double depthM;
  final int stepsCount;
  final bool hasRailing;
  final bool hasRoof;
  final double priceRub;

  const PorchOption({
    required this.id,
    required this.style,
    required this.name,
    required this.material,
    required this.widthM,
    required this.depthM,
    required this.stepsCount,
    required this.hasRailing,
    required this.hasRoof,
    required this.priceRub,
  });
}

const List<PorchOption> kPorchCatalog = [
  PorchOption(
    id: 'porch_concrete_open',
    style: PorchStyle.open,
    name: 'Бетонное крыльцо (открытое)',
    material: 'concrete',
    widthM: 1.5,
    depthM: 1.2,
    stepsCount: 3,
    hasRailing: true,
    hasRoof: false,
    priceRub: 30000,
  ),
  PorchOption(
    id: 'porch_concrete_covered',
    style: PorchStyle.covered,
    name: 'Бетонное крыльцо (с козырьком)',
    material: 'concrete',
    widthM: 2.0,
    depthM: 1.5,
    stepsCount: 4,
    hasRailing: true,
    hasRoof: true,
    priceRub: 60000,
  ),
  PorchOption(
    id: 'porch_wood',
    style: PorchStyle.covered,
    name: 'Деревянное крыльцо',
    material: 'wood',
    widthM: 2.0,
    depthM: 1.5,
    stepsCount: 3,
    hasRailing: true,
    hasRoof: true,
    priceRub: 45000,
  ),
];
