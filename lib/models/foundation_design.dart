import 'foundation.dart';

/// Состояние проектирования фундамента: выбранный тип, устройство и
/// (для свай с ростверком) материал ростверка.
///
/// В дальнейшем сюда будут добавлены числовые параметры: глубина заложения,
/// геометрия ленты/плиты/свай, марка бетона, класс арматуры и т. п.
class FoundationDesign {
  FoundationType? type;
  FoundationDevice? device;
  GrillageMaterial? grillageMaterial;

  FoundationDesign({this.type, this.device, this.grillageMaterial});

  bool get isFilled {
    if (type == null || device == null) return false;
    if (type == FoundationType.pileWithGrillage && grillageMaterial == null) {
      return false;
    }
    return true;
  }

  String get summary {
    final t = type;
    final d = device;
    if (t == null) return 'Не выбран';
    final buf = StringBuffer(t.title);
    if (d != null) buf.write(' · ${d.title}');
    if (t == FoundationType.pileWithGrillage && grillageMaterial != null) {
      buf.write(' · ${grillageMaterial!.title}');
    }
    return buf.toString();
  }

  Map<String, dynamic> toJson() => {
        'type': type?.name,
        'device': device?.name,
        'grillageMaterial': grillageMaterial?.name,
      };

  static FoundationDesign fromJson(Map<String, dynamic> json) {
    return FoundationDesign(
      type: _enumFromName(FoundationType.values, json['type'] as String?),
      device: _enumFromName(FoundationDevice.values, json['device'] as String?),
      grillageMaterial: _enumFromName(
        GrillageMaterial.values,
        json['grillageMaterial'] as String?,
      ),
    );
  }
}

T? _enumFromName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}
