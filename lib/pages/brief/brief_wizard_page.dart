import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/region_catalog.dart';
import '../../data/rooms_catalog.dart';
import '../../data/soil_types.dart';
import '../../data/wall_materials.dart';
import '../../models/client_brief.dart';
import '../../models/house_project.dart';
import '../../models/layout_scheme.dart';
import '../../models/soil_layer.dart';
import '../../models/user_mode.dart';
import '../../state/app_state.dart';
import '../../widgets/hints.dart';
import '../footprint_editor_page.dart';
import '../stage_navigation.dart';
import '../stage_planning_page.dart';
import 'dart:math' as math;

/// Многошаговый визард «Этап 1. Начальные данные».
///
/// Раньше визард собирал ВСЁ техническое задание разом, включая инженерно-геологию
/// (грунт) и климат (снеговой и ветровой район). Это перегружало пользователя
/// на старте проекта и не вязалось с реальной последовательностью
/// проектирования: климат и грунт нужны только при подборе фундамента,
/// поэтому теперь они задаются на этапе «Фундамент» (этап 3).
///
/// На первом этапе остаются только **архитектурно-планировочные**
/// характеристики дома:
///   1) Этажность + наличие мансарды и цокольного/подвального этажа;
///   2) Целевая площадь и пятно застройки;
///   3) Состав комнат (фиксированный список со счётчиками);
///   4) Дополнения (гараж/терраса/балкон/эркер/второй свет/лестница);
///   5) Ориентировочный материал стен (точный выбор будет на этапе «Стены»);
///   6) Особые пожелания (свободный текст).
///
/// Данные сохраняются в проект **после каждого шага**, поэтому даже если
/// пользователь закроет вкладку — прогресс не потеряется. По кнопке
/// «Завершить» в режиме «Клиент» состав сооружения подтягивается из
/// движка правил, а в режиме «Проектировщик» — пользователь дальше
/// заполняет всё руками.
///
/// Поля `region`, `snowZone`, `windZone`, `soilLayers` модели
/// [ClientBrief] не используются здесь и заполняются на этапе фундамента.
class BriefWizardPage extends StatefulWidget {
  const BriefWizardPage({super.key, required this.projectId});

  final String projectId;

  @override
  State<BriefWizardPage> createState() => _BriefWizardPageState();
}

class _BriefWizardPageState extends State<BriefWizardPage> {
  int _step = 0;
  // Шаги: 0 — этажность, 1 — площадь и пятно, 2 — состав комнат,
  // 3 — схема планировки, 4 — дополнения, 5 — габариты пристроек
  // (динамический, появляется только если hasGarage или hasTerrace
  // — см. _stepsCountFor). Материал стен выбирается на этапе 2
  // «Планировка», лестница добавляется автоматически
  // (см. ClientBrief.requiresStaircase).
  int _stepsCountFor(ClientBrief brief) {
    final needsAttachStep =
        (brief.hasGarage == true) || (brief.hasTerrace == true);
    return needsAttachStep ? 6 : 5;
  }

  /// Сообщение об ошибке валидации, если на шаге 1 (площадь и габариты)
  /// введённые данные не сходятся. Если не пусто — пользователь видит
  /// SnackBar и не переходит на следующий шаг.
  String? _stepError(int step, ClientBrief brief) {
    if (step != 1) return null;
    final area = brief.targetArea;
    final w = brief.footprintWidth;
    final l = brief.footprintLength;
    if (area == null || area <= 0) return 'Введите общую площадь дома (м²).';
    if (w == null || w <= 0 || l == null || l <= 0) {
      return 'Введите габариты здания: ширина и длина (м).';
    }
    final floors = (brief.floors ?? 1) +
        ((brief.hasMansard == true) ? 1 : 0);
    final calc = w * l * floors;
    final tol = math.max(area, calc) * 0.07; // ±7 %
    if ((calc - area).abs() > tol) {
      return 'Площадь $area м² не сходится с габаритами '
          '${w.toStringAsFixed(1)}×${l.toStringAsFixed(1)} м '
          '× $floors эт. = ${calc.toStringAsFixed(0)} м². '
          'Подберите габариты автоматически или скорректируйте значения.';
    }
    return null;
  }

  HouseProject? _findProject(AppState state) {
    for (final p in state.projects) {
      if (p.id == widget.projectId) return p;
    }
    return null;
  }

  Future<void> _save(BuildContext context, HouseProject project) async {
    await context.read<AppState>().saveProject(project);
  }

