// Модель мебели/символов для рендера на плане АР.
//
// Соответствует Части II §3 техзадания konstruktor_stroenii_full_spec.md.
// Phase-1 MVP: ограниченный набор типов, достаточный для рецептов
// спальни, гостиной, кухни и санузла.
//
// Координаты и размеры заданы в метрах (как и `PlanRoom`).

/// Тип мебельного символа. Используется графикой в `pdf_builder.dart`
/// для выбора нужного отрисовщика, а также рецептами в
/// `furniture/placement_engine.dart`.
enum FurnitureKind {
  // ─── Спальня ───────────────────────────────────────────────────
  bedDouble, // двуспальная кровать (1.6×2.0 м)
  bedSingle, // односпальная (0.9×2.0 м)
  nightstand, // тумба прикроватная (0.5×0.4 м)
  // ─── Гостиная ──────────────────────────────────────────────────
  sofa3, // диван прямой 3 места (2.2×0.9 м)
  sofaCorner, // диван угловой (2.6×1.7 м, L-форма)
  armchair, // кресло (0.85×0.85 м)
  coffeeTable, // журнальный стол (1.1×0.6 м)
  tvStand, // тумба под ТВ (1.6×0.4 м)
  diningTable, // обеденный стол (1.4×0.9 м)
  diningChair, // стул (0.45×0.45 м)
  // ─── Кухня ─────────────────────────────────────────────────────
  kitchenSection, // секция кухонного гарнитура (произв. длина × 0.6 м)
  kitchenStove, // плита (0.6×0.6 м, конфорки)
  kitchenSink, // мойка (0.6×0.5 м)
  kitchenFridge, // холодильник (0.6×0.7 м)
  // ─── Санузел ───────────────────────────────────────────────────
  bathtub, // ванна (1.7×0.7 м)
  shower, // душ (0.9×0.9 м)
  toilet, // унитаз (0.4×0.7 м)
  washbasin, // раковина (0.6×0.45 м)
  washingMachine, // стиральная (0.6×0.6 м)
  // ─── Универсальное ─────────────────────────────────────────────
  wardrobe, // шкаф (1.6×0.6 м)
  desk, // письменный стол (1.4×0.7 м)
  chair, // стул простой
  staircaseArrow, // стрелка «вверх/вниз» поверх лестницы
  carSilhouette, // силуэт авто (4.6×1.8 м) для гаража/навеса
  // ─── Phase-2 ───────────────────────────────────────────────────
  dryer, // сушильная машина (0.6×0.6 м)
  shoeCabinet, // тумба для обуви (0.9×0.4 м)
  hangerRack, // вешалка/шкаф для верхней одежды (0.6×0.4 м)
  boiler, // котёл/бойлер (0.6×0.5 м)
  outdoorTable, // стол уличный с зонтиком (1.4×0.9 м)
  outdoorChair, // стул уличный (0.5×0.5 м)
  kitchenIsland; // остров на кухне (1.8×1.0 м)

  /// Стандартные габариты в метрах — используются как `default` при
  /// генерации, конкретный экземпляр может переопределить размер.
  ({double w, double h}) get defaultSize {
    switch (this) {
      case FurnitureKind.bedDouble:
        return (w: 1.6, h: 2.0);
      case FurnitureKind.bedSingle:
        return (w: 0.9, h: 2.0);
      case FurnitureKind.nightstand:
        return (w: 0.5, h: 0.4);
      case FurnitureKind.sofa3:
        return (w: 2.2, h: 0.9);
      case FurnitureKind.sofaCorner:
        return (w: 2.6, h: 1.7);
      case FurnitureKind.armchair:
        return (w: 0.85, h: 0.85);
      case FurnitureKind.coffeeTable:
        return (w: 1.1, h: 0.6);
      case FurnitureKind.tvStand:
        return (w: 1.6, h: 0.4);
      case FurnitureKind.diningTable:
        return (w: 1.4, h: 0.9);
      case FurnitureKind.diningChair:
        return (w: 0.45, h: 0.45);
      case FurnitureKind.kitchenSection:
        return (w: 0.6, h: 0.6);
      case FurnitureKind.kitchenStove:
        return (w: 0.6, h: 0.6);
      case FurnitureKind.kitchenSink:
        return (w: 0.6, h: 0.5);
      case FurnitureKind.kitchenFridge:
        return (w: 0.6, h: 0.7);
      case FurnitureKind.bathtub:
        return (w: 1.7, h: 0.7);
      case FurnitureKind.shower:
        return (w: 0.9, h: 0.9);
      case FurnitureKind.toilet:
        return (w: 0.4, h: 0.7);
      case FurnitureKind.washbasin:
        return (w: 0.6, h: 0.45);
      case FurnitureKind.washingMachine:
        return (w: 0.6, h: 0.6);
      case FurnitureKind.wardrobe:
        return (w: 1.6, h: 0.6);
      case FurnitureKind.desk:
        return (w: 1.4, h: 0.7);
      case FurnitureKind.chair:
        return (w: 0.45, h: 0.45);
      case FurnitureKind.staircaseArrow:
        return (w: 0.5, h: 0.5);
      case FurnitureKind.carSilhouette:
        return (w: 4.6, h: 1.8);
      case FurnitureKind.dryer:
        return (w: 0.6, h: 0.6);
      case FurnitureKind.shoeCabinet:
        return (w: 0.9, h: 0.4);
      case FurnitureKind.hangerRack:
        return (w: 0.6, h: 0.4);
      case FurnitureKind.boiler:
        return (w: 0.6, h: 0.5);
      case FurnitureKind.outdoorTable:
        return (w: 1.4, h: 0.9);
      case FurnitureKind.outdoorChair:
        return (w: 0.5, h: 0.5);
      case FurnitureKind.kitchenIsland:
        return (w: 1.8, h: 1.0);
    }
  }
}

/// Размещённый экземпляр мебели на плане.
///
/// `x`, `y` — координата ЛЕВО-ВЕРХ ограничивающего прямоугольника
/// относительно начала координат плана (как у `PlanRoom`).
/// `width`, `height` — габариты в метрах в системе координат пола.
/// `rotationDeg` — поворот по часовой относительно лево-верхнего
/// угла в градусах (0/90/180/270 на Phase-1).
class FurnitureSymbol {
  final FurnitureKind kind;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotationDeg;
  final String? label; // опциональная подпись (например, "ОТ" на радиаторе)

  const FurnitureSymbol({
    required this.kind,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotationDeg = 0,
    this.label,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'x': x,
        'y': y,
        'w': width,
        'h': height,
        if (rotationDeg != 0) 'rot': rotationDeg,
        if (label != null) 'label': label,
      };

  static FurnitureSymbol? fromJson(Map<String, dynamic> j) {
    final name = j['kind'] as String?;
    if (name == null) return null;
    final kind = FurnitureKind.values
        .where((k) => k.name == name)
        .cast<FurnitureKind?>()
        .firstWhere((_) => true, orElse: () => null);
    if (kind == null) return null;
    return FurnitureSymbol(
      kind: kind,
      x: (j['x'] as num).toDouble(),
      y: (j['y'] as num).toDouble(),
      width: (j['w'] as num).toDouble(),
      height: (j['h'] as num).toDouble(),
      rotationDeg: (j['rot'] as num?)?.toDouble() ?? 0,
      label: j['label'] as String?,
    );
  }
}
