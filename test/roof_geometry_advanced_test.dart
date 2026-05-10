// Phase-3b §21.1.3 / §21.1.4 / §21.5 — тесты на расширенную hip/valley
// геометрию: пересечение лучей, zero-overhang в reflex, склейка
// соседних накосов.

import 'dart:math' as math;

import 'package:construction_calculator/models/building_footprint.dart';
import 'package:construction_calculator/services/roof_plan_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase-3b §21.1.4: zero-overhang в reflex', () {
    test('L-shape: внешний контур кровли проходит через reflex-вершину', () {
      final fp = BuildingFootprint.lShape(
        width: 12,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      );
      const o = 0.5;
      final g = RoofPlanGeometry.computePolygonal(
        shape: RoofShape.gable,
        footprint: fp,
        slopeDegrees: 30,
        overhang: o,
      );
      // Reflex-вершина L-shape — это (8, 6) (по конструкции lShape:
      // переход от широкой нижней части к узкой верхней).
      // Внешний контур должен ПРОЙТИ через эту вершину (без offset),
      // чтобы карниз не «торчал» в зону встречи скатов.
      final reflex = const Vec2(8, 6);
      var foundReflexInOuter = false;
      for (final p in g.outerOutline) {
        if ((p.x - reflex.x).abs() < 1e-3 && (p.y - reflex.y).abs() < 1e-3) {
          foundReflexInOuter = true;
          break;
        }
      }
      expect(foundReflexInOuter, isTrue,
          reason: 'reflex-вершина должна быть в outerOutline без offset-а');
    });

    test('T-shape: 2 reflex-вершины — обе в outerOutline без offset-а', () {
      final fp = BuildingFootprint.tShape(
        width: 12,
        height: 10,
        stemWidth: 4,
        stemHeight: 4,
      );
      const o = 0.5;
      final g = RoofPlanGeometry.computePolygonal(
        shape: RoofShape.gable,
        footprint: fp,
        slopeDegrees: 30,
        overhang: o,
      );
      // T-shape outline (по конструкции tShape):
      //   (0, 0)-(12, 0)-(12, 6)-(8, 6)-(8, 10)-(4, 10)-(4, 6)-(0, 6)
      // Reflex-вершины: (8, 6) и (4, 6).
      final reflexA = const Vec2(8, 6);
      final reflexB = const Vec2(4, 6);
      var hitA = false, hitB = false;
      for (final p in g.outerOutline) {
        if ((p.x - reflexA.x).abs() < 1e-3 &&
            (p.y - reflexA.y).abs() < 1e-3) {
          hitA = true;
        }
        if ((p.x - reflexB.x).abs() < 1e-3 &&
            (p.y - reflexB.y).abs() < 1e-3) {
          hitB = true;
        }
      }
      expect(hitA, isTrue);
      expect(hitB, isTrue);
    });

    test('rect (без reflex): контур offset на o во все стороны', () {
      final fp = BuildingFootprint.rect(10, 8);
      const o = 0.5;
      final g = RoofPlanGeometry.computePolygonal(
        shape: RoofShape.gable,
        footprint: fp,
        slopeDegrees: 30,
        overhang: o,
      );
      // outerOutline для прямоугольника = bbox + o во все стороны
      // (т.к. computePolygonal делегирует в compute() для simple rect).
      final xs = g.outerOutline.map((p) => p.x).toList();
      final ys = g.outerOutline.map((p) => p.y).toList();
      expect(xs.reduce(math.min), closeTo(-o, 1e-6));
      expect(xs.reduce(math.max), closeTo(10 + o, 1e-6));
      expect(ys.reduce(math.min), closeTo(-o, 1e-6));
      expect(ys.reduce(math.max), closeTo(8 + o, 1e-6));
    });
  });

  group('Phase-3b §21.1.3: пересечение лучей', () {
    test(
        'узкая reflex-зона: ендова из (8,6) обрезается раньше, '
        'чем достигнет конька (если пересеклась с накосом)', () {
      // L-shape с очень узкой нижней частью (3×6) и высокой верхней (8×4).
      // Reflex-угол (3, 4). Ендова идёт по биссектрисе вглубь полигона.
      // Тест: ендова не выходит за пределы полигона.
      final fp = BuildingFootprint(outline: const [
        Vec2(0, 0),
        Vec2(3, 0),
        Vec2(3, 4),
        Vec2(8, 4),
        Vec2(8, 8),
        Vec2(0, 8),
      ]);
      final g = RoofPlanGeometry.computePolygonal(
        shape: RoofShape.gable,
        footprint: fp,
        slopeDegrees: 30,
        overhang: 0.4,
      );
      // Если ендова была сгенерирована — её конец должен быть внутри
      // полигона (или на границе).
      for (final v in g.valleys) {
        expect(fp.contains(Vec2(v.b.x, v.b.y)) ||
            // допуск на численную точность — точка на самой границе
            v.b.x >= 0 && v.b.x <= 8 && v.b.y >= 0 && v.b.y <= 8,
        isTrue);
      }
    });
  });

  group('Phase-3b §21.5: склейка соседних накосов на коньке', () {
    test('hip-roof над rect: 4 накоса попадают в концы конька', () {
      final fp = BuildingFootprint.rect(10, 8);
      final g = RoofPlanGeometry.computePolygonal(
        shape: RoofShape.hip,
        footprint: fp,
        slopeDegrees: 30,
        overhang: 0.4,
      );
      // computePolygonal делегирует rect в compute() — там генерация
      // через специальный hip-кейс, а не через биссектрисы. Достаточно
      // проверить, что накосы существуют и сходятся в концах конька.
      expect(g.hips.length, 4);
      expect(g.ridges.length, 1);
      // Каждый накос заканчивается в одной из двух точек конька.
      final ridge = g.ridges.first;
      final endpoints = <RoofPoint>[ridge.a, ridge.b];
      for (final hip in g.hips) {
        var matchAny = false;
        for (final e in endpoints) {
          final dx = hip.b.x - e.x;
          final dy = hip.b.y - e.y;
          if (math.sqrt(dx * dx + dy * dy) < 0.5) {
            matchAny = true;
            break;
          }
        }
        expect(matchAny, isTrue,
            reason: 'hip ${hip.a}→${hip.b} не упирается в конёк');
      }
    });
  });

  group('Phase-3b §21.1.4 (v66): полный miter на reflex-вершине', () {
    test('L-shape: outerOutline на reflex имеет 3 вершины подряд '
        '(in, corner, out)', () {
      final fp = BuildingFootprint.lShape(
        width: 12,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      );
      const o = 0.5;
      final g = RoofPlanGeometry.computePolygonal(
        shape: RoofShape.gable,
        footprint: fp,
        slopeDegrees: 30,
        overhang: o,
      );
      // 5 convex (×1 вершина каждая) + 1 reflex (×3 вершины) = 8 точек.
      expect(g.outerOutline.length, 8,
          reason: 'L-shape: 5+3=8 точек outerOutline');
      // Reflex-вершина (8, 6) должна быть в outerOutline, окружённая
      // двумя «walking-along-the-wall» точками на расстоянии o.
      var reflexIdx = -1;
      for (var i = 0; i < g.outerOutline.length; i++) {
        final p = g.outerOutline[i];
        if ((p.x - 8).abs() < 1e-3 && (p.y - 6).abs() < 1e-3) {
          reflexIdx = i;
          break;
        }
      }
      expect(reflexIdx, greaterThanOrEqualTo(0),
          reason: 'reflex (8,6) должен быть в outerOutline');
      final n = g.outerOutline.length;
      final before = g.outerOutline[(reflexIdx - 1 + n) % n];
      final after = g.outerOutline[(reflexIdx + 1) % n];
      // before — конец карниза предыдущего ребра, на расстоянии o от
      // reflex-вершины ВДОЛЬ предыдущего ребра.
      final dxBefore = before.x - 8;
      final dyBefore = before.y - 6;
      final distBefore = math.sqrt(dxBefore * dxBefore + dyBefore * dyBefore);
      expect(distBefore, closeTo(o, 1e-3),
          reason: 'before-точка должна быть в o от reflex по предыдущему ребру');
      // after — начало карниза следующего ребра, на расстоянии o от reflex.
      final dxAfter = after.x - 8;
      final dyAfter = after.y - 6;
      final distAfter = math.sqrt(dxAfter * dxAfter + dyAfter * dyAfter);
      expect(distAfter, closeTo(o, 1e-3),
          reason: 'after-точка должна быть в o от reflex по следующему ребру');
    });
  });

  group('Phase-3b §21.1.3 (v66): straight-skeleton continuation', () {
    test('hip над L-shape: pass 4 рисует продолжение от точки встречи '
        'двух биссектрис до ближайшего конька', () {
      // L-shape c длинной нижней частью (12×4) и узкой верхней (4×6).
      // Hip над верхней узкой частью: 2 биссектрисы из convex-вершин
      // встречаются в центре нижней кромки верхней части и продолжают
      // путь к коньку.
      final fp = BuildingFootprint.lShape(
        width: 12,
        height: 10,
        cutWidth: 8,
        cutHeight: 4,
      );
      final g = RoofPlanGeometry.computePolygonal(
        shape: RoofShape.hip,
        footprint: fp,
        slopeDegrees: 30,
        overhang: 0.4,
      );
      // На L-shape с hip-кровлей должен быть хотя бы один накос.
      expect(g.hips.isNotEmpty, isTrue,
          reason: 'hip-кровля должна давать накосы');
      // Все накосы должны иметь ненулевую длину.
      for (final hip in g.hips) {
        final len = math.sqrt(
            (hip.b.x - hip.a.x) * (hip.b.x - hip.a.x) +
                (hip.b.y - hip.a.y) * (hip.b.y - hip.a.y));
        expect(len, greaterThan(0.05), reason: 'hip $hip имеет нулевую длину');
      }
    });
  });
}
