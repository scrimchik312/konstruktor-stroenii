import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/region_catalog.dart';
import '../../data/soil_types.dart';
import '../../models/borehole.dart';
import '../../models/client_brief.dart';
import '../../models/house_project.dart';
import '../../models/soil_layer.dart';
import '../../state/app_state.dart';
import '../../widgets/hints.dart';
import 'foundation_type_page.dart';

/// Шаг 0 раздела «Фундамент» — инженерно-климатические данные участка.
///
/// Заполняются: регион, снеговой/ветровой район по СП 20.13330.2016,
/// разрез грунта по СП 22.13330.2016. Грунт описывается **списком слоёв**,
/// каждый со своей глубиной залегания, мощностью и опционально —
/// физико-механическими показателями (плотность, e, W, Wₗ, Wₚ, c, φ, E).
/// На основании этих данных подбирается тип фундамента.
class SitePreliminariesPage extends StatefulWidget {
  const SitePreliminariesPage({super.key, required this.projectId});

  final String projectId;

  @override
  State<SitePreliminariesPage> createState() => _SitePreliminariesPageState();
}

class _SitePreliminariesPageState extends State<SitePreliminariesPage> {
  late HouseProject _project;
  late ClientBrief _brief;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _project = state.projects.firstWhere(
      (p) => p.id == widget.projectId,
      orElse: () => throw StateError('project not found'),
    );
    _brief = _project.brief;
    // Гарантируем, что хотя бы расчётная скважина С-1 существует и
    // имеет хотя бы один слой (иначе пользователю нечего будет редактировать).
    if (_brief.boreholes.isEmpty) {
      _brief.boreholes.add(Borehole(label: 'С-1'));
    }
    for (final b in _brief.boreholes) {
      if (b.layers.isEmpty) {
        b.layers.add(SoilLayer(topDepth: 0));
      }
    }
  }

  bool get _isFilled =>
      _brief.region != null &&
      _brief.snowZone != null &&
      _brief.windZone != null &&
      _brief.boreholes.any(
        (b) => b.layers.any((l) => l.type != null),
      );

  Future<void> _continue() async {
    final state = context.read<AppState>();
    final navigator = Navigator.of(context);
    await state.saveProject(_project);
    if (!mounted) return;
    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => FoundationTypePage(projectId: _project.id),
      ),
    );
  }

  void _addLayerToBorehole(Borehole borehole) {
    setState(() {
      // Глубина кровли нового слоя = низ предыдущего слоя (если задано).
      double? newTop;
      if (borehole.layers.isNotEmpty) {
        final last = borehole.layers.last;
        if (last.topDepth != null && last.thickness != null) {
          newTop = last.topDepth! + last.thickness!;
        }
      }
      borehole.layers.add(SoilLayer(topDepth: newTop));
    });
  }

  void _removeLayerFromBorehole(Borehole borehole, int index) {
    setState(() {
      borehole.layers.removeAt(index);
      if (borehole.layers.isEmpty) {
        borehole.layers.add(SoilLayer(topDepth: 0));
      }
    });
  }

  void _addBorehole() {
    setState(() {
      final n = _brief.boreholes.length + 1;
      _brief.boreholes.add(
        Borehole(label: 'С-$n', layers: [SoilLayer(topDepth: 0)]),
      );
    });
  }

  void _removeBorehole(int index) {
    if (index == 0) return; // С-1 (расчётную) удалить нельзя
    setState(() {
      _brief.boreholes.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Фундамент · Участок'),
        actions: const [
          HintIconButton(
            title: 'Зачем эти данные',
            sections: Hints.sitePreliminaries,
          ),
        ],
      ),
      body: HintAutoShow(
        screenKey: 'site-preliminaries',
        title: 'Зачем эти данные',
        sections: Hints.sitePreliminaries,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Чтобы корректно подобрать фундамент, нужны три '
                      'вещи про участок: климат (снеговой и ветровой район '
                      'по СП 20.13330.2016), регион (для глубины промерзания) и '
                      'инженерно-геологический разрез (по СП 22.13330.2016). '
                      'Город заполняет климат автоматически. Грунт '
                      'описывается списком слоёв: для каждого — глубина '
                      'кровли слоя, мощность и (опционально) физико-'
                      'механические показатели.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Регион строительства',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Начните вводить название — подсказки появятся автоматически. '
                  'Каталог: ~300 городов РФ с предзаполненными снеговым и '
                  'ветровым районами по СП 20.13330.2016.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Autocomplete<RegionInfo>(
                  displayStringForOption: (r) => r.city,
                  initialValue: TextEditingValue(text: _brief.region ?? ''),
                  optionsBuilder: (TextEditingValue value) {
                    final q = value.text.trim().toLowerCase();
                    if (q.isEmpty) {
                      return kRegionCatalog.take(20);
                    }
                    return kRegionCatalog.where(
                      (r) => r.city.toLowerCase().contains(q),
                    );
                  },
                  onSelected: (RegionInfo r) {
                    setState(() {
                      _brief.region = r.city;
                      _brief.snowZone = r.snowZone;
                      _brief.windZone = r.windZone;
                    });
                  },
                  fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Город',
                        hintText: 'Например: Санкт-Петербург',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                    );
                  },
                ),
                if (_brief.region != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Снеговой район',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            _brief.snowZone?.toString() ?? '—',
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Ветровой район',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            _brief.windZone ?? '—',
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Геологические скважины',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addBorehole,
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить скважину'),
                    ),
                  ],
                ),
                Text(
                  'Каждая скважина — отдельный столбец справа. По каждой: '
                  'метка, координаты на участке, уровень подземных вод '
                  'на момент бурения и слои сверху вниз. По СП 47.13330.2016 '
                  'для ИЖС — не менее 2-3 скважин глубиной 5-7 м. '
                  'Скважина С-1 (расчётная) используется в подборе фундамента, '
                  'остальные попадают в ведомость изысканий и на ситуационный план.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                // ---- Скважины как горизонтальный набор столбцов ----
                _BoreholeColumnsScroll(
                  boreholes: _brief.boreholes,
                  onAddLayer: _addLayerToBorehole,
                  onRemoveLayer: _removeLayerFromBorehole,
                  onRemoveBorehole: _removeBorehole,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isFilled ? _continue : null,
                  child: const Text('Далее: тип фундамента'),
                ),
                if (!_isFilled)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Заполните регион и тип грунта верхнего слоя, '
                      'чтобы продолжить.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
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
}

