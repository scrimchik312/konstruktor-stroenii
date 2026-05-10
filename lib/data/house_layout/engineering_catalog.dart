/// Каталог инженерных систем: отопление, водоснабжение, канализация,
/// вентиляция, электрика, умный дом.
library;

// ---------------------------------------------------------------------------
// Отопление
// ---------------------------------------------------------------------------

class HeatingOption {
  final String id;
  final String name;
  final String type; // 'gas', 'electric', 'heatPump', 'solidFuel'
  final double powerKw;
  final double efficiencyPercent;
  final double priceRub;
  final String description;
  final double maxAreaM2;

  const HeatingOption({
    required this.id,
    required this.name,
    required this.type,
    required this.powerKw,
    required this.efficiencyPercent,
    required this.priceRub,
    required this.description,
    required this.maxAreaM2,
  });
}

const List<HeatingOption> kHeatingCatalog = [
  HeatingOption(
    id: 'boiler_gas_24',
    name: 'Газовый настенный котёл 24 кВт',
    type: 'gas',
    powerKw: 24,
    efficiencyPercent: 92,
    priceRub: 35000,
    description: 'Двухконтурный, закрытая камера сгорания',
    maxAreaM2: 200,
  ),
  HeatingOption(
    id: 'boiler_gas_35',
    name: 'Газовый котёл 35 кВт (напольный)',
    type: 'gas',
    powerKw: 35,
    efficiencyPercent: 93,
    priceRub: 65000,
    description: 'Напольный конденсационный, для больших домов',
    maxAreaM2: 350,
  ),
  HeatingOption(
    id: 'boiler_electric_12',
    name: 'Электрический котёл 12 кВт',
    type: 'electric',
    powerKw: 12,
    efficiencyPercent: 99,
    priceRub: 25000,
    description: 'Настенный, для домов до 120 м²',
    maxAreaM2: 120,
  ),
  HeatingOption(
    id: 'heat_pump_air',
    name: 'Тепловой насос воздух-вода',
    type: 'heatPump',
    powerKw: 16,
    efficiencyPercent: 300,
    priceRub: 350000,
    description: 'COP 3.0, работает до -25°C',
    maxAreaM2: 200,
  ),
  HeatingOption(
    id: 'boiler_pellet',
    name: 'Пеллетный котёл 25 кВт',
    type: 'solidFuel',
    powerKw: 25,
    efficiencyPercent: 90,
    priceRub: 120000,
    description: 'Автоматическая подача топлива',
    maxAreaM2: 250,
  ),
];

// ---------------------------------------------------------------------------
// Радиаторы
// ---------------------------------------------------------------------------

enum RadiatorType {
  steel,
  aluminum,
  bimetallic,
  castIron,
  underfloor,
}

class RadiatorOption {
  final String id;
  final RadiatorType type;
  final String name;
  final double heatOutputPerSection; // Вт
  final double pricePerSection;

  const RadiatorOption({
    required this.id,
    required this.type,
    required this.name,
    required this.heatOutputPerSection,
    required this.pricePerSection,
  });

  /// Рассчитывает количество секций для комнаты.
  int sectionsForRoom(double areaM2, {double wattsPerM2 = 100}) {
    if (heatOutputPerSection <= 0) return 0;
    return (areaM2 * wattsPerM2 / heatOutputPerSection).ceil();
  }
}

const List<RadiatorOption> kRadiatorCatalog = [
  RadiatorOption(
    id: 'rad_steel_22',
    type: RadiatorType.steel,
    name: 'Стальной панельный 22-тип',
    heatOutputPerSection: 1500, // Вт за панель 600×1000
    pricePerSection: 5000,
  ),
  RadiatorOption(
    id: 'rad_bimetal',
    type: RadiatorType.bimetallic,
    name: 'Биметаллический 500 мм',
    heatOutputPerSection: 180,
    pricePerSection: 700,
  ),
  RadiatorOption(
    id: 'rad_aluminum',
    type: RadiatorType.aluminum,
    name: 'Алюминиевый 500 мм',
    heatOutputPerSection: 190,
    pricePerSection: 500,
  ),
];

// ---------------------------------------------------------------------------
// Электрика
// ---------------------------------------------------------------------------

class ElectricalPanelOption {
  final String id;
  final String name;
  final int moduleCount;
  final double priceRub;

  const ElectricalPanelOption({
    required this.id,
    required this.name,
    required this.moduleCount,
    required this.priceRub,
  });
}

const List<ElectricalPanelOption> kElectricalPanelCatalog = [
  ElectricalPanelOption(
    id: 'panel_12',
    name: 'Щиток 12 модулей',
    moduleCount: 12,
    priceRub: 3000,
  ),
  ElectricalPanelOption(
    id: 'panel_24',
    name: 'Щиток 24 модуля',
    moduleCount: 24,
    priceRub: 5000,
  ),
  ElectricalPanelOption(
    id: 'panel_36',
    name: 'Щиток 36 модулей',
    moduleCount: 36,
    priceRub: 7000,
  ),
];

/// Рассчитывает общую электрическую мощность дома (кВт).
double estimateElectricalLoad(double areaM2, {bool hasElectricHeating = false}) {
  // Базовая нагрузка: ~50 Вт/м² (освещение + розетки).
  var load = areaM2 * 0.05;
  // Кухня: +5 кВт (плита, духовка, посудомойка).
  load += 5.0;
  // Водонагреватель: +2 кВт.
  load += 2.0;
  // Электроотопление.
  if (hasElectricHeating) {
    load += areaM2 * 0.1;
  }
  return load;
}
