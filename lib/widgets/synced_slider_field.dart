import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Слайдер + текстовое поле, синхронизированные между собой.
///
/// Используется там, где нужно одновременно дать пользователю
/// быстро тащить ползунок и точно вписать значение. Любое изменение —
/// и слайдера, и текстового поля — попадает в [onChanged] с уже
/// обрезанным до диапазона [min..max] значением.
///
/// Параметр [step] задаёт «дискретность» (для divisions слайдера и
/// для красивого форматирования текста). Если [decimals] = 0, число
/// показывается без дробной части и считается целым (миллиметры);
/// если > 0 — с указанной точностью (метры).
class SyncedSliderField extends StatefulWidget {
  const SyncedSliderField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.onChanged,
    this.decimals = 0,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String unit;
  final int decimals;
  final ValueChanged<double> onChanged;

  @override
  State<SyncedSliderField> createState() => _SyncedSliderFieldState();
}

class _SyncedSliderFieldState extends State<SyncedSliderField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focusNode = FocusNode();
    // Когда поле теряет фокус — нормализуем введённое значение
    // (если пользователь напечатал, например, «,» или вышел за границы).
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant SyncedSliderField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _format(double v) {
    if (widget.decimals == 0) return v.toStringAsFixed(0);
    return v.toStringAsFixed(widget.decimals);
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commitText(_controller.text);
    }
  }

  void _commitText(String raw) {
    final parsed = double.tryParse(raw.replaceAll(',', '.'));
    if (parsed == null) {
      _controller.text = _format(widget.value);
      return;
    }
    final clamped = parsed.clamp(widget.min, widget.max).toDouble();
    final snapped = _snap(clamped);
    _controller.text = _format(snapped);
    if (snapped != widget.value) widget.onChanged(snapped);
  }

  double _snap(double v) {
    if (widget.step <= 0) return v;
    final n = ((v - widget.min) / widget.step).round();
    return widget.min + n * widget.step;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divisions =
        ((widget.max - widget.min) / widget.step).round().clamp(1, 1000);
    final clampedValue =
        widget.value.clamp(widget.min, widget.max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Slider(
                value: clampedValue,
                min: widget.min,
                max: widget.max,
                divisions: divisions,
                label: '${_format(clampedValue)} ${widget.unit}',
                onChanged: (v) {
                  final snapped = _snap(v);
                  _controller.text = _format(snapped);
                  widget.onChanged(snapped);
                },
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: widget.decimals > 0,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    widget.decimals > 0
                        ? RegExp(r'[0-9.,]')
                        : RegExp(r'[0-9]'),
                  ),
                ],
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixText: widget.unit,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                ),
                onSubmitted: _commitText,
                onEditingComplete: () => _commitText(_controller.text),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
