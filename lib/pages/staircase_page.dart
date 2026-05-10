import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/house_project.dart';
import '../state/app_state.dart';
import '../widgets/hints.dart';
import '../widgets/synced_slider_field.dart';

/// Подраздел «Лестница» этапа 2.
///
/// Появляется только если требуется межэтажная коммуникация: больше одного
/// этажа, мансарда или цокольный/подвальный этаж. Раньше был заглушкой и
/// блокировал переход к этапу 3 — теперь это полноценная форма с типом,
/// высотой этажа и автоматическим расчётом количества ступеней.
///
/// Расчёт ступеней — упрощённый: для маршевой/поворотной берём высоту
/// подступёнка 165 мм (по СП 1.13130.2020 удобный шаг), округляем количество
/// ступеней вверх. Для винтовой — округляем по высоте 180 мм (там обычно
/// ступени чуть выше из-за ограниченной площади). Это базовая прикидка
/// для технического задания; точный расчёт с учётом ширины марша,
/// удобства уклона по СП 54.13330.2022 — задача отдельной фазы.
class StaircasePage extends StatefulWidget {
  const StaircasePage({super.key, required this.projectId});

  final String projectId;

  @override
  State<StaircasePage> createState() => _StaircasePageState();
}

class _StaircasePageState extends State<StaircasePage> {
  late HouseProject _project;
  String? _type;
  double _floorHeight = 3.0;

  static const _types = <_StaircaseTypeOption>[
    _StaircaseTypeOption(
      id: 'marsh',
      title: 'Маршевая',
      hint: 'Прямая или с поворотной площадкой. Самый удобный и простой '
          'в монтаже вариант, занимает 4–6 м² в плане.',
      riserHeight: 0.165,
    ),
    _StaircaseTypeOption(
      id: 'rotary',
      title: 'Поворотная (с забежными ступенями)',
      hint: 'Экономит площадь за счёт поворота на 90° или 180° через '
          'забежные ступени. Сложнее в монтаже, чуть менее удобна.',
      riserHeight: 0.165,
    ),
    _StaircaseTypeOption(
      id: 'screw',
      title: 'Винтовая',
      hint: 'Самая компактная (от 1.5 м²), но менее удобна для частого '
          'использования и переноса мебели. Для второстепенных лестниц.',
      riserHeight: 0.180,
    ),
  ];

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _project = state.projects.firstWhere(
      (p) => p.id == widget.projectId,
      orElse: () => throw StateError('project not found'),
    );
    _type = _project.staircase.type;
    _floorHeight = _project.staircase.floorHeight ?? 3.0;
  }

  int? get _stepsCount {
    if (_type == null) return null;
    final t = _types.firstWhere((e) => e.id == _type);
    return (_floorHeight / t.riserHeight).ceil();
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    _project.staircase.type = _type;
    _project.staircase.floorHeight = _floorHeight;
    _project.staircase.stepsCount = _stepsCount;
    await state.saveProject(_project);
    messenger.showSnackBar(
      const SnackBar(content: Text('Лестница сохранена')),
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Лестница'),
        actions: const [
          HintIconButton(
            title: 'Лестница',
            sections: Hints.staircase,
          ),
        ],
      ),
      body: HintAutoShow(
        screenKey: 'staircase',
        title: 'Лестница',
        sections: Hints.staircase,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Тип лестницы', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._types.map(
                  (t) => Card(
                    child: RadioListTile<String>(
                      value: t.id,
                      groupValue: _type,
                      title: Text(t.title),
                      subtitle: Text(t.hint),
                      isThreeLine: true,
                      onChanged: (v) => setState(() => _type = v),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SyncedSliderField(
                  label: 'Высота этажа',
                  value: _floorHeight,
                  min: 2.4,
                  max: 4.0,
                  step: 0.05,
                  unit: 'м',
                  decimals: 2,
                  onChanged: (v) => setState(() => _floorHeight = v),
                ),
                const SizedBox(height: 8),
                if (_stepsCount != null)
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Расчётное количество ступеней: $_stepsCount.\n'
                        'Высота подступёнка ≈ '
                        '${(_floorHeight / _stepsCount! * 1000).toStringAsFixed(0)} мм.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _type != null ? _save : null,
                  child: const Text('Сохранить'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StaircaseTypeOption {
  const _StaircaseTypeOption({
    required this.id,
    required this.title,
    required this.hint,
    required this.riserHeight,
  });

  final String id;
  final String title;
  final String hint;

  /// Расчётная высота подступёнка, м. Используется для прикидки числа
  /// ступеней.
  final double riserHeight;
}
