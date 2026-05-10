import 'package:uuid/uuid.dart';

import '../models/drawing.dart';
import '../models/floor_plan.dart';
import '../models/furniture_symbol.dart';
import '../models/house_project.dart';
import '../models/user_mode.dart';
import 'floor_plan_generator.dart';
import 'foundation_plan_generator.dart';
import 'furniture/reachability_validator.dart';

/// Генератор чертежей по проекту.
///
/// Все листы — реальные, расчётные, без текстовых «заглушек»:
///   * **План фундамента** — [FoundationPlanGenerator] подбирает геометрию
///     по СП 22 (нагрузки → ширина подошвы → внутренние оси → размеры).
///   * **Схематические планы этажей** — [FloorPlanGenerator] раскладывает
///     помещения, окна и двери по ТЗ.
///   * **Кровля, разрезы, фасады, аксонометрия, спецификация** — рендерятся
///     полностью в PDF (см. [PdfBuilder]) на основе данных проекта;
///     соответствующие [Drawing] здесь служат «оглавлением» и подписью
///     листа в комплекте чертежей. Никаких текстовых описаний-заглушек
///     не сохраняется.
class DrawingGenerator {
  static const _uuid = Uuid();

  static List<Drawing> generate({
    required HouseProject project,
    required UserMode mode,
    bool autoFix = false,
  }) {
    final now = DateTime.now();
    final isClient = mode == UserMode.client;
    final drawings = <Drawing>[];

    // 1. Схематические планы этажей.
    // Phase-3b §17.2.1: пробрасываем `architectureFootprint` (если задан),
    // чтобы при L/T/U-формах генератор обрезал комнаты по полигону, а
    // рендер `_paintPlan` отрисовал контур по уступам. Старые проекты
    // без поля идут прежним rectangular-путём.
    var plans = FloorPlanGenerator.generate(
      project.brief,
      ceilingHeight: project.walls.height ?? project.staircase.floorHeight,
      footprint: project.architectureFootprint,
    );

    // Auto-fix: если включён, убираем мебель из комнат, блокирующих
    // проходы, и повторяем валидацию до 3 раз.
    if (autoFix) {
      plans = _autoFixPlans(plans);
    }

    for (final plan in plans) {
      drawings.add(Drawing(
        id: _uuid.v4(),
        title: 'План: ${plan.floorLabel}',
        kind: DrawingKind.schematicPlan,
        createdAt: now,
        payload: plan.encode(),
      ));
    }

    // §17.2.3 — пиксельный BFS-валидатор достижимости. Записываем
    // все unreachable-предупреждения в `Project.warnings`, чтобы они
    // переживали перезагрузку и попадали в PDF (см. `pdf_general_data`).
    project.warnings.removeWhere((w) => w.startsWith('Этаж '));
    for (var i = 0; i < plans.length; i++) {
      final plan = plans[i];
      final report = ReachabilityValidator.validate(plan);
      if (report.entrancesFound == 0) continue;
      for (final label in report.unreachableRoomLabels) {
        project.warnings.add(
          'Этаж ${plan.floorLabel}: «$label» недоступна — ширина прохода < 0.9 м',
        );
      }
    }

    // 2. План фундамента — реальная геометрия по ТЗ + расчёту.
    if (project.foundation.isFilled) {
      final foundationModel = FoundationPlanGenerator.generate(project);
      if (foundationModel != null) {
        drawings.add(Drawing(
          id: _uuid.v4(),
          title: 'План фундамента',
          kind: DrawingKind.foundationPlan,
          createdAt: now,
          payload: foundationModel.encode(),
        ));
      }
    }

    // 3. Кровля — лист в комплекте, рендерится в PDF.
    if (project.roof.isFilled) {
      drawings.add(Drawing(
        id: _uuid.v4(),
        title: isClient ? 'Эскиз кровли' : 'План кровли',
        kind: isClient ? DrawingKind.sketch : DrawingKind.workingPlan,
        createdAt: now,
        payload: '',
      ));
    }

    // 4. Разрезы и фасады — выводятся на отдельных листах PDF из реальных
    // координат стен, проёмов, выбранного фундамента и формы кровли.
    if (!isClient) {
      drawings.add(Drawing(
        id: _uuid.v4(),
        title: 'Разрез 1-1 (поперечный)',
        kind: DrawingKind.workingSection,
        createdAt: now,
        payload: '',
      ));
      drawings.add(Drawing(
        id: _uuid.v4(),
        title: 'Разрез 2-2 (продольный)',
        kind: DrawingKind.workingSection,
        createdAt: now,
        payload: '',
      ));
      drawings.add(Drawing(
        id: _uuid.v4(),
        title: 'Фасад южный',
        kind: DrawingKind.facade,
        createdAt: now,
        payload: '',
      ));
      drawings.add(Drawing(
        id: _uuid.v4(),
        title: 'Фасад северный',
        kind: DrawingKind.facade,
        createdAt: now,
        payload: '',
      ));
      drawings.add(Drawing(
        id: _uuid.v4(),
        title: 'Фасад восточный',
        kind: DrawingKind.facade,
        createdAt: now,
        payload: '',
      ));
      drawings.add(Drawing(
        id: _uuid.v4(),
        title: 'Фасад западный',
        kind: DrawingKind.facade,
        createdAt: now,
        payload: '',
      ));
    }

    return drawings;
  }

