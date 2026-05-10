import '../models/house_project.dart';

/// Этапы прохождения проекта.
///
/// Раньше проект состоял из трёх независимых разделов («бриф», «состав
/// сооружения», «чертежи»), и пользователь мог в произвольном порядке
/// заполнять любой из них. По новой схеме проект — это **строго
/// последовательный мастер**: пока не завершён предыдущий этап, следующий
/// заблокирован. Это обеспечивает корректность данных: например, фундамент
/// невозможно подобрать без известных нагрузок от стен и перекрытий, а
/// перекрытия — без размещения комнат на этажах.
///
/// Каждый этап знает:
///   * [id] — стабильный идентификатор для аналитики/подсказок;
///   * [title] — то, что видит пользователь в карточке;
///   * [isComplete] — все ли обязательные данные этапа заполнены;
///   * [isUnlocked] — доступен ли этап (предыдущий завершён).
enum ProjectStageId {
  initialData,
  planning,
  foundation,
  roof,
  technicalSpec,
  estimate,
}

class ProjectStageStatus {
  ProjectStageStatus({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.isComplete,
    required this.isUnlocked,
  });

  final ProjectStageId id;
  final String title;
  final String subtitle;
  final bool isComplete;
  final bool isUnlocked;
}

/// Сервис, вычисляющий состояние всех этапов по текущему проекту.
class ProjectStages {
  /// Этап 1 — «Начальные данные» (то, что раньше называлось техническим
  /// заданием клиента, но без вопросов о грунте и климате — они уйдут
  /// в этап «Фундамент»). Считаем заполненным, если есть основные
  /// характеристики дома: этажность, желаемая площадь и состав комнат.
  /// Материал стен выбирается на этапе 2 «Планировка».
  static bool isInitialDataComplete(HouseProject p) {
    final b = p.brief;
    // Состав комнат может быть задан двумя способами:
    //   • общий список (b.rooms) — авто-распределение генератором;
    //   • per-floor (b.floorRooms) — ручное распределение
    //     (включает «Распределить вручную по этажам» в визарде).
    // Проверяем оба, иначе ручной режим блокирует переход на этап 2
    // (фактически закрытый этап 1 показывался как недозаполненный).
    final hasRoomsAuto = b.rooms.values.any((v) => v > 0);
    final hasRoomsManual = b.floorRooms.values
        .any((m) => m.values.any((v) => v > 0));
    final hasRooms = hasRoomsAuto || hasRoomsManual;
    return b.floors != null && b.targetArea != null && hasRooms;
  }

  /// Этап 2 — «Планировка». Полная готовность означает:
  /// стены подобраны (материал и толщина), перекрытия подобраны, и если
  /// нужна лестница — подобрана и она. Сама планировка (чертежи) тут
  /// не требуется — она генерируется централизованно после подтверждения
  /// технического задания.
  static bool isPlanningComplete(HouseProject p) {
    final hasWalls = p.walls.isFilled;
    final hasSlabs = p.floorSlabs.isFilled;
    final hasStair = !p.includesStaircase || p.staircase.isFilled;
    return hasWalls && hasSlabs && hasStair;
  }

  /// Этап «Фундамент». Помимо самого выбора фундамента нужны и
  /// климато-геологические данные участка (грунт + снеговой/ветровой
  /// район). Фундамент идёт **последним** перед ТЗ, потому что только
  /// при известных нагрузках от стен/перекрытий и формы кровли можно
  /// корректно подобрать тип и сечение фундамента.
  static bool isFoundationComplete(HouseProject p) {
    final b = p.brief;
    final hasSite = b.region != null &&
        b.snowZone != null &&
        b.windZone != null &&
        b.soilLayers.any((l) => l.type != null);
    return hasSite && p.foundation.isFilled;
  }

