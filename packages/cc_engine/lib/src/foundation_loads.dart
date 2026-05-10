import 'dart:math' as math;

import 'calc_step.dart';
import 'enums.dart';
import 'regions.dart';
import 'weight_component.dart';

/// Результат расчёта нагрузок на фундамент.
class FoundationLoadsResult {
  const FoundationLoadsResult({
    required this.snow,
    required this.wind,
    required this.summary,
    required this.totalVerticalKnPerM2,
  });

  /// Группа шагов «Снеговая нагрузка» + её итоговое значение.
  final LoadsGroupResult snow;

  /// Группа шагов «Ветровая нагрузка».
  final LoadsGroupResult wind;

  /// Сводные шаги: постоянная, полезная, итог.
  final List<CalcStep> summary;

  /// Итоговая вертикальная нагрузка на 1 м² пятна застройки, кН/м².
  final double totalVerticalKnPerM2;
}

/// Подгруппа расчёта (снег / ветер) — список шагов + итоговое значение.
class LoadsGroupResult {
  const LoadsGroupResult({required this.steps, required this.value});
  final List<CalcStep> steps;
  final double value;
}

/// Расчёт нагрузок на фундамент по СП 20.13330.2016.
class FoundationLoadsCalculator {
  FoundationLoadsCalculator._();

