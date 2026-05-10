/// Генератор планировки — размещает комнаты на прямоугольном пятне застройки
/// с центральным коридором для свободного перемещения.
library;

import 'dart:math' as math;
import '../../data/house_layout/planning_rules.dart';
import '../../models/house_layout/house_config.dart';

class PlacedRoom {
  final String kind;
  final String label;
  final double x, y, w, h;
  final int floor;
  final HouseZone zone;
  final bool hasWindow;
  final String? flooringId;
  final String? wallFinishId;

  const PlacedRoom({
    required this.kind,
    required this.label,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.floor,
    required this.zone,
    this.hasWindow = true,
    this.flooringId,
    this.wallFinishId,
  });

  double get area => w * h;
  double get cx => x + w / 2;
  double get cy => y + h / 2;
  double get right => x + w;
  double get bottom => y + h;
}

class DoorPlacement {
  final double x, y;
  final bool horizontal;
  final double widthM;
  final String roomA, roomB;
  const DoorPlacement({required this.x, required this.y, required this.horizontal, this.widthM = 0.8, required this.roomA, required this.roomB});
}

class WindowPlacement {
  final double x, y;
  final bool horizontal;
  final double widthM;
  final String room;
  final String side;
  const WindowPlacement({required this.x, required this.y, required this.horizontal, this.widthM = 1.2, required this.room, required this.side});
}

class StaircasePlacement {
  final double x, y, w, h;
  final int fromFloor, toFloor;
  const StaircasePlacement({required this.x, required this.y, required this.w, required this.h, required this.fromFloor, required this.toFloor});
}

class FloorPlan {
  final int floor;
  final double width, height;
  final List<PlacedRoom> rooms;
  final List<DoorPlacement> doors;
  final List<WindowPlacement> windows;
  final StaircasePlacement? staircase;
  final double wallThicknessMm;

  const FloorPlan({
    required this.floor,
    required this.width,
    required this.height,
    required this.rooms,
    required this.doors,
    required this.windows,
    this.staircase,
    this.wallThicknessMm = 400,
  });
}

class GeneratedLayout {
  final HouseLayoutConfig config;
  final List<FloorPlan> floorPlans;
  const GeneratedLayout({required this.config, required this.floorPlans});
}

// ---------------------------------------------------------------------------
// Правила коридоров и проходов (из типовых планировок)
// ---------------------------------------------------------------------------
// 1. Минимальная ширина коридора: 1.2 м (СП/IRC), рекомендуемая: 1.4 м
// 2. 1 этаж: прихожая у входа → коридор вдоль оси дома → комнаты по бокам
// 3. 2 этаж: холл/площадка у лестницы → коридор → спальни по бокам
// 4. Коридор обеспечивает независимый доступ ко всем комнатам
// 5. Мокрые зоны (кухня, санузел, котельная) группируются у одного стояка
// 6. Спальни — только на внешних стенах (окна обязательны)
// 7. Хоз. помещения (кладовая, котельная) могут быть без окон

const _corridorWidth = 1.4; // м
const _hallwayDepth = 2.5; // глубина прихожей от входа

// ---------------------------------------------------------------------------
// Генератор
// ---------------------------------------------------------------------------

class LayoutGenerator {
  const LayoutGenerator();

  GeneratedLayout generate(HouseLayoutConfig config) {
    final fpW = config.footprintWidth ?? 10;
    final fpL = config.footprintLength ?? 12;
    final floors = config.floors + (config.hasMansard ? 1 : 0);
    final wallT = (config.wallThicknessMm ?? 400) / 1000;
    final area = config.totalArea ?? (fpW * fpL * floors);
    final catRules = kCategoryRules[houseSizeCategory(area)];
    final styleKey = config.style.name;
    final styleRules = kStyleRules[styleKey];

    final roomsByFloor = _distributeRooms(config.rooms, floors);
    final floorPlans = <FloorPlan>[];
    final hasMultiFloors = floors > 1;

    for (var f = 0; f < floors; f++) {
      final floorRooms = roomsByFloor[f] ?? {};
      final isFirstFloor = f == 0;
      final placed = _placeRoomsWithCorridor(
        floorRooms, fpW, fpL, wallT, f + 1,
        isFirstFloor: isFirstFloor,
        hasStaircase: hasMultiFloors && f < floors - 1,
        catRules: catRules,
        styleRules: styleRules,
      );

      final doors = _placeDoors(placed, isFirstFloor, fpL, wallT);
      final windows = _placeWindows(placed, fpW, fpL, wallT);

      StaircasePlacement? staircase;
      if (hasMultiFloors && f < floors - 1) {
        staircase = _placeStaircase(placed, fpW, fpL, wallT, f + 1, config.staircaseType);
      }

      floorPlans.add(FloorPlan(
        floor: f + 1, width: fpW, height: fpL,
        rooms: placed, doors: doors, windows: windows,
        staircase: staircase,
        wallThicknessMm: config.wallThicknessMm ?? 400,
      ));
    }

    return GeneratedLayout(config: config, floorPlans: floorPlans);
  }

