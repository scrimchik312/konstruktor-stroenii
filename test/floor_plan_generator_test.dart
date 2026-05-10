// Тест трёх инвариантов FloorPlanGenerator:
//   1. На каждом этаже строго один объект с лейблом «Коридор».
//   2. Per-floor схема планировки — `floorSchemes` имеет приоритет над
//      базовой `layoutScheme`.
//   3. Все жилые/служебные помещения должны быть достижимы из «корня»
//      (входной/лестничной зоны) — у каждой такой комнаты есть хотя бы
//      одна дверь/проход.

import 'package:flutter_test/flutter_test.dart';

import 'package:construction_calculator/data/wall_materials.dart';
import 'package:construction_calculator/models/client_brief.dart';
import 'package:construction_calculator/models/floor_plan.dart';
import 'package:construction_calculator/models/layout_scheme.dart';
import 'package:construction_calculator/services/floor_plan_generator.dart';

void main() {
  test('п.1 — один Коридор на этаж в коридорной схеме', () {
    final brief = ClientBrief(
      floors: 2,
      footprintWidth: 12,
      footprintLength: 9,
      rooms: {
        'bedroom': 3,
        'bathroom': 2,
        'kitchen': 1,
        'livingRoom': 1,
      },
      layoutScheme: LayoutScheme.corridor,
    );
    final plans = FloorPlanGenerator.generate(brief);
    expect(plans.length, 2);
    for (final plan in plans) {
      final corridors =
          plan.rooms.where((r) => r.label == 'Коридор').toList();
      expect(
        corridors.length,
        equals(1),
        reason:
            '${plan.floorLabel}: ожидался ровно 1 «Коридор», нашлось '
            '${corridors.length}: '
            '${plan.rooms.map((r) => r.label).join(", ")}',
      );
    }
  });

  test('п.2 — floorSchemes переопределяет схему конкретного этажа', () {
    final brief = ClientBrief(
      floors: 2,
      footprintWidth: 12,
      footprintLength: 9,
      rooms: {
        'bedroom': 3,
        'bathroom': 2,
        'kitchen': 1,
        'livingRoom': 1,
      },
      // Базовая схема — коридорная.
      layoutScheme: LayoutScheme.corridor,
      // На 2-м этаже — анфиладная.
      floorSchemes: {
        '2': LayoutScheme.enfilade.name,
      },
    );
    final plans = FloorPlanGenerator.generate(brief);
    expect(plans.length, 2);
    // 1-й этаж — должен быть «Коридор» (коридорная схема).
    final firstCorridors =
        plans[0].rooms.where((r) => r.label == 'Коридор').toList();
    expect(
      firstCorridors.length,
      equals(1),
      reason: '1-й этаж: ожидался Коридор',
    );
    // 2-й этаж — анфиладная схема не использует «Коридор» как имя
    // (свободные зоны там называются «Прихожая / коридор» или
    // «Холл лестницы»).
    final secondExactCorridors =
        plans[1].rooms.where((r) => r.label == 'Коридор').toList();
    expect(
      secondExactCorridors.isEmpty,
      isTrue,
      reason: '2-й этаж в анфиладной схеме не должен иметь «Коридор», '
          'найдено: ${plans[1].rooms.map((r) => r.label).join(", ")}',
    );
  });

  test('п.3 — каждая комната достижима (BFS reachability)', () {
    final brief = ClientBrief(
      floors: 2,
      footprintWidth: 12,
      footprintLength: 9,
      rooms: {
        'bedroom': 3,
        'bathroom': 2,
        'kitchen': 1,
        'livingRoom': 1,
        'study': 1,
        'storage': 1,
      },
      layoutScheme: LayoutScheme.corridor,
    );
    final plans = FloorPlanGenerator.generate(brief);
    for (final plan in plans) {
      // Граф смежности: для каждой комнаты — соседи через дверь/архивольт.
      final n = plan.rooms.length;
      final adj = List<Set<int>>.generate(n, (_) => <int>{});
      for (final o in plan.openings) {
        if (o.kind != OpeningKind.door && o.kind != OpeningKind.archway) {
          continue;
        }
        final on = <int>[];
        for (var i = 0; i < n; i++) {
          if (_openingOnRoomWall(o, plan.rooms[i])) on.add(i);
        }
        for (var i = 0; i < on.length; i++) {
          for (var j = i + 1; j < on.length; j++) {
            adj[on[i]].add(on[j]);
            adj[on[j]].add(on[i]);
          }
        }
      }
      // Корни.
      final roots = <int>{};
      for (var i = 0; i < n; i++) {
        final r = plan.rooms[i];
        if (r.kind != PlanRoomKind.free) continue;
        if (_hasOuterWall(r, plan.width, plan.height)) roots.add(i);
      }
      for (var i = 0; i < n; i++) {
        if (plan.rooms[i].kind != PlanRoomKind.staircase) continue;
        for (var j = 0; j < n; j++) {
          if (i == j) continue;
          if (plan.rooms[j].kind != PlanRoomKind.free) continue;
          if (_share(plan.rooms[i], plan.rooms[j]) > 1.3) roots.add(j);
        }
      }
      // BFS.
      final reached = <int>{...roots};
      final queue = <int>[...roots];
      while (queue.isNotEmpty) {
        final cur = queue.removeLast();
        for (final nb in adj[cur]) {
          if (reached.add(nb)) queue.add(nb);
        }
      }
      // Каждая жилая/служебная комната должна быть достигнута.
      for (var i = 0; i < n; i++) {
        final r = plan.rooms[i];
        if (r.kind == PlanRoomKind.free) continue;
        if (r.kind == PlanRoomKind.staircase) continue;
        expect(
          reached.contains(i),
          isTrue,
          reason: '${plan.floorLabel}: комната «${r.label}» '
              'не достижима из корня',
        );
      }
    }
  });

  test('п.6 v44 — санузел ≤ 15 м² на больших площадях', () {
    // Большое пятно — даже при scale > 1 ни один санузел не должен
    // быть больше 15 м² (требование пользователя).
    final brief = ClientBrief(
      floors: 1,
      footprintWidth: 20,
      footprintLength: 16,
      rooms: {
        'bathroom': 1,
        'bedroom': 1,
        'kitchen': 1,
        'livingRoom': 1,
      },
      layoutScheme: LayoutScheme.corridor,
    );
    final plans = FloorPlanGenerator.generate(brief);
    expect(plans.length, 1);
    final baths = plans.first.rooms.where(
      (r) => r.roomKindName == 'bathroom',
    );
    expect(baths.isNotEmpty, isTrue);
    for (final b in baths) {
      expect(
        b.area,
        lessThanOrEqualTo(15.01),
        reason:
            'Санузел не должен превышать 15 м² '
            '(нашли ${b.area.toStringAsFixed(1)} м²)',
      );
    }
  });

  test('п.6 v44 — один Коридор на этаж даже на больших площадях', () {
    final brief = ClientBrief(
      floors: 1,
      footprintWidth: 24,
      footprintLength: 18,
      rooms: {
        'bedroom': 4,
        'bathroom': 2,
        'kitchen': 1,
        'livingRoom': 1,
        'study': 1,
        'storage': 2,
      },
      layoutScheme: LayoutScheme.corridor,
    );
    final plans = FloorPlanGenerator.generate(brief);
    final corridors =
        plans.first.rooms.where((r) => r.label == 'Коридор').toList();
    expect(
      corridors.length,
      lessThanOrEqualTo(1),
      reason: 'Большая площадь не должна порождать несколько коридоров; '
          'нашли: ${corridors.length}',
    );
  });

  test('п.11 — дверь в санузел не по центру (off-center)', () {
    final brief = ClientBrief(
      floors: 1,
      footprintWidth: 12,
      footprintLength: 9,
      rooms: {
        'bedroom': 2,
        'bathroom': 1,
        'kitchen': 1,
        'livingRoom': 1,
      },
      layoutScheme: LayoutScheme.corridor,
    );
    final plan = FloorPlanGenerator.generate(brief).first;
    final bath = plan.rooms.firstWhere(
      (r) => r.roomKindName == 'bathroom',
    );
    // Найдём дверь, ведущую в санузел.
    PlanOpening? bathDoor;
    for (final o in plan.openings) {
      if (o.kind != OpeningKind.door) continue;
      if (_openingOnRoomWall(o, bath)) {
        bathDoor = o;
        break;
      }
    }
    expect(bathDoor, isNotNull,
        reason: 'У санузла должна быть хотя бы одна дверь');
    final isHorizontal =
        bathDoor!.side == WallSide.top || bathDoor.side == WallSide.bottom;
    final mid = isHorizontal
        ? bath.x + bath.width / 2
        : bath.y + bath.height / 2;
    final doorMid = isHorizontal
        ? bathDoor.x + bathDoor.length / 2
        : bathDoor.y + bathDoor.length / 2;
    final wallLen = isHorizontal ? bath.width : bath.height;
    // Дверь не должна стоять слишком близко к центру стены —
    // отступ от центра ≥ 10 % длины стены.
    expect(
      (doorMid - mid).abs(),
      greaterThanOrEqualTo(wallLen * 0.10 - 0.05),
      reason:
          'Дверь санузла должна быть смещена от центра — '
          'центр стены ${mid.toStringAsFixed(2)} м, центр двери '
          '${doorMid.toStringAsFixed(2)} м, длина стены '
          '${wallLen.toStringAsFixed(2)} м',
    );
  });

  test('п.12 — каркас: координаты слайсов кратны 0.6 м', () {
    final brief = ClientBrief(
      floors: 1,
      footprintWidth: 12,
      footprintLength: 9,
      rooms: {
        'bedroom': 2,
        'bathroom': 1,
        'kitchen': 1,
        'livingRoom': 1,
      },
      layoutScheme: LayoutScheme.corridor,
      wallMaterial: WallMaterial.frame,
    );
    final plan = FloorPlanGenerator.generate(brief).first;
    const eps = 0.06;
    for (final r in plan.rooms) {
      // Лестницу не снэппим — её фиксированный размер.
      if (r.kind == PlanRoomKind.staircase) continue;
      // Координаты должны быть близки к кратному 0.6 м (с учётом
      // фиксации внешнего контура).
      for (final v in [r.x, r.y, r.x + r.width, r.y + r.height]) {
        final n = (v / 0.6).round();
        final s = n * 0.6;
        // Допуск: либо строго на сетке 0.6, либо совпадает с
        // фиксированной координатой контура (planW/planH).
        final onContour = v.abs() < eps ||
            (v - plan.width).abs() < eps ||
            (v - plan.height).abs() < eps;
        expect(
          (v - s).abs() < eps || onContour,
          isTrue,
          reason:
              'Координата ${v.toStringAsFixed(3)} м не на каркасной '
              'сетке 0.6 м (комната «${r.label}»)',
        );
      }
    }
  });

  test('п.13 — гостиная — лист графа путей (≤1 связь с коридором)', () {
    final brief = ClientBrief(
      floors: 1,
      footprintWidth: 14,
      footprintLength: 10,
      rooms: {
        'bedroom': 2,
        'bathroom': 1,
        'kitchen': 1,
        'livingRoom': 1,
        'study': 1,
      },
      layoutScheme: LayoutScheme.corridor,
    );
    final plan = FloorPlanGenerator.generate(brief).first;
    final living = plan.rooms.firstWhere(
      (r) => r.roomKindName == 'livingRoom',
    );
    var corridorDoors = 0;
    for (final o in plan.openings) {
      if (o.kind != OpeningKind.door && o.kind != OpeningKind.archway) {
        continue;
      }
      if (!_openingOnRoomWall(o, living)) continue;
      // Считаем только проёмы в свободные зоны (коридор/прихожая).
      var inFree = false;
      for (final r in plan.rooms) {
        if (r.label == living.label && r.x == living.x && r.y == living.y) {
          continue;
        }
        if (r.kind != PlanRoomKind.free) continue;
        if (_openingOnRoomWall(o, r)) {
          inFree = true;
          break;
        }
      }
      if (inFree) corridorDoors++;
    }
    expect(
      corridorDoors,
      lessThanOrEqualTo(1),
      reason:
          'Гостиная — лист графа путей: должна иметь не более 1 двери в '
          'коридор/прихожую (нашли $corridorDoors)',
    );
  });

  test('п.14 — терраса: внешняя дверь из гостиной', () {
    final brief = ClientBrief(
      floors: 1,
      footprintWidth: 12,
      footprintLength: 9,
      rooms: {
        'bedroom': 2,
        'bathroom': 1,
        'kitchen': 1,
        'livingRoom': 1,
      },
      layoutScheme: LayoutScheme.corridor,
      hasTerrace: true,
    );
    final plan = FloorPlanGenerator.generate(brief).first;
    final living = plan.rooms.firstWhere(
      (r) => r.roomKindName == 'livingRoom',
    );
    var hasTerraceDoor = false;
    for (final o in plan.openings) {
      if (o.kind != OpeningKind.externalDoor) continue;
      if (_openingOnRoomWall(o, living)) {
        hasTerraceDoor = true;
        break;
      }
    }
    expect(
      hasTerraceDoor,
      isTrue,
      reason: 'При hasTerrace=true у гостиной должна быть наружная дверь '
          '(второй вход с участка)',
    );
  });

  test('п.15 — кухня и гостиная имеют общую стену', () {
    final brief = ClientBrief(
      floors: 1,
      footprintWidth: 12,
      footprintLength: 9,
      rooms: {
        'bedroom': 2,
        'bathroom': 1,
        'kitchen': 1,
        'livingRoom': 1,
      },
      layoutScheme: LayoutScheme.corridor,
    );
    final plan = FloorPlanGenerator.generate(brief).first;
    final kitchen = plan.rooms.firstWhere(
      (r) => r.roomKindName == 'kitchen',
    );
    final living = plan.rooms.firstWhere(
      (r) => r.roomKindName == 'livingRoom',
    );
    final shared = _share(kitchen, living);
    expect(
      shared,
      greaterThanOrEqualTo(1.4),
      reason:
          'Кухня и гостиная должны иметь общую стену ≥ 1.4 м '
          '(найдено ${shared.toStringAsFixed(2)} м)',
    );
  });

  test('п.16 — гардеробная рядом со спальней', () {
    final brief = ClientBrief(
      floors: 1,
      footprintWidth: 14,
      footprintLength: 10,
      rooms: {
        'bedroom': 2,
        'bathroom': 1,
        'kitchen': 1,
        'livingRoom': 1,
        'wardrobe': 1,
      },
      layoutScheme: LayoutScheme.corridor,
    );
    final plan = FloorPlanGenerator.generate(brief).first;
    final wardrobes = plan.rooms.where(
      (r) => r.roomKindName == 'wardrobe',
    );
    expect(
      wardrobes.isNotEmpty,
      isTrue,
      reason: 'В плане должна быть хотя бы одна гардеробная',
    );
    for (final w in wardrobes) {
      var nearBedroom = false;
      for (final r in plan.rooms) {
        if (r.roomKindName != 'bedroom') continue;
        if (_share(w, r) >= 1.4) {
          nearBedroom = true;
          break;
        }
      }
      expect(
        nearBedroom,
        isTrue,
        reason:
            'Гардеробная «${w.label}» должна примыкать к спальне '
            '(общая стена ≥ 1.4 м)',
      );
    }
  });
}

