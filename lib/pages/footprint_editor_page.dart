// Phase-3b §17.2.1 / 17.2.2 next-slice: визуальный редактор контура
// пятна застройки.
//
// Поддерживает четыре параметризованные формы:
//   • Прямоугольник (width × length)
//   • L-форма (с вырезом cutWidth × cutHeight в правом-нижнем углу)
//   • T-форма (центрированный стержень снизу)
//   • U-форма (центрированный вырез сверху)
//   • Свободный полигон (drag-and-drop вершин, любая axis-aligned
//     или произвольная форма ≥ 3 вершин — Phase-3b §21.1.1).
//
// Для каждой формы редактор показывает живое превью контура в
// реальных пропорциях. Сохранение возвращает либо
// `BuildingFootprint?` (полигональная форма), либо `null` (для
// прямоугольника — поля `footprintWidth/Length` в брифе уже
// достаточно).

import 'package:flutter/material.dart';

import '../models/building_footprint.dart';
import '../services/polygon_helpers.dart';
import '../widgets/synced_slider_field.dart';

/// Тип формы пятна для редактора. Не выходит наружу — в проекте
/// хранится только сериализованный `BuildingFootprint`.
enum _FootprintShape { rectangle, lShape, tShape, uShape, custom }

/// Шаг сетки для drag-snap-а (м).
enum _SnapStep { none, fine, half, meter }

extension _SnapStepX on _SnapStep {
  double get meters {
    switch (this) {
      case _SnapStep.none:
        return 0.0;
      case _SnapStep.fine:
        return 0.1;
      case _SnapStep.half:
        return 0.5;
      case _SnapStep.meter:
        return 1.0;
    }
  }

  String get label {
    switch (this) {
      case _SnapStep.none:
        return 'Без привязки';
      case _SnapStep.fine:
        return '0,1 м';
      case _SnapStep.half:
        return '0,5 м';
      case _SnapStep.meter:
        return '1 м';
    }
  }
}

/// Результат сохранения формы.
class FootprintEditorResult {
  /// Габариты bbox в метрах (используются и для прямоугольника, и для
  /// полигональных форм — они совпадают с `footprintWidth/Length`
  /// брифа).
  final double width;
  final double length;

  /// Полигональный контур. `null` означает «обычный прямоугольник» —
  /// проект использует bbox-овую логику.
  final BuildingFootprint? footprint;

  const FootprintEditorResult({
    required this.width,
    required this.length,
    required this.footprint,
  });
}

class FootprintEditorPage extends StatefulWidget {
  /// Начальные значения. Если `initialFootprint` задан и не является
  /// прямоугольником, экран открывается в соответствующем режиме
  /// (L/T/U). Иначе — режим «Прямоугольник».
  final double initialWidth;
  final double initialLength;
  final BuildingFootprint? initialFootprint;

  const FootprintEditorPage({
    super.key,
    required this.initialWidth,
    required this.initialLength,
    this.initialFootprint,
  });

  @override
  State<FootprintEditorPage> createState() => _FootprintEditorPageState();
}

class _FootprintEditorPageState extends State<FootprintEditorPage> {
  late _FootprintShape _shape;
  late double _w;
  late double _l;
  // Параметры выреза/стержня. Хранятся отдельно, чтобы переключение
  // между формами не теряло введённые значения.
  double _cutW = 4;
  double _cutH = 4;
  double _stemW = 4;
  double _stemH = 4;
  // Phase-3b §17.2.4 next-slice: режим «Свободный полигон» —
  // редактируемый список вершин (axis-aligned, любое число ≥ 3).
  List<Vec2> _customOutline = const [];
  // §21.1.1: индекс вершины, которую сейчас тащат (drag); null когда
  // нет активного жеста.
  int? _draggingIndex;
  // §21.7: шаг сетки для drag-snap-а (по умолчанию 0,5 м).
  _SnapStep _snapStep = _SnapStep.half;

