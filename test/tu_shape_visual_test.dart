// Phase-3b §17.2.2 next-slice: визуальные дампы T- и U-образных
// планов. Сохраняют PDF в `/tmp/tshape_plan.pdf` и `/tmp/ushape_plan.pdf`
// для визуальной проверки (план этажа, план кровли, 3D-разрезы).

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

Future<void> _dump({
  required BuildingFootprint footprint,
  required String name,
  required String filePath,
}) async {
  final brief = ClientBrief(
    footprintWidth: footprint.bbox.width,
    footprintLength: footprint.bbox.height,
    floors: 1,
    wallMaterial: WallMaterial.aerated,
  );
  final plans = FloorPlanGenerator.generate(brief, footprint: footprint);
  final plan = plans.first;
  final now = DateTime.now();
  final drawings = <Drawing>[
    Drawing(
      id: 'd-$name',
      title: '${plan.floorLabel} — план',
      kind: DrawingKind.schematicPlan,
      createdAt: now,
      payload: plan.encode(),
    ),
  ];
  final project = HouseProject(
    id: 'p-$name',
    name: '$name Demo',
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
    architectureFootprint: footprint,
  );
  final bytes = await PdfBuilder.buildBatch(
    project: project,
    drawings: drawings,
    versionNumber: 1,
  );
  final f = File(filePath);
  await f.writeAsBytes(bytes);
  // ignore: avoid_print
  print('Saved ${bytes.length} bytes to ${f.path}');
  expect(bytes.length, greaterThan(30000));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'Phase-3b §17.2.2: дамп T-shape PDF в /tmp/tshape_plan.pdf '
      '(bbox 12×10, стержень 4×4 снизу)', () async {
    await _dump(
      footprint: BuildingFootprint.tShape(
        width: 12,
        height: 10,
        stemWidth: 4,
        stemHeight: 4,
      ),
      name: 'T-shape',
      filePath: '/tmp/tshape_plan.pdf',
    );
  });

  test(
      'Phase-3b §17.2.2: дамп U-shape PDF в /tmp/ushape_plan.pdf '
      '(bbox 12×10, вырез 4×4 сверху)', () async {
    await _dump(
      footprint: BuildingFootprint.uShape(
        width: 12,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      ),
      name: 'U-shape',
      filePath: '/tmp/ushape_plan.pdf',
    );
  });
}
