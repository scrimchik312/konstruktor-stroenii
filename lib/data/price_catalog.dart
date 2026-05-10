/// Справочник базовых цен материалов и работ.
///
/// Все цены — **ориентировочные**, по состоянию на 2-й квартал 2025 г.
/// Источники: усреднённые по сетям Леруа Мерлен / Petrovich /
/// «Сатурн» / СтройОПТ; работы — по укрупнённым нормативам ФЕР-2020
/// в редакции Минстроя 2024 г. Без НДС (НДС добавляется в `Estimate`
/// отдельной строкой). Регион учитывается множителем
/// [RegionPriceFactors].
///
/// Каждая позиция привязана к разделу сметы [EstimateSection] и
/// единице измерения. Идентификатор `id` стабилен и используется
/// для override'ов цены пользователем (см. `priceOverrides` в проекте).
///
/// **Не путать со спецификацией материалов в PDF**: спецификация —
/// это нормативные физические свойства (Rb, плотность, ГОСТ), а тут
/// только цены и норма расхода для сметы.
library;

/// Раздел сметы — соответствует разделам ВОР по СП в РФ.
enum EstimateSection {
  foundation,
  walls,
  floorSlabs,
  roof,
  engineering,
  finishing;

  String get title {
    switch (this) {
      case EstimateSection.foundation:
        return 'Фундамент';
      case EstimateSection.walls:
        return 'Стены и перегородки';
      case EstimateSection.floorSlabs:
        return 'Перекрытия';
      case EstimateSection.roof:
        return 'Кровля';
      case EstimateSection.engineering:
        return 'Инженерные системы';
      case EstimateSection.finishing:
        return 'Отделка и заполнения проёмов';
    }
  }

  String get shortTitle {
    switch (this) {
      case EstimateSection.foundation:
        return 'Фундамент';
      case EstimateSection.walls:
        return 'Стены';
      case EstimateSection.floorSlabs:
        return 'Перекрытия';
      case EstimateSection.roof:
        return 'Кровля';
      case EstimateSection.engineering:
        return 'Инженерка';
      case EstimateSection.finishing:
        return 'Отделка';
    }
  }
}

/// Тип строки сметы: материал, работа или комплекс.
enum EstimateItemKind {
  material,
  work,
  composite;

  String get title {
    switch (this) {
      case EstimateItemKind.material:
        return 'Материал';
      case EstimateItemKind.work:
        return 'Работа';
      case EstimateItemKind.composite:
        return 'Комплекс';
    }
  }
}

/// Позиция справочника цен.
class PriceItem {
  /// Стабильный идентификатор (snake_case). Используется в качестве
  /// ключа в `priceOverrides` проекта.
  final String id;
  final EstimateSection section;
  final EstimateItemKind kind;
  final String title;
  final String unit;
  final double basePrice;
  final String source;

  const PriceItem({
    required this.id,
    required this.section,
    required this.kind,
    required this.title,
    required this.unit,
    required this.basePrice,
    required this.source,
  });
}

