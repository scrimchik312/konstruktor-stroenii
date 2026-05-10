import 'dart:convert';

import 'foundation.dart';

/// Структурное описание плана фундамента (вид сверху).
///
/// Содержит ровно те же геометрические сущности, которые рисуются в PDF и
/// на экране: контур здания, элементы фундамента (ленты / плита / сваи /
/// столбы), оси с буквенно-цифровыми марками, размерные цепочки, отметки
/// уровней и аннотации с реальными числами (марка бетона, армирование,
/// глубина заложения).
///
/// Все координаты — в метрах, в системе координат пятна застройки
/// (`(0, 0)` — левый верхний угол, ось Y направлена вниз — как у
/// `FloorPlan`).
class FoundationPlanModel {
  /// Тип фундамента — определяет, что именно рисуется.
  final FoundationType type;

  /// Подпись типа («Ленточный (монолитный)»).
  final String typeLabel;

  /// Размеры пятна застройки (м).
  final double buildingWidth;
  final double buildingLength;

  /// Глубина заложения подошвы фундамента, м.
  final double depthM;

  /// Площадь пятна, м².
  final double footprintArea;

  /// Ленты фундамента (для strip / slab-edge / pileGrillage). Каждая
  /// лента — прямая полоса с шириной [thicknessM] и центральной осью
  /// от ([x1], [y1]) до ([x2], [y2]).
  final List<FoundationBand> bands;

  /// Полигон плиты (для slab). Если задан — рисуется заштрихованный
  /// прямоугольник плиты + контур.
  final FoundationSlab? slab;

  /// Сваи (для pile / pileWithGrillage / columnar) — точечные элементы.
  final List<FoundationPile> piles;

  /// Оси: горизонтальные (буквенные A, Б, В, …) и вертикальные
  /// (цифровые 1, 2, 3, …).
  final List<FoundationAxis> horizontalAxes;
  final List<FoundationAxis> verticalAxes;

  /// Размерные цепочки.
  final List<FoundationDimChain> dimensionChains;

  /// Текстовые аннотации (марка бетона, глубина, тип сваи).
  final List<FoundationAnnotation> annotations;

  /// Список технических примечаний под планом (используется в PDF/UI).
  final List<String> notes;

  /// Список ссылок на нормы (СП), отображается в правом нижнем
  /// углу/штампе.
  final List<String> codeReferences;

