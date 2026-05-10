// Phase-3b §17.2.1 — модель полигонального пятна застройки.
//
// Описывает пятно произвольной формы (L / Т / U / Г / эркер / ризалит)
// как замкнутый CCW-полигон в координатах участка (метры от
// левого-верхнего угла bbox). Поддерживает «дворы» (отверстия) —
// для будущих внутренних патио.
//
// Это ADDITIVE модель — она не заменяет существующих
// `width`/`height` в `FloorPlan` и `HouseProject`. Интеграция в
// `floor_plan_generator.dart` и `pdf_builder._paintWalls` — отдельный
// шаг, требующий миграции сериализации (см. §17.3).

import 'dart:math' as math;

/// Точка / вектор в плоскости участка (м).
class Vec2 {
  const Vec2(this.x, this.y);
  final double x;
  final double y;

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double k) => Vec2(x * k, y * k);

  /// Длина вектора.
  double get length => math.sqrt(x * x + y * y);

  /// Скалярное произведение.
  double dot(Vec2 o) => x * o.x + y * o.y;

  /// Z-компонента векторного произведения (для определения ориентации).
  double cross(Vec2 o) => x * o.y - y * o.x;

  Map<String, double> toJson() => {'x': x, 'y': y};
  static Vec2 fromJson(Map<String, dynamic> j) => Vec2(
        (j['x'] as num).toDouble(),
        (j['y'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is Vec2 &&
      (other.x - x).abs() < 1e-9 &&
      (other.y - y).abs() < 1e-9;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

/// Прямоугольная ограничивающая рамка (axis-aligned).
class FootprintBox {
  const FootprintBox({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  double get width => maxX - minX;
  double get height => maxY - minY;
  double get area => width * height;
  Vec2 get center => Vec2((minX + maxX) / 2, (minY + maxY) / 2);

  bool contains(Vec2 p) =>
      p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY;
}

/// Замкнутый ориентированный полигон-пятно дома.
///
/// Контур [outline] — список вершин в CCW-порядке (положительная
/// ориентированная площадь). Опциональные [holes] — внутренние
/// контуры (CW-порядок, «дворы»).
///
/// Для прямоугольного дома (текущая модель v64.x) можно создать
/// [BuildingFootprint.rect].
class BuildingFootprint {
  BuildingFootprint({
    required this.outline,
    this.holes = const [],
  }) : assert(outline.length >= 3, 'Контур должен иметь минимум 3 вершины');

  final List<Vec2> outline;
  final List<List<Vec2>> holes;

  /// Прямоугольный footprint `width × height` от точки `(0, 0)` (CCW
  /// при положительной оси Y вниз — точки идут TL → TR → BR → BL).
  factory BuildingFootprint.rect(double width, double height) {
    return BuildingFootprint(
      outline: [
        const Vec2(0, 0),
        Vec2(width, 0),
        Vec2(width, height),
        Vec2(0, height),
      ],
    );
  }

  /// L-форма с заданными габаритами bbox `width × height` и вырезом
  /// `cutWidth × cutHeight` в правом-нижнем углу. Используется в
  /// тестах §17.2.1.
  factory BuildingFootprint.lShape({
    required double width,
    required double height,
    required double cutWidth,
    required double cutHeight,
  }) {
    assert(cutWidth > 0 && cutWidth < width);
    assert(cutHeight > 0 && cutHeight < height);
    return BuildingFootprint(
      outline: [
        const Vec2(0, 0),
        Vec2(width, 0),
        Vec2(width, height - cutHeight),
        Vec2(width - cutWidth, height - cutHeight),
        Vec2(width - cutWidth, height),
        Vec2(0, height),
      ],
    );
  }

  /// T-форма (расширенная сверху, стоит на «ножке»): bbox
  /// `width × height` + центрированный «стержень» внизу шириной
  /// `stemWidth` и высотой `stemHeight`. Поясной этаж ([0..width])
  /// высотой `height - stemHeight`, ниже — выступ-стержень.
  factory BuildingFootprint.tShape({
    required double width,
    required double height,
    required double stemWidth,
    required double stemHeight,
  }) {
    assert(stemWidth > 0 && stemWidth < width);
    assert(stemHeight > 0 && stemHeight < height);
    final topH = height - stemHeight;
    final left = (width - stemWidth) / 2;
    final right = left + stemWidth;
    return BuildingFootprint(
      outline: [
        const Vec2(0, 0),
        Vec2(width, 0),
        Vec2(width, topH),
        Vec2(right, topH),
        Vec2(right, height),
        Vec2(left, height),
        Vec2(left, topH),
        Vec2(0, topH),
      ],
    );
  }

  /// U-форма (двор-колодец сверху): bbox `width × height` с центрированным
  /// «вырезом» сверху шириной `cutWidth` и глубиной `cutHeight`.
  factory BuildingFootprint.uShape({
    required double width,
    required double height,
    required double cutWidth,
    required double cutHeight,
  }) {
    assert(cutWidth > 0 && cutWidth < width);
    assert(cutHeight > 0 && cutHeight < height);
    final left = (width - cutWidth) / 2;
    final right = left + cutWidth;
    return BuildingFootprint(
      outline: [
        const Vec2(0, 0),
        Vec2(left, 0),
        Vec2(left, cutHeight),
        Vec2(right, cutHeight),
        Vec2(right, 0),
        Vec2(width, 0),
        Vec2(width, height),
        Vec2(0, height),
      ],
    );
  }

  /// Bounding box контура.
  FootprintBox get bbox {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final p in outline) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    return FootprintBox(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  /// Площадь полигона (по формуле гаусса), м².
  ///
  /// Положительная для CCW-контура, отрицательная — для CW.
  double get signedArea {
    var s = 0.0;
    for (var i = 0; i < outline.length; i++) {
      final p = outline[i];
      final q = outline[(i + 1) % outline.length];
      s += p.x * q.y - q.x * p.y;
    }
    var area = s / 2;
    for (final hole in holes) {
      var sh = 0.0;
      for (var i = 0; i < hole.length; i++) {
        final p = hole[i];
        final q = hole[(i + 1) % hole.length];
        sh += p.x * q.y - q.x * p.y;
      }
      area += sh / 2; // CW-контур даст отрицательную площадь — вычитается
    }
    return area;
  }

  /// Площадь пятна (м²) — модуль `signedArea`.
  double get area => signedArea.abs();

  /// Периметр (внешний + внутренние), м.
  double get perimeter {
    double sum = 0.0;
    void addRing(List<Vec2> ring) {
      for (var i = 0; i < ring.length; i++) {
        final a = ring[i];
        final b = ring[(i + 1) % ring.length];
        sum += (b - a).length;
      }
    }

    addRing(outline);
    for (final h in holes) {
      addRing(h);
    }
    return sum;
  }

  /// Точка [p] лежит внутри пятна (с учётом дыр)?
  ///
  /// Алгоритм — ray casting вправо по горизонтали.
  bool contains(Vec2 p) {
    if (!_pointInRing(p, outline)) return false;
    for (final h in holes) {
      if (_pointInRing(p, h)) return false;
    }
    return true;
  }

  /// Контур на самом деле CCW (`signedArea > 0`)?
  bool get isCcw => signedArea > 0;

  /// Возвращает копию с перевёрнутой ориентацией контура.
  BuildingFootprint reversed() => BuildingFootprint(
        outline: outline.reversed.toList(),
        holes: holes.map((h) => h.reversed.toList()).toList(),
      );

  // ───────────────────────── Сериализация ────────────────────────────

  Map<String, dynamic> toJson() => {
        'outline': outline.map((p) => p.toJson()).toList(),
        if (holes.isNotEmpty)
          'holes': holes
              .map((ring) => ring.map((p) => p.toJson()).toList())
              .toList(),
      };

  static BuildingFootprint fromJson(Map<String, dynamic> j) {
    final outRaw = j['outline'] as List;
    final outline = <Vec2>[
      for (final v in outRaw) Vec2.fromJson(v as Map<String, dynamic>),
    ];
    final holesRaw = j['holes'] as List?;
    final holes = <List<Vec2>>[];
    if (holesRaw != null) {
      for (final ring in holesRaw) {
        final list = ring as List;
        holes.add([
          for (final v in list) Vec2.fromJson(v as Map<String, dynamic>),
        ]);
      }
    }
    return BuildingFootprint(outline: outline, holes: holes);
  }

  /// Декомпозиция в набор axis-aligned прямоугольников
  /// (для прямоугольных контуров и L/T-образных). Основной алгоритм —
  /// rectangle decomposition (sweep-line по уникальным `y`).
  ///
  /// Для прямоугольного полигона возвращает один прямоугольник.
  /// Для произвольного — набор покрывающих прямоугольников без
  /// перекрытий, в сумме дающих ту же площадь.
  ///
  /// Поддерживаются только axis-aligned контуры (все стороны
  /// горизонтальные или вертикальные). Для произвольных полигонов
  /// возвращает один bbox-прямоугольник как фолбэк.
  List<FootprintRect> rectangleDecomposition() {
    if (!_isAxisAligned(outline)) {
      // Фолбэк: возвращаем bbox.
      final b = bbox;
      return [
        FootprintRect(x: b.minX, y: b.minY, width: b.width, height: b.height),
      ];
    }
    // Собираем уникальные y-координаты.
    final ys = <double>{};
    for (final p in outline) {
      ys.add(p.y);
    }
    final sortedY = ys.toList()..sort();
    final stripes = <FootprintRect>[];
    for (var i = 0; i < sortedY.length - 1; i++) {
      final y0 = sortedY[i];
      final y1 = sortedY[i + 1];
      final yMid = (y0 + y1) / 2;
      // Список x-точек, где горизонтальная прямая y=yMid пересекает
      // контур (только вертикальные сегменты).
      final crossings = <double>[];
      for (var k = 0; k < outline.length; k++) {
        final a = outline[k];
        final b = outline[(k + 1) % outline.length];
        if ((a.x - b.x).abs() > 1e-9) continue; // не вертикальный сегмент
        final yLo = math.min(a.y, b.y);
        final yHi = math.max(a.y, b.y);
        if (yMid > yLo && yMid < yHi) {
          crossings.add(a.x);
        }
      }
      crossings.sort();
      // Полосы между парами пересечений лежат внутри полигона.
      for (var k = 0; k + 1 < crossings.length; k += 2) {
        final x0 = crossings[k];
        final x1 = crossings[k + 1];
        stripes.add(FootprintRect(
          x: x0,
          y: y0,
          width: x1 - x0,
          height: y1 - y0,
        ));
      }
    }
    return stripes;
  }

  // ──────────────── Внутренние утилиты ────────────────────────────

  static bool _pointInRing(Vec2 p, List<Vec2> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final pi = ring[i];
      final pj = ring[j];
      final intersect = ((pi.y > p.y) != (pj.y > p.y)) &&
          (p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y + 1e-12) + pi.x);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  static bool _isAxisAligned(List<Vec2> ring) {
    for (var i = 0; i < ring.length; i++) {
      final a = ring[i];
      final b = ring[(i + 1) % ring.length];
      final dx = (a.x - b.x).abs();
      final dy = (a.y - b.y).abs();
      if (dx > 1e-9 && dy > 1e-9) return false;
    }
    return true;
  }
}

/// Прямоугольная ячейка декомпозиции.
class FootprintRect {
  const FootprintRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  double get area => width * height;
}
