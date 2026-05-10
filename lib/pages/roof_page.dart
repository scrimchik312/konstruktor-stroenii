import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/house_project.dart';
import '../state/app_state.dart';
import '../widgets/hints.dart';
import 'foundation/site_preliminaries_page.dart';
import 'stage_navigation.dart';

/// Этап 3 — «Кровля».
///
/// На этом этапе фиксируются три параметра кровли:
///   * **Тип** — двускатная, четырёхскатная, плоская, мансардная.
///   * **Угол ската** — в градусах. Не запрашивается, если выбрана
///     плоская кровля; для остальных типов — обязателен (от 5°).
///   * **Покрытие** — материал кровли: металлочерепица, мягкая, шифер,
///     керамическая, фальцевая. Влияет на снеговую и ветровую нагрузку
///     (учитывается на этапе фундамента) и на пожарные требования.
///
/// Если на этапе 1 пользователь отметил «мансарда», предлагается также
/// чекбокс «Утеплённая крыша» — он уйдёт в спецификацию материалов.
class RoofPage extends StatefulWidget {
  const RoofPage({super.key, required this.projectId});

  final String projectId;

  @override
  State<RoofPage> createState() => _RoofPageState();
}

class _RoofPageState extends State<RoofPage> {
  late HouseProject _project;
  String? _type;
  List<double> _slopes = <double>[];
  String? _roofing;
  bool _insulated = false;

  static const _types = <_RoofTypeOption>[
    _RoofTypeOption(
      id: 'gable',
      title: 'Двускатная',
      hint: 'Самая распространённая. Подходит для большинства частных домов.',
      defaultSlope: 30,
      slopeCount: 2,
      slopeLabels: ['Левый скат', 'Правый скат'],
    ),
    _RoofTypeOption(
      id: 'hip',
      title: 'Четырёхскатная (вальмовая)',
      hint: 'Без фронтонов, лучше держит ветер. Сложнее в монтаже.',
      defaultSlope: 25,
      slopeCount: 4,
      slopeLabels: ['Южный скат', 'Северный скат', 'Западный скат', 'Восточный скат'],
    ),
    _RoofTypeOption(
      id: 'mansard',
      title: 'Мансардная',
      hint: 'Ломаная: внизу — крутой скат, вверху — пологий. Даёт жилое '
          'пространство под кровлей.',
      defaultSlope: 45,
      slopeCount: 2,
      slopeLabels: ['Нижний (крутой) скат', 'Верхний (пологий) скат'],
    ),
    _RoofTypeOption(
      id: 'flat',
      title: 'Плоская',
      hint: 'Скат до 5°, нужен организованный водосток. Для современной '
          'архитектуры и эксплуатируемых кровель.',
      defaultSlope: 3,
      slopeCount: 0,
      slopeLabels: [],
    ),
  ];

