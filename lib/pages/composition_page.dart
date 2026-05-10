import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/foundation_rationale.dart';
import '../models/house_project.dart';
import '../models/user_mode.dart';
import '../services/composition_planner.dart';
import '../state/app_state.dart';
import '../widgets/hints.dart';
import 'foundation/foundation_type_page.dart';
import 'roof_page.dart';
import 'staircase_page.dart';
import 'walls_page.dart';

/// Экран «Состав сооружения» — список конструктивных элементов проекта.
///
/// В режиме «Клиент» список **только для просмотра**: его автоматически
/// подбирает движок правил на основе технического задания, клиент не редактирует.
///
/// В режиме «Проектировщик» каждый элемент можно открыть и поменять
/// (как в визарде фундамента). После сохранения изменений по кнопке
/// «Перегенерировать чертежи» создаётся новая партия чертежей; старые
/// остаются в коллекции и видны на вкладке «Чертежи» ниже текущей.
class CompositionPage extends StatelessWidget {
  const CompositionPage({super.key, required this.projectId});

  final String projectId;

  HouseProject? _findProject(AppState state) {
    for (final p in state.projects) {
      if (p.id == projectId) return p;
    }
    return null;
  }

  Future<void> _regenerate(BuildContext context, HouseProject project) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    await state.regenerateDrawings(project);
    messenger.showSnackBar(
      const SnackBar(content: Text('Чертежи перегенерированы')),
    );
  }

  Future<void> _resetToAuto(
    BuildContext context,
    HouseProject project,
  ) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    await state.applyAutoComposition(project);
    messenger.showSnackBar(
      const SnackBar(content: Text('Применена рекомендация по техническому заданию')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final project = _findProject(state);
    final mode = state.mode ?? UserMode.client;
    if (project == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Состав сооружения')),
        body: const Center(child: Text('Проект не найден.')),
      );
    }

    final theme = Theme.of(context);
    final isClient = mode == UserMode.client;
    final briefStarted = project.brief.isStarted;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Состав сооружения'),
        actions: const [
          HintIconButton(
            title: 'Состав сооружения',
            sections: Hints.composition,
          ),
        ],
      ),
      body: HintAutoShow(
        screenKey: 'composition',
        title: 'Состав сооружения',
        sections: Hints.composition,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!briefStarted)
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Сначала заполните техническое задание клиента — состав '
                              'сооружения подберётся автоматически на его основе.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isClient
                                ? 'Решения подобраны автоматически по техническому заданию'
                                : 'Решения подобраны автоматически — можно править',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isClient
                                ? 'Состав сооружения сформирован программой '
                                    'на основе ваших пожеланий и не редактируется. '
                                    'Если хотите внести правки — обратитесь к '
                                    'проектировщику.'
                                : 'Изменяйте элементы по необходимости. После '
                                    'правок нажмите «Перегенерировать чертежи» — '
                                    'старые версии останутся в истории.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                _ElementCard(
                  title: 'Фундамент',
                  subtitle: project.foundation.summary,
                  done: project.foundation.isFilled,
                  icon: Icons.foundation_outlined,
                  readonly: isClient,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FoundationTypePage(projectId: project.id),
                    ),
                  ),
                ),
                if (!isClient && briefStarted)
                  _RationaleCard(
                    rationale: CompositionPlanner.plan(project.brief)
                        .foundationRationale,
                  ),
                const SizedBox(height: 8),
                _ElementCard(
                  title: 'Стены',
                  subtitle: project.walls.summary,
                  done: project.walls.isFilled,
                  icon: Icons.view_week_outlined,
                  readonly: isClient,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WallsPage(projectId: project.id),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _ElementCard(
                  title: 'Крыша',
                  subtitle: project.roof.summary,
                  done: project.roof.isFilled,
                  icon: Icons.roofing_outlined,
                  readonly: isClient,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RoofPage(projectId: project.id),
                    ),
                  ),
                ),
                if (project.includesStaircase) ...[
                  const SizedBox(height: 8),
                  _ElementCard(
                    title: 'Лестница',
                    subtitle: project.staircase.summary,
                    done: project.staircase.isFilled,
                    icon: Icons.stairs_outlined,
                    readonly: isClient,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StaircasePage(projectId: project.id),
                      ),
                    ),
                  ),
                ],
                if (!isClient && briefStarted) ...[
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () => _regenerate(context, project),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Перегенерировать чертежи'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _resetToAuto(context, project),
                    icon: const Icon(Icons.auto_fix_high_outlined),
                    label: const Text('Сбросить к рекомендации по техническому заданию'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Разворачивающийся блок «Обоснование автоподбора» для фундамента.
/// Показывается только в режиме «Проектировщик». По умолчанию свёрнут.
class _RationaleCard extends StatefulWidget {
  const _RationaleCard({required this.rationale});

  final FoundationRationale rationale;

  @override
  State<_RationaleCard> createState() => _RationaleCardState();
}

class _RationaleCardState extends State<_RationaleCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.rationale.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHigh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.menu_book_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Обоснование автоподбора (ссылки на СП)',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: theme.colorScheme.outline,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final item in widget.rationale.items)
                            _RationaleRow(item: item),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _RationaleRow extends StatelessWidget {
  const _RationaleRow({required this.item});

  final RationaleItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.text, style: theme.textTheme.bodyMedium),
                if (item.codeReference != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.codeReference!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ElementCard extends StatelessWidget {
  const _ElementCard({
    required this.title,
    required this.subtitle,
    required this.done,
    required this.icon,
    required this.readonly,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool done;
  final IconData icon;
  final bool readonly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trailing = readonly
        ? (done
            ? Icon(Icons.lock_outline, color: theme.colorScheme.outline)
            : Icon(Icons.hourglass_empty, color: theme.colorScheme.outline))
        : Icon(
            done ? Icons.check_circle : Icons.chevron_right,
            color: done ? theme.colorScheme.primary : null,
          );
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing: trailing,
        enabled: !readonly,
        onTap: readonly ? null : onTap,
      ),
    );
  }
}
