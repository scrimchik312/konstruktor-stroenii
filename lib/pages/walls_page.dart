import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/wall_materials.dart';
import '../models/house_project.dart';
import '../state/app_state.dart';
import '../widgets/synced_slider_field.dart';

/// Раздел «Стены» — выбор материала, толщины и высоты наружных стен.
///
/// Минимальная форма: тип материала из перечисления [WallMaterial], толщина
/// в миллиметрах и высота этажа в метрах. На этапе планировки эти данные
/// определяют нагрузку, передаваемую перекрытиями и кровлей на фундамент.
/// Внутренние стены пока считаем по умолчанию (200 мм) — отдельным экраном
/// добавим позже, если потребуется.
class WallsPage extends StatefulWidget {
  const WallsPage({super.key, required this.projectId});

  final String projectId;

  @override
  State<WallsPage> createState() => _WallsPageState();
}

class _WallsPageState extends State<WallsPage> {
  late HouseProject _project;
  WallMaterial? _material;
  double _thickness = 380;
  double _height = 3.0;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _project = state.projects.firstWhere(
      (p) => p.id == widget.projectId,
      orElse: () => throw StateError('project not found'),
    );
    _material = WallMaterial.fromName(_project.walls.material) ??
        _project.brief.wallMaterial;
    _thickness = _project.walls.thickness ??
        _defaultThickness(_material ?? WallMaterial.aerated);
    _height = _project.walls.height ?? 3.0;
  }

  static double _defaultThickness(WallMaterial m) {
    switch (m) {
      case WallMaterial.brick:
        return 510;
      case WallMaterial.aerated:
        return 400;
      case WallMaterial.expandedClay:
        return 400;
      case WallMaterial.timber:
        return 200;
      case WallMaterial.frame:
        return 200;
    }
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    _project.walls.material = _material?.name;
    _project.walls.thickness = _thickness;
    _project.walls.height = _height;
    // Синхронизируем выбор материала стен с brief — он используется
    // на этапе «Фундамент» (composition_planner) для расчёта рекомендаций.
    if (_material != null) {
      _project.brief.wallMaterial = _material;
    }
    await state.saveProject(_project);
    messenger.showSnackBar(const SnackBar(content: Text('Стены сохранены')));
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _material != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Стены')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Материал наружных стен',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...WallMaterial.values.map(
                (m) => RadioListTile<WallMaterial>(
                  title: Text(m.title),
                  value: m,
                  groupValue: _material,
                  onChanged: (v) {
                    setState(() {
                      _material = v;
                      _thickness = _defaultThickness(v ?? WallMaterial.aerated);
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),
              SyncedSliderField(
                label: 'Толщина стены',
                value: _thickness,
                min: 100,
                max: 640,
                step: 5,
                unit: 'мм',
                onChanged: (v) => setState(() => _thickness = v),
              ),
              const SizedBox(height: 16),
              SyncedSliderField(
                label: 'Высота этажа',
                value: _height,
                min: 2.4,
                max: 4.0,
                step: 0.05,
                unit: 'м',
                decimals: 2,
                onChanged: (v) => setState(() => _height = v),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: canSave ? _save : null,
                child: const Text('Сохранить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
