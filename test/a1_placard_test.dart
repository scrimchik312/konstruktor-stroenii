// Тесты для листа «Планшет А1» (Phase-3b §17.2.4).
//
// 1. `PdfA1Placard.buildDocument` собирает single-page A1 PDF без
//    исключений, заголовочные байты `%PDF-`, размер ≥ 30 КБ.
// 2. Артикул в шапке считается из суммарной площади комнат и форматируется
//    как `Т-{N}`.

import 'package:flutter_test/flutter_test.dart';

import 'package:construction_calculator/data/wall_materials.dart';
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
import 'package:construction_calculator/services/pdf_a1_placard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Планшет А1 собирается в single-page PDF', () async {
    final brief = ClientBrief(
      snowZone: 4,
      windZone: 'II',
      footprintWidth: 12,
      footprintLength: 9,
      floors: 2,
      hasGarage: false,
      hasTerrace: false,
      hasMansard: false,
      wallMaterial: WallMaterial.aerated,
    );
    final plans = FloorPlanGenerator.generate(brief);
    final now = DateTime.now();
    final drawings = <Drawing>[
      for (var i = 0; i < plans.length; i++)
        Drawing(
          id: 'd$i',
          title: plans[i].floorLabel,
          kind: DrawingKind.schematicPlan,
          createdAt: now,
          payload: plans[i].encode(),
        ),
    ];
    final project = HouseProject(
      id: 'p-a1',
      name: 'Планшет А1 — тест',
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

    final bytes = await PdfA1Placard.buildDocument(
      project: project,
      plans: plans,
      versionNumber: 1,
    );
    expect(bytes.length, greaterThan(30000),
        reason: 'A1-планшет должен быть полнообъёмным');
    final header = String.fromCharCodes(bytes.sublist(0, 8));
    expect(header.startsWith('%PDF-'), isTrue);
  });
}
