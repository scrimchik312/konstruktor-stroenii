// Phase-3c §21.2 — расчёт нагрузок от L/T/U-кровли на фундамент.
//
// Для axis-aligned полигональных пятен (L, T, U, +) кровля разбивается
// на несколько подкрыш (по [BuildingFootprint.rectangleDecomposition]),
// у каждой свой центр тяжести; суммарная нагрузка на периметр имеет
// заметную асимметрию относительно геометрического центра пятна.
// Этот калькулятор:
//   • разбивает полигон на подкрыши и считает их площади/центры;
//   • суммарную нагрузку (снег + постоянная) переносит на периметр
//     каждой подкрыши пропорционально длинам сторон;
//   • в reflex-углах (ендовы) добавляет коэффициент перевода снега
//     k_drift ≈ 1.5 (СП 20.13330.2016, схема Б.6 «снеговые мешки» —
//     для прямого внутреннего угла); линии ендов получают +50% снега;
//   • возвращает структуру [FoundationLoadDistribution] с массивами
//     линейных нагрузок q (кН/м) на каждое ребро outline-а и точкой
//     приложения (centroid) для оценки эксцентриситета.

import 'dart:math' as math;

import '../models/building_footprint.dart';
import 'polygon_helpers.dart';

/// Линейная нагрузка q (кН/м) на одно ребро outline-а пятна.
class FoundationEdgeLoad {
  /// Индекс начальной вершины outline-а.
  final int from;

  /// Индекс конечной вершины outline-а (`from + 1`).
  final int to;

  /// Длина ребра, м.
  final double lengthM;

  /// Расчётная линейная нагрузка от кровли + снег, кН/м.
  /// Включает в себя коэффициент сноса (1.5×) для рёбер, примыкающих
  /// к reflex-углам.
  final double qKnPerM;

  /// True, если ребро примыкает (хотя бы одним концом) к reflex-углу
  /// — даёт пометку «ендова» в выводе.
  final bool isAdjacentToReflex;

  const FoundationEdgeLoad({
    required this.from,
    required this.to,
    required this.lengthM,
    required this.qKnPerM,
    required this.isAdjacentToReflex,
  });
}

/// Один прямоугольник декомпозиции (отдельная двускатная кровля).
class FoundationSubRoof {
  /// Прямоугольник в координатах пятна (м).
  final FootprintRect box;

  /// Геометрический центр прямоугольника, м.
  final Vec2 centroid;

  /// Площадь, м².
  final double areaM2;

  /// Полная вертикальная сила от кровли + снег на этот прямоугольник, кН.
  final double totalKn;

  const FoundationSubRoof({
    required this.box,
    required this.centroid,
    required this.areaM2,
    required this.totalKn,
  });
}

/// Распределение нагрузки от кровли по периметру и подкрышам.
class FoundationLoadDistribution {
  /// Ограничение — все edges имеют outline.length записей; индекс i
  /// соответствует ребру outline[i] → outline[i+1].
  final List<FoundationEdgeLoad> edges;

  /// Подкрыши (для axis-aligned L/T/U/+ — несколько; для прямоугольника
  /// и не-axis-aligned — одна).
  final List<FoundationSubRoof> subRoofs;

  /// Суммарная нагрузка на фундамент, кН.
  final double totalKn;

  /// Центр давления (взвешенный по подкрышам), м.
  final Vec2 centroid;

  /// Геометрический центр пятна, м.
  final Vec2 footprintCentroid;

  /// Эксцентриситет = |centroid − footprintCentroid|, м.
  /// Для симметричных пятен = 0; для L-форм заметно отклонение.
  final double eccentricityM;

  /// Рекомендация: True, если эксцентриситет > 5% от max(width, height) —
  /// значит, классическая лента под равномерной нагрузкой не подходит,
  /// и нужно увеличивать ширину ленты на «нагруженной» стороне или
  /// переходить на плиту.
  final bool recommendSlab;

