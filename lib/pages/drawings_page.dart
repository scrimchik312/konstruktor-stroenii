import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/building3d.dart';
import '../models/drawing.dart';
import '../models/floor_plan.dart';
import '../models/foundation_plan.dart';
import '../models/house_project.dart';
import '../models/title_page_info.dart';
import '../models/user_mode.dart';
import '../services/building3d_generator.dart';
import '../services/dxf_writer.dart';
import '../services/file_download.dart';
import '../services/pdf_a1_placard.dart';
import '../services/pdf_builder.dart';
import '../state/app_state.dart';
import '../widgets/building3d_view.dart';
import '../widgets/floor_plan_view.dart';
import '../widgets/foundation_plan_view.dart';
import '../widgets/hints.dart';
import 'floor_plan_editor_page.dart';

/// Экран «Чертежи».
///
/// Показывает все чертежи проекта, отсортированные по дате создания
/// (новые сверху). Старые партии остаются доступными — их можно листать
/// ниже. Чертежи типа [DrawingKind.schematicPlan] отрисовываются как
/// планы с комнатами; остальные — текстовое описание-заглушка.
class DrawingsPage extends StatelessWidget {
  const DrawingsPage({super.key, required this.projectId});

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
    final theme = Theme.of(context);

    if (project == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Чертежи')),
        body: const Center(child: Text('Проект не найден.')),
      );
    }

    if (project.drawings.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Чертежи'),
          actions: const [
            HintIconButton(
              title: 'Чертежи',
              sections: Hints.drawings,
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.draw_outlined,
                    size: 96,
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Чертежей пока нет',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Чертежи появятся здесь после прохождения этапа создания: '
                    'заполните техническое задание и состав сооружения, затем приложение '
                    'сгенерирует эскизы или рабочие чертежи в зависимости от '
                    'выбранного режима.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final batches = _groupByBatch(project.drawings.drawings);
    final mode = state.mode ?? UserMode.client;
    final canEdit = mode == UserMode.designer;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Чертежи'),
        actions: const [
          HintIconButton(
            title: 'Чертежи',
            sections: Hints.drawings,
          ),
        ],
      ),
      body: HintAutoShow(
        screenKey: 'drawings',
        title: 'Чертежи',
        sections: Hints.drawings,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: batches.length,
              itemBuilder: (context, i) {
                final batch = batches[i];
                return _BatchCard(
                  index: batches.length - i,
                  createdAt: batch.first.createdAt,
                  drawings: batch,
                  isLatest: i == 0,
                  project: project,
                  canEdit: canEdit,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<List<Drawing>> _groupByBatch(List<Drawing> drawings) {
    final batches = <List<Drawing>>[];
    for (final d in drawings) {
      if (batches.isEmpty || batches.last.first.createdAt != d.createdAt) {
        batches.add([d]);
      } else {
        batches.last.add(d);
      }
    }
    return batches;
  }
}

class _BatchCard extends StatefulWidget {
  const _BatchCard({
    required this.index,
    required this.createdAt,
    required this.drawings,
    required this.isLatest,
    required this.project,
    required this.canEdit,
  });

  final int index;
  final DateTime createdAt;
  final List<Drawing> drawings;
  final bool isLatest;
  final HouseProject project;
  final bool canEdit;

  @override
  State<_BatchCard> createState() => _BatchCardState();
}

class _BatchCardState extends State<_BatchCard> {
  // Свежая версия развёрнута по умолчанию, старые свёрнуты.
  late bool _expanded = widget.isLatest;
  bool _fixing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.isLatest
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: widget.isLatest ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(12),
            ),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Версия №${widget.index}',
                              style: theme.textTheme.titleMedium,
                            ),
                            if (widget.isLatest)
                              Chip(
                                label: const Text('текущая'),
                                visualDensity: VisualDensity.compact,
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                              ),
                            if (widget.drawings.any((d) => d.isManualEdit))
                              Chip(
                                label: const Text('ручная правка'),
                                visualDensity: VisualDensity.compact,
                                backgroundColor:
                                    theme.colorScheme.tertiaryContainer,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatDate(widget.createdAt)} · '
                          'листов: ${widget.drawings.length}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Предпросмотр PDF (без скачивания)',
                    icon: const Icon(Icons.visibility_outlined),
                    onPressed: _previewPdf,
                  ),
                  if (widget.isLatest)
                    IconButton(
                      tooltip: 'Скачать комплект (PDF/DXF)',
                      icon: const Icon(Icons.download_outlined),
                      onPressed: _showExportDialog,
                    ),
                  IconButton(
                    tooltip: _expanded ? 'Свернуть' : 'Развернуть',
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
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
                        // §17.2.3 — баннер проектных предупреждений
                        // (например, недостижимые комнаты).
                        if (widget.isLatest &&
                            widget.project.warnings.isNotEmpty)
                          Card(
                            color: theme.colorScheme.errorContainer
                                .withValues(alpha: 0.3),
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        color: theme.colorScheme.error,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Предупреждения '
                                        '(${widget.project.warnings.length})',
                                        style: theme.textTheme.titleSmall,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  for (final w in widget.project.warnings)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 2),
                                      child: Text(
                                        '• $w',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed:
                                          _fixing ? null : _autoFixLayout,
                                      icon: _fixing
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.auto_fix_high),
                                      label: Text(_fixing
                                          ? 'Исправляем…'
                                          : 'Исправить'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (widget.isLatest)
                          _Building3DTile(
                            project: widget.project,
                            drawings: widget.drawings,
                          ),
                        for (final d in widget.drawings)
                          _DrawingTile(
                            drawing: d,
                            project: widget.project,
                            canEdit: widget.canEdit && widget.isLatest,
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Future<void> _showExportDialog() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Скачать комплект'),
        content: const Text(
          'Выберите формат:\n'
          '• PDF — A3 ландшафт, по листу на этаж, с рамкой и штампом.\n'
          '• Планшет А1 — маркетинговый разворот (Phase-3b §17.2.4).\n'
          '• DXF — векторный обмен с CAD (AutoCAD, LibreCAD, QCAD).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Отмена'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop('dxf'),
            child: const Text('DXF'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop('a1'),
            child: const Text('А1'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('pdf'),
            child: const Text('PDF'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    try {
      if (choice == 'pdf') {
        // Перед генерацией PDF показываем редактор титульного листа,
        // чтобы пользователь мог скорректировать наименование объекта,
        // шифр, альбом, стадию, город и год.
        final ok = await _editTitlePage();
        if (!ok) return;
        await _exportPdf();
      } else if (choice == 'a1') {
        // §17.2.4 / open-backlog A1: единый планшет А1 на всю
        // композицию проекта (планы, аксонометрия, фасады, ТЭП).
        await _exportA1Placard();
      } else if (choice == 'dxf') {
        await _exportDxf();
      }
    } catch (e, stackTrace) {
      debugPrint('Export error: $e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить файл: $e')),
      );
    }
  }

  /// Phase-3b §17.2.4 — выгрузка отдельного PDF-планшета А1.
  /// Использует [PdfA1Placard.buildDocument]; не зависит от основного
  /// `PdfBuilder.buildBatch`. Имя файла — `<name>_A1_v<n>.pdf`.
  Future<void> _exportA1Placard() async {
    final organization = context.read<AppState>().organization;
    // Декодируем планы из drawings: payload содержит JSON FloorPlan-а.
    final plans = <FloorPlan>[];
    for (final d in widget.drawings) {
      if (d.kind != DrawingKind.schematicPlan) continue;
      final p = FloorPlan.tryDecode(d.payload);
      if (p != null) plans.add(p);
    }
    final bytes = await PdfA1Placard.buildDocument(
      project: widget.project,
      plans: plans,
      versionNumber: widget.index,
      organization: organization,
    );
    final filename = _safeFileName(
      '${widget.project.name}_A1_v${widget.index}',
      'pdf',
    );
    await FileDownload.downloadBytes(
      bytes: bytes,
      filename: filename,
      mimeType: 'application/pdf',
    );
  }

  /// Показывает диалог редактирования титульного листа альбома (поля:
  /// наименование объекта, шифр, альбом, стадия, город, год). Сохраняет
  /// результат в `project.titlePage` через `AppState.saveProject(...)`,
  /// чтобы поля переживали перезагрузку. Возвращает `true`, если
  /// пользователь согласился сгенерировать PDF, и `false` при отмене.
  Future<bool> _editTitlePage() async {
    final result = await showDialog<TitlePageInfo>(
      context: context,
      builder: (ctx) => _TitlePageEditorDialog(initial: widget.project.titlePage),
    );
    if (result == null) return false;
    widget.project.titlePage = result;
    widget.project.touch();
    if (mounted) {
      await context.read<AppState>().saveProject(widget.project);
    }
    return true;
  }

  Future<void> _exportPdf() async {
    final organization = context.read<AppState>().organization;
    final bytes = await PdfBuilder.buildBatch(
      project: widget.project,
      drawings: widget.drawings,
      versionNumber: widget.index,
      organization: organization,
    );
    final filename = _safeFileName(
      '${widget.project.name}_v${widget.index}',
      'pdf',
    );
    await FileDownload.downloadBytes(
      bytes: bytes,
      filename: filename,
      mimeType: 'application/pdf',
    );
  }

  Future<void> _previewPdf() async {
    try {
      // Перед предпросмотром также даём пользователю возможность
      // скорректировать титульный лист.
      final ok = await _editTitlePage();
      if (!ok) return;
      final organization = context.read<AppState>().organization;
      final bytes = await PdfBuilder.buildBatch(
        project: widget.project,
        drawings: widget.drawings,
        versionNumber: widget.index,
        organization: organization,
      );
      await FileDownload.previewBytes(bytes: bytes);
    } catch (e, stackTrace) {
      debugPrint('PDF preview error: $e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть предпросмотр: $e')),
      );
    }
  }

  Future<void> _autoFixLayout() async {
    setState(() => _fixing = true);
    try {
      final appState = context.read<AppState>();
      await appState.regenerateDrawings(widget.project, autoFix: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.project.warnings.isEmpty
                ? 'Планировка исправлена — нарушений нет'
                : 'Планировка перегенерирована '
                    '(${widget.project.warnings.length} предупр.)',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось исправить: $e')),
      );
    } finally {
      if (mounted) setState(() => _fixing = false);
    }
  }

  Future<void> _exportDxf() async {
    // Если этажей > 1 — отдаём ZIP не реализуем здесь, выгрузим первый
    // схематический план, остальные пользователь может скачать отдельно
    // открыв старые версии. Чтобы не делать ZIP-зависимость, сгенерируем
    // несколько файлов друг за другом — браузер откроет столько диалогов
    // сохранения, сколько листов.
    var n = 0;
    for (final d in widget.drawings) {
      if (d.kind != DrawingKind.schematicPlan) continue;
      final plan = FloorPlan.tryDecode(d.payload);
      if (plan == null) continue;
      final dxf = DxfWriter.write(
        plan,
        title: '${widget.project.name} · ${plan.floorLabel} · v${widget.index}',
      );
      final filename = _safeFileName(
        '${widget.project.name}_v${widget.index}_${plan.floorLabel}',
        'dxf',
      );
      await FileDownload.downloadText(
        content: dxf,
        filename: filename,
        mimeType: 'application/dxf',
      );
      n++;
    }
    if (n == 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет схематических планов для DXF.')),
      );
    }
  }

  String _safeFileName(String base, String ext) {
    final cleaned = base
        .replaceAll(RegExp(r'[^\p{L}\p{N}_\-]+', unicode: true), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    return '$cleaned.$ext';
  }
}

class _DrawingTile extends StatelessWidget {
  const _DrawingTile({
    required this.drawing,
    required this.project,
    required this.canEdit,
  });

  final Drawing drawing;
  final HouseProject project;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (drawing.kind == DrawingKind.foundationPlan) {
      final model = FoundationPlanModel.tryDecode(drawing.payload);
      if (model != null) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(drawing.title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                drawing.kind.title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _FullscreenFoundationPage(
                      title: drawing.title,
                      model: model,
                    ),
                  ),
                ),
                child: FoundationPlanView(model: model),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Нажмите план, чтобы увеличить',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }
    if (drawing.kind == DrawingKind.schematicPlan) {
      final plan = FloorPlan.tryDecode(drawing.payload);
      if (plan != null) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      drawing.title,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (canEdit)
                    TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FloorPlanEditorPage(
                            project: project,
                            drawingId: drawing.id,
                            initialPlan: plan,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Редактировать'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                drawing.kind.title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _FullscreenPlanPage(
                      title: drawing.title,
                      plan: plan,
                    ),
                  ),
                ),
                child: FloorPlanView(plan: plan),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Нажмите план, чтобы увеличить',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.description_outlined),
      title: Text(drawing.title),
      subtitle: Text(
        '${drawing.kind.title}'
        '${drawing.payload.isEmpty ? '' : '\n${drawing.payload}'}',
      ),
      isThreeLine: drawing.payload.isNotEmpty,
    );
  }
}