  /// Итеративно убирает мебель, блокирующую проходы.
  ///
  /// 1. Проверяем каждый план на достижимость.
  /// 2. Если есть недостижимые комнаты — убираем ВСЮ мебель на этаже.
  /// 3. Перепроверяем: без мебели проходы должны быть свободны.
  static List<FloorPlan> _autoFixPlans(List<FloorPlan> plans) {
    final result = <FloorPlan>[];
    for (final plan in plans) {
      final report = ReachabilityValidator.validate(plan);
      if (report.entrancesFound == 0 || !report.hasIssues) {
        result.add(plan);
        continue;
      }
      // Убираем мебель из всех комнат — она может блокировать коридор
      // любой из смежных комнат.
      final strippedRooms = plan.rooms.map((r) {
        if (r.furniture.isEmpty) return r;
        return r.copyWith(furniture: const []);
      }).toList();
      var fixed = plan.copyWith(rooms: strippedRooms);
      // Повторная проверка без мебели.
      final recheck = ReachabilityValidator.validate(fixed);
      if (!recheck.hasIssues) {
        // Успех: добавляем мебель обратно, кроме предметов, которые
        // пересекают дверные проходы (зона 0.9 м от двери).
        final safeRooms = <PlanRoom>[];
        for (var i = 0; i < plan.rooms.length; i++) {
          final orig = plan.rooms[i];
          if (orig.furniture.isEmpty) {
            safeRooms.add(orig);
            continue;
          }
          final kept = orig.furniture.where((f) {
            return !_furnitureBlocksDoorway(f, orig, plan);
          }).toList();
          safeRooms.add(orig.copyWith(furniture: kept));
        }
        fixed = plan.copyWith(rooms: safeRooms);
        // Финальная проверка с отфильтрованной мебелью.
        final finalCheck = ReachabilityValidator.validate(fixed);
        if (finalCheck.hasIssues) {
          // Всё ещё проблемы — убираем всю мебель.
          fixed = plan.copyWith(rooms: strippedRooms);
        }
      }
      result.add(fixed);
    }
    return result;
  }

  /// Проверяет, перекрывает ли мебель зону перед дверным проёмом.
  static bool _furnitureBlocksDoorway(
    FurnitureSymbol f,
    PlanRoom room,
    FloorPlan plan,
  ) {
    const doorZone = 0.9;
    for (final op in plan.openings) {
      if (op.kind == OpeningKind.window) continue;
      // Расширяем bbox двери на doorZone метров внутрь комнаты.
      final isVert =
          op.side == WallSide.left || op.side == WallSide.right;
      final double dzX1, dzY1, dzX2, dzY2;
      if (isVert) {
        dzX1 = op.x - doorZone;
        dzX2 = op.x + doorZone;
        dzY1 = op.y;
        dzY2 = op.y + op.length;
      } else {
        dzX1 = op.x;
        dzX2 = op.x + op.length;
        dzY1 = op.y - doorZone;
        dzY2 = op.y + doorZone;
      }
      // Пересечение bbox мебели с зоной двери.
      if (f.x < dzX2 &&
          f.x + f.width > dzX1 &&
          f.y < dzY2 &&
          f.y + f.height > dzY1) {
        return true;
      }
    }
    return false;
  }
}
