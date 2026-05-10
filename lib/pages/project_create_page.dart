import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/floor_plan_templates.dart';
import '../models/construction_type.dart';
import '../state/app_state.dart';
import '../widgets/hints.dart';
import 'floor_plan_templates_page.dart';

/// Экран создания нового проекта. Спрашиваем название и тип конструкции.
/// Возвращает созданный проект через `Navigator.pop(context, project)`.
class ProjectCreatePage extends StatefulWidget {
  const ProjectCreatePage({super.key, this.initialType});

  /// Тип сооружения, выбранный на главной. Используется как стартовое
  /// значение радио-группы. Если `null`, по умолчанию частный дом.
  final ConstructionType? initialType;

  @override
  State<ProjectCreatePage> createState() => _ProjectCreatePageState();
}

class _ProjectCreatePageState extends State<ProjectCreatePage> {
  final _name = TextEditingController(text: 'Дом клиента');
  late ConstructionType _type =
      widget.initialType ?? ConstructionType.privateHouse;
  bool _saving = false;

  /// Выбранный шаблон планировки. `null` = «без шаблона», бриф
  /// останется пустым и пользователь заполнит его в визарде Этапа 1.
  FloorPlanTemplate? _template;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickTemplate() async {
    final picked = await Navigator.push<FloorPlanTemplate>(
      context,
      MaterialPageRoute(
        builder: (_) => FloorPlanTemplatesPage(initial: _template),
      ),
    );
    if (picked == null) return;
    setState(() => _template = picked);
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    final state = context.read<AppState>();
    final project = await state.createProject(name: name, type: _type);
    final t = _template;
    if (t != null) {
      // Применяем пресет к брифу + опциональный полигональный footprint.
      t.applyTo(project.brief);
      if (t.footprint != null) {
        project.architectureFootprint = t.footprint;
      }
      await state.saveProject(project);
    }
    if (!mounted) return;
    Navigator.pop(context, project);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новый проект'),
        actions: const [
          HintIconButton(
            title: 'Новый проект',
            sections: Hints.projectCreate,
          ),
        ],
      ),
      body: HintAutoShow(
        screenKey: 'project-create',
        title: 'Новый проект',
        sections: Hints.projectCreate,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Text('Название проекта', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Например: «Дом для семьи Ивановых»',
                  ),
                ),
                const SizedBox(height: 16),
                // Тип сооружения уже выбран на главном экране (через карточку
                // типа), поэтому здесь его повторно не спрашиваем — только
                // показываем как информационную плашку.
                if (widget.initialType == null) ...[
                  const SizedBox(height: 8),
                  Text('Тип конструкции', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final type in ConstructionType.values)
                    RadioListTile<ConstructionType>(
                      value: type,
                      groupValue: _type,
                      onChanged: type.isImplemented
                          ? (v) => setState(() => _type = v ?? _type)
                          : null,
                      title: Row(
                        children: [
                          Expanded(child: Text(type.title)),
                          if (!type.isImplemented)
                            Text(
                              'скоро',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                        ],
                      ),
                    ),
                ] else ...[
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.home_work_outlined,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Тип сооружения',
                                    style: theme.textTheme.bodySmall),
                                Text(_type.title,
                                    style: theme.textTheme.titleMedium),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // Phase-3b §17.2.2: выбор готовой планировки из каталога
                // (12 архетипов). Шаблон необязателен — если пропустить,
                // пользователь заполнит бриф в визарде Этапа 1.
                Text('Готовая планировка (необязательно)',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                _TemplateBanner(
                  template: _template,
                  onPick: _pickTemplate,
                  onClear: () => setState(() => _template = null),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _saving ? null : _create,
                  child: const Text('Создать проект'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Виджет-баннер выбранного шаблона: либо «выберите шаблон», либо
/// карточка с заголовком/описанием/составом и кнопками
/// «Сменить» / «Убрать».
class _TemplateBanner extends StatelessWidget {
  final FloorPlanTemplate? template;
  final VoidCallback onPick;
  final VoidCallback onClear;
  const _TemplateBanner({
    required this.template,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = template;
    if (t == null) {
      return OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.architecture_outlined),
        label: const Text('Выбрать из каталога (12 шаблонов)'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      );
    }
    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.architecture_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title, style: theme.textTheme.titleMedium),
                      Text(t.tagline, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(t.description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                Chip(
                    label: Text('${t.footprintWidth.toStringAsFixed(0)} × '
                        '${t.footprintLength.toStringAsFixed(0)} м')),
                Chip(label: Text('${t.floors} эт.')),
                if (t.hasMansard) const Chip(label: Text('+ мансарда')),
                if (t.hasBasement) const Chip(label: Text('+ подвал')),
                if (t.hasGarage) const Chip(label: Text('+ гараж')),
                if (t.footprint != null) const Chip(label: Text('L-форма')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onPick,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Сменить'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                  label: const Text('Убрать'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
