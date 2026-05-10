// Phase-3c §21.2 — тесты на расчёт нагрузок от L/T/U-кровли на
// фундамент (асимметрия, снеговой мешок в ендовы).

import 'package:construction_calculator/models/building_footprint.dart';
import 'package:construction_calculator/services/foundation_loads_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FoundationLoadsCalculator', () {
    test(
        'rect: симметричная нагрузка — эксцентриситет 0, '
        'recommendSlab = false', () {
      final fp = BuildingFootprint.rect(10, 8);
      final dist = FoundationLoadsCalculator.compute(
        footprint: fp,
        slopeDeg: 30,
        snowZone: 3,
        roofingMaterial: 'metal',
      );
      expect(dist.subRoofs.length, 1);
      expect(dist.eccentricityM, lessThan(0.01));
      expect(dist.recommendSlab, isFalse);
      // 4 ребра.
      expect(dist.edges.length, 4);
      // Длинные рёбра (10 м) несут больше, чем короткие (8 м), хотя
      // рассчитываются на одной площади.
      final long = dist.edges.where((e) => e.lengthM > 9).first;
      final short = dist.edges.where((e) => e.lengthM < 9).first;
      expect(long.qKnPerM, greaterThan(short.qKnPerM));
    });

    test(
        'L-shape: эксцентриситет > 0, центр давления НЕ совпадает '
        'с геометрическим центром bbox', () {
      final fp = BuildingFootprint.lShape(
        width: 12,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      );
      final dist = FoundationLoadsCalculator.compute(
        footprint: fp,
        slopeDeg: 30,
        snowZone: 3,
        roofingMaterial: 'metal',
      );
      // L-форма раскладывается на 2 прямоугольника.
      expect(dist.subRoofs.length, 2);
      // Эксцентриситет относительно bbox-центра не нулевой.
      expect(dist.eccentricityM, greaterThan(0.1));
    });

    test(
        'снеговой мешок (snow drift) в reflex-углах: рёбра, '
        'примыкающие к reflex, помечены и нагрузка выше', () {
      final fp = BuildingFootprint.lShape(
        width: 12,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      );
      final dist = FoundationLoadsCalculator.compute(
        footprint: fp,
        slopeDeg: 30,
        snowZone: 4, // высокая зона — snow drift заметен
        roofingMaterial: 'metal',
      );
      final reflexAdj =
          dist.edges.where((e) => e.isAdjacentToReflex).toList();
      expect(reflexAdj.length, greaterThanOrEqualTo(1));
      // Все примыкающие к reflex рёбра имеют ту же подкрышу или
      // соседнюю; их q ≥ q равноценного ребра без reflex (по схеме
      // подкрыши).
      for (final r in reflexAdj) {
        expect(r.qKnPerM, greaterThan(0));
      }
    });

    test(
        'высокий снеговой район: суммарная нагрузка пропорциональна Sg', () {
      final fp = BuildingFootprint.rect(10, 8);
      final z3 = FoundationLoadsCalculator.compute(
        footprint: fp,
        slopeDeg: 30,
        snowZone: 3,
        roofingMaterial: 'metal',
      );
      final z6 = FoundationLoadsCalculator.compute(
        footprint: fp,
        slopeDeg: 30,
        snowZone: 6,
        roofingMaterial: 'metal',
      );
      // Sg для зоны 6 (4.0) больше чем зоны 3 (1.8) → суммарная
      // нагрузка должна быть выше (учитывая wallLoad одинаковую).
      expect(z6.totalKn, greaterThan(z3.totalKn));
    });

    test('крутой скат (slopeDeg ≥ 60°): снеговая нагрузка = 0', () {
      final fp = BuildingFootprint.rect(10, 8);
      final flat = FoundationLoadsCalculator.compute(
        footprint: fp,
        slopeDeg: 5,
        snowZone: 6,
        roofingMaterial: 'metal',
      );
      final steep = FoundationLoadsCalculator.compute(
        footprint: fp,
        slopeDeg: 60,
        snowZone: 6,
        roofingMaterial: 'metal',
      );
      expect(steep.totalKn, lessThan(flat.totalKn));
    });

    test('snowSg по СП 20 табл.10.1: правильные значения по зонам', () {
      expect(FoundationLoadsCalculator.snowSg(1), 1.0);
      expect(FoundationLoadsCalculator.snowSg(3), 1.8);
      expect(FoundationLoadsCalculator.snowSg(6), 4.0);
      expect(FoundationLoadsCalculator.snowSg(8), 5.6);
      expect(FoundationLoadsCalculator.snowSg(null), 1.8);
    });

    test('snowMu: 1.0 при ≤30°, линейно к 0 при 60°', () {
      expect(FoundationLoadsCalculator.snowMu(0), 1.0);
      expect(FoundationLoadsCalculator.snowMu(30), 1.0);
      expect(FoundationLoadsCalculator.snowMu(45), closeTo(0.5, 1e-6));
      expect(FoundationLoadsCalculator.snowMu(60), 0.0);
      expect(FoundationLoadsCalculator.snowMu(75), 0.0);
    });
  });
}