class _FullscreenPlanPage extends StatelessWidget {
  const _FullscreenPlanPage({required this.title, required this.plan});

  final String title;
  final FloorPlan plan;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: FloorPlanView(plan: plan),
          ),
        ),
      ),
    );
  }
}

class _FullscreenFoundationPage extends StatelessWidget {
  const _FullscreenFoundationPage(
      {required this.title, required this.model});

  final String title;
  final FoundationPlanModel model;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: FoundationPlanView(model: model),
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}.${two(dt.month)}.${dt.year} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

/// Карточка с интерактивной 3D-моделью дома.
///
/// Показывается только для самой свежей партии, поскольку модель
/// собирается напрямую из текущих параметров проекта (а не из
/// отдельной [Drawing]-записи). По клику открывается полноэкранный
/// вид с orbit-камерой.
class _Building3DTile extends StatelessWidget {
  const _Building3DTile({required this.project, required this.drawings});

  final HouseProject project;
  final List<Drawing> drawings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 3D-модель строится по реальным планам пользователя из текущей
    // партии чертежей — это синхронизирует проёмы в 3D и на 2D-планах.
    final userPlans = <FloorPlan>[];
    for (final d in drawings) {
      if (d.kind != DrawingKind.schematicPlan) continue;
      final plan = FloorPlan.tryDecode(d.payload);
      if (plan != null) userPlans.add(plan);
    }
    final model = Building3DGenerator.generate(
      project,
      floorPlans: userPlans.isEmpty ? null : userPlans,
    );
    if (model == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Общий вид (3D)', style: theme.textTheme.titleSmall),
              const SizedBox(width: 8),
              const Icon(Icons.threed_rotation_outlined, size: 18),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Аксонометрическая модель здания, '
            '${model.foundation.typeLabel.toLowerCase()}, '
            '${model.roof.typeLabel.toLowerCase()}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    _Fullscreen3DPage(title: 'Общий вид · 3D', model: model),
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(8),
              child: Building3DView(model: model),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Тяните для поворота · колесо мыши — масштаб · '
              'нажмите, чтобы развернуть',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Fullscreen3DPage extends StatelessWidget {
  const _Fullscreen3DPage({required this.title, required this.model});

  final String title;
  final Building3D model;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Building3DView(
          model: model,
          aspectRatio: MediaQuery.of(context).size.width /
              MediaQuery.of(context).size.height,
          initialYawDegrees: 35,
          initialPitchDegrees: 25,
        ),
      ),
    );
  }
}