  // ─── Распределение комнат по этажам ─────────────────────────────────────

  Map<int, Map<String, int>> _distributeRooms(Map<String, int> rooms, int floors) {
    final result = <int, Map<String, int>>{};
    for (var i = 0; i < floors; i++) {
      result[i] = {};
    }

    const firstFloorOnly = {'kitchen', 'kitchenDining', 'livingRoom', 'dining',
      'hallway', 'boilerRoom', 'garage', 'toilet', 'pantry', 'laundry', 'technical'};
    const upperFloorOnly = {'bedroom', 'masterBedroom', 'kidsRoom',
      'masterBathroom', 'wardrobe', 'study', 'balcony'};

    for (final e in rooms.entries) {
      if (floors == 1) {
        result[0]![e.key] = e.value;
      } else if (firstFloorOnly.contains(e.key)) {
        result[0]![e.key] = e.value;
      } else if (upperFloorOnly.contains(e.key)) {
        result[1]![e.key] = e.value;
      } else if (e.key == 'bathroom') {
        for (var f = 0; f < floors; f++) {
          result[f]![e.key] = 1;
        }
      } else if (e.key == 'storage') {
        result[0]![e.key] = e.value;
      } else {
        result[0]![e.key] = e.value;
      }
    }

    return result;
  }

  // ─── Размещение комнат с центральным коридором ─────────────────────────

