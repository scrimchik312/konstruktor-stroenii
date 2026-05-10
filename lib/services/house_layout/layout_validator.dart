/// Валидатор планировки — проверяет соответствие планировки правилам.
///
/// Использует правила из `planning_rules.dart` для проверки:
/// - площадей и пропорций комнат;
/// - правил смежности;
/// - зонирования по этажам;
/// - инженерных ограничений;
/// - нормативных требований (СП, IRC).
library;

import 'dart:math' as math;

import '../../data/house_layout/planning_rules.dart';
import '../../models/floor_plan.dart';

/// Уровень серьёзности замечания.
enum ValidationSeverity {
  /// Нарушение обязательного требования (СП, IRC).
  error,

  /// Нарушение рекомендации — неоптимально.
  warning,

  /// Информация — можно улучшить.
  info,
}

/// Одно замечание валидатора.
class ValidationIssue {
  final ValidationSeverity severity;
  final String code;
  final String message;
  final String? roomLabel;
  final int? floor;

  const ValidationIssue({
    required this.severity,
    required this.code,
    required this.message,
    this.roomLabel,
    this.floor,
  });

  @override
  String toString() => '[$severity] $code: $message'
      '${roomLabel != null ? ' (комната: $roomLabel)' : ''}'
      '${floor != null ? ' (этаж $floor)' : ''}';
}

/// Результат валидации.
class ValidationReport {
  final List<ValidationIssue> issues;
  final DateTime timestamp;

