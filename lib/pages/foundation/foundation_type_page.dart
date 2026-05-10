import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/foundation.dart';
import '../../models/house_project.dart';
import '../../services/composition_planner.dart';
import '../../state/app_state.dart';
import '../../widgets/hints.dart';
import 'foundation_device_page.dart';

/// Шаг 1 раздела «Фундамент»: выбор типа фундамента.
///
/// Получает на вход идентификатор проекта; всё чтение/запись идёт через
/// [AppState], чтобы данные сохранялись в общем хранилище и автоматически
/// синхронизировались с другими экранами.
class FoundationTypePage extends StatelessWidget {
  const FoundationTypePage({super.key, required this.projectId});

  final String projectId;

  HouseProject? _findProject(AppState state) {
    for (final p in state.projects) {
      if (p.id == projectId) return p;
    }
    return null;
  }

  Future<void> _selectType(BuildContext context, FoundationType type) async {
    final state = context.read<AppState>();
    final project = _findProject(state);
    if (project == null) return;

    // Если выбор отличается от рекомендованного — предупреждаем.
    final recommended =
        CompositionPlanner.recommendedFoundationType(project.brief);
    if (type != recommended) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Не рекомендованный тип фундамента'),
          content: Text(
            'По заданным грунтам и параметрам здания рекомендуется '
            '«${recommended.title}». '
            'Выбранный тип «${type.title}» может потребовать дополнительного '
            'обоснования и привести к завышенным осадкам или удорожанию.\n\n'
            'Продолжить с этим типом?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Вернуться к выбору'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Использовать выбранный'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    // Если пользователь поменял тип — сбрасываем подвыборы, иначе
    // оставляем как есть (пусть RadioListTile подхватит сохранённое).
    if (project.foundation.type != type) {
      project.foundation.type = type;
      project.foundation.device = null;
      project.foundation.grillageMaterial = null;
      await state.saveProject(project);
    }

    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FoundationDevicePage(projectId: projectId),
      ),
    );

    // Возвращаемся на экран проекта, минуя выбор типа: пользователь уже
    // зафиксировал свой выбор на следующем шаге.
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final project = _findProject(state);
    final selectedType = project?.foundation.type;
    final recommended = project == null
        ? null
        : CompositionPlanner.recommendedFoundationType(project.brief);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Тип фундамента'),
        actions: const [
          HintIconButton(
            title: 'Параметры фундамента',
            sections: Hints.foundationWizard,
          ),
        ],
      ),
      body: HintAutoShow(
        screenKey: 'foundation-type',
        title: 'Параметры фундамента',
        sections: Hints.foundationWizard,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Выберите тип фундамента',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
                if (recommended != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Рекомендация на основании слоёв грунта и параметров '
                      'здания (СП 22.13330.2016, СП 24.13330.2021, СП 50-101) — '
                      'отмечена стрелкой.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ),
                for (final type in FoundationType.values) ...[
                  _FoundationTypeCard(
                    type: type,
                    selected: selectedType == type,
                    isRecommended: recommended == type,
                    onTap: () => _selectType(context, type),
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
}

class _FoundationTypeCard extends StatelessWidget {
  const _FoundationTypeCard({
    required this.type,
    required this.selected,
    required this.isRecommended,
    required this.onTap,
  });

  final FoundationType type;
  final bool selected;
  final bool isRecommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = isRecommended
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : (isRecommended
                  ? accent.withValues(alpha: 0.6)
                  : theme.colorScheme.outlineVariant),
          width: selected || isRecommended ? 2 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: isRecommended
            ? Tooltip(
                message: 'Рекомендуется по СП — оптимальный вариант '
                    'для заданных грунтов',
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: accent,
                  size: 28,
                ),
              )
            : null,
        title: Row(
          children: [
            Expanded(
              child: Text(type.title, style: theme.textTheme.titleMedium),
            ),
            if (isRecommended)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.5)),
                ),
                child: Text(
                  'Рекомендуем',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(type.description),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
