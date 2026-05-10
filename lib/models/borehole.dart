import 'soil_layer.dart';

/// Описание одной геологической скважины (буровой колонки) на участке.
///
/// Используется для проектирования по СП 47.13330.2016 «Инженерные
/// изыскания для строительства» совместно с СП 22.13330.2016. Для
/// индивидуальных жилых домов (≤ 3 этажей) обязательным является не
/// менее 2-3 скважин на участок (СП 47, табл. 7.4) глубиной 5-7 м.
class Borehole {
  /// Метка скважины (например, «С-1»).
  String? label;

  /// Координаты на участке относительно «угла» здания, м (для отображения
  /// на ситуационном плане).
  double? xOnPlot;
  double? yOnPlot;

  /// Абсолютная отметка устья скважины, м БСВ (опционально, обычно
  /// принимается равной отметке земли).
  double? topElevationM;

  /// Уровень подземных вод (УГВ) на момент бурения, м от устья скважины.
  /// `null` — УГВ не вскрыт в пределах глубины бурения.
  double? groundwaterLevelM;

  /// Слои грунта в этой скважине (сверху вниз).
  final List<SoilLayer> layers;

  Borehole({
    this.label,
    this.xOnPlot,
    this.yOnPlot,
    this.topElevationM,
    this.groundwaterLevelM,
    List<SoilLayer>? layers,
  }) : layers = layers ?? <SoilLayer>[];

  bool get isEmpty =>
      (label == null || label!.isEmpty) &&
      xOnPlot == null &&
      yOnPlot == null &&
      groundwaterLevelM == null &&
      layers.every((l) => l.isEmpty);

  /// Глубина скважины — суммарная мощность всех её слоёв.
  double get depthM {
    var sum = 0.0;
    for (final l in layers) {
      sum += l.thickness ?? 0;
    }
    return sum;
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'xOnPlot': xOnPlot,
        'yOnPlot': yOnPlot,
        'topElevationM': topElevationM,
        'groundwaterLevelM': groundwaterLevelM,
        'layers': layers.map((l) => l.toJson()).toList(),
      };

  static Borehole fromJson(Map<String, dynamic> json) {
    final rawLayers = json['layers'];
    final layers = <SoilLayer>[];
    if (rawLayers is List) {
      for (final l in rawLayers) {
        if (l is Map<String, dynamic>) {
          layers.add(SoilLayer.fromJson(l));
        } else if (l is Map) {
          layers.add(SoilLayer.fromJson(Map<String, dynamic>.from(l)));
        }
      }
    }
    return Borehole(
      label: json['label'] as String?,
      xOnPlot: (json['xOnPlot'] as num?)?.toDouble(),
      yOnPlot: (json['yOnPlot'] as num?)?.toDouble(),
      topElevationM: (json['topElevationM'] as num?)?.toDouble(),
      groundwaterLevelM: (json['groundwaterLevelM'] as num?)?.toDouble(),
      layers: layers,
    );
  }
}
