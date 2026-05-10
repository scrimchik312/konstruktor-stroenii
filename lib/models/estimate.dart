import '../data/price_catalog.dart';

/// Строка сметы — одна позиция (материал/работа/комплекс).
///
/// Базовая цена приходит из [kPriceCatalog]. Если пользователь
/// переопределил цену вручную — записывается в [overridePrice].
/// Региональный коэффициент применяется к итоговой цене (а не к
/// объёму). Итог по строке = `qty * effectivePrice` без НДС.
///
/// **Конвертация единиц измерения**:
///   Для ряда позиций пользователь может поменять единицу
///   (например, кирпич — м³ ↔ шт ↔ поддон, утеплитель — м² ↔ упак.,
///   арматура — т ↔ кг ↔ м.п.). Все вычисления внутри `EstimateRow`
///   выполняются в **базовой** единице, а отображение и пересчёт
///   количества/цены — через `unitFactor`:
///     • [quantity]   — количество в выбранной (отображаемой) единице;
///     • [basePrice]  — цена ₽/выбранная единица (= base ÷ factor);
///     • `quantityBase` / `basePriceBase` — значения в **базовой**
///       единице; именно они являются «инвариантом» расчёта.
///   Итог `total = quantity * effectivePrice` совпадает с итогом
///   в базовых единицах (math identity), что и гарантирует
///   неизменность сметы при смене единицы.
class EstimateRow {
  final String itemId;
  final EstimateSection section;
  final EstimateItemKind kind;
  final String title;
  final String unit;

  /// Объём работ/количество материала **в выбранной единице** [unit].
  final double quantity;

  /// Базовая цена ₽/[unit] (из каталога, делённая на factor для
  /// неосновной единицы — чтобы итог не менялся при переключении).
  final double basePrice;

  /// Базовая единица позиции (та, что в `kPriceCatalog`).
  /// Нужна, чтобы UI знал, к чему пересчитывать обратно.
  final String baseUnit;

  /// Сколько [unit] в 1 [baseUnit]. По умолчанию 1.0 (единица =
  /// базовой, конвертация не применялась).
  final double unitFactor;

  /// Ручное переопределение цены ₽/[unit] (если null — используется
  /// базовая). Цена override хранится **в текущей единице**, поэтому
  /// при смене единицы override автоматически сбрасывается контроллером
  /// смены единицы (см. EstimateCalculator / EstimatePage).
  final double? overridePrice;

  /// Региональный коэффициент. По умолчанию 1.0.
  final double regionFactor;

  /// Объяснение, как посчитан объём (ссылка на формулу/проектную модель).
  final String? quantityNote;

  /// Источник базовой цены (нормативный документ, прайс).
  final String source;

  const EstimateRow({
    required this.itemId,
    required this.section,
    required this.kind,
    required this.title,
    required this.unit,
    required this.quantity,
    required this.basePrice,
    required this.source,
    this.baseUnit = '',
    this.unitFactor = 1.0,
    this.overridePrice,
    this.regionFactor = 1.0,
    this.quantityNote,
  });

  /// Количество в **базовой** единице (инвариант проекта).
  double get quantityBase => unitFactor == 0 ? quantity : quantity / unitFactor;

  /// Цена в **базовой** единице (для проверок и DXF-экспорта).
  double get basePriceInBaseUnit => basePrice * unitFactor;

  /// Цена за единицу с учётом override и регионального коэффициента.
  double get effectivePrice =>
      (overridePrice ?? basePrice) * regionFactor;

  /// Итог по строке (без НДС).
  double get total => quantity * effectivePrice;

  /// Признак: цена была переопределена пользователем.
  bool get isOverridden => overridePrice != null;

  /// Признак: единица была выбрана пользователем (не совпадает с
  /// базовой из каталога).
  bool get isUnitOverridden => baseUnit.isNotEmpty && unit != baseUnit;

  EstimateRow copyWith({
    double? quantity,
    double? overridePrice,
    bool clearOverride = false,
    double? regionFactor,
  }) {
    return EstimateRow(
      itemId: itemId,
      section: section,
      kind: kind,
      title: title,
      unit: unit,
      quantity: quantity ?? this.quantity,
      basePrice: basePrice,
      baseUnit: baseUnit,
      unitFactor: unitFactor,
      overridePrice: clearOverride ? null : (overridePrice ?? this.overridePrice),
      regionFactor: regionFactor ?? this.regionFactor,
      quantityNote: quantityNote,
      source: source,
    );
  }
}

/// Готовая смета — список строк по разделам, с региональным
/// коэффициентом и расчётом НДС.
///
/// Ставка НДС в РФ для строительных работ — 20 % (НК РФ ст. 164,
/// общий случай для коммерческой стройки). Для частного дома НДС
/// формально не платится напрямую заказчиком, но он включён в цену
/// материалов от поставщиков. Поэтому показываем его отдельной
/// строкой как «справочно».
class Estimate {
  final List<EstimateRow> rows;
  final String region;
  final double regionFactor;
  final double vatRate;

  const Estimate({
    required this.rows,
    required this.region,
    required this.regionFactor,
    this.vatRate = 0.20,
  });

  /// Итог по разделам (₽, без НДС).
  Map<EstimateSection, double> totalsBySection() {
    final out = <EstimateSection, double>{};
    for (final r in rows) {
      out[r.section] = (out[r.section] ?? 0) + r.total;
    }
    return out;
  }

  /// Сумма всех строк (₽, без НДС).
  double get subtotal => rows.fold(0.0, (s, r) => s + r.total);

  /// Сумма НДС (₽).
  double get vat => subtotal * vatRate;

  /// Итог с НДС (₽).
  double get total => subtotal + vat;

  /// Сколько строк было переопределено пользователем (для бейджа в UI).
  int get overriddenCount => rows.where((r) => r.isOverridden).length;

  Estimate copyWith({
    List<EstimateRow>? rows,
    String? region,
    double? regionFactor,
    double? vatRate,
  }) =>
      Estimate(
        rows: rows ?? this.rows,
        region: region ?? this.region,
        regionFactor: regionFactor ?? this.regionFactor,
        vatRate: vatRate ?? this.vatRate,
      );
}