  /// Этап «Кровля». Минимально нужны тип и угол (или явный «плоская»).
  /// Кровля идёт **раньше** фундамента: её снеговая и ветровая нагрузка
  /// влияют на нагрузку, которую фундамент должен воспринять.
  static bool isRoofComplete(HouseProject p) {
    final r = p.roof;
    if (!r.isFilled) return false;
    // Для плоской кровли угол не нужен, иначе нужен.
    if (r.type == 'flat') return true;
    return r.slopeAngle != null;
  }

  /// Полный список этапов в нужном порядке с метаданными для UI.
  static List<ProjectStageStatus> all(HouseProject p) {
    final stage1 = isInitialDataComplete(p);
    final stage2 = isPlanningComplete(p);
    final stageRoof = isRoofComplete(p);
    final stageFoundation = isFoundationComplete(p);
    return [
      ProjectStageStatus(
        id: ProjectStageId.initialData,
        title: 'Этап 1. Начальные данные',
        subtitle: _initialSubtitle(p),
        isComplete: stage1,
        isUnlocked: true,
      ),
      ProjectStageStatus(
        id: ProjectStageId.planning,
        title: 'Этап 2. Планировка',
        subtitle: _planningSubtitle(p),
        isComplete: stage2,
        isUnlocked: stage1,
      ),
      ProjectStageStatus(
        id: ProjectStageId.roof,
        title: 'Этап 3. Кровля',
        subtitle: _roofSubtitle(p),
        isComplete: stageRoof,
        isUnlocked: stage2,
      ),
      ProjectStageStatus(
        id: ProjectStageId.foundation,
        title: 'Этап 4. Фундамент',
        subtitle: _foundationSubtitle(p),
        isComplete: stageFoundation,
        isUnlocked: stageRoof,
      ),
      ProjectStageStatus(
        id: ProjectStageId.technicalSpec,
        title: 'Техническое задание и чертежи',
        subtitle: stageFoundation
            ? 'Подтвердите ТЗ — и сгенерируется комплект чертежей.'
            : 'Сформируется автоматически после завершения четырёх этапов.',
        isComplete: false,
        isUnlocked: stageFoundation,
      ),
      ProjectStageStatus(
        id: ProjectStageId.estimate,
        title: 'Смета',
        subtitle: stage2
            ? 'Объёмы работ, материалы, цены ₽/ед. с региональным '
                'коэффициентом — с возможностью править вручную.'
            : 'Появится, как только закончите этап «Планировка».',
        isComplete: false,
        isUnlocked: stage2,
      ),
    ];
  }

  static String _initialSubtitle(HouseProject p) {
    final b = p.brief;
    if (!b.isStarted) {
      return 'Площадь, состав комнат, этажность, материал стен.';
    }
    final parts = <String>[];
    if (b.floors != null) {
      parts.add('${b.floors!} эт.${b.hasMansard == true ? ' + мансарда' : ''}');
    }
    if (b.targetArea != null) {
      parts.add('${b.targetArea!.toStringAsFixed(0)} м²');
    }
    if (b.wallMaterial != null) parts.add(b.wallMaterial!.title);
    return parts.isEmpty ? 'Заполняется' : parts.join(' · ');
  }

  static String _planningSubtitle(HouseProject p) {
    final parts = <String>[];
    if (p.walls.isFilled) parts.add('Стены');
    if (p.floorSlabs.isFilled) parts.add('Перекрытия');
    if (p.includesStaircase && p.staircase.isFilled) parts.add('Лестница');
    if (parts.isEmpty) {
      return 'Стены, перекрытия, лестница (если нужна).';
    }
    return parts.join(' · ');
  }

  static String _foundationSubtitle(HouseProject p) {
    if (p.foundation.isFilled) return p.foundation.summary;
    return 'Грунт, снеговой и ветровой район, тип фундамента.';
  }

  static String _roofSubtitle(HouseProject p) {
    if (p.roof.isFilled) return p.roof.summary;
    return 'Тип кровли, угол ската, покрытие.';
  }
}
