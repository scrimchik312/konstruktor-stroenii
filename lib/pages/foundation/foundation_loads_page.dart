import 'package:cc_engine/cc_engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/wall_materials.dart';
import '../../models/client_brief.dart';
import '../../models/house_project.dart';
import '../../models/roof_design.dart';
import '../../state/app_state.dart';
import '../../widgets/calc_steps_card.dart';
import '../../widgets/hints.dart';
import 'foundation_design_page.dart';

/// Расчёт нагрузок на фундамент по СП 20.13330.2016.
///
/// Это первый из пяти шагов «эталонного» модуля «Фундамент». Страница
/// показывает входные данные (взяты из технического задания), все шаги расчёта с
/// формулами и подстановкой значений, и итоговую вертикальную нагрузку.
///
/// Все расчёты делает [FoundationLoadsCalculator] из пакета
/// `cc_engine` — здесь только UI поверх результата.
class FoundationLoadsPage extends StatelessWidget {
  const FoundationLoadsPage({super.key, required this.projectId});

  final String projectId;

  HouseProject? _findProject(AppState state) {
    for (final p in state.projects) {
      if (p.id == projectId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final project = _findProject(state);

    if (project == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Расчёт нагрузок')),
        body: const Center(child: Text('Проект не найден.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Расчёт нагрузок на фундамент'),
        actions: const [
          HintIconButton(
            title: 'Расчёт нагрузок',
            sections: Hints.foundationLoads,
          ),
        ],
      ),
      body: HintAutoShow(
        screenKey: 'foundation-loads',
        title: 'Расчёт нагрузок',
        sections: Hints.foundationLoads,
        child: _LoadsContent(project: project),
      ),
    );
  }
}

class _LoadsContent extends StatelessWidget {
  const _LoadsContent({required this.project});
  final HouseProject project;

  /// Подобрать [WindRegion] по строке `windZone` из технического задания («I», «II», …).
  WindRegion? _windFromBrief(String? windZone) {
    if (windZone == null) return null;
    switch (windZone.toUpperCase()) {
      case 'IA':
      case 'IА':
        return WindRegion.byId(0);
      case 'I':
        return WindRegion.byId(1);
      case 'II':
        return WindRegion.byId(2);
      case 'III':
        return WindRegion.byId(3);
      case 'IV':
        return WindRegion.byId(4);
      case 'V':
        return WindRegion.byId(5);
      case 'VI':
        return WindRegion.byId(6);
      case 'VII':
        return WindRegion.byId(7);
    }
    return null;
  }

  /// Подобрать постоянные нагрузки от стен по выбранному материалу из технического задания.
  List<WeightComponent> _wallsFromBrief(WallMaterial? material) {
    const defaults = PermanentLoadCalculator.defaults;
    switch (material) {
      case WallMaterial.brick:
        return [defaults['walls_brick']!];
      case WallMaterial.aerated:
      case WallMaterial.expandedClay:
        return [defaults['walls_aerated']!];
      case WallMaterial.timber:
        return [defaults['walls_timber']!];
      case WallMaterial.frame:
        return [defaults['walls_frame']!];
      case null:
        return [defaults['walls_aerated']!];
    }
  }

  /// Подобрать постоянные нагрузки от перекрытий по выбранному типу
  /// и фактической толщине плиты (project.floorSlabs.type/thickness).
  ///
  /// Если толщина задана — пересчитываем собственный вес перекрытия
  /// линейно от толщины (для монолита по СП 20.13330.2016 ρ=25 кН/м³;
  /// для ПК — ρ_eff=14 кН/м³ с учётом пустот; для балочных — масштаб
  /// относительно дефолтной толщины 200 мм).
  List<WeightComponent> _floorsFromProject(HouseProject p) {
    const defaults = PermanentLoadCalculator.defaults;
    final h = p.floorSlabs.thickness;
    WeightComponent base;
    double? scaledKn;
    String? origin;
    switch (p.floorSlabs.type) {
      case 'monolith':
        base = defaults['floor_monolith']!;
        if (h != null) {
          scaledKn = 25.0 * h / 1000; // ρ=25 кН/м³
          origin = 'Монолит ρ=25 кН/м³ · h=${h.toStringAsFixed(0)} мм '
              '(СП 20.13330.2016, прил. А)';
        }
        break;
      case 'precast':
        base = defaults['floor_precast']!;
        if (h != null) {
          scaledKn = 14.0 * h / 1000; // ρ_eff с учётом пустот
          origin = 'ПК ρ_eff=14 кН/м³ · h=${h.toStringAsFixed(0)} мм '
              '(ГОСТ 9561-2016)';
        }
        break;
      case 'metal_beams':
        base = defaults['floor_metal_beams']!;
        if (h != null) {
          // Базовое значение для h=200 мм. Линейное масштабирование.
          scaledKn = base.loadKnPerM2 * (h / 200);
          origin = 'Стальные балки + профнастил, h=${h.toStringAsFixed(0)} мм '
              '(СП 16.13330.2017)';
        }
        break;
      case 'wood_beams':
      default:
        base = defaults['floor_timber_joists']!;
        if (h != null) {
          scaledKn = base.loadKnPerM2 * (h / 200);
          origin = 'Деревянные балки, h=${h.toStringAsFixed(0)} мм '
              '(СП 64.13330.2017)';
        }
        break;
    }
    if (scaledKn != null && origin != null) {
      return [
        WeightComponent(
          id: base.id,
          title: '${base.title} · $h мм',
          loadKnPerM2: double.parse(scaledKn.toStringAsFixed(2)),
          origin: origin,
        ),
      ];
    }
    return [base];
  }

  String _floorOrigin(HouseProject p) {
    if (p.floorSlabs.type == null) {
      return 'По умолчанию: деревянное перекрытие по балкам (перекрытие не выбрано).';
    }
    final h = p.floorSlabs.thickness;
    final hStr = h != null ? ', h=${h.toStringAsFixed(0)} мм' : '';
    return 'Из этапа «Планировка → Перекрытия» '
        '(выбрано: ${p.floorSlabs.summary}$hStr). '
        'Собственный вес пересчитан под фактическую толщину плиты.';
  }

  /// Угадать тип кровли из строки `roof.roofingMaterial`. В модели
  /// [RoofDesign] это пока строка ('metal', 'tile', 'soft', …) — поэтому
  /// сравниваем подстрокой. Когда мы перейдём на enum (см. roadmap),
  /// здесь станет проще.
  List<WeightComponent> _roofFromBrief(RoofDesign roof) {
    const defaults = PermanentLoadCalculator.defaults;
    final m = (roof.roofingMaterial ?? '').toLowerCase();
    if (m.contains('soft') || m.contains('бит') || m.contains('гибк')) {
      return [defaults['roof_soft_bitumen']!];
    }
    if (m.contains('clay') || m.contains('керам')) {
      return [defaults['roof_clay_tile']!];
    }
    return [defaults['roof_metal_tile']!];
  }

  /// Минимальный угол из всех скатов — консервативный выбор для
  /// расчёта снеговой нагрузки (коэффициент μ больше при пологой кровле).
  double _worstSlope(RoofDesign roof) {
    if (roof.slopeAngles.isNotEmpty) {
      return roof.slopeAngles.reduce((a, b) => a < b ? a : b);
    }
    return roof.slopeAngle ?? 30;
  }

  @override
  Widget build(BuildContext context) {
    final brief = project.brief;
    final missingFields = _missingBriefFields(brief);

    if (missingFields.isNotEmpty) {
      return _MissingFields(missingFields: missingFields);
    }

    final snow = SnowRegion.byId(brief.snowZone!);
    final wind = _windFromBrief(brief.windZone) ?? WindRegion.byId(2);
    final roofShape = _detectRoofShape(project.roof);
    final regionLabel = brief.region ?? '—';
    final worstSlope = _worstSlope(project.roof);
    final slopeOrigin = project.roof.slopeAngles.isNotEmpty
        ? 'минимальный из введённых углов скатов '
            '(${project.roof.slopeAngles.map((a) => '${a.toStringAsFixed(0)}°').join('/')}) '
            '— консервативно для снега'
        : 'по умолчанию 30° (уклон не задан на этапе кровли)';
    final result = FoundationLoadsCalculator.compute(
      snowRegion: snow,
      windRegion: wind,
      roofShape: roofShape,
      roofSlopeDegrees: worstSlope,
      windTerrain: TerrainType.b,
      buildingHeight: _estimateBuildingHeight(brief),
      wallComponents: _wallsFromBrief(brief.wallMaterial),
      floorComponents: _floorsFromProject(project),
      roofComponents: _roofFromBrief(project.roof),
      floors: brief.floors ?? 1,
      snowRegionOrigin:
          'Из этапа «Фундамент → Участок»: «Регион → $regionLabel» → ${snow.title} (карта 1, прил. Е СП 20). '
          'Угол ската: $slopeOrigin.',
      windRegionOrigin:
          'Из этапа «Фундамент → Участок»: «Регион → $regionLabel» → ${wind.title} (карта 2, прил. Е СП 20).',
      floorsOrigin:
          'Из этапа «Начальные данные → Этажность» (значение: ${brief.floors} эт.)',
      wallsOrigin:
          'Из этапа «Начальные данные → Материал стен» (выбор: ${brief.wallMaterial?.title ?? "—"})',
      floorsCompOrigin: _floorOrigin(project),
      roofMaterialOrigin: project.roof.roofingMaterial != null
          ? 'Из этапа «Кровля»: материал «${_roofingMaterialRu(project.roof.roofingMaterial)}»'
          : 'По умолчанию: металлочерепица (материал не выбран на этапе «Кровля»)',
      buildingHeightOrigin:
          'Оценка по этажности: ${brief.floors} · 3 м + 2 м на крышу = ${_estimateBuildingHeight(brief)} м. Уточняется по разрезам.',
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InputDataCard(brief: brief, snow: snow, wind: wind, project: project),
        const SizedBox(height: 16),
        CalcStepsCard(
          title: 'Снеговая нагрузка',
          icon: Icons.ac_unit,
          steps: result.snow.steps,
        ),
        const SizedBox(height: 16),
        CalcStepsCard(
          title: 'Ветровая нагрузка',
          icon: Icons.air,
          steps: result.wind.steps,
        ),
        const SizedBox(height: 16),
        CalcStepsCard(
          title: 'Постоянная и полезная нагрузки + сводка',
          icon: Icons.calculate_outlined,
          steps: result.summary,
        ),
        const SizedBox(height: 24),
        _TotalCard(
          totalKnPerM2: result.totalVerticalKnPerM2,
          windKnPerM2: result.wind.value,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FoundationDesignPage(
                  projectId: project.id,
                  loads: result,
                ),
              ),
            );
          },
          icon: const Icon(Icons.architecture_outlined),
          label: const Text('Подобрать сечение фундамента'),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  static List<String> _missingBriefFields(ClientBrief b) {
    final missing = <String>[];
    if (b.snowZone == null) missing.add('снеговой район');
    if (b.windZone == null) missing.add('ветровой район');
    if (b.floors == null) missing.add('этажность');
    if (b.wallMaterial == null) missing.add('материал стен');
    return missing;
  }

  static RoofShape _detectRoofShape(RoofDesign roof) {
    final slopes = roof.slopeAngles.isNotEmpty
        ? roof.slopeAngles
        : [roof.slopeAngle ?? 30];
    final slope = slopes.reduce((a, b) => a < b ? a : b);
    if (slope <= 30) return RoofShape.flatOrLowSlope;
    if (slope >= 60) return RoofShape.steep;
    return RoofShape.gable;
  }

  static String _roofingMaterialRu(String? id, {String? fallback}) =>
      roofingMaterialRu(id, fallback: fallback);

  static double _estimateBuildingHeight(ClientBrief b) {
    // Высота этажа 3 м + 2 м на крышу — грубая оценка для расчёта
    // ветрового профиля. Уточняется в полном расчёте по разрезам.
    final n = b.floors ?? 1;
    return n * 3.0 + 2.0;
  }
}

class _MissingFields extends StatelessWidget {
  const _MissingFields({required this.missingFields});
  final List<String> missingFields;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              'Чтобы рассчитать нагрузки на фундамент, заполните техническое задание:',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Text(
              missingFields.map((f) => '• $f').join('\n'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _InputDataCard extends StatelessWidget {
  const _InputDataCard({
    required this.brief,
    required this.snow,
    required this.wind,
    required this.project,
  });

  final ClientBrief brief;
  final SnowRegion snow;
  final WindRegion wind;
  final HouseProject project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_outlined),
                const SizedBox(width: 12),
                Text('Исходные данные', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            _row('Регион', brief.region ?? '—'),
            _row('Снеговой район', '${snow.title} (Sg = ${snow.sg} кН/м²)'),
            _row('Ветровой район', '${wind.title} (w0 = ${wind.w0} кН/м²)'),
            _row('Этажность', '${brief.floors} эт.'),
            _row('Материал стен', brief.wallMaterial?.title ?? '—'),
            _row(
              'Материал кровли',
              roofingMaterialRu(project.roof.roofingMaterial,
                  fallback: 'металлочерепица (по умолчанию)'),
            ),
            _row('Уклон кровли', '${project.roof.slopeAngle ?? 30}°'),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 160, child: Text(label)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.totalKnPerM2, required this.windKnPerM2});

  final double totalKnPerM2;
  final double windKnPerM2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.summarize_outlined),
                const SizedBox(width: 12),
                Text('Итоговые нагрузки',
                    style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 12),
            _line(
              'Вертикальная нагрузка на фундамент',
              '${_round(totalKnPerM2)} кН/м²',
              theme,
            ),
            const SizedBox(height: 8),
            _line(
              'Ветровое давление (горизонт.)',
              '${_round(windKnPerM2)} кН/м²',
              theme,
            ),
            const SizedBox(height: 12),
            Text(
              'Дальше: подбор подошвы по СП 22.13330.2016 и армирование по '
              'СП 63.13330.2018. Появится в следующей итерации.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value, ThemeData theme) {
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Text(
          value,
          style: theme.textTheme.titleMedium!
              .copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;
}

/// Глобальный перевод id материала кровли (`metal_tile`, `soft`, ...) на
/// русский. Используется на странице расчёта нагрузок и в карточке исходных
/// данных. Если строка уже на русском или неизвестна — возвращаем её как есть.
String roofingMaterialRu(String? id, {String? fallback}) {
  if (id == null) return fallback ?? '—';
  const labels = {
    'metal_tile': 'Металлочерепица',
    'metal': 'Металлочерепица',
    'soft': 'Мягкая (битумная)',
    'bitumen': 'Мягкая (битумная)',
    'ceramic': 'Керамическая черепица',
    'tile': 'Керамическая черепица',
    'slate': 'Шифер',
    'seam': 'Фальцевая кровля',
    'fold': 'Фальцевая кровля',
    'profile': 'Профнастил',
    'profnastil': 'Профнастил',
    'ondulin': 'Ондулин',
  };
  return labels[id.toLowerCase()] ?? id;
}
