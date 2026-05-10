// Phase-3b §17.2.3 — пиксельный BFS-валидатор достижимости.
//
// Проверяет, что от входной двери (`OpeningKind.externalDoor`) до каждой
// комнаты (`PlanRoom`) есть путь шириной ≥ 0.9 м без коллизий с
// мебелью / стенами / дугами распашных дверей.
//
// Реализация — additive: валидатор НЕ мутирует FloorPlan, не удаляет
// мебель, не возвращает изменённый план. Он только формирует отчёт
// (`ReachabilityReport`) с предупреждениями. Откат мебели и привязка
// к `Project.warnings` отложены до следующей итерации (требуют
// миграции сериализации).

import 'dart:math' as math;

import '../../models/floor_plan.dart';

/// Результат валидации достижимости комнат на одном этаже.
class ReachabilityReport {
  ReachabilityReport({
    required this.gridStepM,
    required this.entrancesFound,
    required this.totalRooms,
    required this.unreachableRoomLabels,
    required this.warnings,
  });

  /// Шаг используемой сетки в метрах (по умолчанию 0.05).
  final double gridStepM;

  /// Сколько входных дверей (`OpeningKind.externalDoor`) найдено.
  /// Если 0 — валидация невозможна, но это не ошибка плана.
  final int entrancesFound;

  /// Сколько комнат проверено (исключая лестницы и `free`).
  final int totalRooms;

  /// Комнаты, для которых не нашлось пути ширины ≥ 0.9 м от входа.
  final List<String> unreachableRoomLabels;

  /// Свободные текстовые предупреждения (для будущей привязки к
  /// `Project.warnings`).
  final List<String> warnings;

  bool get hasIssues => unreachableRoomLabels.isNotEmpty;
}

/// Конфигурация валидатора (значения по умолчанию соответствуют ТЗ
/// §17.2.3).
class ReachabilityConfig {
  const ReachabilityConfig({
    this.gridStepM = 0.05,
    this.minPathWidthM = 0.9,
    this.wallThicknessM = 0.20,
    this.doorSwingRadiusM = 0.45,
  });

  final double gridStepM;
  final double minPathWidthM;
  final double wallThicknessM;
  final double doorSwingRadiusM;
}

class ReachabilityValidator {
  ReachabilityValidator._();

