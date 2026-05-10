import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/rooms_catalog.dart';
import '../data/wall_materials.dart';
import '../models/house_project.dart';
import '../services/file_download.dart';
import '../services/rafters_explanation_pdf.dart';
import '../services/technical_spec_pdf.dart';
import '../services/thermal_explanation_pdf.dart';
import '../state/app_state.dart';
import '../widgets/hints.dart';
import 'drawings_page.dart';
import 'foundation/foundation_loads_page.dart';

/// Финальный экран — «Техническое задание».
///
/// Сюда сходятся ответы и решения со всех четырёх этапов: начальные данные
/// клиента, планировка строения, кровля и фундамент. На выходе —
/// готовый комплект документации (PDF/DXF), который ниже и предлагается
/// скачать.
///
/// Чертежи (планы этажей) генерируются здесь же по кнопке
/// «Подтвердить ТЗ и сгенерировать чертежи». До этого у пользователя
/// собраны только параметры — само графическое представление появляется
/// одним действием на финальном экране, чтобы все этапы успели
/// зафиксироваться целостно.
class TechnicalSpecPage extends StatefulWidget {
  const TechnicalSpecPage({super.key, required this.projectId});

  final String projectId;

  @override
  State<TechnicalSpecPage> createState() => _TechnicalSpecPageState();
}

class _TechnicalSpecPageState extends State<TechnicalSpecPage> {
  bool _generating = false;

  HouseProject? _findProject(AppState state) {
    for (final p in state.projects) {
      if (p.id == widget.projectId) return p;
    }
    return null;
  }