/// Карточка одного слоя грунта в инженерно-геологическом разрезе.
///
/// Сверху — обязательные поля (тип, глубина кровли, мощность),
/// ниже — раскрывающаяся секция «Физико-механические показатели»
/// (плотность, влажности, e, c, φ, E).
class _SoilLayerCard extends StatefulWidget {
  const _SoilLayerCard({
    super.key,
    required this.index,
    required this.layer,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final SoilLayer layer;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  State<_SoilLayerCard> createState() => _SoilLayerCardState();
}

class _SoilLayerCardState extends State<_SoilLayerCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layer = widget.layer;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Слой ${widget.index + 1}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                if (widget.canRemove)
                  IconButton(
                    tooltip: 'Удалить слой',
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<SoilType>(
              decoration: const InputDecoration(
                labelText: 'Тип грунта (по СП 22.13330.2016)',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
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
            const SizedBox(height: 12),
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
                const SizedBox(width: 12),
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
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                    const SizedBox(width: 4),
                    Text(
                      'Физико-механические показатели',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              Text('Физические показатели',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              _twoCol(
                _NumField(
                  label: 'ρ — плотность, г/см³',
                  value: layer.density,
                  onChanged: (v) {
                    layer.density = v;
                    widget.onChanged();
                  },
                ),
                _NumField(
                  label: 'ρₛ — частиц, г/см³',
                  value: layer.particleDensity,
                  onChanged: (v) {
                    layer.particleDensity = v;
                    widget.onChanged();
                  },
                ),
              ),
              _twoCol(
                _NumField(
                  label: 'W — влажность',
                  value: layer.naturalMoisture,
                  onChanged: (v) {
                    layer.naturalMoisture = v;
                    widget.onChanged();
                  },
                ),
                _NumField(
                  label: 'e — пористости',
                  value: layer.voidRatio,
                  onChanged: (v) {
                    layer.voidRatio = v;
                    widget.onChanged();
                  },
                ),
              ),
              _twoCol(
                _NumField(
                  label: 'Wₗ — гр. текучести',
                  value: layer.liquidLimit,
                  onChanged: (v) {
                    layer.liquidLimit = v;
                    widget.onChanged();
                  },
                ),
                _NumField(
                  label: 'Wₚ — гр. раскат.',
                  value: layer.plasticLimit,
                  onChanged: (v) {
                    layer.plasticLimit = v;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text('Механические показатели',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              _twoCol(
                _NumField(
                  label: 'φ — угол трения, °',
                  value: layer.frictionAngle,
                  onChanged: (v) {
                    layer.frictionAngle = v;
                    widget.onChanged();
                  },
                ),
                _NumField(
                  label: 'c — сцепление, кПа',
                  value: layer.cohesion,
                  onChanged: (v) {
                    layer.cohesion = v;
                    widget.onChanged();
                  },
                ),
              ),
              _twoCol(
                _NumField(
                  label: 'E — мод. деф., МПа',
                  value: layer.deformationModulus,
                  onChanged: (v) {
                    layer.deformationModulus = v;
                    widget.onChanged();
                  },
                ),
                const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _twoCol(Widget a, Widget b) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b),
        ],
      ),
    );
  }
}

/// Числовое поле, принимающее десятичное значение (запятая или точка).
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
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value == null ? '' : _format(widget.value!),
    );
  }

  @override
  void didUpdateWidget(covariant _NumField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final asText = widget.value == null ? '' : _format(widget.value!);
      if (_controller.text != asText) _controller.text = asText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _format(double v) {
    final s = v.toStringAsFixed(3);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: InputDecoration(
        isDense: true,
        labelText: widget.label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (raw) {
        if (raw.isEmpty) {
          widget.onChanged(null);
          return;
        }
        final parsed = double.tryParse(raw.replaceAll(',', '.'));
        if (parsed != null) widget.onChanged(parsed);
      },
    );
  }
}

/// Горизонтальный скролл колонок-скважин: каждая скважина — отдельный
/// столбец фиксированной ширины. Новая скважина добавляется справа от
/// последнего столбца.
class _BoreholeColumnsScroll extends StatelessWidget {
  const _BoreholeColumnsScroll({
    required this.boreholes,
    required this.onAddLayer,
    required this.onRemoveLayer,
    required this.onRemoveBorehole,
    required this.onChanged,
  });

  final List<Borehole> boreholes;
  final void Function(Borehole) onAddLayer;
  final void Function(Borehole, int) onRemoveLayer;
  final void Function(int) onRemoveBorehole;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < boreholes.length; i++) ...[
              SizedBox(
                width: 360,
                child: _BoreholeColumn(
                  index: i,
                  borehole: boreholes[i],
                  isPrimary: i == 0,
                  onAddLayer: () => onAddLayer(boreholes[i]),
                  onRemoveLayer: (li) => onRemoveLayer(boreholes[i], li),
                  onRemoveBorehole: () => onRemoveBorehole(i),
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ],
        ),
      ),
    );
  }
}

/// Один столбец-скважина: метка, X/Y, УГВ, слои сверху вниз, кнопка
/// «Добавить слой».
class _BoreholeColumn extends StatelessWidget {
  const _BoreholeColumn({
    required this.index,
    required this.borehole,
    required this.isPrimary,
    required this.onAddLayer,
    required this.onRemoveLayer,
    required this.onRemoveBorehole,
    required this.onChanged,
  });