  /// Запускает валидацию одного этажа.
  static ReachabilityReport validate(
    FloorPlan plan, {
    ReachabilityConfig config = const ReachabilityConfig(),
  }) {
    final step = config.gridStepM;
    final cols = math.max(1, (plan.width / step).ceil());
    final rows = math.max(1, (plan.height / step).ceil());
    final pathW = math.max(1, (config.minPathWidthM / step).round());
    final wallW = math.max(1, (config.wallThicknessM / step).round());
    final swingR = math.max(1, (config.doorSwingRadiusM / step).round());

    // 0 — свободно, 1 — занято стеной/мебелью/аркой двери.
    final blocked = List<int>.filled(cols * rows, 0);
    int idx(int c, int r) => r * cols + c;
    void block(int c, int r) {
      if (c < 0 || c >= cols || r < 0 || r >= rows) return;
      blocked[idx(c, r)] = 1;
    }

    // Внешний контур пятна — стенами шириной wallW.
    void fillRect(int c0, int r0, int cN, int rN) {
      for (var r = r0; r < rN; r++) {
        for (var c = c0; c < cN; c++) {
          block(c, r);
        }
      }
    }

    fillRect(0, 0, cols, wallW);
    fillRect(0, rows - wallW, cols, rows);
    fillRect(0, 0, wallW, rows);
    fillRect(cols - wallW, 0, cols, rows);

    // Внутренние стены — между смежными комнатами. Грубо: помечаем
    // полосу `wallW` ячеек по контурам каждой комнаты, кроме мест
    // расположения проёмов (двери / арки).
    int xToCol(double xM) => (xM / step).round().clamp(0, cols);
    int yToRow(double yM) => (yM / step).round().clamp(0, rows);

    for (final room in plan.rooms) {
      final c0 = xToCol(room.x);
      final r0 = yToRow(room.y);
      final c1 = xToCol(room.x + room.width);
      final r1 = yToRow(room.y + room.height);
      // Все 4 стенки комнаты — пометить как occupied.
      fillRect(c0, r0, c1, math.min(rows, r0 + wallW));
      fillRect(c0, math.max(0, r1 - wallW), c1, r1);
      fillRect(c0, r0, math.min(cols, c0 + wallW), r1);
      fillRect(math.max(0, c1 - wallW), r0, c1, r1);
    }

    // «Прорезаем» проёмы (двери / арки / входная дверь / окна
    // считаем непроходимыми, окна — нет).
    for (final op in plan.openings) {
      if (op.kind == OpeningKind.window) continue;
      final isVertical = op.side == WallSide.left || op.side == WallSide.right;
      final cStart = xToCol(op.x);
      final rStart = yToRow(op.y);
      if (isVertical) {
        // вертикальная стена — проём идёт по Y.
        final cBegin = math.max(0, cStart - wallW);
        final cEnd = math.min(cols, cStart + wallW);
        final rEnd = yToRow(op.y + op.length);
        for (var r = rStart; r < rEnd; r++) {
          for (var c = cBegin; c < cEnd; c++) {
            blocked[idx(c, r)] = 0;
          }
        }
      } else {
        final rBegin = math.max(0, rStart - wallW);
        final rEnd = math.min(rows, rStart + wallW);
        final cEnd = xToCol(op.x + op.length);
        for (var r = rBegin; r < rEnd; r++) {
          for (var c = cStart; c < cEnd; c++) {
            blocked[idx(c, r)] = 0;
          }
        }
      }
    }

    // Дугa распашной двери — четверть круга радиуса 0.45 м у точки
    // петли. Считаем petли по серединам проёмов дверей (упрощение).
    for (final op in plan.openings) {
      if (op.kind != OpeningKind.door &&
          op.kind != OpeningKind.externalDoor) {
        continue;
      }
      final isVertical = op.side == WallSide.left || op.side == WallSide.right;
      final cx = isVertical ? xToCol(op.x) : xToCol(op.x + op.length / 2);
      final cy = isVertical ? yToRow(op.y + op.length / 2) : yToRow(op.y);
      final r2 = swingR * swingR;
      for (var dr = -swingR; dr <= swingR; dr++) {
        for (var dc = -swingR; dc <= swingR; dc++) {
          if (dr * dr + dc * dc > r2) continue;
          block(cx + dc, cy + dr);
        }
      }
    }

    // Мебель — каждый прямоугольник как occupied. Координаты мебели —
    // в системе плана (как у комнат).
    for (final room in plan.rooms) {
      for (final f in room.furniture) {
        // Углы при rotation 0/90/180/270: bbox = (x, y, x+w, y+h)
        // независимо от rotation (rot не растягивает bbox). Берём
        // bbox как простое приближение.
        final c0 = xToCol(f.x);
        final r0 = yToRow(f.y);
        final c1 = xToCol(f.x + f.width);
        final r1 = yToRow(f.y + f.height);
        fillRect(c0, r0, c1, r1);
      }
    }

    // Маска «проходим, если 0.9 м × 0.9 м квадрат не пересекает
    // блок». Используем интегральную сумму blocked.
    final integ = List<int>.filled((cols + 1) * (rows + 1), 0);
    int iidx(int c, int r) => r * (cols + 1) + c;
    for (var r = 0; r < rows; r++) {
      var rowSum = 0;
      for (var c = 0; c < cols; c++) {
        rowSum += blocked[idx(c, r)];
        integ[iidx(c + 1, r + 1)] = integ[iidx(c + 1, r)] + rowSum;
      }
    }
    int rectSum(int c0, int r0, int c1, int r1) {
      c0 = c0.clamp(0, cols);
      r0 = r0.clamp(0, rows);
      c1 = c1.clamp(0, cols);
      r1 = r1.clamp(0, rows);
      return integ[iidx(c1, r1)] -
          integ[iidx(c0, r1)] -
          integ[iidx(c1, r0)] +
          integ[iidx(c0, r0)];
    }

    final passable = List<bool>.filled(cols * rows, false);
    final half = pathW ~/ 2;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (blocked[idx(c, r)] == 1) continue;
        final c0 = c - half;
        final r0 = r - half;
        final c1 = c0 + pathW;
        final r1 = r0 + pathW;
        if (c0 < 0 || r0 < 0 || c1 > cols || r1 > rows) continue;
        if (rectSum(c0, r0, c1, r1) > 0) continue;
        passable[idx(c, r)] = true;
      }
    }

    // Источники BFS — ячейки рядом с входной дверью (с внутренней
    // стороны).
    //
    // Идеальный кандидат — `OpeningKind.externalDoor` (выставляется
    // генератором по правилам §17.2.3). Если ни одной такой нет
    // (бывает на компактных планах без entry-room и без котельной с
    // длинной наружной стеной), берём любые двери на периметре пятна
    // как «входные» эвристически.
    final perimeterDoors = <PlanOpening>[];
    bool isPerimeterDoor(PlanOpening op) {
      const eps = 0.05;
      if (op.kind == OpeningKind.window) return false;
      if (op.side == WallSide.top && op.y.abs() < eps) return true;
      if (op.side == WallSide.bottom &&
          (op.y - plan.height).abs() < eps) {
        return true;
      }
      if (op.side == WallSide.left && op.x.abs() < eps) return true;
      if (op.side == WallSide.right && (op.x - plan.width).abs() < eps) {
        return true;
      }
      return false;
    }
    for (final op in plan.openings) {
      if (op.kind == OpeningKind.externalDoor) {
        perimeterDoors.add(op);
      } else if (isPerimeterDoor(op) &&
          plan.openings.every((o) => o.kind != OpeningKind.externalDoor)) {
        perimeterDoors.add(op);
      }
    }
    final sources = <int>[];
    for (final op in perimeterDoors) {
      final cMid = (op.side == WallSide.left || op.side == WallSide.right)
          ? xToCol(op.x)
          : xToCol(op.x + op.length / 2);
      final rMid = (op.side == WallSide.left || op.side == WallSide.right)
          ? yToRow(op.y + op.length / 2)
          : yToRow(op.y);
      // Берём радиус в 4 шага от центра — маленький диск-источник,
      // чтобы попасть в свободные ячейки внутри помещения.
      for (var dr = -8; dr <= 8; dr++) {
        for (var dc = -8; dc <= 8; dc++) {
          final c = cMid + dc;
          final rr = rMid + dr;
          if (c < 0 || rr < 0 || c >= cols || rr >= rows) continue;
          if (passable[idx(c, rr)]) sources.add(idx(c, rr));
        }
      }
    }

    final entrances = perimeterDoors.length;

    // BFS по passable.
    final visited = List<bool>.filled(cols * rows, false);
    final queue = <int>[];
    for (final s in sources) {
      if (!visited[s]) {
        visited[s] = true;
        queue.add(s);
      }
    }
    var head = 0;
    while (head < queue.length) {
      final v = queue[head++];
      final cv = v % cols;
      final rv = v ~/ cols;
      const dx = [1, -1, 0, 0];
      const dy = [0, 0, 1, -1];
      for (var k = 0; k < 4; k++) {
        final nc = cv + dx[k];
        final nr = rv + dy[k];
        if (nc < 0 || nr < 0 || nc >= cols || nr >= rows) continue;
        final nv = idx(nc, nr);
        if (visited[nv]) continue;
        if (!passable[nv]) continue;
        visited[nv] = true;
        queue.add(nv);
      }
    }

    // Проверяем по комнатам.
    final unreachable = <String>[];
    var totalRooms = 0;
    for (final room in plan.rooms) {
      if (room.kind == PlanRoomKind.staircase ||
          room.kind == PlanRoomKind.free) {
        continue;
      }
      totalRooms++;
      final c0 = xToCol(room.x);
      final r0 = yToRow(room.y);
      final c1 = xToCol(room.x + room.width);
      final r1 = yToRow(room.y + room.height);
      var hit = false;
      for (var r = r0; r < r1 && !hit; r++) {
        for (var c = c0; c < c1; c++) {
          if (visited[idx(c, r)]) {
            hit = true;
            break;
          }
        }
      }
      if (!hit && entrances > 0) {
        unreachable.add(room.label);
      }
    }

    final warnings = <String>[];
    if (entrances == 0) {
      warnings.add(
          'Входная дверь не найдена — пешая досягаемость не проверена.');
    }
    for (final lbl in unreachable) {
      warnings.add(
          'Комната «$lbl» недоступна по проходу шириной ≥ ${config.minPathWidthM} м '
          'от входной двери (Phase-3b §17.2.3).');
    }

    return ReachabilityReport(
      gridStepM: step,
      entrancesFound: entrances,
      totalRooms: totalRooms,
      unreachableRoomLabels: unreachable,
      warnings: warnings,
    );
  }
}
