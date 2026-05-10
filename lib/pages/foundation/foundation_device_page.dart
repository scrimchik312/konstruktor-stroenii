import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/foundation.dart';
import '../../models/house_project.dart';
import '../../state/app_state.dart';
import '../../widgets/hints.dart';
import '../stage_navigation.dart';
import '../technical_spec_page.dart';

/// Шаг 2 раздела «Фундамент»: выбор устройства фундамента.
///
/// Набор вариантов зависит от выбранного на предыдущем шаге типа. Для
/// варианта «сваи с ростверком» дополнительно спрашиваем материал
/// ростверка (монолитный / сборный).
class FoundationDevicePage extends StatefulWidget {
  const FoundationDevicePage({super.key, required this.projectId});

  final String projectId;

  @override
  State<FoundationDevicePage> createState() => _FoundationDevicePageState();
}

class _FoundationDevicePageState extends State<FoundationDevicePage> {
  HouseProject? _findProject(AppState state) {
    for (final p in state.projects) {
      if (p.id == widget.projectId) return p;
    }
    return null;
  }

  Future<void> _selectDevice(FoundationDevice device) async {
    final state = context.read<AppState>();
    final project = _findProject(state);
    if (project == null) return;
    project.foundation.device = device;
    await state.saveProject(project);
    setState(() {});
  }

  Future<void> _selectGrillage(GrillageMaterial material) async {
    final state = context.read<AppState>();
    final project = _findProject(state);
    if (project == null) return;
    project.foundation.grillageMaterial = material;
    await state.saveProject(project);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final project = _findProject(state);
    final type = project?.foundation.type;

    if (project == null || type == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Устройство фундамента')),
        body: const Center(
          child: Text('Сначала выберите тип фундамента.'),
        ),
      );
    }

    final foundation = project.foundation;
    final devices = devicesForType(type);
    final isComplete = foundation.isFilled;

    return Scaffold(
      appBar: AppBar(
        title: Text('Устройство фундамента · ${type.title}'),
        actions: const [
          HintIconButton(
            title: 'Параметры фундамента',
            sections: Hints.foundationWizard,
          ),
        ],
      ),
      body: HintAutoShow(
        screenKey: 'foundation-device',
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
                    'Выберите устройство фундамента',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
                for (final d in devices)
                  RadioListTile<FoundationDevice>(
                    value: d,
                    groupValue: foundation.device,
                    onChanged: (value) {
                      if (value != null) _selectDevice(value);
                    },
                    title: Text(d.title),
                  ),
                if (type == FoundationType.pileWithGrillage) ...[
                  const Divider(height: 32),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      'Материал ростверка',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ),
                  for (final g in GrillageMaterial.values)
                    RadioListTile<GrillageMaterial>(
                      value: g,
                      groupValue: foundation.grillageMaterial,
                      onChanged: (value) {
                        if (value != null) _selectGrillage(value);
                      },
                      title: Text(g.title),
                    ),
                ],
                const SizedBox(height: 24),
                // Расчёт нагрузок на фундамент перенесён на этап 5
                // «Техническое задание», после подтверждения ТЗ —
                // там же запускается генерация чертежей.
                FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: isComplete
                      ? () => StageNavigation.jumpToStage(
                            context,
                            TechnicalSpecPage(projectId: widget.projectId),
                          )
                      : null,
                  child: const Text(
                    'Сохранить и перейти к техническому заданию',
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