  static const _roofingOptions = <_RoofingOption>[
    _RoofingOption(id: 'metal_tile', title: 'Металлочерепица'),
    _RoofingOption(id: 'soft', title: 'Мягкая (битумная)'),
    _RoofingOption(id: 'ceramic', title: 'Керамическая'),
    _RoofingOption(id: 'slate', title: 'Шифер'),
    _RoofingOption(id: 'seam', title: 'Фальцевая'),
  ];

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _project = state.projects.firstWhere(
      (p) => p.id == widget.projectId,
      orElse: () => throw StateError('project not found'),
    );
    _type = _project.roof.type;
    _roofing = _project.roof.roofingMaterial;
    _resetSlopesForType(initial: true);
  }

  _RoofTypeOption _optionFor(String? typeId) => _types.firstWhere(
        (t) => t.id == typeId,
        orElse: () => _types.first,
      );

  void _resetSlopesForType({bool initial = false}) {
    if (_type == null || _type == 'flat') {
      _slopes = <double>[];
      return;
    }
    final opt = _optionFor(_type);
    final saved = _project.roof.slopeAngles;
    if (initial && saved.length == opt.slopeCount) {
      _slopes = List<double>.from(saved);
    } else if (initial && _project.roof.slopeAngle != null) {
      _slopes = List<double>.filled(opt.slopeCount, _project.roof.slopeAngle!);
    } else {
      _slopes = List<double>.filled(opt.slopeCount, opt.defaultSlope);
    }
  }

  bool get _canSave {
    if (_type == null) return false;
    if (_type == 'flat') return true;
    if (_slopes.isEmpty) return false;
    for (final s in _slopes) {
      if (s < 5 || s > 60) return false;
    }
    return true;
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    _project.roof.type = _type;
    if (_type == 'flat') {
      _project.roof.slopeAngle = null;
      _project.roof.slopeAngles = <double>[];
    } else {
      _project.roof.slopeAngles = List<double>.from(_slopes);
      // Средний угол — для обратной совместимости с роем вычислений,
      // которые ожидают одно значение.
      final avg = _slopes.reduce((a, b) => a + b) / _slopes.length;
      _project.roof.slopeAngle = avg;
    }
    _project.roof.roofingMaterial = _roofing;
    await state.saveProject(_project);
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('Кровля сохранена')));
    StageNavigation.jumpToStage(
      context,
      SitePreliminariesPage(projectId: _project.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFlat = _type == 'flat';
    final hasMansardInBrief = _project.brief.hasMansard == true;
    final showInsulated = hasMansardInBrief;
    // Мансардная кровля предлагается только если пользователь на этапе 1
    // отметил «Мансарда». Иначе скрываем опцию.
    final visibleTypes = [
      for (final t in _types)
        if (t.id != 'mansard' || hasMansardInBrief) t,
    ];
    final opt = _type != null ? _optionFor(_type) : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Этап 3. Кровля'),
        actions: const [
          HintIconButton(
            title: 'Этап 3. Кровля',
            sections: Hints.roof,
          ),
        ],
      ),
      body: HintAutoShow(
        screenKey: 'roof',
        title: 'Этап 3. Кровля',
        sections: Hints.roof,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Тип кровли', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ...visibleTypes.map(
                  (t) => Card(
                    child: RadioListTile<String>(
                      value: t.id,
                      groupValue: _type,
                      onChanged: (v) {
                        setState(() {
                          _type = v;
                          _resetSlopesForType();
                        });
                      },
                      title: Text(t.title),
                      subtitle: Text(t.hint),
                      isThreeLine: true,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_type != null && !isFlat && opt != null) ...[
                  Text(
                    opt.slopeCount == 1
                        ? 'Угол ската'
                        : 'Углы скатов (${opt.slopeCount} шт.)',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Для двускатной задаются 2 угла, для вальмовой — 4, для '
                    'мансардной — нижний и верхний скаты. Диапазон 5–60°.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _slopes.length; i++) ...[
                    Text(
                      '${i < opt.slopeLabels.length ? opt.slopeLabels[i] : 'Скат ${i + 1}'}: '
                      '${_slopes[i].toStringAsFixed(0)}°',
                      style: theme.textTheme.bodyMedium,
                    ),
                    Slider(
                      value: _slopes[i],
                      min: 5,
                      max: 60,
                      divisions: 55,
                      label: '${_slopes[i].toStringAsFixed(0)}°',
                      onChanged: (v) =>
                          setState(() => _slopes[i] = v.roundToDouble()),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
                Text('Покрытие', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._roofingOptions.map(
                  (r) => RadioListTile<String>(
                    value: r.id,
                    groupValue: _roofing,
                    title: Text(r.title),
                    onChanged: (v) => setState(() => _roofing = v),
                  ),
                ),
                if (showInsulated) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Утеплённая крыша'),
                    subtitle: const Text(
                      'Нужно, если под кровлей будет жилая мансарда.',
                    ),
                    value: _insulated,
                    onChanged: (v) => setState(() => _insulated = v),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _canSave ? _save : null,
                  child: const Text(
                    'Сохранить и перейти к этапу 4: Фундамент',
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

class _RoofTypeOption {
  const _RoofTypeOption({
    required this.id,
    required this.title,
    required this.hint,
    required this.defaultSlope,
    required this.slopeCount,
    required this.slopeLabels,
  });

  final String id;
  final String title;
  final String hint;
  final double defaultSlope;
  final int slopeCount;
  final List<String> slopeLabels;
}

class _RoofingOption {
  const _RoofingOption({required this.id, required this.title});
  final String id;
  final String title;
}
