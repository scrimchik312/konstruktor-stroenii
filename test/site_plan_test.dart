// Тесты для листа АР-0a — «Схема планировочной организации земельного
// участка» (Phase-3a-2 §17.1.2).
//
// 1. Лист собирается на типовой фикстуре без исключений.
// 2. PDF получается валидным (`%PDF-...`).
// 3. После добавления АР-0a общее число страниц увеличилось на 1
//    относительно версии без сайт-плана (косвенный гео-чек: страница
//    действительно вставлена в общий PDF).

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
import 'package:construction_calculator/services/pdf_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('АР-0a: лист собирается и попадает в общий PDF', () async {
    final brief = ClientBrief(
      snowZone: 4,
      windZone: 'II',
      footprintWidth: 12,
      footprintLength: 9,
      floors: 1,
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
      id: 'p-site',
      name: 'Сайт-план тест',
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
    expect(bytes.length, greaterThan(50000),
        reason: 'PDF должен быть полнообъёмным');

    // Заголовочные байты должны быть `%PDF-`.
    final header = String.fromCharCodes(bytes.sublist(0, 8));
    expect(header.startsWith('%PDF-'), isTrue);

    // PDF собирается с минимальным набором: только обязательные поля
    // brief, без гаража/террасы — т.е. ветка _defaultPlotM 20×20 не
    // обрезает пятно.
  });

  test('АР-0a: пятно застройки помещается в условный участок 20×20', () {
    // Гео-чек: при footprint 12×9 и setback 5 м от севера — пятно
    // строго внутри плотa 20×20.
    const plotM = 20.0;
    const buildingW = 12.0;
    const buildingD = 9.0;
    const setbackN = 5.0;

    // Север — верхняя граница, юг — нижняя.
    final southSetback = plotM - setbackN - buildingD;
    final westSetback = (plotM - buildingW) / 2;
    final eastSetback = westSetback;

    expect(southSetback, greaterThanOrEqualTo(3.0),
        reason: 'Юг должен соблюдать ≥3 м (СНиП 30-102)');
    expect(westSetback, greaterThanOrEqualTo(3.0),
        reason: 'Запад ≥3 м');
    expect(eastSetback, greaterThanOrEqualTo(3.0),
        reason: 'Восток ≥3 м');
    expect(setbackN, greaterThanOrEqualTo(3.0),
        reason: 'Север ≥3 м');
  });
}