  @override
  void initState() {
    super.initState();
    _w = widget.initialWidth.clamp(4.0, 25.0).toDouble();
    _l = widget.initialLength.clamp(4.0, 25.0).toDouble();
    final fp = widget.initialFootprint;
    if (fp == null || fp.outline.length == 4) {
      _shape = _FootprintShape.rectangle;
    } else if (fp.outline.length == 6) {
      _shape = _FootprintShape.lShape;
      // Выводим cutWidth/cutHeight из bbox - длиннейшего сегмента.
      final b = fp.bbox;
      _w = b.width;
      _l = b.height;
      // Берём вершину «уступа» как вершину с минимальным X и максимальным Y
      // — для L-формы из `BuildingFootprint.lShape` это outline[3].
      final notch = fp.outline[3];
      _cutW = b.maxX - notch.x;
      _cutH = b.maxY - notch.y;
    } else if (fp.outline.length == 8) {
      // T или U по характерной форме первого сегмента.
      final b = fp.bbox;
      _w = b.width;
      _l = b.height;
      // U-форма: outline[1].y == 0, outline[2].y > 0 (вырез сверху).
      // T-форма: outline[2].y > 0 ниже верхней грани (стержень снизу).
      final p1 = fp.outline[1];
      if (p1.y == 0 && p1.x < b.maxX) {
        _shape = _FootprintShape.uShape;
        // U: cutWidth = outline[4].x - outline[1].x, cutHeight = outline[2].y
        _cutW = fp.outline[4].x - fp.outline[1].x;
        _cutH = fp.outline[2].y;
      } else {
        _shape = _FootprintShape.tShape;
        // T: stemWidth = outline[4].x - outline[5].x, stemHeight = h - topH
        final topH = fp.outline[2].y;
        _stemH = b.height - topH;
        _stemW = fp.outline[4].x - fp.outline[5].x;
      }
    } else {
      _shape = _FootprintShape.rectangle;
    }
    if (fp != null && _shape == _FootprintShape.rectangle && fp.outline.length > 4) {
      // Произвольный полигон — переключаемся в кастом-режим.
      _shape = _FootprintShape.custom;
      _customOutline = List<Vec2>.from(fp.outline);
      _w = fp.bbox.width;
      _l = fp.bbox.height;
    }
  }

  /// Возвращает безопасный кастомный outline. Если пустой — возвращает
  /// прямоугольник по текущим _w / _l.
  List<Vec2> _safeCustomOutline() {
    if (_customOutline.length >= 3) return _customOutline;
    return [
      const Vec2(0, 0),
      Vec2(_w, 0),
      Vec2(_w, _l),
      Vec2(0, _l),
    ];
  }

  /// Текущий полигональный footprint (или null для прямоугольника).
  BuildingFootprint? _currentFootprint() {
    switch (_shape) {
      case _FootprintShape.rectangle:
        return null;
      case _FootprintShape.lShape:
        if (_cutW <= 0 || _cutH <= 0 || _cutW >= _w || _cutH >= _l) {
          return null;
        }
        return BuildingFootprint.lShape(
          width: _w,
          height: _l,
          cutWidth: _cutW,
          cutHeight: _cutH,
        );
      case _FootprintShape.tShape:
        if (_stemW <= 0 || _stemH <= 0 || _stemW >= _w || _stemH >= _l) {
          return null;
        }
        return BuildingFootprint.tShape(
          width: _w,
          height: _l,
          stemWidth: _stemW,
          stemHeight: _stemH,
        );
      case _FootprintShape.uShape:
        if (_cutW <= 0 || _cutH <= 0 || _cutW >= _w || _cutH >= _l) {
          return null;
        }
        return BuildingFootprint.uShape(
          width: _w,
          height: _l,
          cutWidth: _cutW,
          cutHeight: _cutH,
        );
      case _FootprintShape.custom:
        if (_customOutline.length < 3) return null;
        final candidate = BuildingFootprint(outline: List.of(_customOutline));
        if (candidate.area < 0.01) return null;
        // Если outline ориентирован CW — разворачиваем в CCW.
        if (candidate.signedArea < 0) {
          return BuildingFootprint(
            outline: candidate.outline.reversed.toList(),
          );
        }
        return candidate;
    }
  }

