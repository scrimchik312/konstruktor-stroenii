/// Альтернативные единицы измерения для строк сметы.
///
/// **Принцип целостности расчётов**:
///   Для каждого `PriceItem.id` базовая единица — та, что задана в
///   [kPriceCatalog]. Здесь же перечислены **взаимозаменяемые**
///   единицы и `factor = сколько данной единицы в 1 базовой`.
///
///   Когда пользователь меняет единицу на строке сметы:
///     • количество умножается на factor
///         qty_new = qty_base * factor
///     • цена за единицу делится на factor
///         price_new = price_base / factor
///     • ИТОГ строки (qty × price) остаётся **неизменным**, что и
///       гарантирует «целостность расчёта». Подход к расчёту меняется
///       только в плане отображения (м³ → шт → поддон → т),
///       а физический объём заказа — тот же.
///
///   Источники factors:
///     • для бетона/раствора — плотность 2400 кг/м³ (ГОСТ 26633-2015);
///     • для ПГС — 1700 кг/м³;
///     • для арматуры А500С Ø12 — 0.888 кг/м.п. (ГОСТ 34028-2016);
///     • для кирпича 250×120×65 — 0.00195 м³/шт ≈ 512 шт/м³,
///       поддон ≈ 280 шт = 0.546 м³ (СП 15.13330);
///     • для газобетона 600×300×200 — 0.036 м³/шт = 27.78 шт/м³,
///       поддон 1.8 м³;
///     • для керамзитоблока 390×190×190 — 0.0141 м³/шт = 71 шт/м³;
///     • для пиломатериала — расчёт через сечение (50×200 = 0.01 м²/м.п.);
///     • для рулонной/листовой продукции — типовые габариты упаковки.
library;

class UnitVariant {
  /// Единица измерения, как она показывается в смете и PDF.
  final String unit;

  /// Сколько данной единицы содержится в 1 базовой единице.
  /// Например, кирпич: base = м³, variant = шт, factor = 512.0
  /// (1 м³ ≈ 512 шт кирпича).
  final double perBase;

  /// Краткое пояснение, откуда взят коэффициент (для tooltip).
  final String? note;

  const UnitVariant({
    required this.unit,
    required this.perBase,
    this.note,
  });
}

