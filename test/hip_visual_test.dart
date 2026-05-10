// Phase-3b §17.2.3: визуальный дамп hip-кровли на L/T/U-формах.
//
// Сохраняет три PDF: L-shape с hip-крышей, T-shape с hip-крышей,
// U-shape с hip-крышей. На каждом плане кровли видны вальмовые рёбра
// (накосы) с конвексных углов и ендовы с reflex-углов.

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

Future<void> _dumpHip({
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
    name: '$name Hip Demo',
    constructionType: ConstructionType.privateHouse,
    createdAt: now,
    updatedAt: now,
    drawings: DrawingsCollection(drawings: drawings),
    brief: brief,
    walls: WallsDesign(material: 'aerated', thickness: 400, height: 2.8),
    roof: RoofDesign(
      type: 'hip',
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
  await File(filePath).writeAsBytes(bytes);
  // ignore: avoid_print
  print('Saved ${bytes.length} bytes to $filePath');
  expect(bytes.length, greaterThan(30000));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hip L-shape PDF в /tmp/hip_lshape.pdf', () async {
    await _dumpHip(
      footprint: BuildingFootprint.lShape(
        width: 10,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      ),
      name: 'L',
      filePath: '/tmp/hip_lshape.pdf',
    );
  });

  test('hip T-shape PDF в /tmp/hip_tshape.pdf', () async {
    await _dumpHip(
      footprint: BuildingFootprint.tShape(
        width: 12,
        height: 10,
        stemWidth: 4,
        stemHeight: 4,
      ),
      name: 'T',
      filePath: '/tmp/hip_tshape.pdf',
    );
  });

  test('hip U-shape PDF в /tmp/hip_ushape.pdf', () async {
    await _dumpHip(
      footprint: BuildingFootprint.uShape(
        width: 12,
        height: 10,
        cutWidth: 4,
        cutHeight: 4,
      ),
      name: 'U',
      filePath: '/tmp/hip_ushape.pdf',
    );
  });
}
