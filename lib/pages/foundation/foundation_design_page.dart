import 'package:cc_engine/cc_engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/client_brief.dart';
import '../../models/foundation.dart';
import '../../models/house_project.dart';
import '../../models/soil_layer.dart';
import '../../services/composition_planner.dart';
import '../../services/file_download.dart';
import '../../services/foundation_designer.dart';
import '../../services/foundation_explanation_pdf.dart';
import '../../state/app_state.dart';
import '../../widgets/calc_steps_card.dart';
import '../../widgets/hints.dart';

/// Шаг 2 эталонного модуля «Фундамент»: подбор сечения ленточного
/// фундамента и базового армирования.
///
/// Использует [StripFootingDesigner] из `cc_engine`. Все шаги расчёта
/// видны на странице с пометкой «откуда взялось». При завершении
/// будущей работы это уйдёт в ПЗ (шаг 3) и в DXF (шаг 4).
class FoundationDesignPage extends StatelessWidget {
  const FoundationDesignPage({
    super.key,
    required this.projectId,
    required this.loads,
  });

  final String projectId;
  final FoundationLoadsResult loads;

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
        appBar: AppBar(title: const Text('Сечение фундамента')),
        body: const Center(child: Text('Проект не найден.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Подбор сечения фундамента'),
        actions: const [
          HintIconButton(
            title: 'Подбор сечения',
            sections: Hints.foundationDesign,
          ),
        ],
      ),
      body: HintAutoShow(
        screenKey: 'foundation-design',
        title: 'Подбор сечения',
        sections: Hints.foundationDesign,
        child: _DesignContent(
          project: project,
          loads: loads,
        ),
      ),
    );
  }
}

class _DesignContent extends StatelessWidget {
  const _DesignContent({
    required this.project,
    required this.loads,
  });

  final HouseProject project;
  final FoundationLoadsResult loads;

  double get totalLoadKnPerM2 => loads.totalVerticalKnPerM2;