  void _ensureCustomOutline() {
    if (_customOutline.length < 3) {
      _customOutline = _safeCustomOutline();
    }
  }

  void _addVertexAfter(int index) {
    _ensureCustomOutline();
    final cur = _customOutline[index];
    final next = _customOutline[(index + 1) % _customOutline.length];
    final mid = Vec2(
      ((cur.x + next.x) / 2 * 2).round() / 2,
      ((cur.y + next.y) / 2 * 2).round() / 2,
    );
    setState(() {
      _customOutline = [
        ..._customOutline.sublist(0, index + 1),
        mid,
        ..._customOutline.sublist(index + 1),
      ];
    });
  }

  void _removeVertex(int index) {
    if (_customOutline.length <= 3) return;
    setState(() {
      _customOutline = [
        ..._customOutline.sublist(0, index),
        ..._customOutline.sublist(index + 1),
      ];
    });
  }

  void _editVertex(int index, double? x, double? y) {
    final cur = _customOutline[index];
    // §27.3: координаты вершины пятна — в физически осмысленном
    // диапазоне 0..60 м от начала bbox.
    final newX = (x ?? cur.x).clamp(0.0, 60.0);
    final newY = (y ?? cur.y).clamp(0.0, 60.0);
    setState(() {
      _customOutline = [
        ..._customOutline.sublist(0, index),
        Vec2(newX, newY),
        ..._customOutline.sublist(index + 1),
      ];
    });
  }

  /// Кнопка «Сделать axis-aligned» — округляет все вершины кастомного
  /// outline-а к шагу сетки и вычищает coллинеарные вершины (§21.7).
  void _snapAllToGrid() {
    _ensureCustomOutline();
    final step = _snapStep.meters > 0 ? _snapStep.meters : 0.5;
    final snapped = snapOutlineToGrid(
      _customOutline,
      step: step,
      maxX: _w,
      maxY: _l,
    );
    final cleaned = removeCollinearVertices(snapped);
    setState(() {
      _customOutline = cleaned;
    });
  }

