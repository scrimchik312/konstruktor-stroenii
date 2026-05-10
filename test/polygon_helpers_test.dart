// Phase-3b §21.1.1 / §21.1.2 / §21.7 — тесты на общие утилиты для
// полигональных контуров.

import 'package:construction_calculator/models/building_footprint.dart';
import 'package:construction_calculator/services/polygon_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('vertexConvexity (CCW)', () {
    test('квадрат: все 4 вершины convex', () {
      final sq = BuildingFootprint.rect(10, 8).outline;
      for (var i = 0; i < sq.length; i++) {
        expect(vertexConvexity(sq, i), VertexConvexity.convex,
            reason: 'vertex #$i ${sq[i]}');
      }
    });

    test('L-форма: 5 convex + 1 reflex (внутренний угол)', () {
      final l = BuildingFootprint.lShape(
        width: 12,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      ).outline;
      var convex = 0, reflex = 0;
      for (var i = 0; i < l.length; i++) {
        final c = vertexConvexity(l, i);
        if (c == VertexConvexity.convex) convex++;
        if (c == VertexConvexity.reflex) reflex++;
      }
      expect(convex, 5);
      expect(reflex, 1);
    });

    test('T-форма (8 вершин): 6 convex + 2 reflex', () {
      final t = BuildingFootprint.tShape(
        width: 12,
        height: 10,
        stemWidth: 4,
        stemHeight: 4,
      ).outline;
      var convex = 0, reflex = 0;
      for (var i = 0; i < t.length; i++) {
        final c = vertexConvexity(t, i);
        if (c == VertexConvexity.convex) convex++;
        if (c == VertexConvexity.reflex) reflex++;
      }
      expect(convex, 6);
      expect(reflex, 2);
    });

    test('U-форма (8 вершин, вырез сверху): 6 convex + 2 reflex', () {
      final u = BuildingFootprint.uShape(
        width: 12,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      ).outline;
      var convex = 0, reflex = 0;
      for (var i = 0; i < u.length; i++) {
        final c = vertexConvexity(u, i);
        if (c == VertexConvexity.convex) convex++;
        if (c == VertexConvexity.reflex) reflex++;
      }
      expect(convex, 6);
      expect(reflex, 2);
    });

    test('коллинеарные точки: vertexConvexity = collinear', () {
      final outline = const [
        Vec2(0, 0),
        Vec2(5, 0),
        Vec2(10, 0), // на одной прямой с предыдущими — collinear
        Vec2(10, 10),
        Vec2(0, 10),
      ];
      expect(vertexConvexity(outline, 1), VertexConvexity.collinear);
    });
  });

  group('vertexInteriorBisectorCcw', () {
    test('квадрат: биссектрисы — диагонали 45°', () {
      final sq = BuildingFootprint.rect(10, 8).outline;
      // Вершина (0,0): внутренняя биссектриса смотрит «внутрь» → (+, +).
      final b0 = vertexInteriorBisectorCcw(sq, 0);
      expect(b0.x, greaterThan(0));
      expect(b0.y, greaterThan(0));
      // Вершина (10, 0): внутренняя биссектриса смотрит → (-, +).
      final b1 = vertexInteriorBisectorCcw(sq, 1);
      expect(b1.x, lessThan(0));
      expect(b1.y, greaterThan(0));
      // Вершина (10, 8): → (-, -).
      final b2 = vertexInteriorBisectorCcw(sq, 2);
      expect(b2.x, lessThan(0));
      expect(b2.y, lessThan(0));
      // Вершина (0, 8): → (+, -).
      final b3 = vertexInteriorBisectorCcw(sq, 3);
      expect(b3.x, greaterThan(0));
      expect(b3.y, lessThan(0));
    });

    test('единичная норма биссектрисы', () {
      final l = BuildingFootprint.lShape(
        width: 12,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      ).outline;
      for (var i = 0; i < l.length; i++) {
        final b = vertexInteriorBisectorCcw(l, i);
        expect(b.length, closeTo(1.0, 1e-6),
            reason: 'vertex #$i ${l[i]}');
      }
    });

    test('косой треугольник: биссектриса 60° вершины ≈ норм-1', () {
      // Равносторонний треугольник со стороной 1.
      final tri = const [
        Vec2(0, 0),
        Vec2(1, 0),
        Vec2(0.5, 0.8660254038), // sqrt(3)/2
      ];
      // Полигон CCW (signedArea > 0).
      expect(polygonIsCcw(tri), isTrue);
      for (var i = 0; i < 3; i++) {
        final b = vertexInteriorBisectorCcw(tri, i);
        expect(b.length, closeTo(1.0, 1e-6));
      }
    });
  });

  group('snapToGrid / snapOutlineToGrid / removeCollinearVertices', () {
    test('snapToGrid: 0,5 м → ближайшие 0,5', () {
      expect(snapToGrid(2.27, step: 0.5), closeTo(2.5, 1e-9));
      expect(snapToGrid(2.24, step: 0.5), closeTo(2.0, 1e-9));
      expect(snapToGrid(2.50, step: 0.5), closeTo(2.5, 1e-9));
    });

    test('snapToGrid: clamp к [lo, hi]', () {
      expect(snapToGrid(-3.0, step: 0.5, lo: 0, hi: 10), 0.0);
      expect(snapToGrid(15.0, step: 0.5, lo: 0, hi: 10), 10.0);
    });

    test('snapToGrid: step=0 → значение без изменений', () {
      expect(snapToGrid(2.273, step: 0), closeTo(2.273, 1e-9));
    });

    test('snapOutlineToGrid: округление + clamp', () {
      final outline = const [
        Vec2(0.07, -0.13),
        Vec2(11.92, 0.32),
        Vec2(11.92, 7.79),
        Vec2(0.07, 7.79),
      ];
      final snapped = snapOutlineToGrid(
        outline,
        step: 0.5,
        maxX: 12,
        maxY: 8,
      );
      // (0.07, -0.13) → (0.0, 0.0) (clamp y, snap x)
      expect(snapped[0].x, closeTo(0.0, 1e-9));
      expect(snapped[0].y, closeTo(0.0, 1e-9));
      // (11.92, 0.32) → (12, 0.5)
      expect(snapped[1].x, closeTo(12.0, 1e-9));
      expect(snapped[1].y, closeTo(0.5, 1e-9));
    });

    test('removeCollinearVertices удаляет вершины на прямой', () {
      final outline = const [
        Vec2(0, 0),
        Vec2(5, 0),
        Vec2(10, 0),
        Vec2(10, 10),
        Vec2(0, 10),
      ];
      final cleaned = removeCollinearVertices(outline);
      expect(cleaned.length, 4);
      expect(cleaned, isNot(contains(const Vec2(5, 0))));
    });

    test('removeCollinearVertices сохраняет L-форму без изменений', () {
      final l = BuildingFootprint.lShape(
        width: 12,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      ).outline;
      final cleaned = removeCollinearVertices(l);
      expect(cleaned.length, 6);
    });
  });

  group('pointSegmentDistance', () {
    test('точка на отрезке → 0', () {
      expect(
        pointSegmentDistance(
            const Vec2(5, 0), const Vec2(0, 0), const Vec2(10, 0)),
        closeTo(0, 1e-9),
      );
    });

    test('точка над серединой отрезка → высота', () {
      expect(
        pointSegmentDistance(
            const Vec2(5, 3), const Vec2(0, 0), const Vec2(10, 0)),
        closeTo(3, 1e-9),
      );
    });

    test('точка за концом отрезка → расстояние до конца', () {
      expect(
        pointSegmentDistance(
            const Vec2(15, 0), const Vec2(0, 0), const Vec2(10, 0)),
        closeTo(5, 1e-9),
      );
    });
  });

  group('polygonIsCcw', () {
    test('rect — CCW', () {
      expect(polygonIsCcw(BuildingFootprint.rect(10, 8).outline), isTrue);
    });

    test('reversed rect — CW', () {
      expect(
        polygonIsCcw(
            BuildingFootprint.rect(10, 8).outline.reversed.toList()),
        isFalse,
      );
    });
  });

  // ───────────────────── §24.7 v68: CSG / boolean ─────────────────────
  group('clipPolygonByConvex (Sutherland–Hodgman)', () {
    test('subject полностью внутри clip — площадь не меняется', () {
      // 4×4 прямоугольник внутри 10×10.
      final subject = const [
        Vec2(2, 2),
        Vec2(6, 2),
        Vec2(6, 6),
        Vec2(2, 6),
      ];
      final result = clipPolygonByRect(subject,
          xMin: 0, yMin: 0, xMax: 10, yMax: 10);
      expect(result.length, greaterThanOrEqualTo(4));
      expect(polygonArea(result), closeTo(16.0, 1e-6));
    });

    test('subject полностью вне clip — пустой результат', () {
      final subject = const [
        Vec2(20, 20),
        Vec2(25, 20),
        Vec2(25, 25),
        Vec2(20, 25),
      ];
      final result = clipPolygonByRect(subject,
          xMin: 0, yMin: 0, xMax: 10, yMax: 10);
      expect(result, isEmpty);
    });

    test('subject частично пересекает clip — корректное обрезание', () {
      // Прямоугольник 10×10, выходит за clip (5×10) с правой стороны.
      final subject = const [
        Vec2(0, 0),
        Vec2(10, 0),
        Vec2(10, 10),
        Vec2(0, 10),
      ];
      final result = clipPolygonByRect(subject,
          xMin: 0, yMin: 0, xMax: 5, yMax: 10);
      expect(polygonArea(result), closeTo(50.0, 1e-6));
    });

    test('clip CCW и CW дают одинаковый результат', () {
      final subject = const [
        Vec2(0, 0),
        Vec2(10, 0),
        Vec2(10, 10),
        Vec2(0, 10),
      ];
      final clipCcw = const [
        Vec2(2, 2),
        Vec2(8, 2),
        Vec2(8, 8),
        Vec2(2, 8),
      ];
      final clipCw = clipCcw.reversed.toList();
      final aCcw = clipPolygonByConvex(subject, clipCcw);
      final aCw = clipPolygonByConvex(subject, clipCw);
      expect(polygonArea(aCcw), closeTo(polygonArea(aCw), 1e-6));
      expect(polygonArea(aCcw), closeTo(36.0, 1e-6));
    });

    test('L-форма subject обрезается по rect — площадь = пересечение', () {
      final l = BuildingFootprint.lShape(
        width: 12,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      ).outline;
      // Площадь L = 12·10 - 4·4 = 104.
      // Обрезаем верхний-левый угол: rect [0..6, 0..6] → захватывает
      // только нижне-левый угол L, площадь = 6·6 = 36 (т.к. вырез справа
      // не заходит в rect).
      final result = clipPolygonByRect(l,
          xMin: 0, yMin: 0, xMax: 6, yMax: 6);
      expect(polygonArea(result), closeTo(36.0, 1e-6));
    });
  });

  group('polygonArea', () {
    test('квадрат 10×8', () {
      expect(polygonArea(BuildingFootprint.rect(10, 8).outline),
          closeTo(80.0, 1e-9));
    });

    test('L-форма', () {
      final l = BuildingFootprint.lShape(
        width: 12,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      ).outline;
      // 12·10 - 4·4 = 104.
      expect(polygonArea(l), closeTo(104.0, 1e-9));
    });
  });
}