  const FoundationLoadDistribution({
    required this.edges,
    required this.subRoofs,
    required this.totalKn,
    required this.centroid,
    required this.footprintCentroid,
    required this.eccentricityM,
    required this.recommendSlab,
  });
}

/// Калькулятор Phase-3c.
class FoundationLoadsCalculator {
  FoundationLoadsCalculator._();

  /// Sg — нормативный вес снегового покрова (кН/м²), СП 20 табл. 10.1.
  static double snowSg(int? zone) {
    switch (zone ?? 3) {
      case 1:
        return 1.0;
      case 2:
        return 1.2;
      case 3:
        return 1.8;
      case 4:
        return 2.4;
      case 5:
        return 3.2;
      case 6:
        return 4.0;
      case 7:
        return 4.8;
      case 8:
        return 5.6;
      default:
        return 1.8;
    }
  }

  /// μ — коэффициент перехода с земли на покрытие (СП 20 п.10.4).
  /// Линейная аппроксимация для скатов 30°…60°.
  static double snowMu(double slopeDeg) {
    if (slopeDeg <= 30) return 1.0;
    if (slopeDeg >= 60) return 0.0;
    return (60 - slopeDeg) / 30;
  }

  /// Постоянная нагрузка g (кН/м²) от кровельного пирога — те же
  /// значения, что в `RafterSectionPicker.permanentLoadKnPerM2`,
  /// дублируем здесь, чтобы избежать кросс-импорта `house_project.dart`.
  static double permanentLoad(String? roofingMaterial) {
    double roofingKn;
    switch (roofingMaterial) {
      case 'metal':
        roofingKn = 0.05;
        break;
      case 'tile':
        roofingKn = 0.45;
        break;
      case 'soft':
        roofingKn = 0.10;
        break;
      case 'corrugated':
        roofingKn = 0.06;
        break;
      case 'slate':
        roofingKn = 0.18;
        break;
      default:
        roofingKn = 0.10;
    }
    const sheathingKn = 0.10;
    const rafterSelfKn = 0.12;
    const insulationKn = 0.07;
    return roofingKn + sheathingKn + rafterSelfKn + insulationKn;
  }

  /// Коэффициент надёжности γ_f (СП 20 п. 7.3 и 10.12).
  /// Для постоянной нагрузки — 1.1, для снеговой — 1.4.
  static const double _gammaPerm = 1.1;
  static const double _gammaSnow = 1.4;

  /// Множитель для снеговой нагрузки в reflex-углах (снеговые мешки
  /// в ендовах). Эмпирическое значение 1.5 — типичное для прямого
  /// внутреннего угла по СП 20 схема Б.6.
  static const double _kDrift = 1.5;

  /// Доля общей нагрузки на каждое ребро прямоугольника. Для двускатной
  /// крыши с коньком вдоль длинной стороны — нагрузка приходит на 2
  /// длинных ребра (стропилы опираются на них); короткие ребра несут
  /// значительно меньше (только фронтоны). Принимаем 90% на длинные
  /// и 10% на короткие.
  static const double _shareOnLongEdges = 0.9;