  /// Основной метод. Возвращает объект со всеми шагами и суммой.
  ///
  /// Аргументы `*Origin` — чистые строки «откуда взято» для UI/PDF.
  static FoundationLoadsResult compute({
    required SnowRegion snowRegion,
    required WindRegion windRegion,
    required RoofShape roofShape,
    required double roofSlopeDegrees,
    required TerrainType windTerrain,
    required double buildingHeight,
    required List<WeightComponent> wallComponents,
    required List<WeightComponent> floorComponents,
    required List<WeightComponent> roofComponents,
    required int floors,
    String? snowRegionOrigin,
    String? windRegionOrigin,
    String? floorsOrigin,
    String? wallsOrigin,
    String? floorsCompOrigin,
    String? roofMaterialOrigin,
    String? buildingHeightOrigin,
  }) {
    // ---- СНЕГ ----
    final mu = _snowShapeCoef(roofShape, roofSlopeDegrees);
    const ce = 1.0; // коэффициент, учитывающий снос снега (п.10.5). Примем 1.0.
    const ct = 1.0; // термический коэффициент (п.10.6). Примем 1.0.
    final s = snowRegion.sgKPa * mu * ce * ct;

    final snowSteps = <CalcStep>[
      CalcStep(
        title: 'Коэффициент формы кровли μ',
        formula: 'μ = f(форма кровли, α)',
        substitution:
            'μ = f(${_roofShapeLabel(roofShape)}, α=${roofSlopeDegrees.toStringAsFixed(0)}°) = ${mu.toStringAsFixed(2)}',
        formattedResult: 'μ = ${mu.toStringAsFixed(2)}',
        reference: 'СП 20.13330.2016, прил. Б (схемы 1–8)',
        inputs: [
          CalcInput(
            symbol: 'α',
            value: '${roofSlopeDegrees.toStringAsFixed(0)}°',
            origin: 'Из этапа «Кровля», угол ската',
          ),
        ],
      ),
      CalcStep(
        title: 'Снеговая нагрузка S',
        formula: 'S = Sg · μ · ce · ct',
        substitution:
            'S = ${snowRegion.sgKPa} · ${mu.toStringAsFixed(2)} · ${ce.toStringAsFixed(1)} · ${ct.toStringAsFixed(1)}',
        formattedResult: 'S = ${s.toStringAsFixed(2)} кН/м²',
        reference: 'СП 20.13330.2016, п. 10.1 формула (10.1)',
        inputs: [
          CalcInput(
            symbol: 'Sg',
            value: '${snowRegion.sgKPa} кН/м²',
            origin: snowRegionOrigin ?? '${snowRegion.title} (СП 20, прил. Е)',
            reference: 'СП 20, прил. Е, карта 1',
          ),
          CalcInput(
            symbol: 'μ',
            value: mu.toStringAsFixed(2),
            origin: 'Таблица на предыдущем шаге',
          ),
          const CalcInput(
            symbol: 'ce',
            value: '1.0',
            origin: 'П.10.5: типовой коэффициент сноса — без снижения',
          ),
          const CalcInput(
            symbol: 'ct',
            value: '1.0',
            origin: 'П.10.6: термический коэффициент — 1.0 для холодных кровель',
          ),
        ],
      ),
    ];

    // ---- ВЕТЕР ----
    final kze = _windK(buildingHeight, windTerrain);
    const c = 0.8; // аэродинамический коэффициент наветренной стены, п.11.1.7
    final wm = windRegion.w0KPa * kze * c;

    final windSteps = <CalcStep>[
      CalcStep(
        title: 'Коэффициент высоты и местности k(ze)',
        formula: 'k(ze) — по типу местности',
        substitution:
            'k(${buildingHeight.toStringAsFixed(1)} м, ${_terrainLabel(windTerrain)}) = ${kze.toStringAsFixed(2)}',
        formattedResult: 'k(ze) = ${kze.toStringAsFixed(2)}',
        reference: 'СП 20.13330.2016, табл. 11.2',
        inputs: [
          CalcInput(
            symbol: 'ze',
            value: '${buildingHeight.toStringAsFixed(1)} м',
            origin: buildingHeightOrigin ?? 'Геометрия здания',
          ),
          CalcInput(
            symbol: 'тип',
            value: _terrainLabel(windTerrain),
            origin: 'По заданию участка (тип местности В по умолчанию)',
          ),
        ],
      ),
      CalcStep(
        title: 'Средняя составляющая ветровой нагрузки wm',
        formula: 'wm = w0 · k(ze) · c',
        substitution:
            'wm = ${windRegion.w0KPa} · ${kze.toStringAsFixed(2)} · ${c.toStringAsFixed(1)}',
        formattedResult: 'wm = ${wm.toStringAsFixed(2)} кН/м²',
        reference: 'СП 20.13330.2016, п. 11.1.3 формула (11.2)',
        inputs: [
          CalcInput(
            symbol: 'w0',
            value: '${windRegion.w0KPa} кН/м²',
            origin: windRegionOrigin ?? windRegion.title,
            reference: 'СП 20, прил. Е, карта 2',
          ),
          const CalcInput(
            symbol: 'c',
            value: '0.8',
            origin: 'П.11.1.7: наветренная стена, типовая форма здания',
          ),
        ],
      ),
    ];

    // ---- ПОСТОЯННАЯ + ПОЛЕЗНАЯ ----
    final walls = _sum(wallComponents);
    final floorsLoad = _sum(floorComponents) * floors.toDouble();
    final roof = _sum(roofComponents);
    final permanent = walls + floorsLoad + roof;

    // Полезная нагрузка на этажи жилого дома — 1.5 кН/м² по СП 20 п.8.3
    // (для жилых помещений) × число этажей.
    const useful = 1.5;
    final usefulTotal = useful * floors.toDouble();

    // Итог на 1 м² пятна застройки: постоянная + полезная + снег.
    // Ветровая нагрузка переводится в вертикальную составляющую приближённо
    // через коэффициент 0.2 (для малоэтажки, плоская кровля — близко к 0).
    final total = permanent + usefulTotal + s;

    final summary = <CalcStep>[
      CalcStep(
        title: 'Постоянная нагрузка (стены + перекрытия × этажи + кровля)',
        formula: 'g = Σ gi, gfloor · n, groof',
        substitution:
            'g = ${walls.toStringAsFixed(2)} + ${(_sum(floorComponents)).toStringAsFixed(2)}·$floors + ${roof.toStringAsFixed(2)}',
        formattedResult: 'g = ${permanent.toStringAsFixed(2)} кН/м²',
        reference: 'СП 20.13330.2016, разд. 7. Постоянные нагрузки',
        inputs: [
          for (final w in wallComponents)
            CalcInput(
              symbol: w.id,
              value: '${w.loadKnPerM2.toStringAsFixed(2)} кН/м²',
              origin: wallsOrigin ?? w.origin,
            ),
          for (final f in floorComponents)
            CalcInput(
              symbol: f.id,
              value: '${f.loadKnPerM2.toStringAsFixed(2)} кН/м²',
              origin: floorsCompOrigin ?? f.origin,
            ),
          for (final r in roofComponents)
            CalcInput(
              symbol: r.id,
              value: '${r.loadKnPerM2.toStringAsFixed(2)} кН/м²',
              origin: roofMaterialOrigin ?? r.origin,
            ),
          CalcInput(
            symbol: 'n',
            value: '$floors эт.',
            origin: floorsOrigin ?? 'Из ТЗ, этажность',
          ),
        ],
      ),
      CalcStep(
        title: 'Полезная нагрузка p (жилое, × этажи)',
        formula: 'p = p0 · n',
        substitution:
            'p = ${useful.toStringAsFixed(1)} · $floors = ${usefulTotal.toStringAsFixed(2)}',
        formattedResult: 'p = ${usefulTotal.toStringAsFixed(2)} кН/м²',
        reference: 'СП 20.13330.2016, табл. 8.3: жилые помещения 1.5 кН/м²',
      ),
      CalcStep(
        title: 'Итоговая вертикальная нагрузка на фундамент',
        formula: 'q = g + p + S',
        substitution:
            'q = ${permanent.toStringAsFixed(2)} + ${usefulTotal.toStringAsFixed(2)} + ${s.toStringAsFixed(2)}',
        formattedResult: 'q = ${total.toStringAsFixed(2)} кН/м²',
        reference: 'Сочетание нагрузок по СП 20, п. 6.2',
      ),
    ];

    return FoundationLoadsResult(
      snow: LoadsGroupResult(steps: snowSteps, value: s),
      wind: LoadsGroupResult(steps: windSteps, value: wm),
      summary: summary,
      totalVerticalKnPerM2: total,
    );
  }