  List<PlacedRoom> _placeRoomsWithCorridor(
    Map<String, int> rooms, double fpW, double fpL, double wallT, int floor, {
    required bool isFirstFloor,
    required bool hasStaircase,
    CategoryLayoutRules? catRules,
    StyleLayoutRules? styleRules,
  }) {
    final result = <PlacedRoom>[];
    final innerW = fpW - wallT * 2;
    final innerL = fpL - wallT * 2;

    // Параметры из правил категории
    final corridorW = catRules?.corridorWidthM ?? _corridorWidth;
    final hallwayDepthCat = catRules?.hallwayDepthM ?? _hallwayDepth;
    final usesCorridor = catRules?.requiresCorridor ?? true;

    // ── Прихожая / холл ──
    final hallKind = isFirstFloor ? 'hallway' : 'corridor';
    final hallLabel = isFirstFloor ? 'Прихожая' : 'Холл';
    final hallDepth = isFirstFloor ? hallwayDepthCat : 2.0;

    // Для микро-домов без коридора — прихожая шире, ведёт прямо в зону
    final hallW = usesCorridor
        ? math.min(innerW * 0.4, 4.0)
        : math.min(innerW * 0.6, 5.0);
    final hallX = wallT + (innerW - hallW) / 2;
    final hallY = wallT + innerL - hallDepth;

    result.add(PlacedRoom(
      kind: hallKind, label: hallLabel,
      x: hallX, y: hallY, w: hallW, h: hallDepth,
      floor: floor, zone: HouseZone.transition, hasWindow: false,
    ));

    // ── Коридор ──
    final corridorH = innerL - hallDepth;
    final corridorY = wallT;
    final corridorCenterX = hallX + hallW / 2;
    final corrX = usesCorridor
        ? corridorCenterX - corridorW / 2
        : corridorCenterX; // no corridor for micro

    if (usesCorridor) {
      result.add(PlacedRoom(
        kind: 'corridor', label: 'Коридор',
        x: corrX, y: corridorY, w: corridorW, h: corridorH,
        floor: floor, zone: HouseZone.transition, hasWindow: false,
      ));
    }

    // ── Распределяем комнаты по левой и правой стороне от коридора ──
    final expandedRooms = <(String, double)>[];
    final counts = <String, int>{};

    for (final e in rooms.entries) {
      if (e.key == 'hallway' || e.key == 'corridor') continue;
      for (var i = 0; i < e.value; i++) {
        final overrideArea = catRules?.roomAreaOverrides[e.key];
        final std = kRoomAreaStandards[e.key];
        final area = overrideArea ?? std?.recommendedArea ?? 10.0;
        expandedRooms.add((e.key, area));
      }
    }

    expandedRooms.sort((a, b) => b.$2.compareTo(a.$2));

    // Available zones: left of corridor, right of corridor
    final double leftW;
    final double rightW;
    if (usesCorridor) {
      leftW = corrX - wallT;
      rightW = wallT + innerW - (corrX + corridorW);
    } else {
      // No corridor — split space in half
      leftW = innerW / 2;
      rightW = innerW / 2;
    }
    final availableH = corridorH;

    // Split rooms into left and right sides, balancing area
    final leftRooms = <(String, double)>[];
    final rightRooms = <(String, double)>[];
    var leftTotalArea = 0.0;
    var rightTotalArea = 0.0;

    for (final r in expandedRooms) {
      final kind = r.$1;
      final zone = kRoomZones[kind] ?? HouseZone.service;
      
      if (zone == HouseZone.sanitary || zone == HouseZone.service) {
        if (rightTotalArea <= leftTotalArea) {
          rightRooms.add(r);
          rightTotalArea += r.$2;
        } else {
          leftRooms.add(r);
          leftTotalArea += r.$2;
        }
      } else {
        if (leftTotalArea <= rightTotalArea) {
          leftRooms.add(r);
          leftTotalArea += r.$2;
        } else {
          rightRooms.add(r);
          rightTotalArea += r.$2;
        }
      }
    }

    // Place left-side rooms
    _placeRoomStrip(result, leftRooms, counts,
      stripX: wallT, stripW: leftW, stripY: corridorY,
      stripH: availableH, floor: floor, wallT: wallT);

    // Place right-side rooms
    final rightStripX = usesCorridor ? corrX + corridorW : wallT + leftW;
    _placeRoomStrip(result, rightRooms, counts,
      stripX: rightStripX, stripW: rightW, stripY: corridorY,
      stripH: availableH, floor: floor, wallT: wallT);

    // ── Добавляем комнаты по бокам прихожей (если есть место) ──
    final leftOfHallW = hallX - wallT;
    final rightOfHallW = wallT + innerW - (hallX + hallW);

    if (leftOfHallW > 1.5) {
      // Small room left of hallway (e.g. toilet, storage)
      final smallKind = _findSmallRoom(rooms, counts, isFirstFloor);
      if (smallKind != null) {
        counts[smallKind] = (counts[smallKind] ?? 0) + 1;
        final zone = kRoomZones[smallKind] ?? HouseZone.service;
        result.add(PlacedRoom(
          kind: smallKind, label: _makeLabel(smallKind, counts[smallKind]!),
          x: wallT, y: hallY, w: leftOfHallW, h: hallDepth,
          floor: floor, zone: zone,
          hasWindow: zone == HouseZone.public || zone == HouseZone.private,
        ));
      }
    }

    if (rightOfHallW > 1.5) {
      final smallKind = _findSmallRoom(rooms, counts, isFirstFloor);
      if (smallKind != null) {
        counts[smallKind] = (counts[smallKind] ?? 0) + 1;
        final zone = kRoomZones[smallKind] ?? HouseZone.service;
        result.add(PlacedRoom(
          kind: smallKind, label: _makeLabel(smallKind, counts[smallKind]!),
          x: hallX + hallW, y: hallY, w: rightOfHallW, h: hallDepth,
          floor: floor, zone: zone,
          hasWindow: zone == HouseZone.public || zone == HouseZone.private,
        ));
      }
    }

    return result;
  }

