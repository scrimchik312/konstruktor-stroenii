/// Состояние проектирования перекрытий.
///
/// Перекрытие — это горизонтальная конструкция между этажами (или
/// между подвалом и первым этажом, между последним этажом и кровлей).
/// На этапе планировки клиент выбирает только тип и материал, а
/// расчёт сечений и армирования делает движок `cc_engine` на этапе
/// готовых чертежей.
///
/// Поля:
///   * [type] — конструктивная схема: `monolith` (монолитное ж/б),
///     `precast` (сборное ж/б), `wood_beams` (по деревянным балкам),
///     `metal_beams` (по металлическим балкам).
///   * [material] — материал плиты/балок: для `monolith` это марка
///     бетона (B20, B25), для `precast` — серия плит (ПК, ПБ),
///     для деревянных — порода (сосна, лиственница).
///   * [thickness] — толщина плиты или высота балки в мм. Для
///     монолита — толщина бетона, для балочных — высота балки.
class FloorSlabsDesign {
  String? type;
  String? material;
  double? thickness;

  FloorSlabsDesign({this.type, this.material, this.thickness});

  bool get isFilled => type != null;

  String get summary {
    if (!isFilled) return 'Не заполнено';
    final parts = <String>[_typeTitle(type!)];
    if (material != null) parts.add(material!);
    if (thickness != null) parts.add('${thickness!.toStringAsFixed(0)} мм');
    return parts.join(' · ');
  }

  static String _typeTitle(String t) {
    switch (t) {
      case 'monolith':
        return 'Монолитное ж/б';
      case 'precast':
        return 'Сборное ж/б';
      case 'wood_beams':
        return 'По деревянным балкам';
      case 'metal_beams':
        return 'По металлическим балкам';
      default:
        return t;
    }
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'material': material,
        'thickness': thickness,
      };

  static FloorSlabsDesign fromJson(Map<String, dynamic> json) => FloorSlabsDesign(
        type: json['type'] as String?,
        material: json['material'] as String?,
        thickness: (json['thickness'] as num?)?.toDouble(),
      );
}