/// Диалог редактирования реквизитов титульного листа альбома (наименование
/// объекта, шифр, альбом, стадия, город, год). Возвращает обновлённый
/// `TitlePageInfo` через `Navigator.pop`, либо `null` при отмене.
class _TitlePageEditorDialog extends StatefulWidget {
  const _TitlePageEditorDialog({required this.initial});

  final TitlePageInfo initial;

  @override
  State<_TitlePageEditorDialog> createState() =>
      _TitlePageEditorDialogState();
}

class _TitlePageEditorDialogState extends State<_TitlePageEditorDialog> {
  late final TextEditingController _objectTitle;
  late final TextEditingController _code;
  late final TextEditingController _albumName;
  late final TextEditingController _stage;
  late final TextEditingController _city;
  late final TextEditingController _year;

  @override
  void initState() {
    super.initState();
    _objectTitle = TextEditingController(text: widget.initial.objectTitle);
    _code = TextEditingController(text: widget.initial.code);
    _albumName = TextEditingController(text: widget.initial.albumName);
    _stage = TextEditingController(text: widget.initial.stage);
    _city = TextEditingController(text: widget.initial.city);
    _year = TextEditingController(text: widget.initial.year.toString());
  }

  @override
  void dispose() {
    _objectTitle.dispose();
    _code.dispose();
    _albumName.dispose();
    _stage.dispose();
    _city.dispose();
    _year.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Титульный лист альбома'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _objectTitle,
                decoration: const InputDecoration(
                  labelText: 'Наименование объекта',
                  helperText: 'Например: «Индивидуальный жилой дом»',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                decoration: const InputDecoration(
                  labelText: 'Шифр',
                  helperText: 'Например: «29/01-2010-АС»',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _albumName,
                decoration: const InputDecoration(
                  labelText: 'Наименование альбома',
                  helperText: 'Например: «Архитектурно-строительная часть»',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _stage,
                decoration: const InputDecoration(
                  labelText: 'Стадия',
                  helperText:
                      'Проектная документация / Рабочая документация / Рабочий проект',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _city,
                decoration: const InputDecoration(labelText: 'Город'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _year,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Год'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final year = int.tryParse(_year.text.trim()) ??
                widget.initial.year;
            Navigator.of(context).pop(
              TitlePageInfo(
                objectTitle: _objectTitle.text.trim().isEmpty
                    ? widget.initial.objectTitle
                    : _objectTitle.text.trim(),
                code: _code.text.trim(),
                albumName: _albumName.text.trim().isEmpty
                    ? widget.initial.albumName
                    : _albumName.text.trim(),
                stage: _stage.text.trim().isEmpty
                    ? widget.initial.stage
                    : _stage.text.trim(),
                city: _city.text.trim().isEmpty
                    ? widget.initial.city
                    : _city.text.trim(),
                year: year,
              ),
            );
          },
          child: const Text('Сгенерировать PDF'),
        ),
      ],
    );
  }
}