  const FoundationPlanModel({
    required this.type,
    required this.typeLabel,
    required this.buildingWidth,
    required this.buildingLength,
    required this.depthM,
    required this.footprintArea,
    this.bands = const [],
    this.slab,
    this.piles = const [],
    this.horizontalAxes = const [],
    this.verticalAxes = const [],
    this.dimensionChains = const [],
    this.annotations = const [],
    this.notes = const [],
    this.codeReferences = const [],
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'typeLabel': typeLabel,
        'buildingWidth': buildingWidth,
        'buildingLength': buildingLength,
        'depthM': depthM,
        'footprintArea': footprintArea,
        'bands': bands.map((b) => b.toJson()).toList(),
        if (slab != null) 'slab': slab!.toJson(),
        'piles': piles.map((p) => p.toJson()).toList(),
        'horizontalAxes': horizontalAxes.map((a) => a.toJson()).toList(),
        'verticalAxes': verticalAxes.map((a) => a.toJson()).toList(),
        'dimensionChains':
            dimensionChains.map((d) => d.toJson()).toList(),
        'annotations': annotations.map((a) => a.toJson()).toList(),
        'notes': notes,
        'codeReferences': codeReferences,
      };

  String encode() => jsonEncode(toJson());

  static FoundationPlanModel fromJson(Map<String, dynamic> j) {
    return FoundationPlanModel(
      type: FoundationType.values.firstWhere(
        (v) => v.name == (j['type'] as String?),
        orElse: () => FoundationType.strip,
      ),
      typeLabel: j['typeLabel'] as String? ?? '',
      buildingWidth: (j['buildingWidth'] as num).toDouble(),
      buildingLength: (j['buildingLength'] as num).toDouble(),
      depthM: (j['depthM'] as num?)?.toDouble() ?? 0.0,
      footprintArea: (j['footprintArea'] as num?)?.toDouble() ?? 0.0,
      bands: (j['bands'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(FoundationBand.fromJson)
              .toList() ??
          const [],
      slab: j['slab'] is Map<String, dynamic>
          ? FoundationSlab.fromJson(j['slab'] as Map<String, dynamic>)
          : null,
      piles: (j['piles'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(FoundationPile.fromJson)
              .toList() ??
          const [],
      horizontalAxes: (j['horizontalAxes'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(FoundationAxis.fromJson)
              .toList() ??
          const [],
      verticalAxes: (j['verticalAxes'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(FoundationAxis.fromJson)
              .toList() ??
          const [],
      dimensionChains: (j['dimensionChains'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(FoundationDimChain.fromJson)
              .toList() ??
          const [],
      annotations: (j['annotations'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(FoundationAnnotation.fromJson)
              .toList() ??
          const [],
      notes: (j['notes'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const [],
      codeReferences: (j['codeReferences'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const [],
    );
  }

  static FoundationPlanModel? tryDecode(String s) {
    if (s.isEmpty) return null;
    try {
      final j = jsonDecode(s);
      if (j is Map<String, dynamic>) return fromJson(j);
    } catch (_) {
      // not foundation-plan payload
    }
    return null;
  }
}

/// Лента фундамента — прямая полоса с шириной [thicknessM] и
/// центральной осью от ([x1], [y1]) до ([x2], [y2]).
class FoundationBand {
  /// `external` — наружная (по периметру); `internal` — под внутренней
  /// несущей стеной; `grillage` — ростверк по сваям.
  final FoundationBandKind kind;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double thicknessM;

  const FoundationBand({
    required this.kind,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.thicknessM,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'thicknessM': thicknessM,
      };

  static FoundationBand fromJson(Map<String, dynamic> j) {
    return FoundationBand(
      kind: FoundationBandKind.values.firstWhere(
        (v) => v.name == (j['kind'] as String?),
        orElse: () => FoundationBandKind.external,
      ),
      x1: (j['x1'] as num).toDouble(),
      y1: (j['y1'] as num).toDouble(),
      x2: (j['x2'] as num).toDouble(),
      y2: (j['y2'] as num).toDouble(),
      thicknessM: (j['thicknessM'] as num).toDouble(),
    );
  }
}

enum FoundationBandKind { external, internal, grillage }

class FoundationSlab {
  /// Полигон плиты (метры). Для прямоугольной плиты — 4 точки.
  final List<FoundationPoint> polygon;
  final double thicknessM;

  const FoundationSlab({required this.polygon, required this.thicknessM});

  Map<String, dynamic> toJson() => {
        'polygon': polygon.map((p) => p.toJson()).toList(),
        'thicknessM': thicknessM,
      };

  static FoundationSlab fromJson(Map<String, dynamic> j) {
    return FoundationSlab(
      polygon: (j['polygon'] as List)
          .whereType<Map<String, dynamic>>()
          .map(FoundationPoint.fromJson)
          .toList(),
      thicknessM: (j['thicknessM'] as num).toDouble(),
    );
  }
}

class FoundationPile {
  final double x;
  final double y;
  final double diameterM;

  /// Метка сваи (например, «С-1», «С-2»).
  final String label;

  const FoundationPile({
    required this.x,
    required this.y,
    required this.diameterM,
    this.label = '',
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'diameterM': diameterM,
        if (label.isNotEmpty) 'label': label,
      };

  static FoundationPile fromJson(Map<String, dynamic> j) => FoundationPile(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        diameterM: (j['diameterM'] as num).toDouble(),
        label: j['label'] as String? ?? '',
      );
}

class FoundationPoint {
  final double x;
  final double y;
  const FoundationPoint(this.x, this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  static FoundationPoint fromJson(Map<String, dynamic> j) =>
      FoundationPoint((j['x'] as num).toDouble(), (j['y'] as num).toDouble());
}

/// Ось здания (горизонтальная или вертикальная). [position] — координата
/// в метрах вдоль перпендикулярного направления (для horizontal — y,
/// для vertical — x).
class FoundationAxis {
  final String label;
  final double position;
  const FoundationAxis({required this.label, required this.position});

  Map<String, dynamic> toJson() => {'label': label, 'position': position};
  static FoundationAxis fromJson(Map<String, dynamic> j) => FoundationAxis(
        label: j['label'] as String,
        position: (j['position'] as num).toDouble(),
      );
}

/// Размерная цепочка. [side] определяет, где она рисуется: top / bottom /
/// left / right относительно плана. [stops] — позиции вдоль оси цепочки
/// (по горизонтали x, по вертикали y), отсортированные по возрастанию.
class FoundationDimChain {
  /// `top|bottom` — горизонтальная цепочка (размеры по X);
  /// `left|right` — вертикальная (размеры по Y).
  final FoundationDimSide side;
  final List<double> stops;

  /// Уровень цепочки (1 = ближайшая к плану, 2 — следующая, и т. д.).
  final int level;

  const FoundationDimChain({
    required this.side,
    required this.stops,
    this.level = 1,
  });

  Map<String, dynamic> toJson() => {
        'side': side.name,
        'stops': stops,
        'level': level,
      };

  static FoundationDimChain fromJson(Map<String, dynamic> j) =>
      FoundationDimChain(
        side: FoundationDimSide.values.firstWhere(
          (v) => v.name == (j['side'] as String?),
          orElse: () => FoundationDimSide.bottom,
        ),
        stops: (j['stops'] as List).map((e) => (e as num).toDouble()).toList(),
        level: (j['level'] as num?)?.toInt() ?? 1,
      );
}

enum FoundationDimSide { top, bottom, left, right }

/// Текстовая аннотация в произвольной точке плана.
class FoundationAnnotation {
  final double x;
  final double y;
  final String text;

  /// Если задано — рисовать линию-выноску от ([x], [y]) до ([targetX],
  /// [targetY]).
  final double? targetX;
  final double? targetY;

  const FoundationAnnotation({
    required this.x,
    required this.y,
    required this.text,
    this.targetX,
    this.targetY,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'text': text,
        if (targetX != null) 'targetX': targetX,
        if (targetY != null) 'targetY': targetY,
      };

  static FoundationAnnotation fromJson(Map<String, dynamic> j) =>
      FoundationAnnotation(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        text: j['text'] as String,
        targetX: (j['targetX'] as num?)?.toDouble(),
        targetY: (j['targetY'] as num?)?.toDouble(),
      );
}
