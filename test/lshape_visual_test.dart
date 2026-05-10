// Phase-3b §17.2.1 — визуальный дамп L-образного плана.
// Сохраняет PDF в `/tmp/lshape_plan.pdf` для визуальной проверки.
//
// Тест НЕ упадёт — только сохраняет дамп. Используется как утилита
// для скриншотов в HANDOFF.md.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:construction_calculator/data/wall_materials.dart';
import 'package:construction_calculator/models/building_footprint.dart';
import 'package:construction_calculator/models/client_brief.dart';
import 'package:construction_calculator/models/construction_type.dart';
import 'package:construction_calculator/models/drawing.dart';
import 'package:construction_calculator/models/drawings_collection.dart';
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

  test('Phase-3b §17.2.1: дамп L-shape PDF в /tmp/lshape_plan.pdf', () async {
    final brief = ClientBrief(
      footprintWidth: 10,
      footprintLength: 10,
      floors: 1,
      wallMaterial: WallMaterial.aerated,
    );
    // Используем интегрированный путь: footprint передаётся в генератор,
    // комнаты автоматически обрезаются по полигону.
    final lFootprint = BuildingFootprint.lShape(
      width: 10,
      height: 10,
      cutWidth: 4,
      cutHeight: 4,
    );
    final plans = FloorPlanGenerator.generate(brief, footprint: lFootprint);
    final lPlan = plans.first;

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
      name: 'L-shape Demo',
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
      architectureFootprint: lFootprint,
    );

    final bytes = await PdfBuilder.buildBatch(
      project: project,
      drawings: drawings,
      versionNumber: 1,
    );

    final f = File('/tmp/lshape_plan.pdf');
    await f.writeAsBytes(bytes);
    // ignore: avoid_print
    print('Saved ${bytes.length} bytes to ${f.path}');
    expect(bytes.length, greaterThan(30000));
  });
}
