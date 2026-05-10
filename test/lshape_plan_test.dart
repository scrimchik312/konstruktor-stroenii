// Phase-3b §17.2.1 — интеграционный тест L-образного плана.
//
// Проверяет, что:
//   1. FloorPlan с `footprint = BuildingFootprint.lShape(...)` корректно
//      сериализуется/десериализуется (JSON-roundtrip сохраняет полигон).
//   2. `FloorPlan.hasPolygonalFootprint` возвращает `true` для L-формы и
//      `false` для прямоугольника, заданного по умолчанию.
//   3. PDF собирается без исключений, когда хотя бы один план в проекте —
//      L-образный (т.е. кодовый путь `_paintPlan` с polygon outline
//      работает на конце-в-конец).
//   4. Декомпозиция L-формы 10×10 минус 4×4 даёт ровно 84 м² суммарной
//      площади ячеек (то же что и `BuildingFootprint.area`).

import 'package:flutter_test/flutter_test.dart';

import 'package:construction_calculator/data/wall_materials.dart';
import 'package:construction_calculator/models/building_footprint.dart';
import 'package:construction_calculator/models/client_brief.dart';
import 'package:construction_calculator/models/construction_type.dart';
import 'package:construction_calculator/models/drawing.dart';
import 'package:construction_calculator/models/drawings_collection.dart';
import 'package:construction_calculator/models/floor_plan.dart';
import 'package:construction_calculator/models/foundation.dart';
import 'package:construction_calculator/models/foundation_design.dart';
import 'package:construction_calculator/models/house_project.dart';
import 'package:construction_calculator/models/roof_design.dart';
import 'package:construction_calculator/models/staircase_design.dart';
import 'package:construction_calculator/models/walls_design.dart';
import 'package:construction_calculator/services/floor_plan_generator.dart';
import 'package:construction_calculator/services/pdf_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FloorPlan: hasPolygonalFootprint корректно различает L и прямоугольник',
      () {
    final rect = FloorPlan(
      floorLabel: 'Этаж 1',
      width: 10,
      height: 10,
      rooms: const [],
    );
    expect(rect.hasPolygonalFootprint, isFalse);
    expect(rect.effectiveFootprint.area, closeTo(100.0, 1e-6));

    final l = FloorPlan(
      floorLabel: 'Этаж 1',
      width: 10,
      height: 10,
      rooms: const [],
      footprint: BuildingFootprint.lShape(width: 10, height: 10, cutWidth: 4, cutHeight: 4),
    );
    expect(l.hasPolygonalFootprint, isTrue);
    expect(l.effectiveFootprint.area, closeTo(84.0, 1e-6));
  });

  test('FloorPlan JSON-roundtrip сохраняет polygonal footprint', () {
    final original = FloorPlan(
      floorLabel: 'Этаж 1',
      width: 10,
      height: 10,
      rooms: const [],
      footprint: BuildingFootprint.lShape(width: 10, height: 10, cutWidth: 4, cutHeight: 4),
    );
    final restored = FloorPlan.fromJson(
      Map<String, dynamic>.from(original.toJson()),
    );
    expect(restored.hasPolygonalFootprint, isTrue);
    expect(restored.effectiveFootprint.area, closeTo(84.0, 1e-6));
    expect(restored.effectiveFootprint.outline.length,
        original.effectiveFootprint.outline.length);
  });

  test('Декомпозиция L-формы 10×10 − 4×4 даёт ровно 84 м²', () {
    final fp = BuildingFootprint.lShape(width: 10, height: 10, cutWidth: 4, cutHeight: 4);
    final cells = fp.rectangleDecomposition();
    expect(cells.isNotEmpty, isTrue);
    final sumArea = cells.fold<double>(0, (s, c) => s + c.area);
    expect(sumArea, closeTo(fp.area, 1e-6));
    expect(sumArea, closeTo(84.0, 1e-6));
    // Ни одна ячейка не должна выйти за bbox.
    for (final c in cells) {
      expect(c.x >= -1e-9, isTrue);
      expect(c.y >= -1e-9, isTrue);
      expect(c.x + c.width <= 10 + 1e-9, isTrue);
      expect(c.y + c.height <= 10 + 1e-9, isTrue);
    }
  });

  test('PdfBuilder.buildBatch собирается на проекте c L-образным этажом',
      () async {
    final brief = ClientBrief(
      snowZone: 4,
      windZone: 'II',
      footprintWidth: 10,
      footprintLength: 10,
      floors: 1,
      wallMaterial: WallMaterial.aerated,
    );
    // Стартуем со стандартной генерации, но первому плану выставляем
    // L-образный footprint — будем рисовать тот же набор комнат, но
    // внешний контур пройдёт по уступу.
    final plans = FloorPlanGenerator.generate(brief);
    expect(plans.isNotEmpty, isTrue);
    final base = plans.first;
    final lPlan = base.copyWith(
      width: 10,
      height: 10,
      footprint: BuildingFootprint.lShape(width: 10, height: 10, cutWidth: 4, cutHeight: 4),
    );

    final now = DateTime.now();
    final drawings = <Drawing>[
      Drawing(
        id: 'd-l',
        title: '${lPlan.floorLabel} — план',
        kind: DrawingKind.schematicPlan,
        createdAt: now,
        payload: lPlan.encode(),
      ),
    ];

    final project = HouseProject(
      id: 'p-l',
      name: 'L-shape тест',
      constructionType: ConstructionType.privateHouse,
      createdAt: now,
      updatedAt: now,
      drawings: DrawingsCollection(drawings: drawings),
      brief: brief,
      walls: WallsDesign(material: 'aerated', thickness: 400, height: 2.8),
      roof: RoofDesign(
        type: 'gable',
        slopeAngle: 30,
        roofingMaterial: 'metal_tile',
      ),
      foundation: FoundationDesign(type: FoundationType.strip),
      staircase: StaircaseDesign(floorHeight: 2.8),
    );

    final bytes = await PdfBuilder.buildBatch(
      project: project,
      drawings: drawings,
      versionNumber: 1,
    );

    expect(bytes.length, greaterThan(30000),
        reason: 'PDF c L-образным планом должен быть валидным.');
    final magic = String.fromCharCodes(bytes.sublist(0, 5));
    expect(magic, '%PDF-');
  });
}
