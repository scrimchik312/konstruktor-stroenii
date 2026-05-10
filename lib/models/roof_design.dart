/// Состояние проектирования крыши.
///
/// Модель хранит: тип (двускатная/вальмовая/плоская/мансардная),
/// основной угол ската (для обратной совместимости) и список углов
/// по каждому скату — 2 угла для двускатной, 4 для вальмовой, один
/// для односкатной/мансарды, пусто для плоской.
class RoofDesign {
  String? type; // gable, hip, flat, mansard и т. д.
  double? slopeAngle; // градусы — среднее/основной
  List<double> slopeAngles; // углы по каждому скату в порядке С/В/Ю/З
  String? roofingMaterial; // metal, tile, soft

  RoofDesign({
    this.type,
    this.slopeAngle,
    List<double>? slopeAngles,
    this.roofingMaterial,
  }) : slopeAngles = slopeAngles ?? <double>[];

  bool get isFilled => type != null;

  String get summary {
    if (!isFilled) return 'Не заполнено';
    final base = type ?? '?';
    if (slopeAngles.isNotEmpty) {
      final parts = slopeAngles.map((a) => '${a.toStringAsFixed(0)}°').join('/');
      return '$base · $parts';
    }
    if (slopeAngle != null) {
      return '$base · ${slopeAngle!.toStringAsFixed(0)}°';
    }
    return base;
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'slopeAngle': slopeAngle,
        if (slopeAngles.isNotEmpty) 'slopeAngles': slopeAngles,
        'roofingMaterial': roofingMaterial,
      };

  static RoofDesign fromJson(Map<String, dynamic> json) => RoofDesign(
        type: json['type'] as String?,
        slopeAngle: (json['slopeAngle'] as num?)?.toDouble(),
        slopeAngles: [
          for (final a in (json['slopeAngles'] as List? ?? const []))
            (a as num).toDouble(),
        ],
        roofingMaterial: json['roofingMaterial'] as String?,
      );
}