/// Каталог цен. Все позиции в одной плоской таблице — UI группирует по
/// секциям. Добавление нового материала: дописать одну запись.
const List<PriceItem> kPriceCatalog = [
  // ────────────────────────────────────────────────────────────────
  // ФУНДАМЕНТ
  // ────────────────────────────────────────────────────────────────
  PriceItem(
    id: 'foundation_concrete_b25',
    section: EstimateSection.foundation,
    kind: EstimateItemKind.material,
    title: 'Бетон B25 (М350) товарный',
    unit: 'м³',
    basePrice: 7800,
    source: 'ср. цена ТМЦ-бетон 2025-Q2 (без доставки)',
  ),
  PriceItem(
    id: 'foundation_rebar_a500c',
    section: EstimateSection.foundation,
    kind: EstimateItemKind.material,
    title: 'Арматура A500С Ø12 мм',
    unit: 'т',
    basePrice: 72000,
    source: 'ГОСТ 34028-2016, биржевая цена 2025-Q2',
  ),
  PriceItem(
    id: 'foundation_formwork',
    section: EstimateSection.foundation,
    kind: EstimateItemKind.material,
    title: 'Опалубка щитовая (доска + крепёж, оборачиваемость 5)',
    unit: 'м²',
    basePrice: 650,
    source: 'усреднённо ФЕР-2020 раздел 6',
  ),
  PriceItem(
    id: 'foundation_sand_gravel_pad',
    section: EstimateSection.foundation,
    kind: EstimateItemKind.material,
    title: 'Подушка песчано-гравийная (с уплотнением)',
    unit: 'м³',
    basePrice: 1500,
    source: 'ср. карьерная цена ПГС с доставкой',
  ),
  PriceItem(
    id: 'foundation_waterproofing',
    section: EstimateSection.foundation,
    kind: EstimateItemKind.material,
    title: 'Гидроизоляция оклеечная (рулонная битумная, 2 слоя)',
    unit: 'м²',
    basePrice: 280,
    source: 'ГОСТ 30547-97, ср. розничная цена 2025-Q2',
  ),
  PriceItem(
    id: 'foundation_screw_pile_d108',
    section: EstimateSection.foundation,
    kind: EstimateItemKind.composite,
    title: 'Винтовая свая Ø108×3000 мм с монтажом',
    unit: 'шт',
    basePrice: 4500,
    source: 'ср. цена с установкой 2025-Q2',
  ),
  PriceItem(
    id: 'foundation_bored_pile_d300',
    section: EstimateSection.foundation,
    kind: EstimateItemKind.composite,
    title: 'Буронабивная свая Ø300, бетон B20 + А500',
    unit: 'м.п.',
    basePrice: 3200,
    source: 'ср. ФЕР сб. 5 + материалы',
  ),
  PriceItem(
    id: 'foundation_work_strip',
    section: EstimateSection.foundation,
    kind: EstimateItemKind.work,
    title: 'Устройство ленточного фундамента (земляные + бетонные работы)',
    unit: 'м³',
    basePrice: 4200,
    source: 'ФЕР 06-01-001 (рук-вод. 2024), без материалов',
  ),
  PriceItem(
    id: 'foundation_work_slab',
    section: EstimateSection.foundation,
    kind: EstimateItemKind.work,
    title: 'Устройство монолитной плиты (армирование + бетонирование)',
    unit: 'м³',
    basePrice: 3800,
    source: 'ФЕР 06-01-014, без материалов',
  ),

  // ────────────────────────────────────────────────────────────────
  // СТЕНЫ
  // ────────────────────────────────────────────────────────────────
  PriceItem(
    id: 'wall_brick_solid',
    section: EstimateSection.walls,
    kind: EstimateItemKind.material,
    title: 'Кирпич рядовой полнотелый M150 (250×120×65)',
    unit: 'шт',
    basePrice: 14,
    source: 'ГОСТ 530-2012, ср. розница 2025-Q2',
  ),
  PriceItem(
    id: 'wall_aerated_d500',
    section: EstimateSection.walls,
    kind: EstimateItemKind.material,
    title: 'Газобетон D500 B2.5 (600×300×200) — на 1 м³',
    unit: 'м³',
    basePrice: 6500,
    source: 'ГОСТ 31360-2007, ср. розница 2025-Q2',
  ),
  PriceItem(
    id: 'wall_expanded_clay_block',
    section: EstimateSection.walls,
    kind: EstimateItemKind.material,
    title: 'Керамзитоблок 4-щ. (390×190×190) — на 1 м³',
    unit: 'м³',
    basePrice: 4800,
    source: 'ГОСТ 6133-2019, ср. розница 2025-Q2',
  ),
  PriceItem(
    id: 'wall_timber_150',
    section: EstimateSection.walls,
    kind: EstimateItemKind.material,
    title: 'Брус сосновый профилированный 150×150 мм',
    unit: 'м³',
    basePrice: 17500,
    source: 'ГОСТ 8242-88, ср. розница 2025-Q2',
  ),
  PriceItem(
    id: 'wall_frame_lumber_50x150',
    section: EstimateSection.walls,
    kind: EstimateItemKind.material,
    title: 'Доска обрезная 50×150 мм для каркаса (сосна, II сорт)',
    unit: 'м³',
    basePrice: 14500,
    source: 'ГОСТ 24454-80, ср. розница',
  ),
  PriceItem(
    id: 'wall_osb_12',
    section: EstimateSection.walls,
    kind: EstimateItemKind.material,
    title: 'OSB-3 12 мм',
    unit: 'м²',
    basePrice: 580,
    source: 'EN 300, ср. розница',
  ),
  PriceItem(
    id: 'wall_mineral_wool_100',
    section: EstimateSection.walls,
    kind: EstimateItemKind.material,
    title: 'Минвата плотностью 35 кг/м³, толщ. 100 мм',
    unit: 'м²',
    basePrice: 320,
    source: 'ГОСТ 4640-2011, базальт. ср. розница',
  ),
  PriceItem(
    id: 'wall_vapor_barrier',
    section: EstimateSection.walls,
    kind: EstimateItemKind.material,
    title: 'Пароизоляционная плёнка',
    unit: 'м²',
    basePrice: 50,
    source: 'ср. розница 2025-Q2',
  ),
  PriceItem(
    id: 'wall_wind_membrane',
    section: EstimateSection.walls,
    kind: EstimateItemKind.material,
    title: 'Ветрогидрозащитная мембрана',
    unit: 'м²',
    basePrice: 70,
    source: 'ср. розница 2025-Q2',
  ),
  PriceItem(
    id: 'wall_masonry_mortar',
    section: EstimateSection.walls,
    kind: EstimateItemKind.material,
    title: 'Раствор кладочный M100 (готовый сухой)',
    unit: 'м³',
    basePrice: 5200,
    source: 'ГОСТ 28013-98, ср. розница',
  ),
  PriceItem(
    id: 'wall_masonry_mesh',
    section: EstimateSection.walls,
    kind: EstimateItemKind.material,
    title: 'Кладочная сетка 50×50×3 мм',
    unit: 'м²',
    basePrice: 90,
    source: 'ГОСТ 23279-2012, ср. розница',
  ),
  PriceItem(
    id: 'wall_work_masonry',
    section: EstimateSection.walls,
    kind: EstimateItemKind.work,
    title: 'Кладка стен из блоков/кирпича',
    unit: 'м³',
    basePrice: 3600,
    source: 'ФЕР 08-02-001, без материалов',
  ),
  PriceItem(
    id: 'wall_work_frame',
    section: EstimateSection.walls,
    kind: EstimateItemKind.work,
    title: 'Сборка каркасной стены (стойки + обшивка)',
    unit: 'м²',
    basePrice: 1200,
    source: 'ФЕР 10-01-077, без материалов',
  ),
  PriceItem(
    id: 'wall_work_timber',
    section: EstimateSection.walls,
    kind: EstimateItemKind.work,
    title: 'Сборка стен из бруса с шкантованием',
    unit: 'м³',
    basePrice: 4500,
    source: 'ФЕР 10-01-024, без материалов',
  ),

  // ────────────────────────────────────────────────────────────────
  // ПЕРЕКРЫТИЯ
  // ────────────────────────────────────────────────────────────────
  PriceItem(
    id: 'slab_monolith_concrete',
    section: EstimateSection.floorSlabs,
    kind: EstimateItemKind.material,
    title: 'Бетон B25 для монолитного перекрытия',
    unit: 'м³',
    basePrice: 7800,
    source: 'ГОСТ 26633-2015',
  ),
  PriceItem(
    id: 'slab_monolith_rebar',
    section: EstimateSection.floorSlabs,
    kind: EstimateItemKind.material,
    title: 'Арматура A500С для монолитного перекрытия',
    unit: 'т',
    basePrice: 72000,
    source: 'ГОСТ 34028-2016',
  ),
  PriceItem(
    id: 'slab_precast_pk',
    section: EstimateSection.floorSlabs,
    kind: EstimateItemKind.composite,
    title: 'Плита перекрытия ПК (сборный ж/б), типовая',
    unit: 'м²',
    basePrice: 4200,
    source: 'серия 1.141-1, ср. цена 2025-Q2',
  ),
  PriceItem(
    id: 'slab_wood_beam',
    section: EstimateSection.floorSlabs,
    kind: EstimateItemKind.material,
    title: 'Балка деревянная 100×200 мм, сосна',
    unit: 'м³',
    basePrice: 17500,
    source: 'ГОСТ 8486-86',
  ),
  PriceItem(
    id: 'slab_metal_beam',
    section: EstimateSection.floorSlabs,
    kind: EstimateItemKind.material,
    title: 'Балка металлическая (двутавр 20Б1)',
    unit: 'т',
    basePrice: 95000,
    source: 'ГОСТ 26020-83',
  ),
  PriceItem(
    id: 'slab_floor_sheathing',
    section: EstimateSection.floorSlabs,
    kind: EstimateItemKind.material,
    title: 'Обшивка перекрытия (доска + черновой пол)',
    unit: 'м²',
    basePrice: 850,
    source: 'композит — материалы по укрупнённой норме',
  ),
  PriceItem(
    id: 'slab_work_monolith',
    section: EstimateSection.floorSlabs,
    kind: EstimateItemKind.work,
    title: 'Устройство монолитного перекрытия',
    unit: 'м²',
    basePrice: 1900,
    source: 'ФЕР 06-01-041, без материалов',
  ),
  PriceItem(
    id: 'slab_work_precast',
    section: EstimateSection.floorSlabs,
    kind: EstimateItemKind.work,
    title: 'Монтаж сборных плит перекрытия',
    unit: 'м²',
    basePrice: 850,
    source: 'ФЕР 07-05-001, без материалов',
  ),
  PriceItem(
    id: 'slab_work_wood_beams',
    section: EstimateSection.floorSlabs,
    kind: EstimateItemKind.work,
    title: 'Устройство деревянного перекрытия по балкам',
    unit: 'м²',
    basePrice: 950,
    source: 'ФЕР 10-01-002',
  ),

  // ────────────────────────────────────────────────────────────────
  // КРОВЛЯ
  // ────────────────────────────────────────────────────────────────
  PriceItem(
    id: 'roof_rafter_lumber',
    section: EstimateSection.roof,
    kind: EstimateItemKind.material,
    title: 'Стропильный пиломатериал (50×200, сосна)',
    unit: 'м³',
    basePrice: 16500,
    source: 'ГОСТ 24454-80',
  ),
  PriceItem(
    id: 'roof_lathing',
    section: EstimateSection.roof,
    kind: EstimateItemKind.material,
    title: 'Обрешётка кровельная (доска 25×100)',
    unit: 'м³',
    basePrice: 14000,
    source: 'ГОСТ 24454-80',
  ),
  PriceItem(
    id: 'roof_underlay_membrane',
    section: EstimateSection.roof,
    kind: EstimateItemKind.material,
    title: 'Подкровельная гидроизоляционная плёнка',
    unit: 'м²',
    basePrice: 80,
    source: 'ср. розница 2025-Q2',
  ),
  PriceItem(
    id: 'roof_insulation_200',
    section: EstimateSection.roof,
    kind: EstimateItemKind.material,
    title: 'Утеплитель базальт 200 мм (для мансарды)',
    unit: 'м²',
    basePrice: 580,
    source: 'ГОСТ 4640-2011',
  ),
  PriceItem(
    id: 'roof_metal_tile',
    section: EstimateSection.roof,
    kind: EstimateItemKind.material,
    title: 'Металлочерепица (полиэстер, 0.45 мм)',
    unit: 'м²',
    basePrice: 580,
    source: 'ГОСТ Р 58153-2018, ср. розница',
  ),
  PriceItem(
    id: 'roof_soft_tile',
    section: EstimateSection.roof,
    kind: EstimateItemKind.material,
    title: 'Гибкая черепица (битумная) с подкладкой',
    unit: 'м²',
    basePrice: 720,
    source: 'ГОСТ Р 56598-2015',
  ),
  PriceItem(
    id: 'roof_clay_tile',
    section: EstimateSection.roof,
    kind: EstimateItemKind.material,
    title: 'Натуральная керамическая черепица',
    unit: 'м²',
    basePrice: 1850,
    source: 'EN 1304, ср. розница 2025-Q2',
  ),
  PriceItem(
    id: 'roof_corrugated_sheet',
    section: EstimateSection.roof,
    kind: EstimateItemKind.material,
    title: 'Профлист C20 (полиэстер)',
    unit: 'м²',
    basePrice: 480,
    source: 'ГОСТ 24045-2016',
  ),
  PriceItem(
    id: 'roof_work_pitched',
    section: EstimateSection.roof,
    kind: EstimateItemKind.work,
    title: 'Устройство скатной кровли с утеплением',
    unit: 'м²',
    basePrice: 950,
    source: 'ФЕР 12-01-018, без материалов',
  ),
  PriceItem(
    id: 'roof_work_flat',
    section: EstimateSection.roof,
    kind: EstimateItemKind.work,
    title: 'Устройство плоской кровли (наплавляемой)',
    unit: 'м²',
    basePrice: 780,
    source: 'ФЕР 12-01-002, без материалов',
  ),

  // ────────────────────────────────────────────────────────────────
  // ИНЖЕНЕРКА (укрупнённо, по м² жилой)
  // ────────────────────────────────────────────────────────────────
  PriceItem(
    id: 'eng_electrical',
    section: EstimateSection.engineering,
    kind: EstimateItemKind.composite,
    title: 'Электрика (щит, кабель, розетки/выключатели, осветители)',
    unit: 'м² общ.',
    basePrice: 1800,
    source: 'СП 256.1325800.2016, укрупн. норматив',
  ),
  PriceItem(
    id: 'eng_water_supply',
    section: EstimateSection.engineering,
    kind: EstimateItemKind.composite,
    title: 'Водоснабжение и канализация (трубы, фитинги, монтаж)',
    unit: 'точка',
    basePrice: 8500,
    source: 'СП 30.13330.2020, по точкам подключения',
  ),
  PriceItem(
    id: 'eng_heating_radiator',
    section: EstimateSection.engineering,
    kind: EstimateItemKind.composite,
    title: 'Отопление радиаторное (котёл, контур, радиаторы)',
    unit: 'м² общ.',
    basePrice: 1900,
    source: 'СП 60.13330.2020, укрупн. норматив',
  ),
  PriceItem(
    id: 'eng_ventilation',
    section: EstimateSection.engineering,
    kind: EstimateItemKind.composite,
    title: 'Приточно-вытяжная вентиляция',
    unit: 'м² общ.',
    basePrice: 1100,
    source: 'СП 60.13330.2020, укрупн. норматив',
  ),
  PriceItem(
    id: 'eng_gas',
    section: EstimateSection.engineering,
    kind: EstimateItemKind.composite,
    title: 'Газоснабжение (внутренний газопровод)',
    unit: 'м² общ.',
    basePrice: 700,
    source: 'СП 62.13330.2011, укрупн. норматив',
  ),

  // ────────────────────────────────────────────────────────────────
  // ОТДЕЛКА И ПРОЁМЫ
  // ────────────────────────────────────────────────────────────────
  PriceItem(
    id: 'finish_plaster',
    section: EstimateSection.finishing,
    kind: EstimateItemKind.composite,
    title: 'Штукатурка стен по маякам (с материалами)',
    unit: 'м²',
    basePrice: 720,
    source: 'ФЕР 15-02-018 + материалы',
  ),
  PriceItem(
    id: 'finish_putty',
    section: EstimateSection.finishing,
    kind: EstimateItemKind.composite,
    title: 'Шпаклёвка стен и потолков (2 слоя)',
    unit: 'м²',
    basePrice: 320,
    source: 'ФЕР 15-04-005 + материалы',
  ),
  PriceItem(
    id: 'finish_paint',
    section: EstimateSection.finishing,
    kind: EstimateItemKind.composite,
    title: 'Окраска водоэмульсионная (2 слоя)',
    unit: 'м²',
    basePrice: 240,
    source: 'ФЕР 15-04-025',
  ),
  PriceItem(
    id: 'finish_screed',
    section: EstimateSection.finishing,
    kind: EstimateItemKind.composite,
    title: 'Стяжка пола ЦПС 50 мм',
    unit: 'м²',
    basePrice: 720,
    source: 'ФЕР 11-01-011',
  ),
  PriceItem(
    id: 'finish_floor_laminate',
    section: EstimateSection.finishing,
    kind: EstimateItemKind.composite,
    title: 'Покрытие пола ламинат 33 класс с подложкой',
    unit: 'м²',
    basePrice: 1200,
    source: 'ср. розница 2025-Q2',
  ),
  PriceItem(
    id: 'finish_floor_tile',
    section: EstimateSection.finishing,
    kind: EstimateItemKind.composite,
    title: 'Покрытие пола керамогранит',
    unit: 'м²',
    basePrice: 2200,
    source: 'ГОСТ Р 57141-2016, ср. розница',
  ),
  PriceItem(
    id: 'finish_window_pvc',
    section: EstimateSection.finishing,
    kind: EstimateItemKind.composite,
    title: 'Окно ПВХ 2-камерный профиль (1.4 × 1.5 м), с монтажом',
    unit: 'м²',
    basePrice: 6800,
    source: 'ГОСТ 30674-99, ср. розница',
  ),
  PriceItem(
    id: 'finish_door_internal',
    section: EstimateSection.finishing,
    kind: EstimateItemKind.composite,
    title: 'Дверь межкомнатная (полотно + коробка + наличник)',
    unit: 'шт',
    basePrice: 7500,
    source: 'ГОСТ 6629-88, ср. розница',
  ),
  PriceItem(
    id: 'finish_door_entry',
    section: EstimateSection.finishing,
    kind: EstimateItemKind.composite,
    title: 'Дверь входная металлическая утеплённая',
    unit: 'шт',
    basePrice: 28000,
    source: 'ГОСТ 31173-2016, ср. розница',
  ),
];

/// Удобный поиск по `id` (используется при override).
PriceItem? findPriceItem(String id) {
  for (final p in kPriceCatalog) {
    if (p.id == id) return p;
  }
  return null;
}
