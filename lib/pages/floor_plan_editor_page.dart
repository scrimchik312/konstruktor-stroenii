import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/rooms_catalog.dart';
import '../models/floor_plan.dart';
import '../models/house_project.dart';
import '../services/floor_plan_generator.dart';
import '../state/app_state.dart';
import '../widgets/floor_plan_view.dart';
import '../widgets/hints.dart';

/// Полноэкранный редактор схематического плана этажа.
///
/// Доступен только в режиме «Проектировщик». Позволяет:
///   * выделить комнату однократным касанием;
///   * перетащить выделенную комнату за её тело;
///   * изменить размеры комнаты, потянув за одну из 4 угловых ручек;
///   * сохранить результат как **новую версию** чертежей (с пометкой
///     «ручная правка») или сбросить и выйти.
///
/// Координаты при отпускании пальца округляются до сетки 0.1 м.
/// Минимальный размер любой стороны — 1.0 м, чтобы избежать вырожденных
/// прямоугольников. Двери и окна не пересчитываются (пока — фаза 1.7.2).
class FloorPlanEditorPage extends StatefulWidget {
  const FloorPlanEditorPage({
    super.key,
    required this.project,
    required this.drawingId,
    required this.initialPlan,
  });

  final HouseProject project;
  final String drawingId;
  final FloorPlan initialPlan;

  @override
  State<FloorPlanEditorPage> createState() => _FloorPlanEditorPageState();
}

enum _ResizeAnchor { topLeft, topRight, bottomLeft, bottomRight }

enum _DragMode { none, move, resize }

enum _OpeningHandle { start, end }

enum _EditorMode { rooms, openings }

class _FloorPlanEditorPageState extends State<FloorPlanEditorPage> {
  static const double _padding = 24;
  static const double _handleHitRadiusPx = 22;
  static const double _gridStep = 0.1; // м, шаг привязки
  static const double _minSide = 1.0; // м, минимальный размер стороны
  static const double _minOpeningLen = 0.6; // м (СП 55.13330.2017)
  static const double _innerWall = 0.20;

  late FloorPlan _plan = widget.initialPlan;
  _EditorMode _mode = _EditorMode.rooms;

  // Состояние режима «Комнаты».
  int? _selectedIndex;
  _DragMode _dragMode = _DragMode.none;
  _ResizeAnchor? _anchor;
  Offset _dragStartM = Offset.zero;
  PlanRoom? _dragInitialRoom;

  // Состояние режима «Двери и окна».
  int? _selectedOpening;
  _OpeningHandle? _openingHandle;
  PlanOpening? _dragInitialOpening;
  bool _openingsManuallyEdited = false;

  bool _dirty = false;

  bool get _isFirstFloor => widget.initialPlan.floorLabel == 'Этаж 1';

  /// Множество индексов комнат, которые перекрываются с какой-либо другой
  /// «обычной» комнатой (тип `room`). Используется для подсветки красной
  /// рамкой и блокировки кнопки «Сохранить».
  Set<int> _overlappingIndexes() {
    final set = <int>{};
    for (var i = 0; i < _plan.rooms.length; i++) {
      final a = _plan.rooms[i];
      if (a.kind != PlanRoomKind.room) continue;
      for (var j = i + 1; j < _plan.rooms.length; j++) {
        final b = _plan.rooms[j];
        if (b.kind != PlanRoomKind.room) continue;
        final overlapsX =
            a.x < b.x + b.width - 1e-3 && b.x < a.x + a.width - 1e-3;
        final overlapsY =
            a.y < b.y + b.height - 1e-3 && b.y < a.y + a.height - 1e-3;
        if (overlapsX && overlapsY) {
          set.add(i);
          set.add(j);
        }
      }
    }
    return set;
  }

  void _reset() {
    setState(() {
      _plan = widget.initialPlan;
      _selectedIndex = null;
      _selectedOpening = null;
      _dragMode = _DragMode.none;
      _openingHandle = null;
      _openingsManuallyEdited = false;
      _dirty = false;
    });
  }

