import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/house_project.dart';
import '../services/project_stages.dart';
import '../state/app_state.dart';
import '../widgets/hints.dart';
import 'floor_slabs_page.dart';
import 'roof_page.dart';
import 'stage_navigation.dart';
import 'staircase_page.dart';
import 'walls_page.dart';

/// Этап 2 — «Планировка».
///
/// Содержит подразделы: стены, перекрытия, лестница (если этажей больше
/// одного или явный запрос). На этом этапе фиксируются материалы и
/// геометрия строения дома. Сами чертежи планировки **не** генерируются
/// здесь — они собираются автоматически на финальном этапе ТЗ после
/// нажатия «Подтвердить ТЗ и сгенерировать чертежи».
class StagePlanningPage extends StatelessWidget {
  const StagePlanningPage({super.key, required this.projectId});

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
    final p = _findProject(state);
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Планировка')),
        body: const Center(child: Text('Проект не найден.')),
      );
    }

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Этап 2. Планировка'),
        actions: const [
          HintIconButton(
            title: 'Этап 2: что делаем',
            sections: Hints.stagePlanning,
          ),
        ],
      ),
      body: HintAutoShow(
        screenKey: 'stage-planning',
        title: 'Этап 2: что делаем',
        sections: Hints.stagePlanning,
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
                    child: Text(
                      'На этом этапе зафиксируйте материалы и геометрию '
                      'строения. Чертежи планировки соберутся автоматически '
                      'после кнопки «Подтвердить ТЗ» в финальном этапе.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _SubsectionCard(
                  title: 'Стены',
                  subtitle: p.walls.summary,
                  done: p.walls.isFilled,
                  icon: Icons.view_column_outlined,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WallsPage(projectId: p.id),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _SubsectionCard(
                  title: 'Перекрытия',
                  subtitle: p.floorSlabs.summary,
                  done: p.floorSlabs.isFilled,
                  icon: Icons.horizontal_rule_outlined,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FloorSlabsPage(projectId: p.id),
                    ),
                  ),
                ),
                if (p.includesStaircase) ...[
                  const SizedBox(height: 8),
                  _SubsectionCard(
                    title: 'Лестница',
                    subtitle: p.staircase.summary,
                    done: p.staircase.isFilled,
                    icon: Icons.stairs_outlined,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StaircasePage(projectId: p.id),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (ProjectStages.isPlanningComplete(p))
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.roofing_outlined),
                    label: const Text('Перейти к этапу 3: Кровля'),
                    onPressed: () => StageNavigation.jumpToStage(
                      context,
                      RoofPage(projectId: p.id),
                    ),
                  )
                else
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Когда заполнены стены, перекрытия и лестница '
                        '(если нужна), откроется этап «Кровля».',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubsectionCard extends StatelessWidget {
  const _SubsectionCard({
    required this.title,
    required this.subtitle,
    required this.done,
    required this.icon,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final bool done;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing: Icon(
          done ? Icons.check_circle : Icons.chevron_right,
          color: done ? theme.colorScheme.primary : null,
        ),
        onTap: onTap,
      ),
    );
  }
}
