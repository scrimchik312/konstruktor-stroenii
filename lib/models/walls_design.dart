/// Состояние проектирования стен.
///
/// Заполнение появится в следующей фазе (после готового технического задания). Здесь
/// заведена пустая модель с поддержкой сериализации, чтобы дальше
/// безболезненно добавлять поля.
class WallsDesign {
  String? material; // brick, aerated, timber, frame
  double? thickness; // мм — толщина наружных стен
  double? height; // м

  WallsDesign({this.material, this.thickness, this.height});

  bool get isFilled => material != null && thickness != null;

  String get summary {
    if (!isFilled) return 'Не заполнено';
    return '${material ?? '?'} · ${thickness?.toStringAsFixed(0) ?? '?'} мм';
  }

  /// Расчётная толщина ВНУТРЕННИХ несущих стен (перегородок), мм.
  ///
  /// По правилу пользователя:
  ///   * кирпич с наружной стеной 510 мм (типовой 2-кирпичный) →
  ///     внутренняя несущая стена 380 мм (1.5 кирпича по СП 15.13330);
  ///   * кирпич с другой толщиной → 250 мм (1 кирпич);
  ///   * прочие материалы — 150 мм (типовой блок/гипсолит).
  ///
  /// Это влияет на 3D-вид, разрезы, ведомости отделки, спецификации
  /// материалов и смету (см. `MaterialVolumes`).
  double get partitionThicknessMm {
    final m = (material ?? '').toLowerCase();
    final isBrick = m.contains('brick') || m.contains('кирпич');
    if (isBrick) {
      final t = thickness ?? 510;
      if (t >= 500) return 380;
      if (t >= 380) return 250;
      return 250;
    }
    return 150;
  }

  /// Та же величина в метрах — для удобства расчётов объёмов.
  double get partitionThicknessM => partitionThicknessMm / 1000.0;

  Map<String, dynamic> toJson() => {
        'material': material,
        'thickness': thickness,
        'height': height,
      };

  static WallsDesign fromJson(Map<String, dynamic> json) => WallsDesign(
        material: json['material'] as String?,
        thickness: (json['thickness'] as num?)?.toDouble(),
        height: (json['height'] as num?)?.toDouble(),
      );
}
