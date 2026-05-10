import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/price_catalog.dart';
import '../data/region_price_factors.dart';
import '../data/unit_conversions.dart';
import '../models/estimate.dart';
import '../models/house_project.dart';
import '../services/estimate_calculator.dart';
import '../state/app_state.dart';

/// Экран «Смета» — таблица с объёмами работ, ценами и итогами по
/// разделам. Ячейка цены редактируется: ввод сразу пересчитывает
/// итог по строке и общий итог.
///
/// Все ручные правки сохраняются в `HouseProject.priceOverrides`,
/// чтобы пережить перезагрузку приложения. Кнопка «Сбросить к базовым»
/// очищает все правки сразу.
///
/// Региональный коэффициент берётся из [regionFactorFor] по
/// `brief.region` и применяется ко всем строкам автоматически.
class EstimatePage extends StatefulWidget {
  const EstimatePage({super.key, required this.projectId});

  final String projectId;

  @override
  State<EstimatePage> createState() => _EstimatePageState();
}

class _EstimatePageState extends State<EstimatePage> {
  HouseProject? _project;
  Estimate? _estimate;

  // Поля ввода для override-цен — отдельный контроллер на строку.
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final n in _focusNodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _ensureLoaded(AppState state) {
    HouseProject? p;
    for (final x in state.projects) {
      if (x.id == widget.projectId) {
        p = x;
        break;
      }
    }
    if (p == null) return;
    if (_project?.id == p.id && _estimate != null) {
      // Только пересчёт, проект тот же.
      return;
    }
    _project = p;
    _recompute();
  }

  void _recompute() {
    final p = _project;
    if (p == null) return;
    _estimate = EstimateCalculator.compute(p);
  }

  TextEditingController _controllerFor(EstimateRow row) {
    final c = _controllers.putIfAbsent(
      row.itemId,
      () => TextEditingController(
        text: _formatPrice(row.overridePrice ?? row.basePrice),
      ),
    );
    final desired = _formatPrice(row.overridePrice ?? row.basePrice);
    final node = _focusNodes.putIfAbsent(row.itemId, () => FocusNode());
    if (!node.hasFocus && c.text != desired) {
      c.text = desired;
    }
    return c;
  }

  FocusNode _focusFor(String itemId) =>
      _focusNodes.putIfAbsent(itemId, () => FocusNode());

  Future<void> _setOverride(String itemId, double? price) async {
    final state = context.read<AppState>();
    final p = _project;
    if (p == null) return;
    if (price == null) {
      p.priceOverrides.remove(itemId);
    } else {
      p.priceOverrides[itemId] = price;
    }
    await state.saveProject(p);
    setState(() {
      _recompute();
    });
  }

  Future<void> _setUnit(String itemId, String? unit) async {
    final state = context.read<AppState>();
    final p = _project;
    if (p == null) return;
    if (unit == null || unit.isEmpty) {
      p.unitOverrides.remove(itemId);
    } else {
      p.unitOverrides[itemId] = unit;
    }
    // При смене единицы сбрасываем ручной override цены, иначе
    // старый override (в старой единице) даст некорректный итог.
    p.priceOverrides.remove(itemId);
    _controllers.remove(itemId)?.dispose();
    await state.saveProject(p);
    setState(() {
      _recompute();
    });
  }