bool _openingOnRoomWall(PlanOpening o, PlanRoom r) {
  const eps = 0.01;
  if (o.side == WallSide.top || o.side == WallSide.bottom) {
    final onTop = (o.y - r.y).abs() < eps;
    final onBottom = (o.y - (r.y + r.height)).abs() < eps;
    if (!onTop && !onBottom) return false;
    return o.x >= r.x - eps && o.x + o.length <= r.x + r.width + eps;
  }
  final onLeft = (o.x - r.x).abs() < eps;
  final onRight = (o.x - (r.x + r.width)).abs() < eps;
  if (!onLeft && !onRight) return false;
  return o.y >= r.y - eps && o.y + o.length <= r.y + r.height + eps;
}

bool _hasOuterWall(PlanRoom r, double w, double h) {
  const eps = 0.01;
  return r.x <= eps ||
      r.y <= eps ||
      (r.x + r.width) >= w - eps ||
      (r.y + r.height) >= h - eps;
}

double _share(PlanRoom a, PlanRoom b) {
  const eps = 0.01;
  // Вертикальная общая стена.
  final aRight = a.x + a.width;
  final bRight = b.x + b.width;
  if ((aRight - b.x).abs() < eps || (bRight - a.x).abs() < eps) {
    final lo = a.y > b.y ? a.y : b.y;
    final hi = (a.y + a.height) < (b.y + b.height)
        ? a.y + a.height
        : b.y + b.height;
    return hi > lo ? hi - lo : 0.0;
  }
  // Горизонтальная.
  final aBottom = a.y + a.height;
  final bBottom = b.y + b.height;
  if ((aBottom - b.y).abs() < eps || (bBottom - a.y).abs() < eps) {
    final lo = a.x > b.x ? a.x : b.x;
    final hi = (a.x + a.width) < (b.x + b.width)
        ? a.x + a.width
        : b.x + b.width;
    return hi > lo ? hi - lo : 0.0;
  }
  return 0.0;
}