  void _placeRoomStrip(
    List<PlacedRoom> result,
    List<(String, double)> rooms,
    Map<String, int> counts, {
    required double stripX,
    required double stripW,
    required double stripY,
    required double stripH,
    required int floor,
    required double wallT,
  }) {
    if (rooms.isEmpty || stripW < 1.0) return;

    final totalArea = rooms.fold<double>(0, (s, r) => s + r.$2);
    final scale = (stripW * stripH) / (totalArea > 0 ? totalArea : 1);

    var currentY = stripY;
    final remainingH = stripH;

    for (var i = 0; i < rooms.length; i++) {
      final kind = rooms[i].$1;
      counts[kind] = (counts[kind] ?? 0) + 1;
      final scaledArea = rooms[i].$2 * scale;
      var roomH = scaledArea / stripW;

      // Last room takes remaining space
      if (i == rooms.length - 1) {
        roomH = stripY + remainingH - currentY;
      }

      // Clamp minimum height
      roomH = roomH.clamp(2.0, stripH * 0.7);

      final zone = kRoomZones[kind] ?? HouseZone.service;
      final needsWindow = zone == HouseZone.public || zone == HouseZone.private;

      result.add(PlacedRoom(
        kind: kind, label: _makeLabel(kind, counts[kind]!),
        x: stripX, y: currentY,
        w: stripW, h: roomH,
        floor: floor, zone: zone,
        hasWindow: needsWindow,
      ));
      currentY += roomH;
    }

    // Normalize to fill strip exactly
    if (result.isNotEmpty) {
      final roomsInStrip = result.where((r) =>
        (r.x - stripX).abs() < 0.01 && r.zone != HouseZone.transition).toList();
      if (roomsInStrip.isNotEmpty) {
        final actualBottom = roomsInStrip.map((r) => r.bottom).reduce(math.max);
        final targetBottom = stripY + stripH;
        if ((actualBottom - targetBottom).abs() > 0.1) {
          final scaleY = stripH / (actualBottom - stripY);
          for (var i = result.length - 1; i >= 0; i--) {
            final r = result[i];
            if ((r.x - stripX).abs() < 0.01 && r.zone != HouseZone.transition) {
              result[i] = PlacedRoom(
                kind: r.kind, label: r.label,
                x: r.x, y: stripY + (r.y - stripY) * scaleY,
                w: r.w, h: r.h * scaleY,
                floor: r.floor, zone: r.zone,
                hasWindow: r.hasWindow,
              );
            }
          }
        }
      }
    }
  }

  String? _findSmallRoom(Map<String, int> rooms, Map<String, int> counts, bool isFirstFloor) {
    // Prefer: toilet, storage, pantry, laundry, boilerRoom on 1st floor
    // Prefer: bathroom, wardrobe on upper floors
    final candidates = isFirstFloor
      ? ['toilet', 'storage', 'pantry', 'laundry', 'boilerRoom']
      : ['bathroom', 'wardrobe', 'storage'];
    for (final c in candidates) {
      final needed = rooms[c] ?? 0;
      final placed = counts[c] ?? 0;
      if (placed < needed) return c;
    }
    return null;
  }

  String _makeLabel(String kind, int count) {
    const labels = {
      'livingRoom': 'Гостиная', 'bedroom': 'Спальня', 'masterBedroom': 'Мастер-спальня',
      'kidsRoom': 'Детская', 'kitchen': 'Кухня', 'kitchenDining': 'Кухня-столовая',
      'dining': 'Столовая', 'study': 'Кабинет', 'bathroom': 'Санузел',
      'masterBathroom': 'Мастер-санузел', 'toilet': 'Туалет', 'hallway': 'Прихожая',
      'corridor': 'Коридор', 'boilerRoom': 'Котельная', 'storage': 'Кладовая',
      'wardrobe': 'Гардероб.', 'laundry': 'Постироч.', 'garage': 'Гараж',
      'terrace': 'Терраса', 'balcony': 'Балкон', 'pantry': 'Кладовая',
      'technical': 'Техпом.',
    };
    final base = labels[kind] ?? kind;
    return count > 1 ? '$base $count' : base;
  }

  // ─── Двери ─────────────────────────────────────────────────────────────