  Future<void> _save() async {
    if (_overlappingIndexes().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Есть пересекающиеся комнаты (подсвечены красным). '
            'Разведите их перед сохранением.',
          ),
        ),
      );
      return;
    }
    final state = context.read<AppState>();
    // Если пользователь правил двери и окна вручную — сохраняем как есть.
    // Иначе — пересчитываем по правилам СП 55.13330.2017, СП 1.13130.2020, СП 23-102.
    final FloorPlan fresh;
    if (_openingsManuallyEdited) {
      fresh = _plan;
    } else {
      fresh = _plan.copyWith(
        openings: FloorPlanGenerator.recomputeOpenings(
          _plan,
          isFirstFloor: _isFirstFloor,
        ),
      );
    }
    await state.saveManualPlanEdit(
      project: widget.project,
      sourceDrawingId: widget.drawingId,
      editedPlan: fresh,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _addRoom() {
    // Ставим комнату 3×3 м примерно в центре пятна, со сдвигом если уже
    // есть выделение — чтобы не легла идеально поверх старой.
    const w = 3.0;
    const h = 3.0;
    var cx = (_plan.width - w) / 2;
    var cy = (_plan.height - h) / 2;
    final shift = (_plan.rooms.length % 4) * 0.5;
    cx = (cx + shift).clamp(0.0, _plan.width - w);
    cy = (cy + shift).clamp(0.0, _plan.height - h);
    final next = List<PlanRoom>.from(_plan.rooms)
      ..add(PlanRoom(
        label: 'Спальня',
        x: _snap(cx),
        y: _snap(cy),
        width: w,
        height: h,
        area: w * h,
        kind: PlanRoomKind.room,
        roomKindName: RoomKind.bedroom.name,
      ));
    setState(() {
      _plan = _plan.copyWith(rooms: next);
      _selectedIndex = next.length - 1;
      _dirty = true;
    });
  }

  void _deleteSelected() {
    final sel = _selectedIndex;
    if (sel == null) return;
    final r = _plan.rooms[sel];
    if (r.kind != PlanRoomKind.room) return;
    final next = List<PlanRoom>.from(_plan.rooms)..removeAt(sel);
    setState(() {
      _plan = _plan.copyWith(rooms: next);
      _selectedIndex = null;
      _dirty = true;
    });
  }

  void _updateSelected(PlanRoom Function(PlanRoom r) update) {
    final sel = _selectedIndex;
    if (sel == null) return;
    final next = List<PlanRoom>.from(_plan.rooms);
    next[sel] = update(next[sel]);
    setState(() {
      _plan = _plan.copyWith(rooms: next);
      _dirty = true;
    });
  }

  // ---------- Helpers for openings (mode "Двери и окна") ----------

  /// Прямоугольник проёма в координатах метров (по перпендикуляру стене —
  /// на толщину стены 0.20 м, расширенный для удобства hit-теста).
  Rect _openingMeterRect(PlanOpening o, {double pad = 0.0}) {
    final th = _innerWall + pad * 2;
    if (o.side.isHorizontal) {
      return Rect.fromLTWH(o.x, o.y - th / 2, o.length, th);
    }
    return Rect.fromLTWH(o.x - th / 2, o.y, th, o.length);
  }

  /// Концевые точки проёма (для ручек).
  (Offset start, Offset end) _openingEnds(PlanOpening o) {
    if (o.side.isHorizontal) {
      return (Offset(o.x, o.y), Offset(o.x + o.length, o.y));
    }
    return (Offset(o.x, o.y), Offset(o.x, o.y + o.length));
  }

  void _addOpening(OpeningKind kind) {
    final length = switch (kind) {
      OpeningKind.window => 1.5,
      OpeningKind.externalDoor => 0.95,
      OpeningKind.door => 0.9,
      OpeningKind.archway => 1.0,
    };
    // По умолчанию — на верхней наружной стене, посередине.
    final next = List<PlanOpening>.from(_plan.openings)
      ..add(PlanOpening(
        kind: kind,
        side: WallSide.top,
        x: _snap((_plan.width - length) / 2),
        y: 0,
        length: length,
      ));
    setState(() {
      _plan = _plan.copyWith(openings: next);
      _selectedOpening = next.length - 1;
      _openingsManuallyEdited = true;
      _dirty = true;
    });
  }

  void _deleteSelectedOpening() {
    final sel = _selectedOpening;
    if (sel == null) return;
    final next = List<PlanOpening>.from(_plan.openings)..removeAt(sel);
    setState(() {
      _plan = _plan.copyWith(openings: next);
      _selectedOpening = null;
      _openingsManuallyEdited = true;
      _dirty = true;
    });
  }

  void _updateSelectedOpening(PlanOpening Function(PlanOpening o) update) {
    final sel = _selectedOpening;
    if (sel == null) return;
    final next = List<PlanOpening>.from(_plan.openings);
    next[sel] = update(next[sel]);
    setState(() {
      _plan = _plan.copyWith(openings: next);
      _openingsManuallyEdited = true;
      _dirty = true;
    });
  }

  void _onPanStart(Offset localPos, FloorPlanTransform t) {
    if (_mode == _EditorMode.openings) {
      _onPanStartOpening(localPos, t);
      return;
    }
    _onPanStartRoom(localPos, t);
  }

  void _onPanStartRoom(Offset localPos, FloorPlanTransform t) {
    final m = t.toMeters(localPos);
    // 1. Если есть выделение, проверяем угловые ручки.
    final sel = _selectedIndex;
    if (sel != null && sel >= 0 && sel < _plan.rooms.length) {
      final room = _plan.rooms[sel];
      final corners = <(_ResizeAnchor, Offset)>[
        (_ResizeAnchor.topLeft, Offset(room.x, room.y)),
        (_ResizeAnchor.topRight, Offset(room.x + room.width, room.y)),
        (_ResizeAnchor.bottomLeft, Offset(room.x, room.y + room.height)),
        (
          _ResizeAnchor.bottomRight,
          Offset(room.x + room.width, room.y + room.height),
        ),
      ];
      for (final c in corners) {
        final cp = t.toCanvas(c.$2.dx, c.$2.dy);
        if ((cp - localPos).distance <= _handleHitRadiusPx) {
          setState(() {
            _dragMode = _DragMode.resize;
            _anchor = c.$1;
            _dragStartM = m;
            _dragInitialRoom = room;
          });
          return;
        }
      }
    }
    // 2. Хит по комнате (с конца списка — топ-most). Лестницу и
    // свободные зоны не выделяем — они пересчитываются автоматически.
    for (var i = _plan.rooms.length - 1; i >= 0; i--) {
      final r = _plan.rooms[i];
      if (r.kind != PlanRoomKind.room) continue;
      if (m.dx >= r.x &&
          m.dx <= r.x + r.width &&
          m.dy >= r.y &&
          m.dy <= r.y + r.height) {
        setState(() {
          _selectedIndex = i;
          _dragMode = _DragMode.move;
          _dragStartM = m;
          _dragInitialRoom = r;
        });
        return;
      }
    }
    // 3. Пустое попадание — сбрасываем выделение.
    setState(() {
      _selectedIndex = null;
      _dragMode = _DragMode.none;
    });
  }

  void _onPanUpdate(Offset localPos, FloorPlanTransform t) {
    if (_dragMode == _DragMode.none) return;
    if (_mode == _EditorMode.openings) {
      _onPanUpdateOpening(localPos, t);
      return;
    }
    _onPanUpdateRoom(localPos, t);
  }

  void _onPanUpdateRoom(Offset localPos, FloorPlanTransform t) {
    final m = t.toMeters(localPos);
    final dx = m.dx - _dragStartM.dx;
    final dy = m.dy - _dragStartM.dy;
    final sel = _selectedIndex;
    final start = _dragInitialRoom;
    if (sel == null || start == null) return;
    PlanRoom updated;
    if (_dragMode == _DragMode.move) {
      var nx = _snap(start.x + dx);
      var ny = _snap(start.y + dy);
      // Не даём вылезти за пятно застройки. Snap-к-сетке (v68 §24.7):
      // выполняется во время drag, а не после, чтобы пользователь
      // визуально видел шаг 0,1 м.
      nx = nx.clamp(0.0, _plan.width - start.width).toDouble();
      ny = ny.clamp(0.0, _plan.height - start.height).toDouble();
      updated = start.copyWith(x: nx, y: ny);
    } else {
      // resize: snap-к-сетке во время drag (v68 §24.7).
      var left = start.x;
      var top = start.y;
      var right = start.x + start.width;
      var bottom = start.y + start.height;
      switch (_anchor!) {
        case _ResizeAnchor.topLeft:
          left = _snap(start.x + dx).clamp(0.0, right - _minSide).toDouble();
          top = _snap(start.y + dy).clamp(0.0, bottom - _minSide).toDouble();
          break;
        case _ResizeAnchor.topRight:
          right = _snap(start.x + start.width + dx)
              .clamp(left + _minSide, _plan.width)
              .toDouble();
          top = _snap(start.y + dy).clamp(0.0, bottom - _minSide).toDouble();
          break;
        case _ResizeAnchor.bottomLeft:
          left = _snap(start.x + dx).clamp(0.0, right - _minSide).toDouble();
          bottom = _snap(start.y + start.height + dy)
              .clamp(top + _minSide, _plan.height)
              .toDouble();
          break;
        case _ResizeAnchor.bottomRight:
          right = _snap(start.x + start.width + dx)
              .clamp(left + _minSide, _plan.width)
              .toDouble();
          bottom = _snap(start.y + start.height + dy)
              .clamp(top + _minSide, _plan.height)
              .toDouble();
          break;
      }
      updated = start.copyWith(
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
        area: (right - left) * (bottom - top),
      );
    }
    setState(() {
      final next = List<PlanRoom>.from(_plan.rooms);
      next[sel] = updated;
      _plan = _plan.copyWith(rooms: next);
      _dirty = true;
    });
  }

  void _onPanEnd() {
    if (_dragMode == _DragMode.none) return;
    if (_mode == _EditorMode.openings) {
      _onPanEndOpening();
      return;
    }
    _onPanEndRoom();
  }

  void _onPanEndRoom() {
    final sel = _selectedIndex;
    if (sel != null && sel >= 0 && sel < _plan.rooms.length) {
      final r = _plan.rooms[sel];
      final snapped = r.copyWith(
        x: _snap(r.x),
        y: _snap(r.y),
        width: math.max(_minSide, _snap(r.width)),
        height: math.max(_minSide, _snap(r.height)),
        area: math.max(_minSide, _snap(r.width)) *
            math.max(_minSide, _snap(r.height)),
      );
      final next = List<PlanRoom>.from(_plan.rooms);
      next[sel] = snapped;
      setState(() {
        _plan = _plan.copyWith(rooms: next);
      });
    }
    setState(() {
      _dragMode = _DragMode.none;
      _anchor = null;
      _dragInitialRoom = null;
    });
  }

  // ---------- pan handlers for openings mode ----------

  void _onPanStartOpening(Offset localPos, FloorPlanTransform t) {
    final m = t.toMeters(localPos);
    // 1. Если есть выделенный проём — проверяем его концевые ручки.
    final sel = _selectedOpening;
    if (sel != null && sel >= 0 && sel < _plan.openings.length) {
      final o = _plan.openings[sel];
      final ends = _openingEnds(o);
      final startCanvas = t.toCanvas(ends.$1.dx, ends.$1.dy);
      final endCanvas = t.toCanvas(ends.$2.dx, ends.$2.dy);
      if ((startCanvas - localPos).distance <= _handleHitRadiusPx) {
        setState(() {
          _dragMode = _DragMode.resize;
          _openingHandle = _OpeningHandle.start;
          _dragStartM = m;
          _dragInitialOpening = o;
        });
        return;
      }
      if ((endCanvas - localPos).distance <= _handleHitRadiusPx) {
        setState(() {
          _dragMode = _DragMode.resize;
          _openingHandle = _OpeningHandle.end;
          _dragStartM = m;
          _dragInitialOpening = o;
        });
        return;
      }
    }
    // 2. Хит по проёму (с расширением для удобства тача).
    for (var i = _plan.openings.length - 1; i >= 0; i--) {
      final o = _plan.openings[i];
      final r = _openingMeterRect(o, pad: 0.3);
      if (r.contains(Offset(m.dx, m.dy))) {
        setState(() {
          _selectedOpening = i;
          _dragMode = _DragMode.move;
          _dragStartM = m;
          _dragInitialOpening = o;
        });
        return;
      }
    }
    setState(() {
      _selectedOpening = null;
      _dragMode = _DragMode.none;
    });
  }

  void _onPanUpdateOpening(Offset localPos, FloorPlanTransform t) {
    final m = t.toMeters(localPos);
    final sel = _selectedOpening;
    final start = _dragInitialOpening;
    if (sel == null || start == null) return;
    final dx = m.dx - _dragStartM.dx;
    final dy = m.dy - _dragStartM.dy;
    PlanOpening updated;
    if (_dragMode == _DragMode.move) {
      // v68 §24.7: snap-к-сетке во время drag, а не после.
      if (start.side.isHorizontal) {
        final nx = _snap(start.x + dx)
            .clamp(0.0, _plan.width - start.length)
            .toDouble();
        updated = PlanOpening(
          kind: start.kind,
          side: start.side,
          x: nx,
          y: start.y,
          length: start.length,
          swing: start.swing,
        );
      } else {
        final ny = _snap(start.y + dy)
            .clamp(0.0, _plan.height - start.length)
            .toDouble();
        updated = PlanOpening(
          kind: start.kind,
          side: start.side,
          x: start.x,
          y: ny,
          length: start.length,
          swing: start.swing,
        );
      }
    } else {
      // resize: snap-к-сетке во время drag (v68 §24.7).
      if (start.side.isHorizontal) {
        final endX = start.x + start.length;
        if (_openingHandle == _OpeningHandle.start) {
          final nx = _snap(start.x + dx)
              .clamp(0.0, endX - _minOpeningLen)
              .toDouble();
          updated = PlanOpening(
            kind: start.kind,
            side: start.side,
            x: nx,
            y: start.y,
            length: endX - nx,
            swing: start.swing,
          );
        } else {
          final ne = _snap(endX + dx)
              .clamp(start.x + _minOpeningLen, _plan.width)
              .toDouble();
          updated = PlanOpening(
            kind: start.kind,
            side: start.side,
            x: start.x,
            y: start.y,
            length: ne - start.x,
            swing: start.swing,
          );
        }
      } else {
        final endY = start.y + start.length;
        if (_openingHandle == _OpeningHandle.start) {
          final ny = _snap(start.y + dy)
              .clamp(0.0, endY - _minOpeningLen)
              .toDouble();
          updated = PlanOpening(
            kind: start.kind,
            side: start.side,
            x: start.x,
            y: ny,
            length: endY - ny,
            swing: start.swing,
          );
        } else {
          final ne = _snap(endY + dy)
              .clamp(start.y + _minOpeningLen, _plan.height)
              .toDouble();
          updated = PlanOpening(
            kind: start.kind,
            side: start.side,
            x: start.x,
            y: start.y,
            length: ne - start.y,
            swing: start.swing,
          );
        }
      }
    }
    final next = List<PlanOpening>.from(_plan.openings);
    next[sel] = updated;
    setState(() {
      _plan = _plan.copyWith(openings: next);
      _openingsManuallyEdited = true;
      _dirty = true;
    });
  }

  void _onPanEndOpening() {
    final sel = _selectedOpening;
    if (sel != null && sel >= 0 && sel < _plan.openings.length) {
      final o = _plan.openings[sel];
      final snapped = PlanOpening(
        kind: o.kind,
        side: o.side,
        x: _snap(o.x),
        y: _snap(o.y),
        length: math.max(_minOpeningLen, _snap(o.length)),
        swing: o.swing,
      );
      final next = List<PlanOpening>.from(_plan.openings);
      next[sel] = snapped;
      setState(() {
        _plan = _plan.copyWith(openings: next);
      });
    }
    setState(() {
      _dragMode = _DragMode.none;
      _openingHandle = null;
      _dragInitialOpening = null;
    });
  }

  static double _snap(double v) => (v / _gridStep).round() * _gridStep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overlaps = _overlappingIndexes();
    final isRoomsMode = _mode == _EditorMode.rooms;
    final selectedIsRoom = isRoomsMode &&
        _selectedIndex != null &&
        _plan.rooms[_selectedIndex!].kind == PlanRoomKind.room;
    final selectedOpening = !isRoomsMode &&
            _selectedOpening != null &&
            _selectedOpening! >= 0 &&
            _selectedOpening! < _plan.openings.length
        ? _plan.openings[_selectedOpening!]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text('Редактирование: ${_plan.floorLabel}'),
        actions: [
          if (isRoomsMode) ...[
            IconButton(
              tooltip: 'Добавить комнату',
              icon: const Icon(Icons.add_box_outlined),
              onPressed: _addRoom,
            ),
            IconButton(
              tooltip: 'Удалить выделенную комнату',
              icon: const Icon(Icons.delete_outline),
              onPressed: selectedIsRoom ? _deleteSelected : null,
            ),
          ] else ...[
            IconButton(
              tooltip: 'Добавить дверь',
              icon: const Icon(Icons.door_front_door_outlined),
              onPressed: () => _addOpening(OpeningKind.door),
            ),
            IconButton(
              tooltip: 'Добавить окно',
              icon: const Icon(Icons.window_outlined),
              onPressed: () => _addOpening(OpeningKind.window),
            ),
            IconButton(
              tooltip: 'Добавить входную дверь',
              icon: const Icon(Icons.login),
              onPressed: () => _addOpening(OpeningKind.externalDoor),
            ),
            IconButton(
              tooltip: 'Удалить выделенный проём',
              icon: const Icon(Icons.delete_outline),
              onPressed:
                  selectedOpening != null ? _deleteSelectedOpening : null,
            ),
          ],
          if (_dirty)
            IconButton(
              tooltip: 'Сбросить к авторасчёту',
              icon: const Icon(Icons.refresh),
              onPressed: _reset,
            ),
          IconButton(
            tooltip: overlaps.isNotEmpty
                ? 'Сначала разведите пересекающиеся комнаты'
                : 'Сохранить как новую версию',
            icon: const Icon(Icons.save_outlined),
            onPressed: _dirty && overlaps.isEmpty ? _save : null,
          ),
          const HintIconButton(
            title: 'Редактор плана',
            sections: Hints.floorPlanEditor,
          ),
        ],
      ),
      body: HintAutoShow(
        screenKey: 'floor-plan-editor',
        title: 'Редактор плана',
        sections: Hints.floorPlanEditor,
        child: Column(
          children: [
            // Переключатель режима.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SegmentedButton<_EditorMode>(
                segments: const [
                  ButtonSegment(
                    value: _EditorMode.rooms,
                    label: Text('Комнаты'),
                    icon: Icon(Icons.crop_square),
                  ),
                  ButtonSegment(
                    value: _EditorMode.openings,
                    label: Text('Двери и окна'),
                    icon: Icon(Icons.door_sliding_outlined),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) {
                  setState(() {
                    _mode = s.first;
                    _selectedIndex = null;
                    _selectedOpening = null;
                    _dragMode = _DragMode.none;
                  });
                },
              ),
            ),
            Container(
              width: double.infinity,
              color: overlaps.isNotEmpty
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                overlaps.isNotEmpty
                    ? 'Внимание: комнаты пересекаются (красные рамки). '
                        'Разведите их, чтобы можно было сохранить.'
                    : (isRoomsMode
                        ? (selectedIsRoom
                            ? 'Тяните за тело — переместить, за уголки — '
                                'изменить размер. Привязка к сетке 0.1 м. '
                                'После сохранения двери и окна пересчитаются.'
                            : 'Коснитесь комнаты, чтобы выделить. '
                                'Лестница и коридор не редактируются вручную.')
                        : (selectedOpening != null
                            ? 'Тяните за тело — двигать вдоль стены, '
                                'за концы — менять длину. Привязка к 0.1 м. '
                                'Ручная правка отключает автоперерасчёт.'
                            : 'Коснитесь двери или окна, чтобы выделить. '
                                'Кнопками сверху можно добавить новые.')),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: overlaps.isNotEmpty
                      ? theme.colorScheme.onErrorContainer
                      : null,
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  final t = FloorPlanTransform.compute(
                    size: size,
                    plan: _plan,
                    padding: _padding,
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanDown: (d) => _onPanStart(d.localPosition, t),
                    onPanUpdate: (d) => _onPanUpdate(d.localPosition, t),
                    onPanEnd: (_) => _onPanEnd(),
                    onPanCancel: _onPanEnd,
                    onTapDown: (d) {
                      _onPanStart(d.localPosition, t);
                      _onPanEnd();
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: FloorPlanView(plan: _plan, padding: _padding),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _SelectionOverlayPainter(
                                plan: _plan,
                                selectedIndex:
                                    isRoomsMode ? _selectedIndex : null,
                                selectedOpeningIndex:
                                    !isRoomsMode ? _selectedOpening : null,
                                overlapping: overlaps,
                                padding: _padding,
                                accent: theme.colorScheme.primary,
                                error: theme.colorScheme.error,
                                handleFill: theme.colorScheme.surface,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (selectedIsRoom) _buildInfoBar(theme),
            if (selectedOpening != null)
              _buildOpeningInfoBar(theme, selectedOpening),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBar(ThemeData theme) {
    final r = _plan.rooms[_selectedIndex!];
    final currentKind = RoomKind.values.firstWhere(
      (k) => k.name == r.roomKindName,
      orElse: () => RoomKind.bedroom,
    );
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('label-$_selectedIndex'),
                  initialValue: r.label,
                  decoration: const InputDecoration(
                    labelText: 'Название',
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      _updateSelected((room) => room.copyWith(label: v)),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<RoomKind>(
                  key: ValueKey('kind-$_selectedIndex'),
                  value: currentKind,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Тип',
                    isDense: true,
                  ),
                  items: [
                    for (final k in RoomKind.values.where((e) => e.userSelectable))
                      DropdownMenuItem(value: k, child: Text(k.title)),
                  ],
                  onChanged: (k) {
                    if (k == null) return;
                    _updateSelected((room) => room.copyWith(
                          roomKindName: k.name,
                          // Если пользователь не менял label руками,
                          // подгоняем подпись по новому типу.
                          label: room.label == currentKind.title
                              ? k.title
                              : room.label,
                        ));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${r.width.toStringAsFixed(2)} × '
            '${r.height.toStringAsFixed(2)} м '
            '(${(r.width * r.height).toStringAsFixed(1)} м²)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpeningInfoBar(ThemeData theme, PlanOpening o) {
    final kindTitle = switch (o.kind) {
      OpeningKind.door => 'Дверь',
      OpeningKind.externalDoor => 'Входная дверь',
      OpeningKind.window => 'Окно',
      OpeningKind.archway => 'Открытый проход',
    };
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kindTitle, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Стена: ${_sideLabel(o.side)} · '
                  'позиция: ${(o.side.isHorizontal ? o.x : o.y).toStringAsFixed(2)} м · '
                  'длина: ${o.length.toStringAsFixed(2)} м',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<OpeningKind>(
            value: o.kind,
            items: const [
              DropdownMenuItem(value: OpeningKind.door, child: Text('Дверь')),
              DropdownMenuItem(
                value: OpeningKind.externalDoor,
                child: Text('Входная'),
              ),
              DropdownMenuItem(value: OpeningKind.window, child: Text('Окно')),
            ],
            onChanged: (k) {
              if (k == null) return;
              _updateSelectedOpening((op) => PlanOpening(
                    kind: k,
                    side: op.side,
                    x: op.x,
                    y: op.y,
                    length: op.length,
                    swing: op.swing,
                  ));
            },
          ),
        ],
      ),
    );
  }

  String _sideLabel(WallSide s) => switch (s) {
        WallSide.top => 'верх',
        WallSide.bottom => 'низ',
        WallSide.left => 'лево',
        WallSide.right => 'право',
      };
}

class _SelectionOverlayPainter extends CustomPainter {
  _SelectionOverlayPainter({
    required this.plan,
    required this.selectedIndex,
    this.selectedOpeningIndex,
    required this.overlapping,
    required this.padding,
    required this.accent,
    required this.error,
    required this.handleFill,
  });

  final FloorPlan plan;
  final int? selectedIndex;
  final int? selectedOpeningIndex;
  final Set<int> overlapping;
  final double padding;
  final Color accent;
  final Color error;
  final Color handleFill;

  static const double _handleSize = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final t = FloorPlanTransform.compute(
      size: size,
      plan: plan,
      padding: padding,
    );
    // Красные рамки на пересекающихся комнатах.
    final errStroke = Paint()
      ..color = error
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final i in overlapping) {
      if (i < 0 || i >= plan.rooms.length) continue;
      final r = plan.rooms[i];
      final tl = t.toCanvas(r.x, r.y);
      final br = t.toCanvas(r.x + r.width, r.y + r.height);
      canvas.drawRect(Rect.fromPoints(tl, br), errStroke);
    }
    // Выделение проёма (если есть).
    if (selectedOpeningIndex != null &&
        selectedOpeningIndex! >= 0 &&
        selectedOpeningIndex! < plan.openings.length) {
      _paintOpeningSelection(canvas, t, plan.openings[selectedOpeningIndex!]);
    }
    // Выделение и угловые ручки комнаты.
    if (selectedIndex == null) return;
    if (selectedIndex! < 0 || selectedIndex! >= plan.rooms.length) return;
    final r = plan.rooms[selectedIndex!];
    final tl = t.toCanvas(r.x, r.y);
    final br = t.toCanvas(r.x + r.width, r.y + r.height);
    final rect = Rect.fromPoints(tl, br);
    final stroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, stroke);
    final corners = [
      tl,
      Offset(br.dx, tl.dy),
      Offset(tl.dx, br.dy),
      br,
    ];
    final fill = Paint()..color = handleFill;
    final border = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final c in corners) {
      final hr = Rect.fromCenter(
        center: c,
        width: _handleSize,
        height: _handleSize,
      );
      canvas.drawRect(hr, fill);
      canvas.drawRect(hr, border);
    }
  }

  void _paintOpeningSelection(
    Canvas canvas,
    FloorPlanTransform t,
    PlanOpening o,
  ) {
    final stroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final Offset start;
    final Offset end;
    if (o.side.isHorizontal) {
      start = t.toCanvas(o.x, o.y);
      end = t.toCanvas(o.x + o.length, o.y);
    } else {
      start = t.toCanvas(o.x, o.y);
      end = t.toCanvas(o.x, o.y + o.length);
    }
    canvas.drawLine(start, end, stroke);
    // Концевые ручки.
    final fill = Paint()..color = handleFill;
    final border = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final c in [start, end]) {
      final hr = Rect.fromCenter(
        center: c,
        width: _handleSize,
        height: _handleSize,
      );
      canvas.drawRect(hr, fill);
      canvas.drawRect(hr, border);
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionOverlayPainter oldDelegate) =>
      oldDelegate.plan != plan ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.selectedOpeningIndex != selectedOpeningIndex ||
      oldDelegate.overlapping != overlapping ||
      oldDelegate.padding != padding ||
      oldDelegate.accent != accent;
}
