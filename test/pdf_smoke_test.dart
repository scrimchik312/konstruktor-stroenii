// Smoke-тест: PdfBuilder корректно собирает PDF из синтетического плана
// без бросков исключений (типовая ловушка — кириллица + дуги дверей).
//
// Если установлена переменная окружения CC_DUMP_SAMPLE_PDF=1 — итоговый
// файл также пишется в /tmp/sample_plan.pdf для визуальной проверки.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:construction_calculator/models/client_brief.dart';
import 'package:construction_calculator/models/construction_type.dart';
import 'package:construction_calculator/models/drawing.dart';
import 'package:construction_calculator/models/drawings_collection.dart';
import 'package:construction_calculator/models/floor_plan.dart';
import 'package:construction_calculator/models/house_project.dart';
import 'package:construction_calculator/models/roof_design.dart';
import 'package:construction_calculator/services/pdf_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('PdfBuilder produces a non-empty PDF for a sample plan', () async {

    const plan = FloorPlan(
      floorLabel: 'Этаж 1',
      width: 12,
      height: 9,
      rooms: [
        // Прихожая
        PlanRoom(
          label: 'Прихожая',
          x: 0,
          y: 0,
          width: 3,
          height: 1.4,
          area: 4.2,
          kind: PlanRoomKind.free,
          roomKindName: 'hallway',
        ),
        // Коридор
        PlanRoom(
          label: 'Коридор',
          x: 3,
          y: 0,
          width: 9,
          height: 1.4,
          area: 12.6,
          kind: PlanRoomKind.free,
        ),
        // Гостиная
        PlanRoom(
          label: 'Гостиная',
          x: 0,
          y: 1.4,
          width: 7,
          height: 5,
          area: 35,
          roomKindName: 'livingRoom',
        ),
        // Кухня
        PlanRoom(
          label: 'Кухня',
          x: 7,
          y: 1.4,
          width: 5,
          height: 3,
          area: 15,
          roomKindName: 'kitchen',
        ),
        // Спальня
        PlanRoom(
          label: 'Спальня',
          x: 7,
          y: 4.4,
          width: 5,
          height: 2,
          area: 10,
          roomKindName: 'bedroom',
        ),
        // Санузел
        PlanRoom(
          label: 'Санузел',
          x: 0,
          y: 6.4,
          width: 3,
          height: 2.6,
          area: 7.8,
          roomKindName: 'bathroom',
        ),
        // Лестница
        PlanRoom(
          label: 'Лестница',
          x: 3,
          y: 6.4,
          width: 3,
          height: 2.6,
          area: 7.8,
          kind: PlanRoomKind.staircase,
        ),
        // Свободная зона
        PlanRoom(
          label: 'Свободная зона',
          x: 6,
          y: 6.4,
          width: 6,
          height: 2.6,
          area: 15.6,
          kind: PlanRoomKind.free,
        ),
      ],
      openings: [
        // Входная дверь со стороны улицы.
        PlanOpening(
          kind: OpeningKind.externalDoor,
          side: WallSide.top,
          x: 0.8,
          y: 0,
          length: 0.95,
        ),
        // Окно гостиной.
        PlanOpening(
          kind: OpeningKind.window,
          side: WallSide.left,
          x: 0,
          y: 3,
          length: 1.8,
        ),
        // Окно кухни.
        PlanOpening(
          kind: OpeningKind.window,
          side: WallSide.right,
          x: 12,
          y: 2,
          length: 1.5,
        ),
        // Окно спальни.
        PlanOpening(
          kind: OpeningKind.window,
          side: WallSide.right,
          x: 12,
          y: 4.8,
          length: 1.5,
        ),
        // Окно санузла.
        PlanOpening(
          kind: OpeningKind.window,
          side: WallSide.left,
          x: 0,
          y: 7.4,
          length: 0.6,
        ),
        // Дверь гостиной из коридора.
        PlanOpening(
          kind: OpeningKind.door,
          side: WallSide.top,
          x: 4,
          y: 1.4,
          length: 0.9,
        ),
        // Дверь кухни.
        PlanOpening(
          kind: OpeningKind.door,
          side: WallSide.top,
          x: 8,
          y: 1.4,
          length: 0.9,
        ),
        // Дверь спальни.
        PlanOpening(
          kind: OpeningKind.door,
          side: WallSide.left,
          x: 7,
          y: 5,
          length: 0.9,
        ),
        // Дверь санузла.
        PlanOpening(
          kind: OpeningKind.door,
          side: WallSide.top,
          x: 1,
          y: 6.4,
          length: 0.7,
        ),
        // Окно санузла (ещё одно) — с южной стороны.
        PlanOpening(
          kind: OpeningKind.window,
          side: WallSide.bottom,
          x: 0.6,
          y: 9,
          length: 0.6,
        ),
        // Окно «свободной зоны» — с южной стороны.
        PlanOpening(
          kind: OpeningKind.window,
          side: WallSide.bottom,
          x: 7,
          y: 9,
          length: 1.5,
        ),
        // Открытый проход в свободную зону.
        PlanOpening(
          kind: OpeningKind.archway,
          side: WallSide.left,
          x: 6,
          y: 7.4,
          length: 1.6,
        ),
      ],
      attachments: [
        // Крыльцо у входной двери (со стороны ул., side=top).
        PlanAttachment(
          kind: PlanAttachmentKind.porch,
          label: 'Крыльцо',
          x: 0.5,
          y: -1.0,
          width: 1.55,
          height: 1.0,
        ),
        // Терраса у гостиной на левой стене.
        PlanAttachment(
          kind: PlanAttachmentKind.terrace,
          label: 'Терраса',
          x: -2.0,
          y: 2.5,
          width: 2.0,
          height: 3.0,
        ),
      ],
    );

    final now = DateTime.now();
    final drawing = Drawing(
      id: 'd1',
      title: 'Схематический план — 1 этаж',
      kind: DrawingKind.schematicPlan,
      createdAt: now,
      payload: plan.encode(),
    );
    final project = HouseProject(
      id: 'p1',
      name: 'Тестовый дом',
      constructionType: ConstructionType.privateHouse,
      createdAt: now,
      updatedAt: now,
      drawings: DrawingsCollection(drawings: [drawing]),
      brief: ClientBrief(
        snowZone: 4,
        windZone: 'II',
        footprintWidth: 12,
        footprintLength: 9,
        floors: 1,
      ),
      roof: RoofDesign(
        type: 'gable',
        slopeAngle: 30,
        roofingMaterial: 'metal_tile',
      ),
    );

    final bytes = await PdfBuilder.buildBatch(
      project: project,
      drawings: [drawing],
      versionNumber: 1,
    );
    expect(bytes, isNotEmpty);
    expect(bytes.length, greaterThan(2000));

    if (Platform.environment['CC_DUMP_SAMPLE_PDF'] == '1') {
      final out = File('/tmp/sample_plan.pdf');
      await out.writeAsBytes(bytes);
      // ignore: avoid_print
      print('Saved sample PDF to ${out.path}');
    }
  });

  test('PdfBuilder produces АР-N+ roof plan sheet for hip / flat / shed', () async {
    const plan = FloorPlan(
      floorLabel: 'Этаж 1',
      width: 10,
      height: 8,
      rooms: [
        PlanRoom(
          label: 'Гостиная',
          x: 0,
          y: 0,
          width: 6,
          height: 4,
          area: 24,
          roomKindName: 'livingRoom',
        ),
        PlanRoom(
          label: 'Кухня',
          x: 6,
          y: 0,
          width: 4,
          height: 4,
          area: 16,
          roomKindName: 'kitchen',
        ),
        PlanRoom(
          label: 'Спальня',
          x: 0,
          y: 4,
          width: 5,
          height: 4,
          area: 20,
          roomKindName: 'bedroom',
        ),
        PlanRoom(
          label: 'Санузел',
          x: 5,
          y: 4,
          width: 5,
          height: 4,
          area: 20,
          roomKindName: 'bathroom',
        ),
      ],
    );
    final now = DateTime.now();
    final drawing = Drawing(
      id: 'd1',
      title: 'Схематический план — 1 этаж',
      kind: DrawingKind.schematicPlan,
      createdAt: now,
      payload: plan.encode(),
    );

    for (final type in ['hip', 'flat', 'shed', 'mansard']) {
      final project = HouseProject(
        id: 'p1',
        name: 'Тестовый дом ($type)',
        constructionType: ConstructionType.privateHouse,
        createdAt: now,
        updatedAt: now,
        drawings: DrawingsCollection(drawings: [drawing]),
        brief: ClientBrief(snowZone: 5, windZone: 'II'),
        roof: RoofDesign(
          type: type,
          slopeAngle: type == 'flat' ? 2 : 25,
          roofingMaterial: type == 'flat' ? 'membrane' : 'metal_tile',
        ),
      );
      final bytes = await PdfBuilder.buildBatch(
        project: project,
        drawings: [drawing],
        versionNumber: 1,
      );
      expect(bytes, isNotEmpty,
          reason: 'PDF should be generated for roof type $type');
      expect(bytes.length, greaterThan(2000),
          reason: 'PDF should be non-trivial for roof type $type');
    }
  });
}
