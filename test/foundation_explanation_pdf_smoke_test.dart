// Smoke-тест: FoundationExplanationPdf собирает ПЗ без падений на
// реальных данных из cc_engine. Кириллица + табличная вёрстка —
// типовое место ошибок при работе с pdf-пакетом.

import 'dart:io';

import 'package:cc_engine/cc_engine.dart';
import 'package:construction_calculator/models/construction_type.dart';
import 'package:construction_calculator/models/house_project.dart';
import 'package:construction_calculator/services/foundation_explanation_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FoundationExplanationPdf produces a non-empty PDF', () async {
    final project = HouseProject(
      id: 't1',
      name: 'Тестовый дом',
      constructionType: ConstructionType.privateHouse,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final loads = FoundationLoadsCalculator.compute(
      snowRegion: SnowRegion.byId(3),
      windRegion: WindRegion.byId(2),
      roofShape: RoofShape.gable,
      roofSlopeDegrees: 30,
      windTerrain: TerrainType.b,
      buildingHeight: 5,
      wallComponents: [PermanentLoadCalculator.defaults['walls_brick']!],
      floorComponents: [
        PermanentLoadCalculator.defaults['floor_timber_joists']!
      ],
      roofComponents: [PermanentLoadCalculator.defaults['roof_metal_tile']!],
      floors: 1,
    );

    final design = StripFootingDesigner.design(
      verticalLoadKnPerM2: loads.totalVerticalKnPerM2,
      footprintAreaM2: 80,
      loadBearingWallsPerimeterM: 44,
      soilType: FoundationSoilType.loamStiff,
      freezingDepthM: 1.4,
    );

    final bytes = await FoundationExplanationPdf.build(
      project: project,
      loads: loads,
      design: design,
      inputDataRows: const {
        'Объект': 'Тестовый дом',
        'Регион': 'Москва',
        'Грунт': 'Суглинок тугопластичный',
      },
    );

    expect(bytes, isNotEmpty);
    expect(bytes.length, greaterThan(2000));

    if (Platform.environment['CC_DUMP_SAMPLE_PDF'] == '1') {
      File('/tmp/sample_explanation.pdf').writeAsBytesSync(bytes);
    }
  });
}
