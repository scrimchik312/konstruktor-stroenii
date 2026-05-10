// Тесты валидатора достижимости (Phase-3b §17.2.3).

import 'package:flutter_test/flutter_test.dart';

import 'package:construction_calculator/data/wall_materials.dart';
import 'package:construction_calculator/models/client_brief.dart';
import 'package:construction_calculator/models/floor_plan.dart';
import 'package:construction_calculator/models/furniture_symbol.dart';
import 'package:construction_calculator/services/floor_plan_generator.dart';
import 'package:construction_calculator/services/furniture/reachability_validator.dart';

void main() {
  test('Стандартный план: валидатор отрабатывает без падений', () {
    // Базовый smoke-тест: даже если у плана нет externalDoor (на
    // компактных пятнах без entry-room генератор его не ставит),
    // валидатор должен корректно сформировать отчёт без исключений.
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
    final ground = plans.first;
    final report = ReachabilityValidator.validate(ground);
    expect(report.totalRooms, greaterThan(0));
    expect(report.gridStepM, 0.05);
    if (report.entrancesFound == 0) {
      expect(
        report.warnings.any((w) => w.contains('Входная дверь не найдена')),
        isTrue,
        reason: 'Если входной двери нет — должно быть предупреждение',
      );
    }
  });

  test('Шкаф, перекрывший узкий коридор, делает комнату недоступной', () {
    // Конструируем синтетический план: 6×6 м, две комнаты,
    // соединённые узким коридором 0.9 м. Ставим шкаф 1.0×1.0 м
    // прямо в коридоре → BFS не должен пройти.
    final entranceRoom = PlanRoom(
      label: '1. Прихожая',
      x: 0,
      y: 0,
      width: 3,
      height: 3,
      area: 9,
      kind: PlanRoomKind.room,
      roomKindName: 'hallway',
    );
    final blockedRoom = PlanRoom(
      label: '2. Комната',
      x: 4,
      y: 0,
      width: 2,
      height: 3,
      area: 6,
      kind: PlanRoomKind.room,
      roomKindName: 'bedroom',
      // Шкаф 1×1 м прямо у двери, перекрывает узкий проход.
      furniture: const [
        FurnitureSymbol(
          kind: FurnitureKind.wardrobe,
          x: 4.0,
          y: 0.5,
          width: 2.0,
          height: 2.0,
        ),
      ],
    );
    final plan = FloorPlan(
      floorLabel: '1 этаж',
      width: 6,
      height: 3,
      rooms: [entranceRoom, blockedRoom],
      openings: const [
        // Входная дверь по нижней стене прихожей.
        PlanOpening(
          kind: OpeningKind.externalDoor,
          side: WallSide.bottom,
          x: 1.0,
          y: 3.0,
          length: 0.9,
        ),
        // Межкомнатная дверь между прихожей и комнатой (узкий проём).
        PlanOpening(
          kind: OpeningKind.door,
          side: WallSide.right,
          x: 3.0,
          y: 1.0,
          length: 0.9,
        ),
      ],
    );

    final report = ReachabilityValidator.validate(plan);
    expect(report.entrancesFound, 1);
    expect(
      report.unreachableRoomLabels.contains('2. Комната'),
      isTrue,
      reason: 'Шкаф 2×2 м перекрывает узкий проём — комната должна '
          'считаться недостижимой',
    );
  });
}