  Future<void> _resetAll() async {
    final state = context.read<AppState>();
    final p = _project;
    if (p == null) return;
    p.priceOverrides.clear();
    p.unitOverrides.clear();
    await state.saveProject(p);
    setState(() {
      for (final c in _controllers.values) {
        c.dispose();
      }
      _controllers.clear();
      _recompute();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _ensureLoaded(state);
    final project = _project;
    final estimate = _estimate;
    if (project == null || estimate == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Смета')),
        body: const Center(child: Text('Проект не найден')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Смета · ${project.name}'),
        actions: [
          if (project.priceOverrides.isNotEmpty ||
              project.unitOverrides.isNotEmpty)
            TextButton.icon(
              onPressed: _resetAll,
              icon: const Icon(Icons.restore),
              label: Text(
                'Сбросить ${project.priceOverrides.length + project.unitOverrides.length} правк${_pluralRu(project.priceOverrides.length + project.unitOverrides.length, "у", "и", "")}',
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SummaryCard(estimate: estimate),
              const SizedBox(height: 16),
              for (final section in EstimateSection.values)
                _SectionCard(
                  section: section,
                  rows:
                      estimate.rows.where((r) => r.section == section).toList(),
                  controllerFor: _controllerFor,
                  focusFor: _focusFor,
                  onCommit: (id, price) => _setOverride(id, price),
                  onUnitChanged: (id, unit) => _setUnit(id, unit),
                ),
              const SizedBox(height: 16),
              _NoticeCard(estimate: estimate),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.estimate});

  final Estimate estimate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byS = estimate.totalsBySection();
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calculate_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Итоги по проекту',
                      style: theme.textTheme.titleMedium),
                ),
                _RegionChip(estimate: estimate),
              ],
            ),
            const SizedBox(height: 12),
            for (final s in EstimateSection.values) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(s.title, style: theme.textTheme.bodyMedium),
                    ),
                    Text(
                      _money(byS[s] ?? 0),
                      style: theme.textTheme.bodyMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ],
                ),
              ),
            ],
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: Text('Сумма без НДС',
                      style: theme.textTheme.bodyLarge),
                ),
                Text(
                  _money(estimate.subtotal),
                  style: theme.textTheme.bodyLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'НДС 20 % (справочно)',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Text(
                  _money(estimate.vat),
                  style: theme.textTheme.bodySmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text('ИТОГО с НДС',
                      style: theme.textTheme.titleLarge),
                ),
                Text(
                  _money(estimate.total),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RegionChip extends StatelessWidget {
  const _RegionChip({required this.estimate});
  final Estimate estimate;

  @override
  Widget build(BuildContext context) {
    final delta = ((estimate.regionFactor - 1.0) * 100).round();
    final label = estimate.region.isEmpty
        ? 'Регион не указан · k=1.00'
        : '${estimate.region} · k=${estimate.regionFactor.toStringAsFixed(2)}'
            '${delta == 0 ? '' : ' (${delta > 0 ? '+' : ''}$delta%)'}';
    return Tooltip(
      message: 'Региональный коэффициент берётся из ТЗ (поле «Регион»). '
          'Применяется ко всем ценам сметы.',
      child: Chip(
        avatar: const Icon(Icons.location_on_outlined, size: 18),
        label: Text(label),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.rows,
    required this.controllerFor,
    required this.focusFor,
    required this.onCommit,
    required this.onUnitChanged,
  });

  final EstimateSection section;
  final List<EstimateRow> rows;
  final TextEditingController Function(EstimateRow) controllerFor;
  final FocusNode Function(String) focusFor;
  final void Function(String itemId, double? price) onCommit;
  final void Function(String itemId, String? unit) onUnitChanged;

  double get _sectionTotal => rows.fold(0.0, (s, r) => s + r.total);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rows.isEmpty) {
      return Card(
        child: ListTile(
          leading: Icon(_iconFor(section), color: theme.colorScheme.outline),
          title: Text(section.title, style: theme.textTheme.titleMedium),
          subtitle: const Text(
            'Раздел ещё не считается — нужны исходные данные '
            'из этапов проекта.',
          ),
        ),
      );
    }
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(_iconFor(section), color: theme.colorScheme.primary),
        title: Text(section.title, style: theme.textTheme.titleMedium),
        subtitle: Text(
          'Итого: ${_money(_sectionTotal)}',
          style: theme.textTheme.bodyMedium,
        ),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 800),
              child: DataTable(
                columnSpacing: 18,
                horizontalMargin: 12,
                headingRowHeight: 40,
                dataRowMinHeight: 56,
                dataRowMaxHeight: 80,
                columns: const [
                  DataColumn(label: Text('Наименование')),
                  DataColumn(label: Text('Ед.')),
                  DataColumn(label: Text('Кол-во'), numeric: true),
                  DataColumn(label: Text('Цена ₽/ед.'), numeric: true),
                  DataColumn(label: Text('Сумма ₽'), numeric: true),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(
                      cells: [
                        DataCell(_TitleCell(row: r)),
                        DataCell(_UnitCell(
                          row: r,
                          onChanged: onUnitChanged,
                        )),
                        DataCell(_NumberCell(value: r.quantity, fractionForce: r.unit == 'шт')),
                        DataCell(
                          _PriceCell(
                            row: r,
                            controller: controllerFor(r),
                            focusNode: focusFor(r.itemId),
                            onCommit: onCommit,
                          ),
                        ),
                        DataCell(
                          _NumberCell(
                            value: r.total,
                            mono: true,
                            bold: r.isOverridden,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

IconData _iconFor(EstimateSection s) {
  switch (s) {
    case EstimateSection.foundation:
      return Icons.foundation_outlined;
    case EstimateSection.walls:
      return Icons.view_module_outlined;
    case EstimateSection.floorSlabs:
      return Icons.horizontal_rule_outlined;
    case EstimateSection.roof:
      return Icons.roofing_outlined;
    case EstimateSection.engineering:
      return Icons.electrical_services_outlined;
    case EstimateSection.finishing:
      return Icons.format_paint_outlined;
  }
}

/// Ячейка «Ед.» — если для строки есть альтернативные единицы,
/// показываем Dropdown; иначе — просто текст.
class _UnitCell extends StatelessWidget {
  const _UnitCell({
    required this.row,
    required this.onChanged,
  });

  final EstimateRow row;
  final void Function(String itemId, String? unit) onChanged;

  @override
  Widget build(BuildContext context) {
    final variants = unitVariantsFor(row.itemId);
    // Если у позиции только базовая единица (или вообще нет записи
    // в kUnitVariants) — показываем текст без интерактива.
    if (variants.length <= 1) {
      return Text(row.unit);
    }
    final theme = Theme.of(context);
    return DropdownButton<String>(
      value: row.unit,
      isDense: true,
      underline: const SizedBox.shrink(),
      style: theme.textTheme.bodyMedium,
      items: [
        for (final v in variants)
          DropdownMenuItem(
            value: v.unit,
            child: Tooltip(
              message: v.note ?? v.unit,
              child: Text(v.unit, overflow: TextOverflow.ellipsis),
            ),
          ),
      ],
      onChanged: (val) {
        if (val == null || val == row.unit) return;
        // Если выбранная единица совпадает с базовой — убираем override.
        final base = row.baseUnit.isEmpty ? row.unit : row.baseUnit;
        onChanged(row.itemId, val == base ? null : val);
      },
    );
  }
}

class _TitleCell extends StatelessWidget {
  const _TitleCell({required this.row});
  final EstimateRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: [
        if (row.quantityNote != null) 'Объём: ${row.quantityNote}',
        'Цена: ${row.source}',
        if (row.regionFactor != 1.0)
          'Региональный коэф. ×${row.regionFactor.toStringAsFixed(2)}',
        if (row.isOverridden)
          'Цена переопределена. Базовая: ${_money(row.basePrice)}',
      ].join('\n'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(row.title,
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _kindLabel(row.kind),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _kindLabel(EstimateItemKind k) {
    switch (k) {
      case EstimateItemKind.material:
        return 'материал';
      case EstimateItemKind.work:
        return 'работа';
      case EstimateItemKind.composite:
        return 'комплекс';
    }
  }
}

class _NumberCell extends StatelessWidget {
  const _NumberCell({
    required this.value,
    this.mono = false,
    this.bold = false,
    this.fractionForce = false,
  });

  final double value;
  final bool mono;
  final bool bold;
  final bool fractionForce;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final txt = mono ? _money(value) : _formatQty(value, asInt: fractionForce);
    return Text(
      txt,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: bold ? FontWeight.w600 : null,
      ),
    );
  }
}

class _PriceCell extends StatefulWidget {
  const _PriceCell({
    required this.row,
    required this.controller,
    required this.focusNode,
    required this.onCommit,
  });
  final EstimateRow row;
  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(String itemId, double? price) onCommit;

  @override
  State<_PriceCell> createState() => _PriceCellState();
}

class _PriceCellState extends State<_PriceCell> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (!widget.focusNode.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    final raw = widget.controller.text.replaceAll(',', '.').trim();
    if (raw.isEmpty) {
      widget.onCommit(widget.row.itemId, null);
      return;
    }
    final price = double.tryParse(raw);
    if (price == null) return;
    final base = widget.row.basePrice;
    if ((price - base).abs() < 0.01) {
      // Совпадает с базовой → снимаем override.
      widget.onCommit(widget.row.itemId, null);
    } else {
      widget.onCommit(widget.row.itemId, price);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.row;
    return SizedBox(
      width: 130,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        textAlign: TextAlign.right,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: false),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        style: TextStyle(
          fontWeight: r.isOverridden ? FontWeight.w600 : FontWeight.normal,
          color: r.isOverridden ? theme.colorScheme.primary : null,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          suffixIcon: r.isOverridden
              ? IconButton(
                  tooltip: 'Сбросить к базовой цене',
                  icon: const Icon(Icons.restore, size: 18),
                  onPressed: () {
                    widget.controller.text = _formatPrice(r.basePrice);
                    widget.onCommit(r.itemId, null);
                  },
                )
              : null,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _commit(),
        onEditingComplete: _commit,
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.estimate});
  final Estimate estimate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('О смете', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Цены справочные и усреднённые по сетям ИЖС-материалов на '
              '2-й квартал 2025 г. (без НДС). Региональный коэффициент '
              'учитывается через таблицу '
              '${kRegionFactorTable.map((e) => "${e.city} ${e.factor.toStringAsFixed(2)}").take(4).join(", ")}… '
              'Любую цену можно переопределить — она сохранится в проекте.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Объёмы посчитаны по тем же формулам, что и спецификация '
              'материалов в PDF (СП 22, СП 50, СП 63). При изменении '
              'материала стен/перекрытий/кровли смета пересчитывается '
              'автоматически.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

// ── helpers ──────────────────────────────────────────────────
String _money(double v) {
  // 1 234 567 ₽ — пробельный разделитель тысяч.
  final n = v.round();
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final pos = s.length - i;
    buf.write(s[i]);
    if (pos > 1 && (pos - 1) % 3 == 0) buf.write(' ');
  }
  return '${buf.toString()} ₽';
}

String _formatPrice(double v) {
  if (v >= 100) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2);
}

String _formatQty(double v, {bool asInt = false}) {
  if (asInt) return v.round().toString();
  if (v >= 100) return v.toStringAsFixed(0);
  if (v >= 10) return v.toStringAsFixed(1);
  return v.toStringAsFixed(2);
}

String _pluralRu(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}
