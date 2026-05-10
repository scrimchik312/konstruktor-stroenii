import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:construction_calculator/services/pdf_builder.dart';
import 'package:construction_calculator/services/floor_plan_generator.dart';
import 'package:construction_calculator/models/house_project.dart';
import 'package:construction_calculator/models/client_brief.dart';
import 'package:construction_calculator/models/foundation.dart';
import 'package:construction_calculator/models/foundation_design.dart';
import 'package:construction_calculator/models/walls_design.dart';
import 'package:construction_calculator/models/roof_design.dart';
import 'package:construction_calculator/models/staircase_design.dart';
import 'package:construction_calculator/models/drawing.dart';
import 'package:construction_calculator/models/drawings_collection.dart';
import 'package:construction_calculator/models/construction_type.dart';
import 'package:construction_calculator/data/wall_materials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('dump full PDF for v64-fix review', () async {
    final brief = ClientBrief(
      snowZone: 4,
      windZone: 'II',
      footprintWidth: 12,
      footprintLength: 9,
      floors: 1,
      hasBasement: true,
      hasGarage: true,
      hasStaircase: true,
      hasTerrace: true,
      hasMansard: false,
      wallMaterial: WallMaterial.aerated,
      garageSpec: AttachmentSpec.defaultGarage(WallMaterial.aerated),
      terraceSpec: AttachmentSpec.defaultTerrace(),
    );

    final plans = FloorPlanGenerator.generate(brief);
    final drawings = <Drawing>[];
    final now = DateTime.now();
    for (var i = 0; i < plans.length; i++) {
      drawings.add(Drawing(
        id: 'd$i',
        title: '${plans[i].floorLabel} — план',
        kind: DrawingKind.schematicPlan,
        createdAt: now,
        payload: plans[i].encode(),
      ));
    }

    final project = HouseProject(
      id: 'p1',
      name: 'Тестовый дом',
      constructionType: ConstructionType.privateHouse,
      createdAt: now,
      updatedAt: now,
      drawings: DrawingsCollection(drawings: drawings),
      brief: brief,
      walls: WallsDesign(material: 'aerated', thickness: 400, height: 2.8),
      roof: RoofDesign(type: 'gable', slopeAngle: 30, roofingMaterial: 'metal_tile'),
      foundation: FoundationDesign(type: FoundationType.strip),
      staircase: StaircaseDesign(floorHeight: 2.8),
    );

    final bytes = await PdfBuilder.buildBatch(
      project: project,
      drawings: drawings,
      versionNumber: 1,
    );
    final out = File('/tmp/full_plan.pdf');
    await out.writeAsBytes(bytes);
    print('Saved ${bytes.length} bytes to ${out.path}');
  });
}
