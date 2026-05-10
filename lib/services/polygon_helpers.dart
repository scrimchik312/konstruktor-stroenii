// Phase-3b §21.1 — общие геометрические утилиты для полигонов
// (footprint/outline/кровля). Не зависят от Flutter / pdf — pure Dart.
//
// Содержит:
//   • [vertexConvexity] — convex / reflex / collinear для вершины
//     CCW-полигона.
//   • [vertexInteriorBisectorCcw] — единичный вектор внутренней
//     биссектрисы (для произвольных, не обязательно axis-aligned
//     полигонов).
//   • [polygonIsCcw] — определение ориентации.
//   • [snapToGrid] — клампируемая привязка к шагу.

import 'dart:math' as math;

import '../models/building_footprint.dart';

/// Тип угла в вершине полигона относительно внутренности.
enum VertexConvexity {
  /// Внутренний угол < 180°: «выпуклый» (для CCW — поворот налево).
  convex,

  /// Внутренний угол > 180°: «впуклый» (поворот направо для CCW —
  /// характерен для L/T/U-форм).
  reflex,

  /// 180° (или почти) — три точки на одной прямой.
  collinear,
}

/// Определяет, выпуклая или впуклая вершина [outline][i] в
/// CCW-полигоне. Для полигона с обратной ориентацией (CW) логика
/// инвертируется — вызывающая сторона должна сначала проверить
/// ориентацию через [polygonIsCcw].
VertexConvexity vertexConvexity(List<Vec2> outline, int i,
    {double eps = 1e-9}) {
  final n = outline.length;
  if (n < 3) return VertexConvexity.collinear;
  final prev = outline[(i - 1 + n) % n];
  final cur = outline[i];
  final next = outline[(i + 1) % n];
  final eIn = cur - prev;
  final eOut = next - cur;
  final cross = eIn.cross(eOut);
  if (cross.abs() < eps) return VertexConvexity.collinear;
  return cross > 0 ? VertexConvexity.convex : VertexConvexity.reflex;
}

/// Возвращает единичный вектор **внутренней** биссектрисы вершины
/// `outline[i]` для CCW-полигона. Для прямого угла (90°) — нормирован
/// к (`±1, ±1`)/√2. Для произвольных углов — `bisector =
/// normalize(-edgeIn) + normalize(edgeOut)` (по формуле из
/// straight-skeleton-теории), затем нормируется. Для convex-вершины
/// вектор направлен **внутрь** полигона; для reflex-вершины —
/// тоже внутрь (но именно «к спине» reflex-угла, что для кровли
/// порождает ендову).
Vec2 vertexInteriorBisectorCcw(List<Vec2> outline, int i,
    {double eps = 1e-9}) {
  final n = outline.length;
  assert(n >= 3, 'Полигон должен иметь минимум 3 вершины');
  final prev = outline[(i - 1 + n) % n];
  final cur = outline[i];
  final next = outline[(i + 1) % n];
  final eInNorm = _safeNormalize(cur - prev, eps);
  final eOutNorm = _safeNormalize(next - cur, eps);
  // Внутренняя биссектриса вершины — это вектор, делящий пополам
  // внутренний угол. Получается как сумма внутренних нормалей двух
  // соседних рёбер. Для CCW-полигона (signedArea > 0) внутренняя
  // нормаль ребра — поворот единичного ребра на +90°
  // (математический CCW): (dx, dy) → (-dy, dx).
  final nIn = Vec2(-eInNorm.y, eInNorm.x); // нормаль внутрь от eIn
  final nOut = Vec2(-eOutNorm.y, eOutNorm.x); // нормаль внутрь от eOut
  final sum = nIn + nOut;
  final len = sum.length;
  if (len < eps) {
    // Угол ≈ 180° — биссектриса вырождается. Возвращаем нормаль одной
    // из сторон.
    return nIn;
  }
  return Vec2(sum.x / len, sum.y / len);
}