  Future<void> _finish(BuildContext context, HouseProject project) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    await state.saveProject(project);
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Начальные данные сохранены. Открываем этап 2 — «Планировка».',
        ),
      ),
    );
    StageNavigation.jumpToStage(
      context,
      StagePlanningPage(projectId: project.id),
    );
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
    final brief = project.brief;
    final stepsCount = _stepsCountFor(brief);
    // Если пользователь снял оба чекбокса — не висим на шаге 5.
    if (_step >= stepsCount) _step = stepsCount - 1;
    final isLast = _step == stepsCount - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('Начальные данные · шаг ${_step + 1} из $stepsCount'),
        actions: const [
          HintIconButton(
            title: 'Этап 1. Начальные данные',
            sections: Hints.briefWizard,
          ),
        ],
      ),
      body: HintAutoShow(
        screenKey: 'brief-wizard',
        title: 'Этап 1. Начальные данные',
        sections: Hints.briefWizard,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                LinearProgressIndicator(value: (_step + 1) / stepsCount),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildStep(context, project, brief),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        OutlinedButton(
                          onPressed:
                              _step == 0 ? null : () => setState(() => _step--),
                          child: const Text('Назад'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () async {
                            final err = _stepError(_step, brief);
                            if (err != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(err),
                                  duration: const Duration(seconds: 5),
                                ),
                              );
                              return;
                            }
                            await _save(context, project);
                            if (!context.mounted) return;
                            if (isLast) {
                              await _finish(context, project);
                            } else {
                              setState(() => _step++);
                            }
                          },
                          child: Text(
                            isLast
                                ? 'Сохранить и перейти к этапу 2'
                                : 'Далее',
                          ),
                        ),
                      ],
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

  Widget _buildStep(
    BuildContext context,
    HouseProject project,
    ClientBrief brief,
  ) {
    // mode пока не используется в новой схеме (после удаления шагов
    // региона и грунта вариативность по режимам исчезла), но оставляем
    // выборку — пригодится в _NotesStep, если понадобится разделение.
    // ignore: unused_local_variable
    final mode = context.read<AppState>().mode ?? UserMode.client;
    switch (_step) {
      case 0:
        return _FloorsStep(brief: brief, onChanged: () => setState(() {}));
      case 1:
        return _AreaStep(
          brief: brief,
          project: project,
          onChanged: () => setState(() {}),
        );
      case 2:
        return _RoomsStep(brief: brief, onChanged: () => setState(() {}));
      case 3:
        return _LayoutSchemeStep(
          brief: brief,
          onChanged: () => setState(() {}),
        );
      case 4:
        return _AddonsStep(brief: brief, onChanged: () => setState(() {}));
      case 5:
        return _AttachmentDimensionsStep(
          brief: brief,
          onChanged: () => setState(() {}),
        );
    }
    return const SizedBox.shrink();
  }
}

// =====================================================================
// НИЖЕ СОХРАНЕНЫ ШАГИ «регион» и «грунт».
// Они больше не показываются на этапе 1, но будут переиспользованы
// на этапе «Фундамент» (фаза 4 рефакторинга). Пока оставлены в этом
// файле как «запасные части» — их вынесем в отдельный виджет на этапе фундамента.
// =====================================================================

// ignore: unused_element
class _RegionStep extends StatelessWidget {
  const _RegionStep({
    required this.brief,
    required this.mode,
    required this.onChanged,
  });

  final ClientBrief brief;
  final UserMode mode;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final designer = mode == UserMode.designer;
    return ListView(
      children: [
        Text('Регион строительства', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Выберите город — снеговой и ветровой районы заполнятся '
          'автоматически по СП 20.13330.2016.'
          '${designer ? ' Значения районов можно вручную поменять или ввести свой город.' : ''}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Город',
            border: OutlineInputBorder(),
          ),
          isExpanded: true,
          value: kRegionCatalog.any((r) => r.city == brief.region)
              ? brief.region
              : null,
          items: [
            for (final r in kRegionCatalog)
              DropdownMenuItem(value: r.city, child: Text(r.city)),
            if (designer)
              const DropdownMenuItem(
                value: '__custom__',
                child: Text('Другой город…'),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            if (value == '__custom__') {
              brief.region = '';
              brief.snowZone = null;
              brief.windZone = null;
            } else {
              final r = kRegionCatalog.firstWhere((c) => c.city == value);
              brief.region = r.city;
              brief.snowZone = r.snowZone;
              brief.windZone = r.windZone;
            }
            onChanged();
          },
        ),
        if (designer && brief.region != null) ...[
          const SizedBox(height: 16),
          TextFormField(
            initialValue: brief.region,
            decoration: const InputDecoration(
              labelText: 'Название города',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              brief.region = value;
              onChanged();
            },
          ),
        ],
        if (brief.region != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Снеговой район',
                    border: OutlineInputBorder(),
                  ),
                  value: brief.snowZone,
                  items: [
                    for (final z in kSnowZones)
                      DropdownMenuItem(value: z, child: Text('$z')),
                  ],
                  onChanged: designer
                      ? (v) {
                          brief.snowZone = v;
                          onChanged();
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Ветровой район',
                    border: OutlineInputBorder(),
                  ),
                  value: brief.windZone,
                  items: [
                    for (final z in kWindZones)
                      DropdownMenuItem(value: z, child: Text(z)),
                  ],
                  onChanged: designer
                      ? (v) {
                          brief.windZone = v;
                          onChanged();
                        }
                      : null,
                ),
              ),
            ],
          ),
          if (!designer)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Значения районов проставлены автоматически и недоступны для '
                'правки в режиме клиента.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// =====================================================================
// Шаг 2: грунт
// =====================================================================

// ignore: unused_element
class _SoilStep extends StatelessWidget {
  const _SoilStep({
    required this.brief,
    required this.mode,
    required this.onChanged,
  });

  final ClientBrief brief;
  final UserMode mode;
  final VoidCallback onChanged;

  void _ensureAtLeastOneLayer() {
    if (brief.soilLayers.isEmpty) brief.soilLayers.add(SoilLayer());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _ensureAtLeastOneLayer();
    final isClient = mode == UserMode.client;
    return ListView(
      children: [
        Text('Грунты на участке', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          isClient
              ? 'Укажите тип грунта верхнего слоя. Если есть инженерно-геологический '
                  'отчёт — раскройте «Расширенные показатели» и введите значения.'
              : 'Опишите все слои инженерно-геологического разреза с физико-'
                  'механическими показателями (СП 22.13330.2016, СП 47.13330.2016).',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < brief.soilLayers.length; i++)
          _SoilLayerCard(
            key: ValueKey('layer-$i'),
            index: i,
            layer: brief.soilLayers[i],
            startExpanded: !isClient,
            canRemove: brief.soilLayers.length > 1,
            onChanged: onChanged,
            onRemove: () {
              brief.soilLayers.removeAt(i);
              onChanged();
            },
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            brief.soilLayers.add(SoilLayer());
            onChanged();
          },
          icon: const Icon(Icons.add),
          label: const Text('Добавить слой'),
        ),
      ],
    );
  }
}