  List<DoorPlacement> _placeDoors(List<PlacedRoom> rooms, bool isFirstFloor, double fpL, double wallT) {
    final doors = <DoorPlacement>[];
    final corridor = rooms.where((r) => r.kind == 'corridor').firstOrNull;
    final hallway = rooms.where((r) => r.kind == 'hallway').firstOrNull;

    // Door from each room to corridor (if adjacent)
    if (corridor != null) {
      for (final r in rooms) {
        if (r.kind == 'corridor' || r.kind == 'hallway') continue;
        if (_sharesVerticalWall(r, corridor)) {
          final overlapStart = math.max(r.y, corridor.y);
          final overlapEnd = math.min(r.bottom, corridor.bottom);
          if (overlapEnd - overlapStart > 0.8) {
            final doorY = (overlapStart + overlapEnd) / 2;
            final doorX = r.x < corridor.x ? r.right : r.x;
            doors.add(DoorPlacement(x: doorX, y: doorY, horizontal: false, roomA: r.kind, roomB: 'corridor'));
          }
        }
        if (_sharesHorizontalWall(r, corridor)) {
          final overlapStart = math.max(r.x, corridor.x);
          final overlapEnd = math.min(r.right, corridor.right);
          if (overlapEnd - overlapStart > 0.8) {
            final doorX = (overlapStart + overlapEnd) / 2;
            final doorY = r.y < corridor.y ? r.bottom : r.y;
            doors.add(DoorPlacement(x: doorX, y: doorY, horizontal: true, roomA: r.kind, roomB: 'corridor'));
          }
        }
      }
    }

    // Door from corridor to hallway
    if (corridor != null && hallway != null) {
      if (_sharesHorizontalWall(corridor, hallway)) {
        final overlapStart = math.max(corridor.x, hallway.x);
        final overlapEnd = math.min(corridor.right, hallway.right);
        final doorX = (overlapStart + overlapEnd) / 2;
        final doorY = math.min(corridor.bottom, hallway.bottom);
        doors.add(DoorPlacement(x: doorX, y: doorY, horizontal: true, roomA: 'corridor', roomB: 'hallway'));
      }
    }

    // Doors from rooms adjacent to hallway (side rooms by entrance)
    if (hallway != null) {
      for (final r in rooms) {
        if (r.kind == 'hallway' || r.kind == 'corridor') continue;
        if (_sharesVerticalWall(r, hallway)) {
          final overlapStart = math.max(r.y, hallway.y);
          final overlapEnd = math.min(r.bottom, hallway.bottom);
          if (overlapEnd - overlapStart > 0.8) {
            final doorY = (overlapStart + overlapEnd) / 2;
            final doorX = r.x < hallway.x ? r.right : r.x;
            doors.add(DoorPlacement(x: doorX, y: doorY, horizontal: false, roomA: r.kind, roomB: 'hallway'));
          }
        }
      }
    }

    // Entrance door (in hallway, bottom wall = exterior wall)
    if (isFirstFloor && hallway != null) {
      doors.add(DoorPlacement(
        x: hallway.cx, y: fpL - wallT,
        horizontal: true, widthM: 0.9,
        roomA: 'exterior', roomB: 'hallway',
      ));
    }

    return doors;
  }

  bool _sharesVerticalWall(PlacedRoom a, PlacedRoom b) {
    return ((a.right - b.x).abs() < 0.15 || (b.right - a.x).abs() < 0.15)
      && a.y < b.bottom - 0.1 && b.y < a.bottom - 0.1;
  }

  bool _sharesHorizontalWall(PlacedRoom a, PlacedRoom b) {
    return ((a.bottom - b.y).abs() < 0.15 || (b.bottom - a.y).abs() < 0.15)
      && a.x < b.right - 0.1 && b.x < a.right - 0.1;
  }

  // ─── Окна ─────────────────────────────────────────────────────────────

  List<WindowPlacement> _placeWindows(List<PlacedRoom> rooms, double fpW, double fpL, double wallT) {
    final windows = <WindowPlacement>[];
    for (final r in rooms) {
      if (!r.hasWindow) continue;

      // Only place windows on exterior walls
      if ((r.x - wallT).abs() < 0.15) {
        windows.add(WindowPlacement(x: wallT, y: r.cy, horizontal: false, room: r.kind, side: 'left'));
      }
      if ((r.right - (fpW - wallT)).abs() < 0.15) {
        windows.add(WindowPlacement(x: fpW - wallT, y: r.cy, horizontal: false, room: r.kind, side: 'right'));
      }
      if ((r.y - wallT).abs() < 0.15) {
        windows.add(WindowPlacement(x: r.cx, y: wallT, horizontal: true, room: r.kind, side: 'top'));
      }
      if ((r.bottom - (fpL - wallT)).abs() < 0.15) {
        windows.add(WindowPlacement(x: r.cx, y: fpL - wallT, horizontal: true, room: r.kind, side: 'bottom'));
      }
    }
    return windows;
  }

  // ─── Лестница ─────────────────────────────────────────────────────────

  StaircasePlacement _placeStaircase(List<PlacedRoom> rooms, double fpW, double fpL, double wallT, int floor, StaircaseType? type) {
    final corridor = rooms.where((r) => r.kind == 'corridor').firstOrNull;
    final sw = type == StaircaseType.spiral ? 1.5 : 2.5;
    final sh = type == StaircaseType.spiral ? 1.5 : 1.0;

    if (corridor != null) {
      // Place staircase at the end of corridor (near hallway connection)
      return StaircasePlacement(
        x: corridor.x + (corridor.w - sw).clamp(0, sw) / 2,
        y: corridor.bottom - sh - 0.1,
        w: sw, h: sh,
        fromFloor: floor, toFloor: floor + 1,
      );
    }

    final innerW = fpW - wallT * 2;
    return StaircasePlacement(
      x: wallT + innerW / 2 - sw / 2,
      y: fpL - wallT - sh - 3,
      w: sw, h: sh,
      fromFloor: floor, toFloor: floor + 1,
    );
  }
}