  ValidationReport({
    required this.issues,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get hasErrors =>
      issues.any((i) => i.severity == ValidationSeverity.error);
  bool get hasWarnings =>
      issues.any((i) => i.severity == ValidationSeverity.warning);
  int get errorCount =>
      issues.where((i) => i.severity == ValidationSeverity.error).length;
  int get warningCount =>
      issues.where((i) => i.severity == ValidationSeverity.warning).length;

  /// Оценка качества планировки (0..100).
  int get score {
    var s = 100;
    for (final issue in issues) {
      switch (issue.severity) {
        case ValidationSeverity.error:
          s -= 15;
        case ValidationSeverity.warning:
          s -= 5;
        case ValidationSeverity.info:
          s -= 1;
      }
    }
    return s.clamp(0, 100);
  }
}

/// Валидатор планировки.
class LayoutValidator {
  const LayoutValidator();

  /// Выполняет полную валидацию набора этажей.
  ValidationReport validate(List<FloorPlan> plans) {
    final issues = <ValidationIssue>[];

    for (var i = 0; i < plans.length; i++) {
      final plan = plans[i];
      final floorNum = i + 1;

      _validateRoomAreas(plan, floorNum, issues);
      _validateRoomProportions(plan, floorNum, issues);
      _validateAdjacency(plan, floorNum, issues);
      _validateWindows(plan, floorNum, issues);
      _validateCorridors(plan, floorNum, issues);
    }

    _validateFloorZoning(plans, issues);
    _validateBathroomAlignment(plans, issues);
    _validateStaircasePresence(plans, issues);

    return ValidationReport(issues: issues);
  }

  /// Проверяет площади комнат.
  void _validateRoomAreas(
    FloorPlan plan,
    int floor,
    List<ValidationIssue> issues,
  ) {
    for (final room in plan.rooms) {
      final kindName = room.roomKindName;
      if (kindName == null) continue;
      final standard = kRoomAreaStandards[kindName];
      if (standard == null) continue;

      if (room.area < standard.minArea) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.error,
          code: 'AREA_TOO_SMALL',
          message: '«${room.label}» ${room.area.toStringAsFixed(1)} м² — '
              'менее минимума ${standard.minArea} м² '
              'по СП 55.13330',
          roomLabel: room.label,
          floor: floor,
        ));
      }

      if (room.area > standard.maxArea) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.warning,
          code: 'AREA_TOO_LARGE',
          message: '«${room.label}» ${room.area.toStringAsFixed(1)} м² — '
              'превышает типовой максимум ${standard.maxArea} м²',
          roomLabel: room.label,
          floor: floor,
        ));
      }

      final minDim = math.min(room.width, room.height);
      if (minDim < standard.minWidth) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.error,
          code: 'ROOM_TOO_NARROW',
          message: '«${room.label}» ширина ${minDim.toStringAsFixed(1)} м — '
              'менее минимума ${standard.minWidth} м',
          roomLabel: room.label,
          floor: floor,
        ));
      }
    }
  }

  /// Проверяет пропорции комнат.
  void _validateRoomProportions(
    FloorPlan plan,
    int floor,
    List<ValidationIssue> issues,
  ) {
    for (final room in plan.rooms) {
      if (room.kind == PlanRoomKind.free) continue;
      if (room.kind == PlanRoomKind.staircase) continue;

      if (!ProportionRule.isValidProportion(room.width, room.height)) {
        final ratio =
            math.max(room.width, room.height) /
            math.min(room.width, room.height);
        issues.add(ValidationIssue(
          severity: ValidationSeverity.warning,
          code: 'BAD_PROPORTION',
          message: '«${room.label}» соотношение сторон '
              '${ratio.toStringAsFixed(1)}:1 — рекомендуется не более '
              '${ProportionRule.maxAspectRatio}:1',
          roomLabel: room.label,
          floor: floor,
        ));
      }
    }
  }

  /// Проверяет правила смежности.
  void _validateAdjacency(
    FloorPlan plan,
    int floor,
    List<ValidationIssue> issues,
  ) {
    for (final rule in kAdjacencyRules) {
      final roomsA = plan.rooms
          .where((r) => r.roomKindName == rule.roomA)
          .toList();
      final roomsB = plan.rooms
          .where((r) => r.roomKindName == rule.roomB)
          .toList();

      if (roomsA.isEmpty || roomsB.isEmpty) continue;

      switch (rule.type) {
        case AdjacencyType.forbidden:
          for (final a in roomsA) {
            for (final b in roomsB) {
              if (_areAdjacent(a, b)) {
                issues.add(ValidationIssue(
                  severity: ValidationSeverity.error,
                  code: 'FORBIDDEN_ADJACENCY',
                  message: '«${a.label}» и «${b.label}» не должны '
                      'быть рядом: ${rule.reason}',
                  floor: floor,
                ));
              }
            }
          }
        case AdjacencyType.required:
          bool found = false;
          for (final a in roomsA) {
            for (final b in roomsB) {
              if (_areAdjacent(a, b)) {
                found = true;
                break;
              }
            }
            if (found) break;
          }
          if (!found) {
            issues.add(ValidationIssue(
              severity: ValidationSeverity.warning,
              code: 'MISSING_ADJACENCY',
              message: '${rule.roomA} и ${rule.roomB} должны быть '
                  'рядом: ${rule.reason}',
              floor: floor,
            ));
          }
        case AdjacencyType.undesirable:
          for (final a in roomsA) {
            for (final b in roomsB) {
              if (a != b && _areAdjacent(a, b)) {
                issues.add(ValidationIssue(
                  severity: ValidationSeverity.info,
                  code: 'UNDESIRABLE_ADJACENCY',
                  message: '«${a.label}» и «${b.label}»: ${rule.reason}',
                  floor: floor,
                ));
              }
            }
          }
        case AdjacencyType.recommended:
          break;
      }
    }
  }

  /// Проверяет наличие окон в жилых комнатах.
  void _validateWindows(
    FloorPlan plan,
    int floor,
    List<ValidationIssue> issues,
  ) {
    final habitableKinds = {
      'bedroom',
      'masterBedroom',
      'kidsRoom',
      'livingRoom',
      'kitchen',
      'kitchenDining',
      'study',
      'dining',
    };

    for (final room in plan.rooms) {
      final kind = room.roomKindName;
      if (kind == null || !habitableKinds.contains(kind)) continue;

      final windowsForRoom = plan.openings.where((o) {
        if (o.kind != OpeningKind.window) return false;
        return _openingBelongsToRoom(o, room);
      });

      if (windowsForRoom.isEmpty) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.error,
          code: 'NO_WINDOW',
          message: '«${room.label}» — жилое помещение без окон. '
              'Требуется минимум 1 окно (IRC R303.1)',
          roomLabel: room.label,
          floor: floor,
        ));
      }
    }
  }

  /// Проверяет долю коридоров.
  void _validateCorridors(
    FloorPlan plan,
    int floor,
    List<ValidationIssue> issues,
  ) {
    final totalArea =
        plan.rooms.fold<double>(0, (s, r) => s + r.area);
    final corridorArea = plan.rooms
        .where((r) => r.kind == PlanRoomKind.free)
        .fold<double>(0, (s, r) => s + r.area);

    if (totalArea > 0 &&
        corridorArea / totalArea > LayoutEfficiency.maxCorridorShare) {
      issues.add(ValidationIssue(
        severity: ValidationSeverity.warning,
        code: 'CORRIDOR_TOO_LARGE',
        message: 'Доля коридоров '
            '${(corridorArea / totalArea * 100).toStringAsFixed(0)}% — '
            'рекомендуется не более '
            '${(LayoutEfficiency.maxCorridorShare * 100).toStringAsFixed(0)}%',
        floor: floor,
      ));
    }
  }

  /// Проверяет зонирование по этажам.
  void _validateFloorZoning(
    List<FloorPlan> plans,
    List<ValidationIssue> issues,
  ) {
    if (plans.isEmpty) return;

    // На первом этаже должна быть кухня.
    final firstFloor = plans.first;
    final hasKitchen = firstFloor.rooms.any(
      (r) =>
          r.roomKindName == 'kitchen' || r.roomKindName == 'kitchenDining',
    );
    if (!hasKitchen) {
      issues.add(const ValidationIssue(
        severity: ValidationSeverity.error,
        code: 'NO_KITCHEN_GROUND',
        message: 'На 1-м этаже отсутствует кухня',
        floor: 1,
      ));
    }

    // На каждом этаже хотя бы один санузел.
    for (var i = 0; i < plans.length; i++) {
      final hasBathroom = plans[i].rooms.any(
        (r) =>
            r.roomKindName == 'bathroom' ||
            r.roomKindName == 'masterBathroom' ||
            r.roomKindName == 'toilet',
      );
      if (!hasBathroom) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.warning,
          code: 'NO_BATHROOM_FLOOR',
          message: 'На этаже ${i + 1} отсутствует санузел',
          floor: i + 1,
        ));
      }
    }
  }

  /// Проверяет вертикальное выравнивание санузлов (стояки).
  void _validateBathroomAlignment(
    List<FloorPlan> plans,
    List<ValidationIssue> issues,
  ) {
    if (plans.length < 2) return;

    for (var i = 1; i < plans.length; i++) {
      final upperBathrooms = plans[i].rooms.where(
        (r) =>
            r.roomKindName == 'bathroom' ||
            r.roomKindName == 'masterBathroom',
      );
      final lowerBathrooms = plans[i - 1].rooms.where(
        (r) =>
            r.roomKindName == 'bathroom' ||
            r.roomKindName == 'masterBathroom' ||
            r.roomKindName == 'kitchen' ||
            r.roomKindName == 'kitchenDining' ||
            r.roomKindName == 'laundry',
      );

      for (final upper in upperBathrooms) {
        final aligned = lowerBathrooms.any((lower) {
          final dx = (upper.x - lower.x).abs();
          final dy = (upper.y - lower.y).abs();
          return dx < EngineeringRule.maxPipeRunFromStack &&
              dy < EngineeringRule.maxPipeRunFromStack;
        });
        if (!aligned) {
          issues.add(ValidationIssue(
            severity: ValidationSeverity.warning,
            code: 'BATHROOM_NOT_ALIGNED',
            message: '«${upper.label}» на этаже ${i + 1} не над '
                'мокрой зоной нижнего этажа — '
                'удлинение канализационных труб',
            roomLabel: upper.label,
            floor: i + 1,
          ));
        }
      }
    }
  }

  /// Проверяет наличие лестницы в многоэтажных домах.
  void _validateStaircasePresence(
    List<FloorPlan> plans,
    List<ValidationIssue> issues,
  ) {
    if (plans.length < 2) return;

    for (var i = 0; i < plans.length; i++) {
      final hasStaircase =
          plans[i].rooms.any((r) => r.kind == PlanRoomKind.staircase);
      if (!hasStaircase) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.error,
          code: 'NO_STAIRCASE',
          message: 'На этаже ${i + 1} отсутствует лестничный проём',
          floor: i + 1,
        ));
      }
    }
  }

  // -- Вспомогательные методы --

  /// Проверяет смежность двух комнат (общая стена).
  bool _areAdjacent(PlanRoom a, PlanRoom b) {
    const eps = 0.01;
    final touchH = (a.x + a.width - b.x).abs() < eps ||
        (b.x + b.width - a.x).abs() < eps;
    final touchV = (a.y + a.height - b.y).abs() < eps ||
        (b.y + b.height - a.y).abs() < eps;
    final overlapH = a.x < b.x + b.width + eps && b.x < a.x + a.width + eps;
    final overlapV =
        a.y < b.y + b.height + eps && b.y < a.y + a.height + eps;

    return (touchH && overlapV) || (touchV && overlapH);
  }

  /// Проверяет, что проём принадлежит комнате.
  bool _openingBelongsToRoom(PlanOpening opening, PlanRoom room) {
    const eps = 0.3;
    return opening.x >= room.x - eps &&
        opening.x <= room.x + room.width + eps &&
        opening.y >= room.y - eps &&
        opening.y <= room.y + room.height + eps;
  }
}
