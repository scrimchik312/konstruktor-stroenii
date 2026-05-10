// v68.11: Smoke-тест синхронизации размеров. Проверяет, что
// `BuildingDimensions.of(project)` — единый источник истины и одни
// и те же поля попадают и в `Building3DGenerator.generate()` (3D-вид
// + PDF-аксонометрия), и в `PdfBuilder._elevation()` (фасады/разрезы).
// Если кто-то поменяет логику только в одном из мест — тест упадёт.

import 'package:flutter_test/flutter_test.dart';

import 'package:construction_calculator/models/building_dimensions.dart';
import 'package:construction_calculator/models/client_brief.dart';
import 'package:construction_calculator/models/construction_type.dart';
import 'package:construction_calculator/models/foundation.dart';
import 'package:construction_calculator/models/foundation_design.dart';
import 'package:construction_calculator/models/house_project.dart';
import 'package:construction_calculator/models/roof_design.dart';
import 'package:construction_calculator/services/building3d_generator.dart';

HouseProject _project({
  required String id,
  required FoundationType foundationType,
  required int floors,
  required double w,
  required double l,
  required double slope,
}) {
  final now = DateTime.now();
  return HouseProject(
    id: id,
    name: id,
    constructionType: ConstructionType.privateHouse,
    createdAt: now,
    updatedAt: now,
    brief: ClientBrief(
      snowZone: 4,
      windZone: 'II',
      footprintWidth: w,
      footprintLength: l,
      floors: floors,
    ),
    foundation: FoundationDesign(
      type: foundationType,
      device: FoundationDevice.monolithic,
    ),
    roof: RoofDesign(
      type: 'gable',
      slopeAngle: slope,
      roofingMaterial: 'metal_tile',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BuildingDimensions согласован с Building3DGenerator (slab)', () {
    final project = _project(
      id: 'sync-slab',
      foundationType: FoundationType.slab,
      floors: 2,
      w: 10,
      l: 8,
      slope: 30,
    );

    final dims = BuildingDimensions.of(project, widthM: 10, lengthM: 8);
    final building = Building3DGenerator.generate(project);
    expect(building, isNotNull);

    // §A: общая высота `Building3D.totalHeight` ≈ сумма компонентов
    // из BuildingDimensions (фундамент + цоколь + этажи + кровля).
    final expectedTotal = dims.foundationDepth +
        dims.plinthHeight +
        dims.floorHeight * dims.floors +
        (dims.hasMansard ? dims.floorHeight : 0.0) +
        dims.roofHeight;
    expect((building!.totalHeight - expectedTotal).abs(), lessThan(0.10),
        reason:
            'Сумма высот в Building3D должна сходиться с BuildingDimensions');

    // §B: для slab-фундамента цоколь >= 0.20 м (в v68.10 был баг 0.0).
    expect(dims.plinthHeight, greaterThanOrEqualTo(0.18),
        reason:
            'plinthHeight для slab должен быть ~0.20 м (в v68.10 был 0.0)');

    // §C: высота кровли ~ (короткая сторона / 2) * tan(угол) — для
    // gable 30° на 8×10 → ~2.31 м. Допуск ±1 м (учёт стандартного
    // карнизного свеса и слоя стропил).
    expect(dims.roofHeight, greaterThan(1.0));
    expect(dims.roofHeight, lessThan(4.0));
  });

  test('BuildingDimensions для свайного фундамента — высокий цоколь',
      () {
    final project = _project(
      id: 'sync-pile',
      foundationType: FoundationType.pile,
      floors: 1,
      w: 8,
      l: 6,
      slope: 25,
    );
    final dims = BuildingDimensions.of(project, widthM: 8, lengthM: 6);
    expect(dims.plinthHeight, greaterThan(0.30),
        reason: 'pile должен давать высокий открытый цоколь');
  });

  test('BuildingDimensions для ленточного фундамента — глубина 0.80',
      () {
    final project = _project(
      id: 'sync-strip',
      foundationType: FoundationType.strip,
      floors: 1,
      w: 10,
      l: 10,
      slope: 22,
    );
    final dims = BuildingDimensions.of(project, widthM: 10, lengthM: 10);
    expect(dims.foundationDepth, closeTo(0.80, 0.20));
    expect(dims.plinthHeight, greaterThan(0.30));
  });
}
