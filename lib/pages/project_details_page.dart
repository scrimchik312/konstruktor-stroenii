import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/house_project.dart';
import '../services/project_stages.dart';
import '../state/app_state.dart';
import '../widgets/hints.dart';
import 'brief_page.dart';
import 'estimate_page.dart';
import 'foundation/site_preliminaries_page.dart';
import 'roof_page.dart';
import 'stage_planning_page.dart';
import 'technical_spec_page.dart';

/// Главный экран проекта — четырёхэтапный мастер с финальной карточкой
/// «Техническое задание».
///
/// Этап доступен только тогда, когда предыдущий завершён. Это
/// продиктовано предметной областью: например, фундамент нельзя
/// корректно подобрать, не зная стен и перекрытий, а кровля — пока не
/// определены пролёты, опираемые ею. Список заблокированных карточек
/// помогает пользователю не «бегать» по разделам в произвольном порядке.
class ProjectDetailsPage extends StatelessWidget {
  const ProjectDetailsPage({super.key, required this.projectId});

  final String projectId;

  HouseProject? _findProject(AppState state) {
    for (final p in state.projects) {
      if (p.id == projectId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final project = _findProject(state);
    if (project == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Проект')),
        body: const Center(child: Text('Проект не найден.')),
      );
    }

    final theme = Theme.of(context);
    final stages = ProjectStages.all(project);

    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        actions: const [
          HintIconButton(
            title: 'Структура проекта',
            sections: Hints.projectDetails,
          ),
        ],
      ),
      body: HintAutoShow(
        screenKey: 'project-details',
        title: 'Структура проекта',
        sections: Hints.projectDetails,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.constructionType.title,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Проходите этапы по очереди — следующий этап '
                          'разблокируется, как только закончите текущий.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                for (final s in stages) ...[
                  _StageCard(
                    status: s,
                    onOpen: () => _openStage(context, project, s.id),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openStage(
    BuildContext context,
    HouseProject p,
    ProjectStageId id,
  ) {
    Widget page;
    switch (id) {
      case ProjectStageId.initialData:
        page = BriefPage(projectId: p.id);
        break;
      case ProjectStageId.planning:
        page = StagePlanningPage(projectId: p.id);
        break;
      case ProjectStageId.foundation:
        page = SitePreliminariesPage(projectId: p.id);
        break;
      case ProjectStageId.roof:
        page = RoofPage(projectId: p.id);
        break;
      case ProjectStageId.technicalSpec:
        page = TechnicalSpecPage(projectId: p.id);
        break;
      case ProjectStageId.estimate:
        page = EstimatePage(projectId: p.id);
        break;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}

class _StageCard extends StatelessWidget {
  const _StageCard({required this.status, required this.onOpen});

  final ProjectStageStatus status;
  final VoidCallback onOpen;

  IconData _iconFor(ProjectStageId id) {
    switch (id) {
      case ProjectStageId.initialData:
        return Icons.assignment_outlined;
      case ProjectStageId.planning:
        return Icons.draw_outlined;
      case ProjectStageId.foundation:
        return Icons.foundation_outlined;
      case ProjectStageId.roof:
        return Icons.roofing_outlined;
      case ProjectStageId.technicalSpec:
        return Icons.description_outlined;
      case ProjectStageId.estimate:
        return Icons.calculate_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLocked = !status.isUnlocked;
    final iconColor = isLocked
        ? theme.colorScheme.outline
        : theme.colorScheme.primary;
    final trailingIcon = isLocked
        ? Icons.lock_outline
        : (status.isComplete ? Icons.check_circle : Icons.chevron_right);
    final trailingColor = isLocked
        ? theme.colorScheme.outline
        : (status.isComplete ? theme.colorScheme.primary : null);

    return Card(
      child: Opacity(
        opacity: isLocked ? 0.55 : 1,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(_iconFor(status.id), color: iconColor),
          title: Text(status.title, style: theme.textTheme.titleMedium),
          subtitle: Text(
            isLocked
                ? 'Этап заблокирован: завершите предыдущий, чтобы '
                    'продолжить.'
                : status.subtitle,
          ),
          trailing: Icon(trailingIcon, color: trailingColor),
          onTap: isLocked ? null : onOpen,
        ),
      ),
    );
  }
}