  Future<void> _confirmAndGenerate(
      BuildContext context, HouseProject p) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _generating = true);
    try {
      await state.regenerateDrawings(p);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Техническое задание подтверждено. Чертежи сгенерированы.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось сгенерировать чертежи: $e')),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = _findProject(state);
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Техническое задание и чертежи')),
        body: const Center(child: Text('Проект не найден.')),
      );
    }

    final theme = Theme.of(context);
    final hasDrawings = !p.drawings.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Техническое задание и чертежи'),
        actions: const [
          HintIconButton(
            title: 'Что такое техническое задание',
            sections: Hints.technicalSpec,
          ),
        ],
      ),
      body: HintAutoShow(
        screenKey: 'technical-spec',
        title: 'Что такое техническое задание',
        sections: Hints.technicalSpec,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: theme.colorScheme.tertiaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      hasDrawings
                          ? 'Все четыре этапа пройдены, ТЗ подтверждено и '
                              'чертежи сгенерированы. Можно скачивать ТЗ '
                              'и комплект чертежей.'
                          : 'Все четыре этапа пройдены. Проверьте сводку '
                              'ниже и нажмите «Подтвердить ТЗ» — после '
                              'этого автоматически соберутся чертежи '
                              'планов этажей.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _SectionTile(
                  title: 'Этап 1. Начальные данные',
                  body: _initialDataSummary(p),
                ),
                _SectionTile(
                  title: 'Этап 2. Планировка',
                  body: _planningSummary(p),
                ),
                _SectionTile(
                  title: 'Этап 3. Кровля',
                  body: _roofSummary(p),
                ),
                _SectionTile(
                  title: 'Этап 4. Фундамент',
                  body: _foundationSummary(p),
                ),
                const SizedBox(height: 16),
                // ----------------------------------------------------------------
                // Сначала — все расчёты (ПЗ): нагрузки, теплотехника, стропила.
                // ----------------------------------------------------------------
                Text(
                  'Расчёты (пояснительные записки)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.calculate_outlined),
                  label: const Text(
                    'Расчёт нагрузок на фундамент (СП 20.13330.2016)',
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FoundationLoadsPage(projectId: p.id),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.thermostat_outlined),
                  label: const Text(
                      'ПЗ. Теплотехнический расчёт (СП 50.13330)'),
                  onPressed: () => _downloadThermalPz(context, p),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.roofing_outlined),
                  label: const Text(
                      'ПЗ. Расчёт стропильной системы (СП 64.13330)'),
                  onPressed: () => _downloadRaftersPz(context, p),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                // ----------------------------------------------------------------
                // Затем — подтверждение ТЗ → скачать ТЗ → скачать комплект.
                // ----------------------------------------------------------------
                Text(
                  'Техническое задание и чертежи',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: _generating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(hasDrawings
                          ? Icons.refresh
                          : Icons.fact_check_outlined),
                  label: Text(
                    hasDrawings
                        ? 'Перегенерировать чертежи'
                        : 'Подтвердить ТЗ и сгенерировать чертежи',
                  ),
                  onPressed: _generating
                      ? null
                      : () => _confirmAndGenerate(context, p),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Скачать техническое задание (PDF)'),
                  onPressed: () => _downloadTechnicalSpec(context, p),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.architecture),
                  label: const Text('Скачать комплект чертежей (PDF/DXF)'),
                  onPressed: hasDrawings
                      ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DrawingsPage(projectId: p.id),
                            ),
                          )
                      : null,
                ),
                if (!hasDrawings)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Чертежи появятся после подтверждения ТЗ.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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

  Future<void> _downloadTechnicalSpec(
      BuildContext context, HouseProject p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await TechnicalSpecPdf.build(p);
      final safeName = p.name
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      await FileDownload.downloadBytes(
        bytes: bytes,
        filename: '${safeName}_ТЗ.pdf',
        mimeType: 'application/pdf',
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Техническое задание скачано')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось собрать PDF: $e')),
      );
    }
  }

  Future<void> _downloadThermalPz(
      BuildContext context, HouseProject p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await ThermalExplanationPdf.build(project: p);
      final safeName = p.name
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      await FileDownload.downloadBytes(
        bytes: bytes,
        filename: 'ПЗ_теплотехника_$safeName.pdf',
        mimeType: 'application/pdf',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось собрать ПЗ: $e')),
      );
    }
  }

  Future<void> _downloadRaftersPz(
      BuildContext context, HouseProject p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await RaftersExplanationPdf.build(project: p);
      final safeName = p.name
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      await FileDownload.downloadBytes(
        bytes: bytes,
        filename: 'ПЗ_стропилка_$safeName.pdf',
        mimeType: 'application/pdf',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось собрать ПЗ: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------
  // Сводки по этапам — те же значения, что и в PDF, на русском.
  // ---------------------------------------------------------------------

  static String _roomLabel(String name) {
    for (final r in RoomKind.values.where((e) => e.userSelectable)) {
      if (r.name == name) return r.title;
    }
    return name;
  }

  static const _roofTypeLabels = {
    'gable': 'Двускатная',
    'hip': 'Четырёхскатная',
    'mansard': 'Мансардная',
    'flat': 'Плоская',
  };

  static const _roofMaterialLabels = {
    'metal_tile': 'Металлочерепица',
    'soft': 'Мягкая (битумная)',
    'ceramic': 'Керамическая',
    'slate': 'Шифер',
    'seam': 'Фальцевая',
  };

  static const _staircaseTypeLabels = {
    'marsh': 'Маршевая',
    'rotary': 'Поворотная',
    'screw': 'Винтовая',
  };

  static const _slabTypeLabels = {
    'monolith': 'Монолитное ж/б',
    'precast': 'Сборное ж/б',
    'wood_beams': 'По деревянным балкам',
    'metal_beams': 'По металлическим балкам',
  };

  String _initialDataSummary(HouseProject p) {
    final b = p.brief;
    final parts = <String>[];
    if (b.floors != null) {
      parts.add('${b.floors!} эт.${b.hasMansard == true ? ' + мансарда' : ''}'
          '${b.hasBasement == true ? ' + цокольный/подвальный' : ''}');
    }
    if (b.targetArea != null) {
      parts.add('Площадь: ${b.targetArea!.toStringAsFixed(0)} м²');
    }
    final rooms = b.rooms.entries
        .where((e) => e.value > 0)
        .map((e) => '${_roomLabel(e.key)} ×${e.value}')
        .join(', ');
    if (rooms.isNotEmpty) parts.add('Комнаты: $rooms');
    if (b.wallMaterial != null) {
      parts.add('Ориентир по стенам: ${b.wallMaterial!.title}');
    }
    return parts.isEmpty ? '—' : parts.join('\n');
  }

  String _planningSummary(HouseProject p) {
    final parts = <String>[];
    if (p.walls.isFilled) {
      final mat =
          WallMaterial.fromName(p.walls.material)?.title ?? p.walls.material;
      parts.add(
        'Стены: $mat · ${p.walls.thickness?.toStringAsFixed(0)} мм',
      );
    }
    if (p.floorSlabs.isFilled) {
      final t = _slabTypeLabels[p.floorSlabs.type] ?? p.floorSlabs.type ?? '?';
      parts.add('Перекрытия: $t');
    }
    if (p.includesStaircase && p.staircase.isFilled) {
      final t =
          _staircaseTypeLabels[p.staircase.type] ?? p.staircase.type ?? '?';
      parts.add('Лестница: $t · ${p.staircase.stepsCount ?? '?'} ступеней');
    }
    return parts.isEmpty ? '—' : parts.join('\n');
  }

  String _foundationSummary(HouseProject p) {
    final b = p.brief;
    final parts = <String>[];
    if (b.region != null) parts.add('Регион: ${b.region}');
    if (b.snowZone != null) parts.add('Снеговой район: ${b.snowZone}');
    if (b.windZone != null) parts.add('Ветровой район: ${b.windZone}');
    if (b.soilLayers.where((l) => l.type != null).isNotEmpty) {
      final n = b.soilLayers.where((l) => l.type != null).length;
      parts.add('Грунты: $n слой(-ёв)');
    }
    if (p.foundation.isFilled) parts.add('Фундамент: ${p.foundation.summary}');
    return parts.isEmpty ? '—' : parts.join('\n');
  }

  /// Описание углов скатов: для двускатной/мансардной — 2 ската
  /// («левый/правый» или «нижний/верхний»), для вальмовой — 4 (стороны
  /// света), для плоской — без углов.
  static const Map<String, List<String>> _slopeLabels = {
    'gable': ['Левый скат', 'Правый скат'],
    'mansard': ['Нижний (крутой) скат', 'Верхний (пологий) скат'],
    'hip': ['Южный скат', 'Северный скат', 'Западный скат', 'Восточный скат'],
  };

  String _roofSummary(HouseProject p) {
    if (!p.roof.isFilled) return '—';
    final type = _roofTypeLabels[p.roof.type] ?? p.roof.type ?? '?';
    final mat = p.roof.roofingMaterial == null
        ? ''
        : '\nПокрытие: ${_roofMaterialLabels[p.roof.roofingMaterial!] ?? p.roof.roofingMaterial}';

    if (p.roof.type == 'flat') {
      return '$type · плоская$mat';
    }

    // Подбираем список углов: приоритет — slopeAngles (новый формат),
    // если пусто — берём slopeAngle и тиражируем по количеству скатов.
    final labels = _slopeLabels[p.roof.type] ?? const <String>[];
    List<double> angles;
    if (p.roof.slopeAngles.isNotEmpty) {
      angles = p.roof.slopeAngles;
    } else if (p.roof.slopeAngle != null && labels.isNotEmpty) {
      angles = List<double>.filled(labels.length, p.roof.slopeAngle!);
    } else {
      angles = const <double>[];
    }

    if (angles.isEmpty) return '$type$mat';

    final lines = <String>[];
    for (var i = 0; i < angles.length; i++) {
      final lbl = i < labels.length ? labels[i] : 'Скат ${i + 1}';
      lines.add('  · $lbl: ${angles[i].toStringAsFixed(0)}°');
    }
    return '$type\nУглы скатов:\n${lines.join('\n')}$mat';
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