Vec2 _safeNormalize(Vec2 v, double eps) {
  final len = v.length;
  if (len < eps) return const Vec2(1, 0);
  return Vec2(v.x / len, v.y / len);
}

/// Возвращает true, если полигон ориентирован против часовой
/// стрелки (в системе с осью Y вниз — это «по часовой» в screen-
/// координатах, см. правило знака `signedArea`).
bool polygonIsCcw(List<Vec2> outline) {
  var s = 0.0;
  for (var i = 0; i < outline.length; i++) {
    final p = outline[i];
    final q = outline[(i + 1) % outline.length];
    s += p.x * q.y - q.x * p.y;
  }
  return s > 0;
}

/// Привязка координаты к шагу сетки. `step <= 0` означает «без
/// привязки» (возвращается исходное значение). Опциональные
/// `lo` / `hi` ограничивают диапазон.
double snapToGrid(double v,
    {required double step, double? lo, double? hi}) {
  double snapped = v;
  if (step > 0) {
    snapped = (v / step).round() * step;
  }
  if (lo != null && snapped < lo) snapped = lo;
  if (hi != null && snapped > hi) snapped = hi;
  return snapped;
}

/// Возвращает копию [outline] с координатами, прокруглёнными к шагу
/// `step` (по умолчанию 0.5 м). Полезно при кнопке «Сделать
/// axis-aligned» в редакторе пятна.
List<Vec2> snapOutlineToGrid(List<Vec2> outline,
    {double step = 0.5, double? maxX, double? maxY}) {
  return [
    for (final p in outline)
      Vec2(
        snapToGrid(p.x, step: step, lo: 0, hi: maxX),
        snapToGrid(p.y, step: step, lo: 0, hi: maxY),
      ),
  ];
}

/// Удаляет из [outline] вершины, в которых угол ≈ 180° (collinear) —
/// они избыточны и могут появиться после авто-snap-а.
List<Vec2> removeCollinearVertices(List<Vec2> outline,
    {double eps = 1e-6}) {
  if (outline.length <= 3) return List<Vec2>.from(outline);
  final cleaned = <Vec2>[];
  final n = outline.length;
  for (var i = 0; i < n; i++) {
    final prev = outline[(i - 1 + n) % n];
    final cur = outline[i];
    final next = outline[(i + 1) % n];
    final cross = (cur - prev).cross(next - cur);
    if (cross.abs() > eps) {
      cleaned.add(cur);
    }
  }
  return cleaned.length >= 3 ? cleaned : List<Vec2>.from(outline);
}

/// Минимальное расстояние от точки [p] до отрезка `[a, b]`.
double pointSegmentDistance(Vec2 p, Vec2 a, Vec2 b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final len2 = dx * dx + dy * dy;
  if (len2 < 1e-12) return (p - a).length;
  final t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2;
  final tc = t.clamp(0.0, 1.0);
  final projX = a.x + tc * dx;
  final projY = a.y + tc * dy;
  return math.sqrt((p.x - projX) * (p.x - projX) +
      (p.y - projY) * (p.y - projY));
}

// ───────────────────── §24.7 v68: CSG / boolean ─────────────────────
//
// Phase-3b §24.7: clipping произвольного полигона выпуклым окном по
// алгоритму Sutherland–Hodgman (1974). Для невыпуклого clipPolygon
// результат неверен, но для прямоугольных границ участка / пятна и
// выпуклых вырезов этого достаточно. Используется для:
//   • обрезки footprint по границе участка;
//   • вычисления пересечения двух прямоугольных пристроек (гараж +
//     терраса);
//   • проверки, лежит ли комната внутри пятна, до раскладки.
//
// Алгоритм классический: для каждого ребра clipPolygon (направленного
// CCW) проходим по subjectPolygon и оставляем точки, которые лежат
// слева от ребра; если ребро subject пересекает clip-edge — добавляем
// точку пересечения.