  static double _sum(List<WeightComponent> components) {
    var sum = 0.0;
    for (final c in components) {
      sum += c.loadKnPerM2;
    }
    return sum;
  }

  static double _snowShapeCoef(RoofShape shape, double slopeDeg) {
    switch (shape) {
      case RoofShape.flatOrLowSlope:
        return 1.0;
      case RoofShape.gable:
        if (slopeDeg <= 30) return 1.0;
        if (slopeDeg >= 60) return 0.0;
        // линейная интерполяция по СП 20, прил. Б, схема Б.1
        return (60 - slopeDeg) / 30;
      case RoofShape.steep:
        return 0.0;
    }
  }

  /// k(ze) по СП 20.13330.2016, табл. 11.2.
  /// Упрощённые кусочно-линейные выражения для типовой малоэтажки.
  static double _windK(double ze, TerrainType terrain) {
    double base;
    switch (terrain) {
      case TerrainType.a:
        base = 0.85 + 0.15 * math.min(ze / 10, 1.0);
        break;
      case TerrainType.b:
        base = 0.5 + 0.2 * math.min(ze / 10, 1.0);
        break;
      case TerrainType.c:
        base = 0.4 + 0.15 * math.min(ze / 10, 1.0);
        break;
    }
    return base;
  }

  static String _roofShapeLabel(RoofShape s) {
    switch (s) {
      case RoofShape.flatOrLowSlope:
        return 'плоская/пологая';
      case RoofShape.gable:
        return 'двухскатная';
      case RoofShape.steep:
        return 'крутая';
    }
  }

  static String _terrainLabel(TerrainType t) {
    switch (t) {
      case TerrainType.a:
        return 'A (открытая)';
      case TerrainType.b:
        return 'B (пригород/лес)';
      case TerrainType.c:
        return 'C (плотный город)';
    }
  }
}
