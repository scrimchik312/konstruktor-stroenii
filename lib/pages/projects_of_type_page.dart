import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/construction_type.dart';
import '../models/house_project.dart';
import '../state/app_state.dart';
import 'project_create_page.dart';
import 'project_details_page.dart';
import 'settings_page.dart';

const Map<ConstructionType, IconData> _typeIcons = {
  ConstructionType.privateHouse: Icons.cottage_outlined,
  ConstructionType.apartmentBuilding: Icons.apartment_outlined,
  ConstructionType.commercialBuilding: Icons.store_mall_directory_outlined,
  ConstructionType.commercialStructure: Icons.warehouse_outlined,
  ConstructionType.metalStructure: Icons.precision_manufacturing_outlined,
};

/// Страница «Проекты <тип>». Показывает существующие проекты выбранного
/// типа и боковое меню с быстрыми действиями (новый проект, настройки и т.д.).
class ProjectsOfTypePage extends StatelessWidget {
  const ProjectsOfTypePage({super.key, required this.type});

  final ConstructionType type;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final projects = state.projects
        .where((p) => p.constructionType == type)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_typeIcons[type] ?? Icons.business_outlined),
            const SizedBox(width: 8),
            Text(type.title),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final isWide = c.maxWidth >= 720;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SideMenu(type: type),
                const VerticalDivider(width: 1),
                Expanded(child: _ProjectsList(type: type, projects: projects)),
              ],
            );
          }
          return Column(
            children: [
              _SideMenu(type: type, compact: true),
              const Divider(height: 1),
              Expanded(child: _ProjectsList(type: type, projects: projects)),
            ],
          );
        },
      ),
    );
  }
}

class _SideMenu extends StatelessWidget {
  const _SideMenu({required this.type, this.compact = false});

  final ConstructionType type;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = compact ? double.infinity : 240.0;
    return Container(
      width: width,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            FilledButton.icon(
              onPressed: type.isImplemented
                  ? () => _newProject(context)
                  : () => _showSoonDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Новый проект'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            _MenuTile(
              icon: Icons.home_outlined,
              label: 'На главную',
              onTap: () => Navigator.pop(context),
            ),
            _MenuTile(
              icon: Icons.settings_outlined,
              label: 'Настройки',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
            ),
            _MenuTile(
              icon: Icons.help_outline,
              label: 'Инструкция',
              onTap: () => _showInstructions(context),
            ),
            _MenuTile(
              icon: Icons.info_outline,
              label: 'О приложении',
              onTap: () => _showAbout(context),
            ),
            if (!compact) const Spacer(),
            if (!compact)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Все данные хранятся локально в браузере.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _newProject(BuildContext context) async {
    final state = context.read<AppState>();
    final project = await Navigator.push<HouseProject>(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectCreatePage(initialType: type),
      ),
    );
    if (project == null || !context.mounted) return;
    await state.saveProject(project);
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: 'project-details'),
        builder: (_) => ProjectDetailsPage(projectId: project.id),
      ),
    );
  }

  void _showSoonDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(type.title),
        content: const Text(
          'Этот тип сооружения ещё в разработке. Сейчас полностью '
          'реализован только частный дом — на нём можно пройти весь поток '
          'техническое задание → чертежи → расчёт фундамента → пояснительная '
          'записка.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  void _showInstructions(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Инструкция'),
        content: const SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Text(
              '1. Создайте проект кнопкой «Новый проект» слева.\n'
              '2. Заполните техническое задание из 8 шагов.\n'
              '3. Получите состав сооружения (фундамент, стены, кровля, '
              'лестница) — подбирается автоматически.\n'
              '4. Откройте раздел «Чертежи»: план этажа в PDF/DXF.\n'
              '5. В разделе «Состав → Фундамент» рассчитайте нагрузки '
              'и подберите сечение.\n'
              '6. Скачайте пояснительную записку (PDF) к расчёту фундамента.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    // Используем собственный диалог вместо стандартного showAboutDialog,
    // чтобы убрать кнопку «View Licenses» — она нерелевантна для конечных
    // пользователей и не локализована.
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('О приложении'),
        content: const SizedBox(
          width: 480,
          child: Text(
            'Конструктор строений · beta\n\n'
            'Расчёты по СП 20/22/63. Чертежи в PDF/DXF. Все данные — '
            'локально в браузере.\n\n'
            'Веб-демо: scrim4344-droid.github.io/construction-calculator',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class _ProjectsList extends StatelessWidget {
  const _ProjectsList({required this.type, required this.projects});

  final ConstructionType type;
  final List<HouseProject> projects;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (projects.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _typeIcons[type] ?? Icons.folder_open_outlined,
                  size: 64,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  'Ваш первый проект появится здесь',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  type.isImplemented
                      ? 'Нажмите «Новый проект» слева, чтобы создать первый '
                          'проект (${type.title.toLowerCase()}).'
                      : 'Этот тип сооружения ещё в разработке. Полностью '
                          'реализован только частный дом.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: projects.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ProjectTile(project: projects[i]),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project});

  final HouseProject project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(_typeIcons[project.constructionType] ??
            Icons.home_work_outlined),
        title: Text(project.name, style: theme.textTheme.titleMedium),
        subtitle: Text(
          'Обновлён ${_formatDate(project.updatedAt)}',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'rename':
                _rename(context);
                break;
              case 'delete':
                _delete(context);
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Переименовать')),
            PopupMenuItem(value: 'delete', child: Text('Удалить')),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            settings: const RouteSettings(name: 'project-details'),
            builder: (_) => ProjectDetailsPage(projectId: project.id),
          ),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final state = context.read<AppState>();
    final controller = TextEditingController(text: project.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать проект'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await state.renameProject(project.id, name);
  }

  Future<void> _delete(BuildContext context) async {
    final state = context.read<AppState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить проект?'),
        content: Text(
          'Проект «${project.name}» будет удалён без возможности '
          'восстановления.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await state.deleteProject(project.id);
  }
}

String _formatDate(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}.${two(dt.month)}.${dt.year} '
      '${two(dt.hour)}:${two(dt.minute)}';
}