  @override
  Widget build(BuildContext context) {
    final brief = project.brief;
    final missing = _missing(brief);
    if (missing.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                'Чтобы подобрать сечение фундамента, заполните техническое задание:',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(missing.map((f) => '• $f').join('\n')),
            ],
          ),
        ),
      );
    }

    final soil = _soilFromBrief(brief.soilLayers);
    final footprintArea =
        (brief.footprintWidth ?? 8.0) * (brief.footprintLength ?? 10.0);
    final perimeter = 2 *
        ((brief.footprintWidth ?? 8.0) + (brief.footprintLength ?? 10.0));
    // Грубо учитываем 1 поперечную несущую стену.
    final wallsLength = perimeter + (brief.footprintWidth ?? 8.0);
    final freezing = _freezingDepthForRegion(brief.region);

    final foundationType = project.foundation.type ?? FoundationType.strip;
    final recommended =
        CompositionPlanner.recommendedFoundationType(brief);
    final isRecommended = foundationType == recommended;

    // Для ленточного фундамента — детальный расчёт по cc_engine.
    if (foundationType == FoundationType.strip) {
      // Подвал увеличивает требуемую глубину заложения подошвы
      // (под пол подвала ≥ 0.3 м, СП 22.13330).
      final basementMinDepthM = brief.hasBasement == true
          ? (project.walls.height ??
                  project.staircase.floorHeight ??
                  2.5) +
              0.3
          : null;
      final design = StripFootingDesigner.design(
        verticalLoadKnPerM2: totalLoadKnPerM2,
        footprintAreaM2: footprintArea,
        loadBearingWallsPerimeterM: wallsLength,
        soilType: soil,
        freezingDepthM: freezing,
        minimumDepthM: basementMinDepthM,
        loadOrigin:
            'Из расчёта нагрузок на предыдущей странице '
            '(q = g·n + p·n + S по СП 20.13330.2016)',
        footprintOrigin:
            'Из технического задания: габариты здания «${brief.footprintWidth} × ${brief.footprintLength} м» '
            '⇒ A = ${footprintArea.toStringAsFixed(1)} м²',
        wallsOrigin:
            'Из технического задания: периметр ${perimeter.toStringAsFixed(1)} м '
            '+ 1 поперечная несущая стена ${brief.footprintWidth} м '
            '⇒ L = ${wallsLength.toStringAsFixed(1)} м (упрощённо)',
        soilOrigin:
            'Из технического задания, шаг «Грунты»: верхний слой — '
            '${brief.soilLayers.isNotEmpty ? (brief.soilLayers.first.type?.title ?? "не задано") : "не задано"}',
        freezingOrigin:
            'СП 131.13330.2020 для региона «${brief.region ?? "—"}»: '
            'df = ${freezing.toStringAsFixed(1)} м',
      );

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TypeBanner(
            type: foundationType,
            recommended: recommended,
            isRecommended: isRecommended,
            codeReferences: const [
              'СП 22.13330.2016 «Основания зданий и сооружений»',
              'СП 20.13330.2016 «Нагрузки и воздействия»',
              'СП 63.13330.2018 «Бетонные и железобетонные конструкции»',
            ],
          ),
          const SizedBox(height: 16),
          _InputDataCard(
            totalLoad: totalLoadKnPerM2,
            footprintArea: footprintArea,
            wallsLength: wallsLength,
            soil: soil,
            freezing: freezing,
            brief: brief,
          ),
          const SizedBox(height: 16),
          CalcStepsCard(
            title: 'Сопротивление грунта и подбор подошвы',
            icon: Icons.layers_outlined,
            steps: design.steps.take(7).toList(),
          ),
          const SizedBox(height: 16),
          CalcStepsCard(
            title: 'Глубина заложения и геометрия ленты',
            icon: Icons.height_outlined,
            steps: design.steps.skip(7).take(2).toList(),
          ),
          const SizedBox(height: 16),
          CalcStepsCard(
            title: 'Армирование и бетон',
            icon: Icons.grid_4x4_outlined,
            steps: design.steps.skip(9).toList(),
          ),
          const SizedBox(height: 24),
          _ResultCard(design: design),
          const SizedBox(height: 16),
          _DownloadExplanationButton(
            project: project,
            loads: loads,
            design: design,
            inputDataRows: {
              'Объект': project.name,
              'Регион': brief.region ?? '—',
              'Этажность': '${brief.floors ?? "—"} эт.',
              'Габариты здания':
                  '${brief.footprintWidth} × ${brief.footprintLength} м',
              'Площадь застройки A': '${footprintArea.toStringAsFixed(1)} м²',
              'Длина несущих стен L': '${wallsLength.toStringAsFixed(1)} м',
              'Грунт основания': soil.title,
              'R0 грунта': '${soil.r0KPa} кПа',
              'Глубина промерзания df':
                  '${freezing.toStringAsFixed(1)} м (СП 131.13330.2020)',
              'Снеговой район':
                  'Из технического задания → ${SnowRegion.byId(brief.snowZone ?? 3).title}',
              'Ветровой район':
                  'Из технического задания → район ${brief.windZone ?? 2}',
            },
          ),
          const SizedBox(height: 32),
        ],
      );
    }

    // Для остальных типов — упрощённый расчёт по соответствующим СП.
    final byType = FoundationByTypeDesigner.design(
      type: foundationType,
      verticalLoadKnPerM2: totalLoadKnPerM2,
      footprintWidthM: brief.footprintWidth ?? 8.0,
      footprintLengthM: brief.footprintLength ?? 10.0,
      soil: soil,
      freezingDepthM: freezing,
      brief: brief,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TypeBanner(
          type: foundationType,
          recommended: recommended,
          isRecommended: isRecommended,
          codeReferences: byType.codeReferences,
        ),
        const SizedBox(height: 16),
        _InputDataCard(
          totalLoad: totalLoadKnPerM2,
          footprintArea: footprintArea,
          wallsLength: wallsLength,
          soil: soil,
          freezing: freezing,
          brief: brief,
        ),
        const SizedBox(height: 16),
        CalcStepsCard(
          title: 'Расчёт по выбранному типу',
          icon: Icons.calculate_outlined,
          steps: byType.steps,
        ),
        const SizedBox(height: 24),
        _ByTypeResultCard(result: byType),
        const SizedBox(height: 32),
      ],
    );
  }

  static List<String> _missing(ClientBrief b) {
    final m = <String>[];
    if (b.footprintWidth == null || b.footprintLength == null) {
      m.add('габариты здания (ширина и длина)');
    }
    return m;
  }

  /// Маппинг между типом грунта в техническом задании (SoilType) и FoundationSoilType
  /// в cc_engine. Сейчас в техническом задании типы упрощённые («песок», «глина», …).
  /// Этот конвертер достанет верхний слой и подберёт ближайший аналог.
  static FoundationSoilType _soilFromBrief(List<SoilLayer> layers) {
    if (layers.isEmpty || layers.first.type == null) {
      return FoundationSoilType.loamStiff; // безопасное допущение
    }
    final name = layers.first.type!.name.toLowerCase();
    if (name.contains('gravel')) return FoundationSoilType.sandGravel;
    if (name.contains('coarse')) return FoundationSoilType.sandCoarse;
    if (name.contains('sand') && name.contains('fine')) {
      return FoundationSoilType.sandFine;
    }
    if (name.contains('sand')) return FoundationSoilType.sandMedium;
    if (name.contains('sandyloam') || name.contains('sandy_loam')) {
      return FoundationSoilType.sandyLoamHard;
    }
    if (name.contains('clay') && name.contains('hard')) {
      return FoundationSoilType.clayHard;
    }
    if (name.contains('clay') && name.contains('soft')) {
      return FoundationSoilType.claySoft;
    }
    if (name.contains('clay')) return FoundationSoilType.clayStiff;
    if (name.contains('loam') && name.contains('soft')) {
      return FoundationSoilType.loamSoft;
    }
    if (name.contains('loam')) return FoundationSoilType.loamStiff;
    return FoundationSoilType.loamStiff;
  }

  /// Грубая оценка нормативной глубины промерзания по региону. Для
  /// итогового проекта берётся из СП 131.13330.2020 (карта 1) — здесь
  /// упрощённо.
  static double _freezingDepthForRegion(String? region) {
    if (region == null) return 1.4;
    final r = region.toLowerCase();
    if (r.contains('мурманск') ||
        r.contains('архангельск') ||
        r.contains('сургут')) {
      return 2.0;
    }
    if (r.contains('новосибирск') ||
        r.contains('екатеринбург') ||
        r.contains('пермь') ||
        r.contains('омск') ||
        r.contains('тюмень')) {
      return 1.8;
    }
    if (r.contains('москва') ||
        r.contains('казань') ||
        r.contains('челябинск') ||
        r.contains('самара')) {
      return 1.4;
    }
    if (r.contains('ростов') ||
        r.contains('волгоград') ||
        r.contains('краснодар') ||
        r.contains('сочи')) {
      return 0.8;
    }
    return 1.4;
  }
}

