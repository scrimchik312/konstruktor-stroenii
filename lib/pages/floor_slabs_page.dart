import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/house_project.dart';
import '../state/app_state.dart';
import '../widgets/synced_slider_field.dart';

/// Раздел «Перекрытия» — выбор конструктивной схемы межэтажных
/// перекрытий: монолитное ж/б, сборное ж/б, по деревянным балкам,
/// по металлическим балкам.
///
/// Сечения и армирование подбирает движок `cc_engine` на этапе чертежей,
/// здесь только верхнеуровневый выбор: что именно проектируем и из чего.
class FloorSlabsPage extends StatefulWidget {
  const FloorSlabsPage({super.key, required this.projectId});

  final String projectId;

  @override
  State<FloorSlabsPage> createState() => _FloorSlabsPageState();
}

class _FloorSlabsPageState extends State<FloorSlabsPage> {
  late HouseProject _project;
  String? _type;
  late TextEditingController _materialCtrl;
  double _thickness = 200;

  static const _types = <_SlabTypeOption>[
    _SlabTypeOption(
      id: 'monolith',
      title: 'Монолитное ж/б',
      defaultMaterial: 'Бетон B25 (СП 63.13330.2018), арматура А500С Ø12 (ГОСТ 5781-82)',
      defaultThickness: 200,
      hint: 'Бетон по месту, армирование сетками. Универсальное '
          'решение под любые планировки.',
    ),
    _SlabTypeOption(
      id: 'precast',
      title: 'Сборное ж/б',
      defaultMaterial: 'Плиты ПК 60.15 (ГОСТ 9561-2016), бетон B22,5',
      defaultThickness: 220,
      hint: 'Готовые плиты с завода. Быстрая укладка, но требует '
          'модульной планировки и использование крана для монтажа.',
    ),
    _SlabTypeOption(
      id: 'wood_beams',
      title: 'По деревянным балкам',
      defaultMaterial: 'Сосна 2-го сорта (ГОСТ 8486-86), балка 200×100 мм, шаг 600 мм',
      defaultThickness: 200,
      hint: 'Балки из бруса с настилом. Лёгкое решение для частного '
          'дома без больших пролётов.',
    ),
    _SlabTypeOption(
      id: 'metal_beams',
      title: 'По металлическим балкам',
      defaultMaterial: 'Двутавр 20Б1 (СТО АСЧМ 20-93), сталь С255 (ГОСТ 27772-2015), шаг 800 мм',
      defaultThickness: 200,
      hint: 'Стальные балки и настил. Большие пролёты, трудоёмкий монтаж.',
    ),
  ];

  _SlabTypeOption? _optionFor(String? id) {
    for (final t in _types) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _project = state.projects.firstWhere(
      (p) => p.id == widget.projectId,
      orElse: () => throw StateError('project not found'),
    );
    _type = _project.floorSlabs.type;
    final initialMaterial = _project.floorSlabs.material ??
        _optionFor(_type)?.defaultMaterial ??
        '';
    _materialCtrl = TextEditingController(text: initialMaterial);
    _thickness = _project.floorSlabs.thickness ?? 200;
  }