  List<Widget> _buildCustomVertexEditors(ThemeData theme) {
    _ensureCustomOutline();
    final list = <Widget>[];
    for (var i = 0; i < _customOutline.length; i++) {
      final v = _customOutline[i];
      final convexity = vertexConvexity(_customOutline, i);
      final dotColor = _convexityColor(convexity, theme);
      list.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${i + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: TextFormField(
                  initialValue: v.x.toStringAsFixed(1),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: false,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'X, м',
                    isDense: true,
                  ),
                  onFieldSubmitted: (s) {
                    final p = double.tryParse(s.replaceAll(',', '.'));
                    if (p != null) _editVertex(i, p, null);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: v.y.toStringAsFixed(1),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: false,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Y, м',
                    isDense: true,
                  ),
                  onFieldSubmitted: (s) {
                    final p = double.tryParse(s.replaceAll(',', '.'));
                    if (p != null) _editVertex(i, null, p);
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Добавить вершину после',
                onPressed: () => _addVertexAfter(i),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Удалить вершину',
                onPressed: _customOutline.length <= 3
                    ? null
                    : () => _removeVertex(i),
              ),
            ],
          ),
        ),
      );
    }
    return list;
  }

  Color _convexityColor(VertexConvexity c, ThemeData theme) {
    switch (c) {
      case VertexConvexity.convex:
        return Colors.green.shade700;
      case VertexConvexity.reflex:
        return Colors.deepOrange.shade700;
      case VertexConvexity.collinear:
        return theme.colorScheme.outline;
    }
  }

  /// Сидинг для перехода в режим «Свободный» — берёт текущую форму
  /// (прямоугольник / L / T / U) как стартовый полигон.
  BuildingFootprint _currentFootprintForCustomSeed() {
    final fp = _currentFootprint();
    if (fp != null) return fp;
    return BuildingFootprint.rect(_w, _l);
  }

  void _save() {
    Navigator.pop(
      context,
      FootprintEditorResult(
        width: _w,
        length: _l,
        footprint: _currentFootprint(),
      ),
    );
  }

  // ─────────────────── Drag-and-drop помощники (§21.1.1) ──────────────

  /// Конвертирует точку из локальных координат превью-canvas-а в
  /// модельные координаты (метры, [0..viewW] × [0..viewH]).
  Vec2 _localToModel(Offset p, Size size, double viewW, double viewH) {
    const pad = 16.0;
    final scaleX = (size.width - 2 * pad) / viewW;
    final scaleY = (size.height - 2 * pad) / viewH;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final ox = (size.width - viewW * scale) / 2;
    final oy = (size.height - viewH * scale) / 2;
    final mx = (p.dx - ox) / scale;
    final my = (p.dy - oy) / scale;
    return Vec2(mx, my);
  }

  /// Возвращает индекс ближайшей вершины custom-outline в радиусе
  /// `hitRadiusPx` от точки [p] (в локальных пикселях). null если
  /// никто не попадает.
  int? _hitVertexAt(Offset p, Size size, double viewW, double viewH,
      {double hitRadiusPx = 18.0}) {
    if (_customOutline.length < 3) return null;
    const pad = 16.0;
    final scaleX = (size.width - 2 * pad) / viewW;
    final scaleY = (size.height - 2 * pad) / viewH;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final ox = (size.width - viewW * scale) / 2;
    final oy = (size.height - viewH * scale) / 2;
    int? bestIdx;
    double bestDist2 = hitRadiusPx * hitRadiusPx;
    for (var i = 0; i < _customOutline.length; i++) {
      final v = _customOutline[i];
      final x = ox + v.x * scale;
      final y = oy + v.y * scale;
      final dx = x - p.dx;
      final dy = y - p.dy;
      final d2 = dx * dx + dy * dy;
      if (d2 < bestDist2) {
        bestDist2 = d2;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  void _onPanStart(Offset localPos, Size size, double viewW, double viewH) {
    _ensureCustomOutline();
    final idx = _hitVertexAt(localPos, size, viewW, viewH);
    if (idx != null) {
      setState(() => _draggingIndex = idx);
    }
  }

  void _onPanUpdate(Offset localPos, Size size, double viewW, double viewH) {
    if (_draggingIndex == null) return;
    final m = _localToModel(localPos, size, viewW, viewH);
    final step = _snapStep.meters;
    final clampedX = snapToGrid(m.x, step: step, lo: 0, hi: viewW);
    final clampedY = snapToGrid(m.y, step: step, lo: 0, hi: viewH);
    final i = _draggingIndex!;
    setState(() {
      _customOutline = [
        ..._customOutline.sublist(0, i),
        Vec2(clampedX, clampedY),
        ..._customOutline.sublist(i + 1),
      ];
    });
  }

  void _onPanEnd() {
    if (_draggingIndex != null) {
      setState(() => _draggingIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fp = _currentFootprint();
    final area =
        fp == null ? _w * _l : fp.area; // для прямоугольника — bbox.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Форма пятна застройки'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Тип формы', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<_FootprintShape>(
            segments: const [
              ButtonSegment(
                value: _FootprintShape.rectangle,
                label: Text('Прямоугольник'),
                icon: Icon(Icons.crop_square),
              ),
              ButtonSegment(
                value: _FootprintShape.lShape,
                label: Text('L'),
              ),
              ButtonSegment(
                value: _FootprintShape.tShape,
                label: Text('T'),
              ),
              ButtonSegment(
                value: _FootprintShape.uShape,
                label: Text('U'),
              ),
              ButtonSegment(
                value: _FootprintShape.custom,
                label: Text('Свободный'),
                icon: Icon(Icons.gesture),
              ),
            ],
            selected: {_shape},
            onSelectionChanged: (s) {
              setState(() {
                _shape = s.first;
                if (_shape == _FootprintShape.custom &&
                    _customOutline.isEmpty) {
                  // Инициализируем кастомный outline на текущий
                  // прямоугольник или текущий полигон из L/T/U.
                  final fp = _currentFootprintForCustomSeed();
                  _customOutline = List<Vec2>.from(fp.outline);
                }
              });
            },
          ),
          const SizedBox(height: 16),
          Text('Габариты, м', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SyncedSliderField(
            label: 'Ширина (по X)',
            min: 4,
            max: 25,
            step: 0.5,
            unit: 'м',
            value: _w,
            onChanged: (v) => setState(() => _w = v),
          ),
          const SizedBox(height: 8),
          SyncedSliderField(
            label: 'Длина (по Y)',
            min: 4,
            max: 25,
            step: 0.5,
            unit: 'м',
            value: _l,
            onChanged: (v) => setState(() => _l = v),
          ),
          if (_shape == _FootprintShape.custom) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text('Вершины полигона (м)',
                      style: theme.textTheme.titleSmall),
                ),
                DropdownButton<_SnapStep>(
                  value: _snapStep,
                  onChanged: (v) {
                    if (v != null) setState(() => _snapStep = v);
                  },
                  items: [
                    for (final s in _SnapStep.values)
                      DropdownMenuItem(value: s, child: Text('Шаг: ${s.label}')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Перетаскивай вершины пальцем/мышкой прямо на превью '
              '(зелёные — выпуклые, оранжевые — впуклые «уступы»). '
              'Координаты можно править вручную и ниже. Кнопка '
              '«Привязать к сетке» выровняет все вершины по выбранному '
              'шагу и удалит лишние коллинеарные точки.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ..._buildCustomVertexEditors(theme),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить вершину в конец'),
                  onPressed: () {
                    _ensureCustomOutline();
                    _addVertexAfter(_customOutline.length - 1);
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.grid_4x4),
                  label: const Text('Привязать к сетке'),
                  onPressed: _snapAllToGrid,
                ),
              ],
            ),
          ],
          if (_shape != _FootprintShape.rectangle &&
              _shape != _FootprintShape.custom) ...[
            const SizedBox(height: 16),
            Text(_shape == _FootprintShape.tShape ? 'Стержень' : 'Вырез',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_shape == _FootprintShape.tShape) ...[
              SyncedSliderField(
                label: 'Ширина стержня',
                min: 1,
                max: _w - 0.5,
                step: 0.5,
                unit: 'м',
                value: _stemW.clamp(1.0, _w - 0.5),
                onChanged: (v) => setState(() => _stemW = v),
              ),
              const SizedBox(height: 8),
              SyncedSliderField(
                label: 'Высота стержня',
                min: 1,
                max: _l - 0.5,
                step: 0.5,
                unit: 'м',
                value: _stemH.clamp(1.0, _l - 0.5),
                onChanged: (v) => setState(() => _stemH = v),
              ),
            ] else ...[
              SyncedSliderField(
                label: 'Ширина выреза',
                min: 1,
                max: _w - 0.5,
                step: 0.5,
                unit: 'м',
                value: _cutW.clamp(1.0, _w - 0.5),
                onChanged: (v) => setState(() => _cutW = v),
              ),
              const SizedBox(height: 8),
              SyncedSliderField(
                label: 'Глубина выреза',
                min: 1,
                max: _l - 0.5,
                step: 0.5,
                unit: 'м',
                value: _cutH.clamp(1.0, _l - 0.5),
                onChanged: (v) => setState(() => _cutH = v),
              ),
            ],
          ],
          const SizedBox(height: 16),
          Text('Превью контура', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: _w / _l,
            child: _shape == _FootprintShape.custom
                ? LayoutBuilder(builder: (ctx, constraints) {
                    final size =
                        Size(constraints.maxWidth, constraints.maxHeight);
                    return Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colorScheme.outline
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) => _onPanStart(
                            d.localPosition, size, _w, _l),
                        onPanUpdate: (d) => _onPanUpdate(
                            d.localPosition, size, _w, _l),
                        onPanEnd: (_) => _onPanEnd(),
                        onPanCancel: _onPanEnd,
                        child: CustomPaint(
                          painter: _FootprintInteractivePainter(
                            outline: _safeCustomOutline(),
                            viewWidth: _w,
                            viewHeight: _l,
                            fillColor: theme.colorScheme.primary
                                .withValues(alpha: 0.18),
                            strokeColor: theme.colorScheme.primary,
                            gridStepM: _snapStep.meters,
                            gridColor: theme.colorScheme.outline
                                .withValues(alpha: 0.2),
                            convexColor: Colors.green.shade700,
                            reflexColor: Colors.deepOrange.shade700,
                            collinearColor: theme.colorScheme.outline,
                            draggingColor:
                                theme.colorScheme.tertiary,
                            draggingIndex: _draggingIndex,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    );
                  })
                : Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.outline
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: CustomPaint(
                      painter: _FootprintPreviewPainter(
                        footprint: fp ?? BuildingFootprint.rect(_w, _l),
                        fillColor: theme.colorScheme.primary
                            .withValues(alpha: 0.18),
                        strokeColor: theme.colorScheme.primary,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text('Площадь: ${area.toStringAsFixed(1)} м²')),
              Chip(label: Text('Габарит: '
                  '${_w.toStringAsFixed(1)} × '
                  '${_l.toStringAsFixed(1)} м')),
              if (fp != null)
                Chip(label: Text('Вершин: ${fp.outline.length}')),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Сохранить форму'),
          ),
        ],
      ),
    );
  }
}

