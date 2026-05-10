/// Состояние проектирования лестницы.
///
/// Появляется в составе сооружения только если пользователь отметил это
/// в техническом задании (поле [ClientBrief.hasStaircase]) либо при этажности > 1.
/// Полноценный визард параметров лестницы появится в следующих итерациях.
class StaircaseDesign {
  /// Тип лестницы: marsh (маршевая), screw (винтовая), rotary (поворотная).
  String? type;

  /// Высота этажа, м (от чистого пола до чистого пола).
  double? floorHeight;

  /// Количество ступеней.
  int? stepsCount;

  StaircaseDesign({this.type, this.floorHeight, this.stepsCount});

  bool get isFilled => type != null;

  String get summary {
    if (!isFilled) return 'Не заполнено';
    final parts = <String>[type!];
    if (stepsCount != null) parts.add('${stepsCount!} ступеней');
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'floorHeight': floorHeight,
        'stepsCount': stepsCount,
      };

  static StaircaseDesign fromJson(Map<String, dynamic> json) => StaircaseDesign(
        type: json['type'] as String?,
        floorHeight: (json['floorHeight'] as num?)?.toDouble(),
        stepsCount: json['stepsCount'] as int?,
      );
}