  /// Главный расчёт.
  ///
  /// [footprint] — пятно застройки (CCW-полигон).
  /// [slopeDeg] — угол ската, °.
  /// [snowZone] — снеговой район (1..8).
  /// [roofingMaterial] — материал кровли (для постоянной нагрузки).
  /// [floors] — число этажей (для увеличения нагрузки от стен/перекрытий).
  /// [wallLoadKnPerM2] — погонная нагрузка от стен/перекрытий, кН/м²;
  /// если null — берём 4.0 (типовое значение для одноэтажного ИЖС).
  static FoundationLoadDistribution compute({
    required BuildingFootprint footprint,
    required double slopeDeg,
    required int snowZone,
    String? roofingMaterial,
    int floors = 1,
    double? wallLoadKnPerM2,
  }) {
    final outline = footprint.outline;
    final n = outline.length;
    if (n < 3) {
      return const FoundationLoadDistribution(
        edges: [],
        subRoofs: [],
        totalKn: 0,
        centroid: Vec2(0, 0),
        footprintCentroid: Vec2(0, 0),
        eccentricityM: 0,
        recommendSlab: false,
      );
    }

    // Разбивка на подкрыши (axis-aligned → много, иначе → 1 bbox).
    final boxes = footprint.rectangleDecomposition();
    final subRoofs = <FoundationSubRoof>[];

    final sg = snowSg(snowZone);
    final mu = snowMu(slopeDeg);
    final s0 = sg * mu; // снеговая на покрытие, кН/м²
    final perm = permanentLoad(roofingMaterial);
    final wallLoad = wallLoadKnPerM2 ?? 4.0;
    final qRoofKn = (s0 * _gammaSnow + perm * _gammaPerm); // кН/м²

    var totalKn = 0.0;
    var sumX = 0.0;
    var sumY = 0.0;

    for (final b in boxes) {
      final area = b.width * b.height;
      final centroid = Vec2(b.x + b.width / 2, b.y + b.height / 2);
      final knRoof = area * qRoofKn;
      // Стены и перекрытия добавляют ещё ~floors * wallLoad на ту же
      // площадь.
      final knWalls = area * wallLoad * floors;
      final kn = knRoof + knWalls;
      subRoofs.add(FoundationSubRoof(
        box: b,
        centroid: centroid,
        areaM2: area,
        totalKn: kn,
      ));
      totalKn += kn;
      sumX += centroid.x * kn;
      sumY += centroid.y * kn;
    }

    final centroid = totalKn > 0
        ? Vec2(sumX / totalKn, sumY / totalKn)
        : const Vec2(0, 0);
    // Эталон для оценки асимметрии — геометрический центр bbox,
    // потому что лента/плита проектируется по описывающему
    // прямоугольнику. Если центр давления L/T/U-формы заметно
    // смещён от центра bbox, значит классическая равномерная схема
    // не подходит — и нам нужна асимметричная лента или плита.
    final bbox = footprint.bbox;
    final footprintCentroid = bbox.center;
    final eccentricity = math.sqrt(
      math.pow(centroid.x - footprintCentroid.x, 2).toDouble() +
          math.pow(centroid.y - footprintCentroid.y, 2).toDouble(),
    );

    // Распределение по рёбрам outline-а: для каждого ребра определяем,
    // к какой подкрыше оно относится (то есть какая sub-рожь касается
    // его внутренней стороны), и берём пропорциональную долю.
    // Для axis-aligned 90°-полигона ребро либо горизонтальное, либо
    // вертикальное; делим нагрузку подкрыши на 2*(width + height)
    // и учитываем «короткие/длинные» рёбра.
    final ccw = polygonIsCcw(outline);
    final reflexFlags = List<bool>.generate(n, (i) {
      var c = vertexConvexity(outline, i);
      if (!ccw) {
        if (c == VertexConvexity.convex) {
          c = VertexConvexity.reflex;
        } else if (c == VertexConvexity.reflex) {
          c = VertexConvexity.convex;
        }
      }
      return c == VertexConvexity.reflex;
    });

    // Линейная нагрузка на стены: общая = (стены + кровля) / периметр,
    // но с пере-распределением на длинные/короткие рёбра подкрыши.
    final edges = <FoundationEdgeLoad>[];
    for (var i = 0; i < n; i++) {
      final a = outline[i];
      final b = outline[(i + 1) % n];
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final len = math.sqrt(dx * dx + dy * dy);
      // К какой подкрыше относится это ребро: то, у кого центр ближе
      // и сама точка принадлежит box (или граничит с ним).
      final mid = Vec2((a.x + b.x) / 2, (a.y + b.y) / 2);
      FoundationSubRoof? best;
      double bestScore = double.infinity;
      for (final r in subRoofs) {
        final cx = r.box.x + r.box.width / 2;
        final cy = r.box.y + r.box.height / 2;
        final d = math.sqrt(
          math.pow(cx - mid.x, 2).toDouble() +
              math.pow(cy - mid.y, 2).toDouble(),
        );
        if (d < bestScore) {
          bestScore = d;
          best = r;
        }
      }
      if (best == null || len < 1e-9) {
        edges.add(FoundationEdgeLoad(
          from: i,
          to: (i + 1) % n,
          lengthM: len,
          qKnPerM: 0,
          isAdjacentToReflex: false,
        ));
        continue;
      }
      // Длинная или короткая сторона подкрыши?
      final isHorizontal = dy.abs() < 1e-3;
      final boxLong = math.max(best.box.width, best.box.height);
      final isLongSide = (isHorizontal && boxLong == best.box.width) ||
          (!isHorizontal && boxLong == best.box.height);
      // Доля нагрузки на это ребро из общей.
      final share = isLongSide
          ? _shareOnLongEdges / 2 // 2 длинных ребра делят 90%
          : (1 - _shareOnLongEdges) / 2; // 2 коротких делят 10%
      var q = best.totalKn * share / len;
      // Snow drift в ендовах (reflex-углы): рёбра, у которых ХОТЯ БЫ
      // один конец — reflex-вершина, получают +50% снеговой нагрузки.
      final adjReflex =
          reflexFlags[i] || reflexFlags[(i + 1) % n];
      if (adjReflex) {
        // Мы суммировали постоянную + снег; добавим (kDrift-1) * snow
        // часть. Снеговая доля приближённо = s0 * γ_snow / qRoofKn.
        if (qRoofKn > 1e-6) {
          final snowFraction = (s0 * _gammaSnow) / qRoofKn;
          // Какая часть ребра — snow * area share? Грубо: добавляем
          // (kDrift-1) * snowFraction * roofShare к q.
          // roofShare = knRoof / kn у этой подкрыши.
          final knRoof = best.areaM2 * qRoofKn;
          final roofShare = knRoof / best.totalKn;
          q *= 1 + (_kDrift - 1) * snowFraction * roofShare;
        }
      }
      edges.add(FoundationEdgeLoad(
        from: i,
        to: (i + 1) % n,
        lengthM: len,
        qKnPerM: q,
        isAdjacentToReflex: adjReflex,
      ));
    }

    final maxDim =
        math.max(footprint.bbox.width, footprint.bbox.height);
    final recommendSlab =
        maxDim > 0 && eccentricity / maxDim > 0.05;

    return FoundationLoadDistribution(
      edges: edges,
      subRoofs: subRoofs,
      totalKn: totalKn,
      centroid: centroid,
      footprintCentroid: footprintCentroid,
      eccentricityM: eccentricity,
      recommendSlab: recommendSlab,
    );
  }

  /// Геометрический центр CCW-полигона (формула Гаусса). Не используется
  /// в [compute] (там бeрётся центр bbox), но полезен внешним вызывающим.
  static Vec2 polygonCentroid(List<Vec2> outline) {
    var cx = 0.0;
    var cy = 0.0;
    var area = 0.0;
    final n = outline.length;
    for (var i = 0; i < n; i++) {
      final a = outline[i];
      final b = outline[(i + 1) % n];
      final cross = a.x * b.y - b.x * a.y;
      cx += (a.x + b.x) * cross;
      cy += (a.y + b.y) * cross;
      area += cross;
    }
    area /= 2;
    if (area.abs() < 1e-9) {
      // Вырожденный полигон — берём bbox-центр.
      var minX = outline.first.x, maxX = outline.first.x;
      var minY = outline.first.y, maxY = outline.first.y;
      for (final p in outline) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }
      return Vec2((minX + maxX) / 2, (minY + maxY) / 2);
    }
    return Vec2(cx / (6 * area), cy / (6 * area));
  }
}


