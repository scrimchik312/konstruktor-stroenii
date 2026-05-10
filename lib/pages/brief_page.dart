import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/client_brief.dart';
import '../models/house_project.dart';
import '../services/project_stages.dart';
import '../state/app_state.dart';
import 'brief/brief_wizard_page.dart';

/// Стартовая страница этапа 1 — «Начальные данные».
///
/// Показывает текущую сводку введённых начальных данных и кнопку запуска
/// визарда. После прохождения визарда автоматически разблокируется
/// этап 2 «Планировка».
class BriefPage extends StatelessWidget {
  const BriefPage({super.key, required this.projectId});

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
        appBar: AppBar(title: const Text('Начальные данные')),
        body: const Center(child: Text('Проект не найден.')),
      );
    }

    final theme = Theme.of(context);
    final brief = project.brief;
    final started = brief.isStarted;
    final complete = ProjectStages.isInitialDataComplete(project);

    return Scaffold(
      appBar: AppBar(title: const Text('Этап 1. Начальные данные')),
      body: Center(
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
                        complete
                            ? 'Начальные данные заполнены'
                            : started
                                ? 'Начальные данные заполняются'
                                : 'Начальные данные ещё не заполнены',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(brief.summary),
                      const SizedBox(height: 8),
                      Text(
                        'Шесть коротких шагов: этажность, площадь, состав '
                        'комнат, дополнения, ориентировочный материал стен '
                        'и особые пожелания. Грунт и климат на этом этапе '
                        'не запрашиваются — они появятся на этапе «Фундамент».',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        BriefWizardPage(projectId: project.id),
                  ),
                ),
                icon: Icon(started
                    ? Icons.edit_outlined
                    : Icons.play_arrow_outlined),
                label: Text(
                  started ? 'Продолжить заполнение' : 'Начать заполнение',
                ),
              ),
              if (complete) ...[
                const SizedBox(height: 8),
                Text(
                  _detailsSummary(brief),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _detailsSummary(ClientBrief brief) {
    final parts = <String>[];
    if (brief.floors != null) {
      final addons = <String>[];
      if (brief.hasMansard == true) addons.add('мансарда');
      if (brief.hasBasement == true) addons.add('подвал/цоколь');
      final addonStr = addons.isEmpty ? '' : ' + ${addons.join(' + ')}';
      parts.add('Этажей: ${brief.floors}$addonStr');
    }
    if (brief.targetArea != null) {
      parts.add('Площадь: ${brief.targetArea!.toStringAsFixed(0)} м²');
    }
    if (brief.footprintWidth != null && brief.footprintLength != null) {
      parts.add(
        'Габариты: ${brief.footprintWidth!.toStringAsFixed(0)}'
        '×${brief.footprintLength!.toStringAsFixed(0)} м',
      );
    }
    final rooms = brief.rooms.entries
        .where((e) => e.value > 0)
        .map((e) => '${e.key} ×${e.value}')
        .join(', ');
    if (rooms.isNotEmpty) parts.add('Комнаты: $rooms');
    if (brief.wallMaterial != null) {
      parts.add('Ориентир по стенам: ${brief.wallMaterial!.title}');
    }
    return parts.join('\n');
  }
}