class _FootprintPreviewPainter extends CustomPainter {
  final BuildingFootprint footprint;
  final Color fillColor;
  final Color strokeColor;
  _FootprintPreviewPainter({
    required this.footprint,
    required this.fillColor,
    required this.strokeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final box = footprint.bbox;
    const pad = 16.0;
    final scaleX = (size.width - 2 * pad) / box.width;
    final scaleY = (size.height - 2 * pad) / box.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final ox = (size.width - box.width * scale) / 2;
    final oy = (size.height - box.height * scale) / 2;
    final path = Path();
    final outline = footprint.outline;
    for (var i = 0; i < outline.length; i++) {
      final p = outline[i];
      final x = ox + (p.x - box.minX) * scale;
      final y = oy + (p.y - box.minY) * scale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Маркеры вершин.
    final dotPaint = Paint()..color = strokeColor;
    for (final p in outline) {
      final x = ox + (p.x - box.minX) * scale;
      final y = oy + (p.y - box.minY) * scale;
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_FootprintPreviewPainter oldDelegate) {
    if (oldDelegate.footprint.outline.length != footprint.outline.length) {
      return true;
    }
    for (var i = 0; i < footprint.outline.length; i++) {
      if (oldDelegate.footprint.outline[i].x != footprint.outline[i].x ||
          oldDelegate.footprint.outline[i].y != footprint.outline[i].y) {
        return true;
      }
    }
    return false;
  }
}

/// Painter для интерактивного режима «Свободный полигон» (§21.1.1):
/// фиксированная видовая область `viewWidth × viewHeight` (в
/// метрах), сетка с шагом [gridStepM], цветовая подсветка
/// convex/reflex вершин, выделение перетаскиваемой вершины.
class _FootprintInteractivePainter extends CustomPainter {
  final List<Vec2> outline;
  final double viewWidth;
  final double viewHeight;
  final Color fillColor;
  final Color strokeColor;
  final double gridStepM;
  final Color gridColor;
  final Color convexColor;
  final Color reflexColor;
  final Color collinearColor;
  final Color draggingColor;
  final int? draggingIndex;

  _FootprintInteractivePainter({
    required this.outline,
    required this.viewWidth,
    required this.viewHeight,
    required this.fillColor,
    required this.strokeColor,
    required this.gridStepM,
    required this.gridColor,
    required this.convexColor,
    required this.reflexColor,
    required this.collinearColor,
    required this.draggingColor,
    required this.draggingIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 16.0;
    final scaleX = (size.width - 2 * pad) / viewWidth;
    final scaleY = (size.height - 2 * pad) / viewHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final ox = (size.width - viewWidth * scale) / 2;
    final oy = (size.height - viewHeight * scale) / 2;

    // Рамка видовой области.
    final viewRect = Rect.fromLTWH(
      ox,
      oy,
      viewWidth * scale,
      viewHeight * scale,
    );
    canvas.drawRect(
      viewRect,
      Paint()
        ..color = gridColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Сетка по шагу snap-а.
    if (gridStepM > 0) {
      final gridPaint = Paint()
        ..color = gridColor
        ..strokeWidth = 0.6;
      for (double gx = 0; gx <= viewWidth + 1e-6; gx += gridStepM) {
        final x = ox + gx * scale;
        canvas.drawLine(
          Offset(x, oy),
          Offset(x, oy + viewHeight * scale),
          gridPaint,
        );
      }
      for (double gy = 0; gy <= viewHeight + 1e-6; gy += gridStepM) {
        final y = oy + gy * scale;
        canvas.drawLine(
          Offset(ox, y),
          Offset(ox + viewWidth * scale, y),
          gridPaint,
        );
      }
    }

    // Сам полигон.
    if (outline.length >= 3) {
      final path = Path();
      for (var i = 0; i < outline.length; i++) {
        final p = outline[i];
        final x = ox + p.x * scale;
        final y = oy + p.y * scale;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = strokeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      // Подсветка вершин по convex/reflex + выделение dragging.
      final ccw = polygonIsCcw(outline);
      for (var i = 0; i < outline.length; i++) {
        final v = outline[i];
        var c = vertexConvexity(outline, i);
        if (!ccw) {
          // В CW-полигоне convex и reflex меняются местами.
          if (c == VertexConvexity.convex) {
            c = VertexConvexity.reflex;
          } else if (c == VertexConvexity.reflex) {
            c = VertexConvexity.convex;
          }
        }
        final color = c == VertexConvexity.convex
            ? convexColor
            : c == VertexConvexity.reflex
                ? reflexColor
                : collinearColor;
        final x = ox + v.x * scale;
        final y = oy + v.y * scale;
        final isDragging = i == draggingIndex;
        final radius = isDragging ? 8.0 : 5.0;
        canvas.drawCircle(
          Offset(x, y),
          radius,
          Paint()..color = isDragging ? draggingColor : color,
        );
        if (isDragging) {
          canvas.drawCircle(
            Offset(x, y),
            radius + 3,
            Paint()
              ..color = draggingColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_FootprintInteractivePainter old) {
    if (old.outline.length != outline.length) return true;
    if (old.draggingIndex != draggingIndex) return true;
    if (old.gridStepM != gridStepM) return true;
    if (old.viewWidth != viewWidth || old.viewHeight != viewHeight) return true;
    for (var i = 0; i < outline.length; i++) {
      if (old.outline[i].x != outline[i].x ||
          old.outline[i].y != outline[i].y) {
        return true;
      }
    }
    return false;
  }
}