/// Таблица альтернативных единиц по `PriceItem.id`.
///
/// Если `id` отсутствует — у строки сметы единица не переключается.
/// Первый элемент в каждом списке — базовая единица (perBase = 1.0).
const Map<String, List<UnitVariant>> kUnitVariants = {
  // ────────────── ФУНДАМЕНТ ──────────────
  'foundation_concrete_b25': [
    UnitVariant(unit: 'м³', perBase: 1.0),
    UnitVariant(unit: 'т', perBase: 2.4, note: 'плотность бетона B25 ≈ 2400 кг/м³'),
    UnitVariant(unit: 'кг', perBase: 2400.0, note: 'плотность ≈ 2400 кг/м³'),
  ],
  'foundation_rebar_a500c': [
    UnitVariant(unit: 'т', perBase: 1.0),
    UnitVariant(unit: 'кг', perBase: 1000.0),
    UnitVariant(
      unit: 'м.п.',
      perBase: 1126.0,
      note: 'А500С Ø12 — 0.888 кг/м.п. → 1 т ≈ 1126 м.п.',
    ),
  ],
  'foundation_formwork': [
    UnitVariant(unit: 'м²', perBase: 1.0),
    UnitVariant(
      unit: 'щит',
      perBase: 0.667,
      note: 'типовой щит 1.5×1.0 = 1.5 м²',
    ),
  ],
  'foundation_sand_gravel_pad': [
    UnitVariant(unit: 'м³', perBase: 1.0),
    UnitVariant(unit: 'т', perBase: 1.7, note: 'ПГС укатанный ≈ 1700 кг/м³'),
  ],
  'foundation_waterproofing': [
    UnitVariant(unit: 'м²', perBase: 1.0),
    UnitVariant(unit: 'рулон', perBase: 0.067, note: 'битумный рулон ≈ 15 м²'),
  ],
  'foundation_screw_pile_d108': [
    UnitVariant(unit: 'шт', perBase: 1.0),
  ],
  'foundation_bored_pile_d300': [
    UnitVariant(unit: 'м.п.', perBase: 1.0),
    UnitVariant(
      unit: 'м³ бетона',
      perBase: 0.071,
      note: 'сечение π·(0.15)² ≈ 0.071 м²/м.п.',
    ),
  ],
  'foundation_work_strip': [
    UnitVariant(unit: 'м³', perBase: 1.0),
  ],
  'foundation_work_slab': [
    UnitVariant(unit: 'м³', perBase: 1.0),
    UnitVariant(
      unit: 'м²',
      perBase: 4.0,
      note: 'при типовой толщине плиты 250 мм',
    ),
  ],

  // ────────────── СТЕНЫ ──────────────
  'wall_brick_solid': [
    UnitVariant(unit: 'шт', perBase: 1.0),
    UnitVariant(unit: 'тыс. шт', perBase: 0.001),
    UnitVariant(
      unit: 'поддон',
      perBase: 1.0 / 280,
      note: 'поддон ≈ 280 шт',
    ),
    UnitVariant(
      unit: 'м³',
      perBase: 1.0 / 512,
      note: 'кирпич 250×120×65 — 1 м³ ≈ 512 шт',
    ),
  ],
  'wall_aerated_d500': [
    UnitVariant(unit: 'м³', perBase: 1.0),
    UnitVariant(
      unit: 'шт',
      perBase: 27.78,
      note: 'блок 600×300×200 = 0.036 м³',
    ),
    UnitVariant(
      unit: 'поддон',
      perBase: 0.556,
      note: 'поддон ≈ 1.8 м³',
    ),
  ],
  'wall_expanded_clay_block': [
    UnitVariant(unit: 'м³', perBase: 1.0),
    UnitVariant(
      unit: 'шт',
      perBase: 71.0,
      note: 'блок 390×190×190 = 0.0141 м³',
    ),
    UnitVariant(
      unit: 'поддон',
      perBase: 1.0,
      note: 'поддон ≈ 1.0 м³',
    ),
  ],
  'wall_timber_150': [
    UnitVariant(unit: 'м³', perBase: 1.0),
    UnitVariant(
      unit: 'м.п.',
      perBase: 44.44,
      note: 'брус 150×150 = 0.0225 м²/м.п.',
    ),
  ],
  'wall_frame_lumber_50x150': [
    UnitVariant(unit: 'м³', perBase: 1.0),
    UnitVariant(
      unit: 'м.п.',
      perBase: 133.33,
      note: 'доска 50×150 = 0.0075 м²/м.п.',
    ),
    UnitVariant(
      unit: 'шт (6 м)',
      perBase: 22.22,
      note: 'доска 6 м = 0.045 м³',
    ),
  ],
  'wall_osb_12': [
    UnitVariant(unit: 'м²', perBase: 1.0),
    UnitVariant(
      unit: 'лист',
      perBase: 0.336,
      note: 'лист 2440×1220 = 2.98 м²',
    ),
  ],
  'wall_mineral_wool_100': [
    UnitVariant(unit: 'м²', perBase: 1.0),
    UnitVariant(
      unit: 'упаковка',
      perBase: 0.231,
      note: 'упаковка ≈ 4.32 м²',
    ),
    UnitVariant(
      unit: 'м³',
      perBase: 0.1,
      note: 'толщина 100 мм',
    ),
  ],
  'wall_vapor_barrier': [
    UnitVariant(unit: 'м²', perBase: 1.0),
    UnitVariant(unit: 'рулон', perBase: 1.0 / 60, note: 'рулон 60 м²'),
  ],
  'wall_wind_membrane': [
    UnitVariant(unit: 'м²', perBase: 1.0),
    UnitVariant(unit: 'рулон', perBase: 1.0 / 70, note: 'рулон 70 м²'),
  ],
  'wall_masonry_mortar': [
    UnitVariant(unit: 'м³', perBase: 1.0),
    UnitVariant(unit: 'т', perBase: 1.8, note: 'плотность ≈ 1800 кг/м³'),
    UnitVariant(
      unit: 'мешок 25 кг',
      perBase: 72.0,
      note: '1.8 т/м³ ÷ 25 кг = 72 мешка/м³',
    ),
  ],
  'wall_masonry_mesh': [
    UnitVariant(unit: 'м²', perBase: 1.0),
    UnitVariant(unit: 'рулон', perBase: 1.0 / 15, note: 'рулон 15 м²'),
  ],
  'wall_work_masonry': [
    UnitVariant(unit: 'м³', perBase: 1.0),
  ],
  'wall_work_frame': [
    UnitVariant(unit: 'м²', perBase: 1.0),
  ],
  'wall_work_timber': [
    UnitVariant(unit: 'м³', perBase: 1.0),
  ],

  // ────────────── ПЕРЕКРЫТИЯ ──────────────
  'slab_monolith_concrete': [
    UnitVariant(unit: 'м³', perBase: 1.0),
    UnitVariant(unit: 'т', perBase: 2.4, note: 'плотность ≈ 2400 кг/м³'),
    UnitVariant(
      unit: 'м²',
      perBase: 5.0,
      note: 'при толщине плиты 200 мм',
    ),
  ],
  'slab_monolith_rebar': [
    UnitVariant(unit: 'т', perBase: 1.0),
    UnitVariant(unit: 'кг', perBase: 1000.0),
  ],
  'slab_precast_pk': [
    UnitVariant(unit: 'м²', perBase: 1.0),
    UnitVariant(
      unit: 'шт',
      perBase: 1.0 / 7.2,
      note: 'плита ПК 6.0×1.2 ≈ 7.2 м²',
    ),
  ],
  'slab_wood_beam': [
    UnitVariant(unit: 'м³', perBase: 1.0),
    UnitVariant(
      unit: 'м.п.',
      perBase: 50.0,
      note: 'балка 100×200 = 0.02 м²/м.п.',
    ),
  ],
  'slab_metal_beam': [
    UnitVariant(unit: 'т', perBase: 1.0),
    UnitVariant(unit: 'кг', perBase: 1000.0),
    UnitVariant(
      unit: 'м.п.',
      perBase: 44.44,
      note: 'двутавр 20Б1 ≈ 22.5 кг/м.п. → 1 т ≈ 44 м.п.',
    ),
  ],
  'slab_floor_sheathing': [
    UnitVariant(unit: 'м²', perBase: 1.0),
  ],

  // ────────────── КРОВЛЯ ──────────────
  'roof_rafter_lumber': [
    UnitVariant(unit: 'м³', perBase: 1.0),
    UnitVariant(
      unit: 'м.п.',
      perBase: 100.0,
      note: '50×200 = 0.01 м²/м.п.',
    ),
  ],
  'roof_lathing': [
    UnitVariant(unit: 'м³', perBase: 1.0),
    UnitVariant(
      unit: 'м.п.',
      perBase: 400.0,
      note: '25×100 = 0.0025 м²/м.п.',
    ),
  ],
  'roof_underlay_membrane': [
    UnitVariant(unit: 'м²', perBase: 1.0),
    UnitVariant(unit: 'рулон', perBase: 1.0 / 75, note: 'рулон 75 м²'),
  ],
  'roof_insulation_200': [
    UnitVariant(unit: 'м²', perBase: 1.0),
    UnitVariant(
      unit: 'упаковка',
      perBase: 0.463,
      note: 'упаковка ≈ 2.16 м² (для 200 мм)',
    ),
    UnitVariant(unit: 'м³', perBase: 0.2, note: 'толщина 200 мм'),
  ],
  'roof_metal_tile': [
    UnitVariant(unit: 'м²', perBase: 1.0),
    UnitVariant(
      unit: 'лист',
      perBase: 0.4,
      note: 'лист 1.18×2.12 ≈ 2.5 м²',
    ),
  ],
  'roof_soft_tile': [
    UnitVariant(unit: 'м²', perBase: 1.0),
    UnitVariant(
      unit: 'упаковка',
      perBase: 0.333,
      note: 'упаковка ≈ 3.0 м²',
    ),
  ],
  'roof_clay_tile': [
    UnitVariant(unit: 'м²', perBase: 1.0),
    UnitVariant(
      unit: 'шт',
      perBase: 10.0,
      note: 'типовой расход 10 шт/м²',
    ),
  ],
  'roof_corrugated_sheet': [
    UnitVariant(unit: 'м²', perBase: 1.0),
    UnitVariant(unit: 'лист', perBase: 0.5, note: 'лист 1.0×2.0 ≈ 2.0 м²'),
  ],
};

/// Возвращает список доступных вариантов единиц для строки сметы.
/// Если у `itemId` нет дополнительных вариантов — вернёт пустой список,
/// и UI скрывает выпадающий список.
List<UnitVariant> unitVariantsFor(String itemId) {
  return kUnitVariants[itemId] ?? const <UnitVariant>[];
}

/// Найти вариант по подписи (UI хранит выбранный unit как строку).
UnitVariant? findUnitVariant(String itemId, String? unit) {
  if (unit == null) return null;
  for (final v in unitVariantsFor(itemId)) {
    if (v.unit == unit) return v;
  }
  return null;
}