  @override
  void dispose() {
    _materialCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    _project.floorSlabs.type = _type;
    final m = _materialCtrl.text.trim();
    _project.floorSlabs.material = m.isEmpty ? null : m;
    _project.floorSlabs.thickness = _thickness;
    await state.saveProject(_project);
    messenger.showSnackBar(
      const SnackBar(content: Text('Перекрытия сохранены')),
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _type != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Перекрытия')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Тип перекрытия',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ..._types.map(
                (t) => Card(
                  child: RadioListTile<String>(
                    value: t.id,
                    groupValue: _type,
                    onChanged: (v) {
                      setState(() {
                        _type = v;
                        // При смене типа оба поля сбрасываются на дефолты
                        // для выбранного типа перекрытия — иначе остаются былые
                        // значения, не имеющие смысла в новой конструкции (напр.
                        // «B25» в поле для деревянного перекрытия).
                        _materialCtrl.text = t.defaultMaterial;
                        _thickness = t.defaultThickness;
                      });
                    },
                    title: Text(t.title),
                    subtitle: Text(t.hint),
                    isThreeLine: true,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_type != null) ...[
                Text(
                  'Материал / марка',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _materialCtrl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Например: B25, ПК 60.15, Сосна 200×100',
                  ),
                ),
                const SizedBox(height: 16),
                SyncedSliderField(
                  label: 'Толщина / высота',
                  value: _thickness,
                  min: 100,
                  max: 400,
                  step: 10,
                  unit: 'мм',
                  onChanged: (v) => setState(() => _thickness = v),
                ),
                const SizedBox(height: 16),
                _SlabCalcCard(typeId: _type!, thickness: _thickness),
              ],
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

/// Карточка расчётных показателей перекрытия: ориентировочный пролёт,
/// эксплуатационная нагрузка, собственный вес и прогиб по СП 20.13330.2016 /
/// СП 63.13330.2018 / СП 64.13330.2017 / СП 16.13330.2017.
///
/// Значения ориентировочные и предназначены для предпроектной оценки —
/// окончательный расчёт выполняется в разделе «Расчёты».
class _SlabCalcCard extends StatelessWidget {
  const _SlabCalcCard({required this.typeId, required this.thickness});

  final String typeId;
  final double thickness;

  _SlabCalcResult _calculate() {
    final h = thickness; // мм
    switch (typeId) {
      case 'monolith':
        // Монолит ж/б B25, плита со свободным опиранием, армир. сетка
        // Ø12 шаг 200 ↓+↑. По СП 63.13330.2018 табл. 6.7/6.8.
        // Рекомендуемый пролёт h/L ≈ 1/30…1/25.
        final spanMax = h * 30 / 1000;
        final selfWeight = 25 * h / 1000; // ρ=25 кН/м³ (СП 20.13330.2016)
        final liveLoad = h >= 200 ? 3.0 : (h >= 160 ? 2.0 : 1.5);
        return _SlabCalcResult(
          spanMax: spanMax,
          selfWeight: selfWeight,
          liveLoad: liveLoad,
          deflection: spanMax * 1000 / 200,
          note: 'Монолит B25 (СП 63.13330.2018), арм. А500С Ø12 шаг 200 ↓↑.',
        );
      case 'precast':
        // ПК-плиты пустотного настила (ГОСТ 9561-2016). Длина плиты = пролёт.
        // Расчётные параметры зависят от h: при увеличении толщины растут
        // несущая способность и пролёт, но и собственный вес.
        final spanMax = (h * 27 / 1000).clamp(3.5, 7.2); // h=220 → ~5.94м
        // Средневзвешенный собственный вес ПК ≈ ρ_eff·h, где ρ_eff ≈ 14 кН/м³
        // (бетон с пустотами 35 %).
        final selfWeight = 14.0 * h / 1000;
        final liveLoad = h >= 220 ? 8.0 : (h >= 160 ? 6.0 : 4.5);
        return _SlabCalcResult(
          spanMax: spanMax,
          selfWeight: selfWeight,
          liveLoad: liveLoad,
          deflection: spanMax * 1000 / 250,
          note: 'Плиты пустотного настила ПК (ГОСТ 9561-2016), бетон B22,5.',
        );
      case 'wood_beams':
        // Балка 200×100 мм, шаг 0.6 м, сосна 2 сорта (СП 64.13330.2017).
        // Пролёт: L ≤ h/20 по условию прогиба f/L ≤ 1/250.
        final spanMax = h * 20 / 1000;
        // Собственный вес: балка 200×100·ρ=5кН/м³ /шаг + настил 40мм·6=
        // 0.83 кН/м² базово, плюс линейный рост от высоты балки сверх 200.
        final selfWeight = 0.85 + 0.7 * ((h - 200).clamp(0, 200) / 200);
        const liveLoad = 2.0; // кН/м² — жилое (СП 20.13330.2016 табл. 8.3)
        return _SlabCalcResult(
          spanMax: spanMax,
          selfWeight: selfWeight,
          liveLoad: liveLoad,
          deflection: spanMax * 1000 / 250,
          note: 'Сосна 2 сорт (СП 64.13330.2017), балка 200×100, шаг 600 мм.',
        );
      case 'metal_beams':
        // Двутавр 20Б1 (Wx=184 см³), шаг 0.8 м. По СП 16.13330.2017.
        // Момент сопротивления Wx × Ry (23.5 кН/см²) → M ≈ 43 кН·м.
        // Из условия прогиба f/L ≤ 1/200.
        final spanMax = h * 25 / 1000;
        // Собственный вес: профиль ~22 кг/м/шаг·g + настил 80мм·12=
        // 1.0 кН/м² базово, плюс линейный рост.
        final selfWeight = 1.0 + 0.8 * ((h - 200).clamp(0, 200) / 200);
        const liveLoad = 2.5;
        return _SlabCalcResult(
          spanMax: spanMax,
          selfWeight: selfWeight,
          liveLoad: liveLoad,
          deflection: spanMax * 1000 / 200,
          note: 'Двутавр 20Б1 (СП 16.13330.2017), шаг 800 мм, профнастил.',
        );
      default:
        return const _SlabCalcResult(
          spanMax: 0,
          selfWeight: 0,
          liveLoad: 0,
          deflection: 0,
          note: '',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _calculate();
    TextStyle? v = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    TextStyle? l = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Расчётные показатели',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              'Ориентировочные значения по СП 20/63/64/16.13330 для '
              'предпроектной оценки.',
              style: l,
            ),
            const SizedBox(height: 10),
            _row('Макс. свободный пролёт',
                '${r.spanMax.toStringAsFixed(2)} м', v, l),
            _row('Собственный вес перекрытия',
                '${r.selfWeight.toStringAsFixed(2)} кН/м²', v, l),
            _row('Расчётная полезная нагрузка',
                '${r.liveLoad.toStringAsFixed(2)} кН/м²', v, l),
            _row('Предельный прогиб',
                '≤ ${r.deflection.toStringAsFixed(1)} мм (L/'
                '${(r.spanMax * 1000 / r.deflection).round()})',
                v, l),
            if (r.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(r.note, style: l),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, TextStyle? v, TextStyle? l) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: l)),
          const SizedBox(width: 8),
          Text(value, style: v),
        ],
      ),
    );
  }
}

class _SlabCalcResult {
  final double spanMax;
  final double selfWeight;
  final double liveLoad;
  final double deflection;
  final String note;
  const _SlabCalcResult({
    required this.spanMax,
    required this.selfWeight,
    required this.liveLoad,
    required this.deflection,
    required this.note,
  });
}

class _SlabTypeOption {
  const _SlabTypeOption({
    required this.id,
    required this.title,
    required this.defaultMaterial,
    required this.defaultThickness,
    required this.hint,
  });

  final String id;
  final String title;
  final String defaultMaterial;
  final double defaultThickness;
  final String hint;
}