class _InputDataCard extends StatelessWidget {
  const _InputDataCard({
    required this.totalLoad,
    required this.footprintArea,
    required this.wallsLength,
    required this.soil,
    required this.freezing,
    required this.brief,
  });

  final double totalLoad;
  final double footprintArea;
  final double wallsLength;
  final FoundationSoilType soil;
  final double freezing;
  final ClientBrief brief;

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
                Text('Исходные данные и их источник',
                    style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Все данные ниже определяются автоматически из ответов на '
              'предыдущих этапах визарда; формулы расчёта взяты из '
              'действующих сводов правил (СП).',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 12),
            _row(
              'Нагрузка q',
              '${totalLoad.toStringAsFixed(2)} кН/м²',
              'С предыдущей страницы «Расчёт нагрузок» '
                  '(СП 20.13330.2016: q = g·γf + p·γf + S).',
            ),
            _row(
              'Габариты здания',
              '${brief.footprintWidth} × ${brief.footprintLength} м '
                  '⇒ A = ${footprintArea.toStringAsFixed(1)} м²',
              'Из технического задания, шаг «Площадь и габариты». '
                  'A = B · L (СП 22.13330.2016).',
            ),
            _row(
              'Длина несущих стен L',
              '${wallsLength.toStringAsFixed(1)} м (периметр + 1 поперечная)',
              'L = 2·(B + L) + B (упрощённо). См. СП 70.13330 раздел '
                  '«Каменные конструкции» — стена в каждом пролёте ≤ 6 м.',
            ),
            _row(
              'Грунт основания',
              soil.title,
              'Из шага «Грунты»: верхний слой технического задания. '
                  'Тип определяет R0 по табл. Б.1 СП 22.13330.2016.',
            ),
            _row(
              'R0 грунта',
              '${soil.r0KPa} кПа',
              'СП 22.13330.2016, прил. Б, таблица Б.1 (расчётное '
                  'сопротивление основания для соответствующего типа грунта).',
            ),
            _row(
              'Глубина промерзания df',
              '${freezing.toStringAsFixed(1)} м '
                  '(СП 131.13330.2020 для «${brief.region ?? "—"}»)',
              'СП 131.13330.2020 «Строительная климатология», приложение Е. '
                  'Минимальная глубина заложения d ≥ df + 0,1 м (защита '
                  'от морозного пучения).',
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, [String? origin]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 200, child: Text(label)),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          if (origin != null)
            Padding(
              padding: const EdgeInsets.only(left: 200, top: 2),
              child: Builder(builder: (context) {
                final theme = Theme.of(context);
                return Text(
                  '↑ $origin',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.design});
  final StripFootingDesign design;

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
                const Icon(Icons.architecture_outlined),
                const SizedBox(width: 12),
                Text('Подобранное сечение',
                    style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 16),
            _row('Ширина подошвы b',
                '${design.widthM.toStringAsFixed(2)} м'),
            _row('Высота ленты h',
                '${design.heightM.toStringAsFixed(2)} м'),
            _row('Глубина заложения d',
                '${design.depthM.toStringAsFixed(2)} м'),
            const Divider(height: 24),
            _row('Бетон', design.concreteClass.title),
            _row(
                'Продольная арматура',
                '${design.longitudinalCount}⌀${design.longitudinalDiameterMm} '
                    '${design.longitudinalClass.title}'),
            _row(
                'Поперечная арматура',
                '⌀${design.stirrupDiameterMm} '
                    '${design.stirrupClass.title}, '
                    'шаг ${design.stirrupSpacingMm} мм'),
            const SizedBox(height: 12),
            Text(
              'Дальше: пояснительная записка ПЗ → DXF узла → '
              'строка ВОР (бетон м³, арматура кг). '
              'Появятся в следующих итерациях.',
              style: theme.textTheme.bodySmall,
            ),
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
          SizedBox(width: 200, child: Text(label)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _DownloadExplanationButton extends StatefulWidget {
  const _DownloadExplanationButton({
    required this.project,
    required this.loads,
    required this.design,
    required this.inputDataRows,
  });

  final HouseProject project;
  final FoundationLoadsResult loads;
  final StripFootingDesign design;
  final Map<String, String> inputDataRows;

  @override
  State<_DownloadExplanationButton> createState() =>
      _DownloadExplanationButtonState();
}

class _DownloadExplanationButtonState
    extends State<_DownloadExplanationButton> {
  bool _busy = false;

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final bytes = await FoundationExplanationPdf.build(
        project: widget.project,
        loads: widget.loads,
        design: widget.design,
        inputDataRows: widget.inputDataRows,
      );
      await FileDownload.downloadBytes(
        bytes: bytes,
        filename:
            'ПЗ_фундамент_${widget.project.name.replaceAll(" ", "_")}.pdf',
        mimeType: 'application/pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сгенерировать ПЗ: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      onPressed: _busy ? null : _download,
      icon: _busy
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.picture_as_pdf_outlined),
      label: Text(_busy
          ? 'Готовим ПЗ…'
          : 'Скачать пояснительную записку (PDF)'),
    );
  }
}

/// Баннер сверху страницы: показывает выбранный тип фундамента, отметку
/// «рекомендуется ли он по СП», предупреждение при отклонении и список
/// нормативов, по которым ведётся расчёт.
class _TypeBanner extends StatelessWidget {
  const _TypeBanner({
    required this.type,
    required this.recommended,
    required this.isRecommended,
    required this.codeReferences,
  });

  final FoundationType type;
  final FoundationType recommended;
  final bool isRecommended;
  final List<String> codeReferences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isRecommended
        ? theme.colorScheme.tertiary
        : theme.colorScheme.error;
    final bg = isRecommended
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.errorContainer;
    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isRecommended
                      ? Icons.verified_outlined
                      : Icons.warning_amber_outlined,
                  color: color,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Расчёт для типа «${type.title}»',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isRecommended
                  ? 'Это рекомендованный тип фундамента для заданных грунтов '
                      'и параметров здания.'
                  : 'Внимание: рекомендованный тип — «${recommended.title}». '
                      'Выбранный тип «${type.title}» может потребовать '
                      'дополнительного обоснования; результаты ниже '
                      'рассчитаны для выбранного варианта.',
              style: theme.textTheme.bodySmall,
            ),
            if (codeReferences.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Нормативы: ${codeReferences.join('; ')}.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Итоговый блок «Подобранные параметры» для не-ленточных фундаментов.
class _ByTypeResultCard extends StatelessWidget {
  const _ByTypeResultCard({required this.result});
  final FoundationByTypeResult result;

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
                const Icon(Icons.architecture_outlined),
                const SizedBox(width: 12),
                Text('Подобранные параметры',
                    style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 16),
            for (final row in result.summary)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 220, child: Text(row.$1)),
                    Expanded(
                      child: Text(
                        row.$2,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Расчёт упрощённый, для предварительного подбора. '
              'Окончательные значения принимаются после геотехнических '
              'изысканий и проверочных расчётов в специализированных '
              'программах (Plaxis, SCAD, Лира).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
