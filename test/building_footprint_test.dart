// Тесты модели BuildingFootprint (Phase-3b §17.2.1).

import 'package:flutter_test/flutter_test.dart';
import 'package:construction_calculator/models/building_footprint.dart';

void main() {
  group('BuildingFootprint.rect', () {
    test('Площадь и периметр прямоугольника', () {
      final f = BuildingFootprint.rect(10, 6);
      expect(f.area, closeTo(60.0, 1e-9));
      expect(f.perimeter, closeTo(32.0, 1e-9));
      expect(f.bbox.width, 10);
      expect(f.bbox.height, 6);
      expect(f.contains(const Vec2(5, 3)), isTrue);
      expect(f.contains(const Vec2(11, 3)), isFalse);
    });

    test('Декомпозиция прямоугольника = 1 ячейка', () {
      final f = BuildingFootprint.rect(8, 5);
      final cells = f.rectangleDecomposition();
      expect(cells.length, 1);
      expect(cells.first.area, closeTo(40.0, 1e-9));
    });
  });

  group('BuildingFootprint.lShape', () {
    test('L-форма: площадь = bbox − вырез', () {
      // 10×10 − вырез 4×4 = 100 − 16 = 84.
      final f = BuildingFootprint.lShape(
        width: 10,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      );
      expect(f.area, closeTo(84.0, 1e-9));
      expect(f.bbox.width, 10);
      expect(f.bbox.height, 10);
      expect(f.contains(const Vec2(2, 2)), isTrue);
      // Точка в вырезе должна быть СНАРУЖИ.
      expect(f.contains(const Vec2(8, 8)), isFalse);
    });

    test('L-форма раскладывается в прямоугольники без потерь', () {
      final f = BuildingFootprint.lShape(
        width: 10,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      );
      final cells = f.rectangleDecomposition();
      expect(cells.length, greaterThanOrEqualTo(2),
          reason: 'L-форма должна давать ≥ 2 прямоугольных ячеек');
      final sum = cells.fold<double>(0, (s, c) => s + c.area);
      expect(sum, closeTo(f.area, 1e-9),
          reason: 'Сумма площадей ячеек = площадь полигона');
      // Ячейки не пересекаются — проверим грубо: каждая центр-точка
      // принадлежит ровно одной ячейке.
      for (final c in cells) {
        var hits = 0;
        final cx = c.x + c.width / 2;
        final cy = c.y + c.height / 2;
        for (final d in cells) {
          if (cx > d.x && cx < d.x + d.width && cy > d.y && cy < d.y + d.height) {
            hits++;
          }
        }
        expect(hits, 1,
            reason: 'Центр ячейки попадает только в собственный прямоугольник');
      }
    });

    test('CCW: signedArea > 0', () {
      final f = BuildingFootprint.lShape(
        width: 10,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      );
      expect(f.signedArea, greaterThan(0));
      expect(f.isCcw, isTrue);
    });
  });

  test('JSON roundtrip', () {
    final f = BuildingFootprint.lShape(
      width: 12,
      height: 8,
      cutWidth: 4,
      cutHeight: 4,
    );
    final j = f.toJson();
    final back = BuildingFootprint.fromJson(j);
    expect(back.area, closeTo(f.area, 1e-9));
    expect(back.outline.length, f.outline.length);
    for (var i = 0; i < f.outline.length; i++) {
      expect(back.outline[i], f.outline[i]);
    }
  });
}