/// Возвращает true, если точка `p` лежит «внутри» относительно
/// направленного ребра `[a, b]` (для CCW-полигона — слева от ребра,
/// что эквивалентно cross(b-a, p-a) >= 0).
bool _insideClipEdge(Vec2 p, Vec2 a, Vec2 b, double eps) {
  final c = (b - a).cross(p - a);
  return c >= -eps;
}

/// Возвращает точку пересечения отрезка `[s, e]` с направленной
/// прямой `[a, b]`. Предполагается, что пересечение существует и
/// детерминант не вырождается; вызывающая сторона уже проверила,
/// что одна из точек `s`, `e` — внутри clip-edge, а другая — вне.
Vec2 _clipIntersect(Vec2 s, Vec2 e, Vec2 a, Vec2 b) {
  final dx1 = e.x - s.x;
  final dy1 = e.y - s.y;
  final dx2 = b.x - a.x;
  final dy2 = b.y - a.y;
  final det = dx1 * dy2 - dy1 * dx2;
  if (det.abs() < 1e-12) return s; // вырождение
  final t = ((a.x - s.x) * dy2 - (a.y - s.y) * dx2) / det;
  return Vec2(s.x + t * dx1, s.y + t * dy1);
}

/// Sutherland–Hodgman clipping: возвращает полигон-пересечение
/// [subject] ∩ [clip]. **Требование**: `clip` — выпуклый CCW-полигон
/// (например, прямоугольник участка). Если результат пуст —
/// возвращается пустой список. Если subject полностью внутри clip —
/// результат равен subject (с точностью до eps).
///
/// `subject` может быть невыпуклым (L/T/U-форма пятна) — алгоритм
/// корректен для произвольного simple-полигона как subject.
List<Vec2> clipPolygonByConvex(List<Vec2> subject, List<Vec2> clip,
    {double eps = 1e-9}) {
  if (subject.length < 3 || clip.length < 3) return const [];
  // Гарантируем CCW для clip: если CW — разворачиваем.
  final clipCcw = polygonIsCcw(clip)
      ? clip
      : List<Vec2>.from(clip.reversed);
  var output = List<Vec2>.from(subject);
  for (var i = 0; i < clipCcw.length; i++) {
    if (output.isEmpty) return const [];
    final a = clipCcw[i];
    final b = clipCcw[(i + 1) % clipCcw.length];
    final input = output;
    output = <Vec2>[];
    for (var j = 0; j < input.length; j++) {
      final s = input[(j - 1 + input.length) % input.length];
      final e = input[j];
      final sIn = _insideClipEdge(s, a, b, eps);
      final eIn = _insideClipEdge(e, a, b, eps);
      if (eIn) {
        if (!sIn) output.add(_clipIntersect(s, e, a, b));
        output.add(e);
      } else if (sIn) {
        output.add(_clipIntersect(s, e, a, b));
      }
    }
  }
  return output;
}

/// Удобная обёртка: пересечение subject-полигона с прямоугольным
/// окном `[xMin, yMin] × [xMax, yMax]`. CCW-обход.
List<Vec2> clipPolygonByRect(
  List<Vec2> subject, {
  required double xMin,
  required double yMin,
  required double xMax,
  required double yMax,
}) {
  final rect = <Vec2>[
    Vec2(xMin, yMin),
    Vec2(xMax, yMin),
    Vec2(xMax, yMax),
    Vec2(xMin, yMax),
  ];
  return clipPolygonByConvex(subject, rect);
}

/// Площадь произвольного simple-полигона (по shoelace). Для CCW
/// возвращает положительное число, для CW — отрицательное; берётся
/// абсолютное значение.
double polygonArea(List<Vec2> outline) {
  if (outline.length < 3) return 0;
  var s = 0.0;
  for (var i = 0; i < outline.length; i++) {
    final p = outline[i];
    final q = outline[(i + 1) % outline.length];
    s += p.x * q.y - q.x * p.y;
  }
  return s.abs() / 2;
}