  final int index;
  final Borehole borehole;

  /// `true` — это расчётная С-1 (нельзя удалить).
  final bool isPrimary;

  final VoidCallback onAddLayer;
  final ValueChanged<int> onRemoveLayer;
  final VoidCallback onRemoveBorehole;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: isPrimary
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
          : theme.colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок столбца
            Row(
              children: [
                Expanded(
                  child: Text(
                    isPrimary
                        ? '${borehole.label ?? 'С-1'} · расчётная'
                        : (borehole.label ?? 'Скважина'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!isPrimary)
                  IconButton(
                    tooltip: 'Удалить скважину',
                    onPressed: onRemoveBorehole,
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // Метка
            TextFormField(
              key: ValueKey('bh-label-$index-${borehole.label}'),
              initialValue: borehole.label,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Метка скважины',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                borehole.label = v;
                onChanged();
              },
            ),
            const SizedBox(height: 8),
            // Координаты X/Y
            Row(
              children: [
                Expanded(
                  child: _NumField(
                    label: 'X, м',
                    value: borehole.xOnPlot,
                    onChanged: (v) {
                      borehole.xOnPlot = v;
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NumField(
                    label: 'Y, м',
                    value: borehole.yOnPlot,
                    onChanged: (v) {
                      borehole.yOnPlot = v;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // УГВ для этой скважины
            _NumField(
              label: 'УГВ от устья, м',
              value: borehole.groundwaterLevelM,
              onChanged: (v) {
                borehole.groundwaterLevelM = v;
                onChanged();
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Глубина встречи подземных вод при бурении. '
              'Пусто — УГВ не вскрыт. СП 22.13330.2016 п. 5.5.5.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // Слои этой скважины
            Text('Слои грунта (сверху вниз)',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (var i = 0; i < borehole.layers.length; i++)
              _SoilLayerCard(
                key: ValueKey(
                    'bh-${borehole.label}-${index}-layer-$i-${borehole.layers.length}'),
                index: i,
                layer: borehole.layers[i],
                canRemove: borehole.layers.length > 1,
                onRemove: () => onRemoveLayer(i),
                onChanged: onChanged,
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAddLayer,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Добавить слой'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