class _SoilLayerCard extends StatefulWidget {
  const _SoilLayerCard({
    super.key,
    required this.index,
    required this.layer,
    required this.startExpanded,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final SoilLayer layer;
  final bool startExpanded;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_SoilLayerCard> createState() => _SoilLayerCardState();
}

class _SoilLayerCardState extends State<_SoilLayerCard> {
  late bool _expanded = widget.startExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layer = widget.layer;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Слой №${widget.index + 1}',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                if (widget.canRemove)
                  IconButton(
                    tooltip: 'Удалить слой',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: widget.onRemove,
                  ),
              ],
            ),
            DropdownButtonFormField<SoilType>(
              decoration: const InputDecoration(
                labelText: 'Тип грунта',
                border: OutlineInputBorder(),
              ),
              value: layer.type,
              items: [
                for (final t in SoilType.values)
                  DropdownMenuItem(value: t, child: Text(t.title)),
              ],
              onChanged: (v) {
                layer.type = v;
                widget.onChanged();
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _NumField(
                    label: 'Глубина залегания, м',
                    value: layer.topDepth,
                    onChanged: (v) {
                      layer.topDepth = v;
                      widget.onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NumField(
                    label: 'Толщина слоя, м',
                    value: layer.thickness,
                    onChanged: (v) {
                      layer.thickness = v;
                      widget.onChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                    const SizedBox(width: 4),
                    Text(
                      _expanded
                          ? 'Скрыть расширенные показатели'
                          : 'Расширенные показатели (физика и механика)',
                      style: theme.textTheme.labelLarge,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const _SectionLabel('Физические показатели'),
              _NumGrid([
                _NumDef(
                  label: 'ρ, г/см³',
                  value: layer.density,
                  set: (v) => layer.density = v,
                ),
                _NumDef(
                  label: 'ρₛ, г/см³',
                  value: layer.particleDensity,
                  set: (v) => layer.particleDensity = v,
                ),
                _NumDef(
                  label: 'W, %',
                  value: layer.naturalMoisture,
                  set: (v) => layer.naturalMoisture = v,
                ),
                _NumDef(
                  label: 'e (пористость)',
                  value: layer.voidRatio,
                  set: (v) => layer.voidRatio = v,
                ),
                _NumDef(
                  label: 'Wₗ, %',
                  value: layer.liquidLimit,
                  set: (v) => layer.liquidLimit = v,
                ),
                _NumDef(
                  label: 'Wₚ, %',
                  value: layer.plasticLimit,
                  set: (v) => layer.plasticLimit = v,
                ),
                _NumDef(
                  label: 'Iₚ',
                  value: layer.plasticityIndex,
                  set: (v) => layer.plasticityIndex = v,
                ),
                _NumDef(
                  label: 'Iₗ',
                  value: layer.liquidityIndex,
                  set: (v) => layer.liquidityIndex = v,
                ),
              ], onChanged: widget.onChanged),
              const _SectionLabel('Механические показатели'),
              _NumGrid([
                _NumDef(
                  label: 'E, МПа',
                  value: layer.deformationModulus,
                  set: (v) => layer.deformationModulus = v,
                ),
                _NumDef(
                  label: 'φ, °',
                  value: layer.frictionAngle,
                  set: (v) => layer.frictionAngle = v,
                ),
                _NumDef(
                  label: 'c, кПа',
                  value: layer.cohesion,
                  set: (v) => layer.cohesion = v,
                ),
              ], onChanged: widget.onChanged),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}

class _NumDef {
  final String label;
  final double? value;
  final void Function(double?) set;
  _NumDef({required this.label, required this.value, required this.set});
}

class _NumGrid extends StatelessWidget {
  const _NumGrid(this.defs, {required this.onChanged});
  final List<_NumDef> defs;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < defs.length; i += 2) {
      final a = defs[i];
      final b = i + 1 < defs.length ? defs[i + 1] : null;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: _NumField(
                label: a.label,
                value: a.value,
                onChanged: (v) {
                  a.set(v);
                  onChanged();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: b == null
                  ? const SizedBox.shrink()
                  : _NumField(
                      label: b.label,
                      value: b.value,
                      onChanged: (v) {
                        b.set(v);
                        onChanged();
                      },
                    ),
            ),
          ],
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

class _NumField extends StatefulWidget {
  const _NumField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final double? value;
  final ValueChanged<double?> onChanged;
  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: _format(widget.value));
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  static String _format(double? v) {
    if (v == null) return '';
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toString();
  }

  double? _parse(String v) {
    final norm = v.replaceAll(',', '.').trim();
    if (norm.isEmpty) return null;
    return double.tryParse(norm);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (v) => widget.onChanged(_parse(v)),
    );
  }
}

// =====================================================================
// Шаг 3: этажность
// =====================================================================

class _FloorsStep extends StatelessWidget {
  const _FloorsStep({required this.brief, required this.onChanged});

  final ClientBrief brief;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Text('Этажность', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1 этаж')),
            ButtonSegment(value: 2, label: Text('2 этажа')),
            ButtonSegment(value: 3, label: Text('3 этажа')),
          ],
          selected: brief.floors == null ? <int>{} : {brief.floors!},
          emptySelectionAllowed: true,
          onSelectionChanged: (set) {
            brief.floors = set.isEmpty ? null : set.first;
            onChanged();
          },
        ),
        const SizedBox(height: 24),
        SwitchListTile(
          title: const Text('Мансарда'),
          subtitle: const Text('Жилое пространство под скатной крышей'),
          value: brief.hasMansard ?? false,
          onChanged: (v) {
            brief.hasMansard = v;
            onChanged();
          },
        ),
        SwitchListTile(
          title: const Text('Подвал / цокольный этаж'),
          value: brief.hasBasement ?? false,
          onChanged: (v) {
            brief.hasBasement = v;
            onChanged();
          },
        ),
      ],
    );
  }
}

// =====================================================================
// Шаг 4: площадь и габариты здания
// =====================================================================
//
// Авто-подбор габаритов под общую площадь: фиксируем соотношение сторон
// 5:8 (типовой комфортный домовой формат), пересчитываем площадь пятна
// S₁ = S/n, и подбираем W = √(S₁·5/8), L = √(S₁·8/5).

class _AreaStep extends StatefulWidget {
  const _AreaStep({
    required this.brief,
    required this.project,
    required this.onChanged,
  });

  final ClientBrief brief;
  final HouseProject project;
  final VoidCallback onChanged;

  @override
  State<_AreaStep> createState() => _AreaStepState();
}

class _AreaStepState extends State<_AreaStep> {
  late final TextEditingController _area;
  late final TextEditingController _width;
  late final TextEditingController _length;

  @override
  void initState() {
    super.initState();
    _area = TextEditingController(
      text: widget.brief.targetArea?.toStringAsFixed(0) ?? '',
    );
    _width = TextEditingController(
      text: widget.brief.footprintWidth?.toStringAsFixed(0) ?? '',
    );
    _length = TextEditingController(
      text: widget.brief.footprintLength?.toStringAsFixed(0) ?? '',
    );
  }

  @override
  void dispose() {
    _area.dispose();
    _width.dispose();
    _length.dispose();
    super.dispose();
  }

  /// Сводка по согласованности «площадь ↔ габариты × этажность».
  /// Возвращает `null`, если данных мало; иначе строку: «совпадает» или
  /// «не сходится» с конкретными числами.
  String? _checkConsistency() {
    final a = widget.brief.targetArea;
    final w = widget.brief.footprintWidth;
    final l = widget.brief.footprintLength;
    if (a == null || w == null || l == null) return null;
    final floors = (widget.brief.floors ?? 1) +
        ((widget.brief.hasMansard == true) ? 1 : 0);
    final calc = w * l * floors;
    final tol = math.max(a, calc) * 0.07;
    if ((calc - a).abs() <= tol) {
      return 'Площадь по габаритам: ${calc.toStringAsFixed(1)} м² · '
          'разница ${(calc - a).abs().toStringAsFixed(1)} м² (в пределах 7 %).';
    }
    return 'Площадь по габаритам: ${calc.toStringAsFixed(1)} м² · '
        'не сходится с целевой ${a.toStringAsFixed(0)} м² '
        '(разница ${((calc - a) / a * 100).abs().toStringAsFixed(0)} %).';
  }

  /// Счётчик нажатий на кнопку «Подобрать габариты» (п.8 v40).
  ///
  /// При каждом следующем нажатии берём следующий вариант
  /// из набора реалистичных соотношений сторон. Когда значения
  /// исчерпаны — продолжаем по кругу. Подбор детерминирован: при
  /// одной и той же площади и числе этажей одна и та же
  /// последовательность нажатий даст одни и те же варианты.
  int _autoFitClicks = 0;

  /// Реалистичные пропорции пятна застройки для индивидуального
  /// жилого дома. Каждое нажатие на «Подобрать» циклически выбирает
  /// следующее.
  ///
  /// Пара (W:L). 1:1 — квадрат, 5:8 — комфортный «удлинённый»
  /// (типовой для двухэтажки), 4:7 — узкий длинный (для участка
  /// шириной 12-15 м), 7:9 — почти квадрат (компактный одноэтажный),
  /// 3:5 — узкий, для длинных участков.
  static const List<List<int>> _aspectRatios = [
    [5, 8],
    [1, 1],
    [4, 7],
    [7, 9],
    [3, 5],
    [6, 7],
    [2, 3],
  ];

  /// Подобрать ширину и длину под введённую общую площадь.
  /// Соотношение сторон выбирается из набора [_aspectRatios] циклически
  /// — каждое нажатие даёт следующий вариант.
  void _autoFitDimensions() {
    final a = widget.brief.targetArea;
    if (a == null || a <= 0) return;
    final floors = (widget.brief.floors ?? 1) +
        ((widget.brief.hasMansard == true) ? 1 : 0);
    final footprint = a / floors;
    final ratio = _aspectRatios[_autoFitClicks % _aspectRatios.length];
    _autoFitClicks++;
    final wRatio = ratio[0];
    final lRatio = ratio[1];
    // S₁ = W × L, при заданном соотношении W:L = wRatio:lRatio
    //   → W = √(S₁ · wRatio/lRatio), L = √(S₁ · lRatio/wRatio).
    final widthM =
        (math.sqrt(footprint * wRatio / lRatio) * 10).round() / 10;
    final lengthM =
        (math.sqrt(footprint * lRatio / wRatio) * 10).round() / 10;
    setState(() {
      widget.brief.footprintWidth = widthM;
      widget.brief.footprintLength = lengthM;
      _width.text = widthM.toStringAsFixed(1);
      _length.text = lengthM.toStringAsFixed(1);
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const inputs = TextInputType.numberWithOptions(decimal: true);
    final formatters = [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
    ];
    final consistency = _checkConsistency();
    final isOk = consistency != null && consistency.contains('в пределах');
    return ListView(
      children: [
        Text('Площадь и габариты здания', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        TextFormField(
          controller: _area,
          keyboardType: inputs,
          inputFormatters: formatters,
          decoration: const InputDecoration(
            labelText: 'Целевая общая площадь, м²',
            border: OutlineInputBorder(),
            helperText: 'Сумма площадей всех этажей по внутреннему контуру стен.',
          ),
          onChanged: (v) {
            widget.brief.targetArea = _parse(v);
            widget.onChanged();
            setState(() {});
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _width,
                keyboardType: inputs,
                inputFormatters: formatters,
                decoration: const InputDecoration(
                  labelText: 'Ширина (габарит), м',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  widget.brief.footprintWidth = _parse(v);
                  widget.onChanged();
                  setState(() {});
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _length,
                keyboardType: inputs,
                inputFormatters: formatters,
                decoration: const InputDecoration(
                  labelText: 'Длина (габарит), м',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  widget.brief.footprintLength = _parse(v);
                  widget.onChanged();
                  setState(() {});
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Габариты здания — внешние размеры основной коробки дома, '
          'без террасы и крыльца.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        if (consistency != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isOk
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  isOk
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_outlined,
                  color: isOk
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    consistency,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isOk
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: Icon(
            _autoFitClicks == 0 ? Icons.straighten : Icons.refresh,
          ),
          label: Text(
            _autoFitClicks == 0
                ? 'Подобрать габариты под площадь'
                : 'Другой вариант габаритов',
          ),
          onPressed: widget.brief.targetArea != null &&
                  widget.brief.targetArea! > 0
              ? _autoFitDimensions
              : null,
        ),
        const SizedBox(height: 8),
        // Phase-3b §17.2.1 next-slice: ручной редактор формы пятна.
        // Позволяет выбрать L/T/U-форму и сохранить её в
        // `architectureFootprint`. Прямоугольник сбрасывает поле в null.
        OutlinedButton.icon(
          icon: const Icon(Icons.architecture_outlined),
          label: Text(
            widget.project.architectureFootprint == null
                ? 'Изменить форму пятна (L / T / U / свободный)…'
                : 'Изменить форму пятна (текущая: '
                    '${widget.project.architectureFootprint!.outline.length} вершин)',
          ),
          onPressed: () async {
            final w = widget.brief.footprintWidth ?? 8;
            final l = widget.brief.footprintLength ?? 10;
            final result = await Navigator.push<FootprintEditorResult>(
              context,
              MaterialPageRoute(
                builder: (_) => FootprintEditorPage(
                  initialWidth: w,
                  initialLength: l,
                  initialFootprint: widget.project.architectureFootprint,
                ),
              ),
            );
            if (result == null) return;
            setState(() {
              widget.brief.footprintWidth = result.width;
              widget.brief.footprintLength = result.length;
              widget.project.architectureFootprint = result.footprint;
              _width.text = result.width.toStringAsFixed(1);
              _length.text = result.length.toStringAsFixed(1);
            });
            widget.onChanged();
          },
        ),
      ],
    );
  }

  double? _parse(String v) {
    final norm = v.replaceAll(',', '.').trim();
    if (norm.isEmpty) return null;
    final parsed = double.tryParse(norm);
    if (parsed == null) return null;
    // §27.3: клампим габариты пятна в физически осмысленный диапазон
    // 3..60 м. Без верхней границы пользователь мог ввести 99999 и
    // сломать масштабирование чертежей. 60 м — это разумный предел
    // для индивидуального жилого дома (СП 55.13330).
    return parsed.clamp(0.0, 60.0);
  }
}

// =====================================================================
// Шаг 5: состав комнат
// =====================================================================

class _RoomsStep extends StatefulWidget {
  const _RoomsStep({required this.brief, required this.onChanged});

  final ClientBrief brief;
  final VoidCallback onChanged;

  @override
  State<_RoomsStep> createState() => _RoomsStepState();
}

class _RoomsStepState extends State<_RoomsStep> {
  int _activeFloor = 1;

  /// Активен ли «ручной» режим. Хранится как явное состояние
  /// виджета, а не выводится из `brief.floorRooms.isNotEmpty`,
  /// потому что пустые под-карты в floorRooms могли сохраниться от
  /// прошлой сессии и не должны автоматически отключать manual UI.
  /// Стартовое значение восстанавливается из brief: если есть хотя бы
  /// один этаж с заполненными комнатами — manual on.
  late bool _manualOn = brief.floorRooms.values
      .any((m) => m.values.any((v) => v > 0));

  ClientBrief get brief => widget.brief;

  // ----- Auto-режим (общий список комнат) -----
  int _count(RoomKind k) => brief.rooms[k.name] ?? 0;
  void _set(RoomKind k, int v) {
    setState(() {
      if (v <= 0) {
        brief.rooms.remove(k.name);
      } else {
        brief.rooms[k.name] = v;
      }
    });
    widget.onChanged();
  }

  // ----- Manual-режим (per-floor) -----
  String get _activeKey =>
      _activeFloor == 0
          ? ClientBrief.floorKey(0, mansard: true)
          : ClientBrief.floorKey(_activeFloor);

  Map<String, int> _floorRoomMap(String key) =>
      brief.floorRooms.putIfAbsent(key, () => <String, int>{});

  int _countForActive(RoomKind k) => _floorRoomMap(_activeKey)[k.name] ?? 0;
  void _setForActive(RoomKind k, int v) {
    setState(() {
      final map = _floorRoomMap(_activeKey);
      if (v <= 0) {
        map.remove(k.name);
      } else {
        map[k.name] = v;
      }
      // Если этаж пустой — удаляем запись, чтобы при пустой карте
      // floorRooms полностью «выключался» ручной режим.
      if (map.isEmpty) brief.floorRooms.remove(_activeKey);
    });
    widget.onChanged();
  }

  void _toggleManual(bool on) {
    setState(() {
      _manualOn = on;
      if (on) {
        // Включаем ручной режим: засеваем 1-й этаж текущим списком комнат
        // (если он непустой). brief.rooms НЕ очищаем — это «резервная
        // копия»: если пользователь снова выключит ручной режим без
        // изменений, мы сможем вернуться к исходному составу даже при
        // пустых картах этажей.
        final floors = brief.floors ?? 1;
        if (brief.rooms.isNotEmpty) {
          final firstKey = ClientBrief.floorKey(1);
          brief.floorRooms[firstKey] =
              Map<String, int>.from(brief.rooms);
        }
        if (floors > 1) {
          for (var f = 2; f <= floors; f++) {
            brief.floorRooms.putIfAbsent(
              ClientBrief.floorKey(f),
              () => <String, int>{},
            );
          }
        }
        if (brief.hasMansard == true) {
          brief.floorRooms.putIfAbsent(
            ClientBrief.floorKey(0, mansard: true),
            () => <String, int>{},
          );
        }
      } else {
        // Выключаем ручной режим: агрегируем этажи в brief.rooms.
        // Если агрегат пуст (пользователь включил ручной режим, ничего
        // не добавил и сразу выключил) — НЕ затираем brief.rooms,
        // оставляем то, что было до включения.
        final aggregated = <String, int>{};
        for (final inner in brief.floorRooms.values) {
          inner.forEach((k, v) {
            aggregated[k] = (aggregated[k] ?? 0) + v;
          });
        }
        brief.floorRooms.clear();
        if (aggregated.isNotEmpty) {
          brief.rooms
            ..clear()
            ..addAll(aggregated);
        }
      }
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final floors = brief.floors ?? 1;
    final hasMansard = brief.hasMansard == true;
    return ListView(
      children: [
        Text('Состав помещений', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Укажите желаемое количество помещений каждого типа.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Распределить вручную по этажам'),
          subtitle: const Text(
            'Включите, если хотите задать состав комнат отдельно для '
            'каждого этажа. Иначе генератор распределит автоматически.',
          ),
          value: _manualOn,
          onChanged: floors > 1 || hasMansard ? _toggleManual : null,
        ),
        if (_manualOn) ...[
          const SizedBox(height: 8),
          _FloorTabs(
            floors: floors,
            hasMansard: hasMansard,
            active: _activeFloor,
            onChanged: (v) => setState(() => _activeFloor = v),
          ),
          const SizedBox(height: 8),
          for (final k in RoomKind.values.where((e) => e.userSelectable))
            ListTile(
              title: Text(k.title),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _countForActive(k) <= 0
                        ? null
                        : () => _setForActive(k, _countForActive(k) - 1),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${_countForActive(k)}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () =>
                        _setForActive(k, _countForActive(k) + 1),
                  ),
                ],
              ),
            ),
        ] else ...[
          for (final k in RoomKind.values.where((e) => e.userSelectable))
            ListTile(
              title: Text(k.title),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed:
                        _count(k) <= 0 ? null : () => _set(k, _count(k) - 1),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${_count(k)}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _set(k, _count(k) + 1),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// Полоса вкладок для выбора активного этажа в ручном режиме
/// распределения комнат.
class _FloorTabs extends StatelessWidget {
  const _FloorTabs({
    required this.floors,
    required this.hasMansard,
    required this.active,
    required this.onChanged,
  });

  final int floors;
  final bool hasMansard;
  final int active; // 0 = мансарда, иначе номер этажа
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <_FloorTabItem>[
      for (var f = 1; f <= floors; f++)
        _FloorTabItem(value: f, label: 'Этаж $f'),
      if (hasMansard) const _FloorTabItem(value: 0, label: 'Мансарда'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(it.label),
                selected: it.value == active,
                onSelected: (_) => onChanged(it.value),
                labelStyle: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }
}

class _FloorTabItem {
  final int value;
  final String label;
  const _FloorTabItem({required this.value, required this.label});
}

// =====================================================================
// Шаг 6: дополнения
// =====================================================================

class _AddonsStep extends StatelessWidget {
  const _AddonsStep({required this.brief, required this.onChanged});

  final ClientBrief brief;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Text('Дополнения', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Отметьте всё, что нужно учесть в проекте.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Гараж'),
          subtitle: const Text(
            'На следующем шаге попросим габариты, тип кровли и материал стен.',
          ),
          value: brief.hasGarage ?? false,
          onChanged: (v) {
            brief.hasGarage = v;
            if (v && brief.garageSpec == null) {
              brief.garageSpec =
                  AttachmentSpec.defaultGarage(brief.wallMaterial);
            }
            onChanged();
          },
        ),
        SwitchListTile(
          title: const Text('Терраса'),
          subtitle: const Text(
            'На следующем шаге попросим габариты и тип навеса.',
          ),
          value: brief.hasTerrace ?? false,
          onChanged: (v) {
            brief.hasTerrace = v;
            if (v && brief.terraceSpec == null) {
              brief.terraceSpec = AttachmentSpec.defaultTerrace();
            }
            onChanged();
          },
        ),
        SwitchListTile(
          title: const Text('Балкон'),
          value: brief.hasBalcony ?? false,
          onChanged: (v) {
            brief.hasBalcony = v;
            onChanged();
          },
        ),
        SwitchListTile(
          title: const Text('Эркер'),
          value: brief.hasOriel ?? false,
          onChanged: (v) {
            brief.hasOriel = v;
            onChanged();
          },
        ),
        SwitchListTile(
          title: const Text('Второй свет'),
          subtitle: const Text(
            'Помещение высотой в два этажа без перекрытия',
          ),
          value: brief.hasDoubleHeight ?? false,
          onChanged: (v) {
            brief.hasDoubleHeight = v;
            onChanged();
          },
        ),
      ],
    );
  }
}

// =====================================================================

class _LayoutSchemeStep extends StatefulWidget {
  const _LayoutSchemeStep({required this.brief, required this.onChanged});

  final ClientBrief brief;
  final VoidCallback onChanged;

  @override
  State<_LayoutSchemeStep> createState() => _LayoutSchemeStepState();
}

class _LayoutSchemeStepState extends State<_LayoutSchemeStep> {
  // 0 = «общая схема» (применяется ко всем этажам по умолчанию),
  // 1..floors = конкретный этаж, -1 = мансарда.
  int _activeTab = 0;

  ClientBrief get brief => widget.brief;

  bool get _hasMultipleFloors =>
      (brief.floors ?? 1) > 1 || brief.hasMansard == true;

  String? _activeKey() {
    if (_activeTab == 0) return null; // общая схема
    if (_activeTab < 0) {
      return ClientBrief.floorKey(0, mansard: true);
    }
    return ClientBrief.floorKey(_activeTab);
  }

  LayoutScheme _activeScheme() {
    final key = _activeKey();
    if (key == null) return brief.layoutScheme;
    return brief.schemeForFloor(key);
  }

  void _setActiveScheme(LayoutScheme s) {
    setState(() {
      final key = _activeKey();
      if (key == null) {
        // Меняем «базовую» схему. Записи в floorSchemes не трогаем —
        // этажи без явной записи продолжат брать из базовой.
        brief.layoutScheme = s;
      } else {
        brief.floorSchemes[key] = s.name;
      }
    });
    widget.onChanged();
  }

  void _resetFloorOverride() {
    final key = _activeKey();
    if (key == null) return;
    setState(() {
      brief.floorSchemes.remove(key);
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final floors = brief.floors ?? 1;
    final hasMansard = brief.hasMansard == true;
    final activeKey = _activeKey();
    final activeScheme = _activeScheme();
    final hasOverride = activeKey != null &&
        brief.floorSchemes.containsKey(activeKey);

    return ListView(
      children: [
        Text('Схема планировки', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Как расставить комнаты внутри застройки. Выбранная '
          'схема определяет логику автоматического планировщика. '
          'Для большинства домов 80–150 м² подходит коридорная.',
          style: theme.textTheme.bodyMedium,
        ),
        if (_hasMultipleFloors) ...[
          const SizedBox(height: 12),
          Text(
            'Вы можете задать общую схему для всего дома или выбрать '
            'отдельную схему для каждого этажа.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          _SchemeFloorTabs(
            floors: floors,
            hasMansard: hasMansard,
            active: _activeTab,
            floorSchemes: brief.floorSchemes,
            onChanged: (v) => setState(() => _activeTab = v),
          ),
          const SizedBox(height: 8),
          if (activeKey == null)
            Text(
              'Базовая схема применяется ко всем этажам, для которых '
              'не выбрана своя.',
              style: theme.textTheme.bodySmall,
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    hasOverride
                        ? 'У этажа задана своя схема.'
                        : 'Используется базовая схема. Выберите ниже, '
                            'чтобы задать отдельную схему для этажа.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (hasOverride)
                  TextButton(
                    onPressed: _resetFloorOverride,
                    child: const Text('Сбросить'),
                  ),
              ],
            ),
        ],
        const SizedBox(height: 12),
        for (final s in LayoutScheme.values)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: activeScheme == s
                ? theme.colorScheme.primaryContainer
                : null,
            child: ListTile(
              leading: Icon(
                activeScheme == s
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: activeScheme == s
                    ? theme.colorScheme.primary
                    : null,
              ),
              title: Text(s.title),
              subtitle: Text(s.description),
              onTap: () => _setActiveScheme(s),
            ),
          ),
        // П.9 v40: кнопка «Сгенерировать другой вариант» — увеличивает
        // brief.planSeed, чтобы FloorPlanGenerator перемешал комнаты
        // в банках и предложил иное расположение тех же помещений.
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Альтернативная расстановка',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Перемешает порядок комнат в банках и предложит '
                'другую расстановку — но в рамках выбранной схемы '
                'и того же состава комнат. '
                'Текущий вариант: №${(brief.planSeed ?? 0) + 1}.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Сгенерировать другой вариант'),
                onPressed: () {
                  setState(() {
                    brief.planSeed = (brief.planSeed ?? 0) + 1;
                  });
                  widget.onChanged();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Полоса вкладок для выбора активного этажа в шаге «Схема планировки».
/// Первая вкладка — «Все этажи» (базовая схема), далее по этажам и
/// мансарда. Этажи с заданной собственной схемой помечаются точкой.
class _SchemeFloorTabs extends StatelessWidget {
  const _SchemeFloorTabs({
    required this.floors,
    required this.hasMansard,
    required this.active,
    required this.floorSchemes,
    required this.onChanged,
  });

  final int floors;
  final bool hasMansard;
  final int active; // 0 = общий, -1 = мансарда, иначе номер этажа
  final Map<String, String> floorSchemes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    bool hasOverride(String key) => floorSchemes.containsKey(key);
    final items = <_SchemeTabItem>[
      const _SchemeTabItem(value: 0, label: 'Все этажи', hasOverride: false),
      for (var f = 1; f <= floors; f++)
        _SchemeTabItem(
          value: f,
          label: 'Этаж $f',
          hasOverride: hasOverride(ClientBrief.floorKey(f)),
        ),
      if (hasMansard)
        _SchemeTabItem(
          value: -1,
          label: 'Мансарда',
          hasOverride: hasOverride(ClientBrief.floorKey(0, mansard: true)),
        ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(it.label),
                    if (it.hasOverride) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                selected: it.value == active,
                onSelected: (_) => onChanged(it.value),
                labelStyle: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }
}

class _SchemeTabItem {
  final int value;
  final String label;
  final bool hasOverride;
  const _SchemeTabItem({
    required this.value,
    required this.label,
    required this.hasOverride,
  });
}

// =====================================================================

/// Шаг «Габариты пристроек»: отдельные мини-брифы для гаража и
/// террасы — Ш×Д×В, тип кровли, материал стен. Появляется только
/// если выбран хотя бы один из пунктов «Гараж» / «Терраса».
class _AttachmentDimensionsStep extends StatefulWidget {
  const _AttachmentDimensionsStep({
    required this.brief,
    required this.onChanged,
  });
  final ClientBrief brief;
  final VoidCallback onChanged;

  @override
  State<_AttachmentDimensionsStep> createState() =>
      _AttachmentDimensionsStepState();
}

class _AttachmentDimensionsStepState extends State<_AttachmentDimensionsStep> {
  ClientBrief get brief => widget.brief;

  AttachmentSpec _ensureGarage() => brief.garageSpec ??=
      AttachmentSpec.defaultGarage(brief.wallMaterial);

  AttachmentSpec _ensureTerrace() =>
      brief.terraceSpec ??= AttachmentSpec.defaultTerrace();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showGarage = brief.hasGarage == true;
    final showTerrace = brief.hasTerrace == true;
    return ListView(
      children: [
        Text('Габариты пристроек', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Эти размеры пойдут в чертежи плана, фасадов и 3D-модель. '
          'Можете изменить позже на этапе «Архитектурные решения».',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (showGarage)
          _AttachmentCard(
            title: 'Гараж',
            spec: _ensureGarage(),
            allowEmptyWalls: false,
            onChanged: () {
              setState(() {});
              widget.onChanged();
            },
          ),
        if (showGarage && showTerrace) const SizedBox(height: 16),
        if (showTerrace)
          _AttachmentCard(
            title: 'Терраса',
            spec: _ensureTerrace(),
            allowEmptyWalls: true,
            onChanged: () {
              setState(() {});
              widget.onChanged();
            },
          ),
        if (!showGarage && !showTerrace)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Пристройки не выбраны. Нажмите «Сохранить и перейти '
              'к этапу 2».',
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

/// Карточка ввода для одной пристройки (гараж или терраса).
class _AttachmentCard extends StatefulWidget {
  const _AttachmentCard({
    required this.title,
    required this.spec,
    required this.allowEmptyWalls,
    required this.onChanged,
  });
  final String title;
  final AttachmentSpec spec;

  /// Для террасы — можно «без стен» (открытая); для гаража — стены
  /// обязательны.
  final bool allowEmptyWalls;
  final VoidCallback onChanged;

  @override
  State<_AttachmentCard> createState() => _AttachmentCardState();
}

class _AttachmentCardState extends State<_AttachmentCard> {
  late final TextEditingController _w;
  late final TextEditingController _l;
  late final TextEditingController _h;

  @override
  void initState() {
    super.initState();
    _w = TextEditingController(text: _fmt(widget.spec.width));
    _l = TextEditingController(text: _fmt(widget.spec.length));
    _h = TextEditingController(text: _fmt(widget.spec.height));
  }

  @override
  void dispose() {
    _w.dispose();
    _l.dispose();
    _h.dispose();
    super.dispose();
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void _setW(String s) {
    final v = double.tryParse(s.replaceAll(',', '.'));
    if (v == null || v <= 0) return;
    // §27.3: ограничиваем 0.5..30 м (для гаража/террасы реально
    // максимум 12-15, но даём запас).
    widget.spec.width = v.clamp(0.5, 30.0);
    widget.onChanged();
  }

  void _setL(String s) {
    final v = double.tryParse(s.replaceAll(',', '.'));
    if (v == null || v <= 0) return;
    widget.spec.length = v.clamp(0.5, 30.0);
    widget.onChanged();
  }

  void _setH(String s) {
    final v = double.tryParse(s.replaceAll(',', '.'));
    if (v == null || v <= 0) return;
    // §27.3: высота пристройки 1.5..6 м.
    widget.spec.height = v.clamp(1.5, 6.0);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = widget.spec;
    final wallMaterials = WallMaterial.values;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _w,
                    decoration: const InputDecoration(
                      labelText: 'Ширина, м',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: _setW,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _l,
                    decoration: const InputDecoration(
                      labelText: 'Длина, м',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: _setL,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _h,
                    decoration: const InputDecoration(
                      labelText: 'Высота, м',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: _setH,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Тип кровли', style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: AttachmentRoofKind.values.map((k) {
                final selected = spec.roof == k;
                return ChoiceChip(
                  label: Text(k.title),
                  selected: selected,
                  onSelected: (_) {
                    spec.roof = k;
                    widget.onChanged();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text(
              widget.allowEmptyWalls
                  ? 'Материал стен (или «без стен» — открытая)'
                  : 'Материал стен',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (widget.allowEmptyWalls)
                  ChoiceChip(
                    label: const Text('Без стен'),
                    selected: spec.wallMaterialName == null,
                    onSelected: (_) {
                      spec.wallMaterialName = null;
                      widget.onChanged();
                    },
                  ),
                ...wallMaterials.map((m) {
                  final selected = spec.wallMaterialName == m.name;
                  return ChoiceChip(
                    label: Text(m.title),
                    selected: selected,
                    onSelected: (_) {
                      spec.wallMaterialName = m.name;
                      widget.onChanged();
                    },
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
