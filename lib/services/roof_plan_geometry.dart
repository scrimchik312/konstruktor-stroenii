import 'dart:math' as math;

import '../models/building_footprint.dart';
import 'polygon_helpers.dart';

/// Нормализованный тип формы кровли (для геометрии плана АР-N).
enum RoofShape {
  /// Двускатная — два ската с коньком вдоль длинной стороны.
  gable,

  /// Вальмовая — четыре ската, конёк по центру длинной стороны,
  /// накосы (хребты) от каждого угла.
  hip,

  /// Плоская — единый «скат» со слабым уклоном (1.5–3°), сток в одну
  /// или несколько точек.
  flat,

  /// Односкатная — один ровный скат с одного карниза до другого.
  shed,

  /// Мансардная (ломаная) — две пары скатов с разным углом наклона;
  /// в плане эквивалентна двускатной (мы рисуем верхний коньковый узел).
  mansard;

  /// Преобразует строку из `RoofDesign.type` (`'gable'`, `'hip'`, …) в
  /// нормализованный enum. Если строка пустая или незнакомая —
  /// считаем двускатную (самый частый вариант).
  static RoofShape fromTypeId(String? id) {
    switch (id) {
      case 'hip':
      case 'hipped':
      case 'fourSlope':
      case 'four_slope':
        return RoofShape.hip;
      case 'flat':
        return RoofShape.flat;
      case 'shed':
      case 'mono':
      case 'singleSlope':
      case 'single_slope':
        return RoofShape.shed;
      case 'mansard':
      case 'mansarda':
        return RoofShape.mansard;
      case 'gable':
      case 'twoSlope':
      case 'two_slope':
      default:
        return RoofShape.gable;
    }
  }
}

/// Точка в плане кровли (модельные координаты, м).
class RoofPoint {
  final double x;
  final double y;
  const RoofPoint(this.x, this.y);
}

/// Отрезок (от точки до точки).
class RoofSegment {
  final RoofPoint a;
  final RoofPoint b;
  const RoofSegment(this.a, this.b);
}

/// Один скат: его поверхность задаётся полигоном, направление стока —
/// единичным вектором (в плановых координатах), уклон — в градусах.
class RoofSlope {
  /// Многоугольник скатной поверхности (по часовой стрелке) в плановых
  /// координатах.
  final List<RoofPoint> polygon;

  /// Точка, в которой стоит метка стрелки уклона.
  final RoofPoint arrowAnchor;

  /// Единичный вектор направления стока (по плану).
  final RoofPoint flowDirection;

  /// Уклон ската в градусах (от горизонтали).
  final double slopeDegrees;

  /// Уклон ската в процентах (= tan(angle) * 100).
  final double slopePercent;

  const RoofSlope({
    required this.polygon,
    required this.arrowAnchor,
    required this.flowDirection,
    required this.slopeDegrees,
    required this.slopePercent,
  });
}

/// Phase-3b §21.1.3 / §21.5: рабочий объект — луч из вершины полигона
/// (биссектриса) с длиной до ближайшего конька / соседнего луча.
/// Поле [length] мутабельно: pass 2 (взаимные пересечения) и pass 3
/// (склейка соседних накосов) корректируют длину уже после pass 1.
class _BisectorRay {
  final int index;
  final Vec2 origin;
  final Vec2 dir;
  double length;
  final bool isConvex;
  final bool isReflex;

  _BisectorRay({
    required this.index,
    required this.origin,
    required this.dir,
    required this.length,
    required this.isConvex,
    required this.isReflex,
  });
}

/// §21.1.3 + §21.1 п. 3 — точка встречи двух биссектрис до конька.
/// От такой точки исходит «merged wavefront» — продолжение в среднем
/// направлении до ближайшего конька (или ещё одной встречи). Это
/// аналог edge-event в straight-skeleton (Aichholzer/Aurenhammer 1995).
class _MergeEvent {
  final double x;
  final double y;
  final double dirX;
  final double dirY;
  /// Обе биссектрисы шли из convex-вершин (накосы) — продолжение
  /// рисуется как hip.
  final bool convex;
  /// Обе биссектрисы шли из reflex-вершин (ендовы) — продолжение
  /// рисуется как valley.
  final bool reflex;
  const _MergeEvent({
    required this.x,
    required this.y,
    required this.dirX,
    required this.dirY,
    required this.convex,
    required this.reflex,
  });
}

/// Геометрия плана кровли — то, что мы рисуем на листе АР-N.
///
/// Все координаты — в метрах в системе пятна застройки (ось Y вниз).
/// Свес ([overhang]) уже учтён в координатах [outerOutline]; стены здания
/// идут по прямоугольнику от (0, 0) до ([buildingWidth], [buildingHeight]).
class RoofPlanGeometry {
  final RoofShape shape;
  final double buildingWidth; // м (X в плане)
  final double buildingHeight; // м (Y в плане)
  final double overhang; // м, карнизный свес
  final double slopeDegrees; // средний угол ската
  final double slopePercent;

  /// Внешний контур кровли (с учётом свеса). Замкнутый прямоугольник:
  /// (-o, -o), (W+o, -o), (W+o, H+o), (-o, H+o).
  final List<RoofPoint> outerOutline;

  /// Скаты.
  final List<RoofSlope> slopes;

  /// Линии конька (1 — для двускатной, 1 — для вальмовой; 0 — для
  /// плоской/односкатной; до 2 — для мансардной).
  final List<RoofSegment> ridges;

  /// Хребты/накосы (только для вальмовой кровли — 4 шт. от углов
  /// здания к концам конька).
  final List<RoofSegment> hips;

  /// Ендовы (внутренние стыки скатов). В v14 пустые — поддержка
  /// L/T-форм здания появится в v14.1.
  final List<RoofSegment> valleys;

  /// Точки водосливных воронок/выпусков.
  final List<RoofPoint> drains;

  /// Линии снегозадержателей (по карнизам). Появляются, если
  /// снеговой район ≥ 4 (по СП 17.13330.2017, п. 9.12).
  final List<RoofSegment> snowGuards;

  /// Дымоходы (квадратные маркеры).
  final List<RoofPoint> chimneys;

  /// Аэраторы (вентиляционные выходы — кружки).
  final List<RoofPoint> aerators;

  /// Габарит кровли с учётом свеса: ширина и высота прямоугольника.
  double get totalWidth => buildingWidth + overhang * 2;
  double get totalHeight => buildingHeight + overhang * 2;

  RoofPlanGeometry({
    required this.shape,
    required this.buildingWidth,
    required this.buildingHeight,
    required this.overhang,
    required this.slopeDegrees,
    required this.outerOutline,
    required this.slopes,
    required this.ridges,
    required this.hips,
    required this.valleys,
    required this.drains,
    required this.snowGuards,
    required this.chimneys,
    required this.aerators,
  }) : slopePercent = math.tan(slopeDegrees * math.pi / 180) * 100;

  /// Собирает план кровли из исходных данных проекта.
  ///
  /// [buildingWidth] и [buildingHeight] — габариты пятна верхнего этажа,
  /// именно по этому контуру кладутся скатные плоскости. Карнизный свес
  /// принимается равным [overhang] (по умолчанию 0.5 м, типовое значение
  /// для частного домостроения).
  static RoofPlanGeometry compute({
    required RoofShape shape,
    required double buildingWidth,
    required double buildingHeight,
    required double slopeDegrees,
    double overhang = 0.5,
    int snowZone = 1,
    int chimneyCount = 0,
    int aeratorCount = 0,
  }) {
    final w = buildingWidth;
    final h = buildingHeight;
    final o = overhang;

    // Внешний контур кровли (с учётом свеса).
    final outer = <RoofPoint>[
      RoofPoint(-o, -o),
      RoofPoint(w + o, -o),
      RoofPoint(w + o, h + o),
      RoofPoint(-o, h + o),
    ];

    final slopes = <RoofSlope>[];
    final ridges = <RoofSegment>[];
    final hips = <RoofSegment>[];
    final drains = <RoofPoint>[];
    final snowGuards = <RoofSegment>[];
    final chimneys = <RoofPoint>[];
    final aerators = <RoofPoint>[];

    // Чтобы конёк всегда шёл вдоль длинной стороны, ориентируем форму:
    // если высота > ширины, считаем «вертикальную» ориентацию (для gable/hip).
    final ridgeAlongX = w >= h;

    switch (shape) {
      case RoofShape.gable:
      case RoofShape.mansard:
        if (ridgeAlongX) {
          // Конёк идёт горизонтально по середине высоты.
          final yMid = h / 2;
          ridges.add(RoofSegment(
            RoofPoint(-o, yMid),
            RoofPoint(w + o, yMid),
          ));
          // Верхний скат: стекает вверх (в плане — на север).
          slopes.add(RoofSlope(
            polygon: [
              RoofPoint(-o, -o),
              RoofPoint(w + o, -o),
              RoofPoint(w + o, yMid),
              RoofPoint(-o, yMid),
            ],
            arrowAnchor: RoofPoint(w / 2, yMid / 2),
            flowDirection: const RoofPoint(0, -1),
            slopeDegrees: slopeDegrees,
            slopePercent: math.tan(slopeDegrees * math.pi / 180) * 100,
          ));
          // Нижний скат: стекает вниз (в плане — на юг).
          slopes.add(RoofSlope(
            polygon: [
              RoofPoint(-o, yMid),
              RoofPoint(w + o, yMid),
              RoofPoint(w + o, h + o),
              RoofPoint(-o, h + o),
            ],
            arrowAnchor: RoofPoint(w / 2, yMid + (h - yMid) / 2),
            flowDirection: const RoofPoint(0, 1),
            slopeDegrees: slopeDegrees,
            slopePercent: math.tan(slopeDegrees * math.pi / 180) * 100,
          ));
        } else {
          final xMid = w / 2;
          ridges.add(RoofSegment(
            RoofPoint(xMid, -o),
            RoofPoint(xMid, h + o),
          ));
          slopes.add(RoofSlope(
            polygon: [
              RoofPoint(-o, -o),
              RoofPoint(xMid, -o),
              RoofPoint(xMid, h + o),
              RoofPoint(-o, h + o),
            ],
            arrowAnchor: RoofPoint(xMid / 2, h / 2),
            flowDirection: const RoofPoint(-1, 0),
            slopeDegrees: slopeDegrees,
            slopePercent: math.tan(slopeDegrees * math.pi / 180) * 100,
          ));
          slopes.add(RoofSlope(
            polygon: [
              RoofPoint(xMid, -o),
              RoofPoint(w + o, -o),
              RoofPoint(w + o, h + o),
              RoofPoint(xMid, h + o),
            ],
            arrowAnchor: RoofPoint(xMid + (w - xMid) / 2, h / 2),
            flowDirection: const RoofPoint(1, 0),
            slopeDegrees: slopeDegrees,
            slopePercent: math.tan(slopeDegrees * math.pi / 180) * 100,
          ));
        }
        break;

      case RoofShape.hip:
        // Конёк и накосы для вальмовой кровли.
        // Длина конька = max(W,H) - min(W,H), середина по короткой стороне.
        if (ridgeAlongX) {
          final yMid = h / 2;
          final ridgeStart = h / 2; // конёк начинается на расстоянии h/2 от края
          final ridgeEnd = w - h / 2;
          if (ridgeEnd > ridgeStart) {
            ridges.add(RoofSegment(
              RoofPoint(ridgeStart, yMid),
              RoofPoint(ridgeEnd, yMid),
            ));
          }
          // Накосы от 4 углов здания к концам конька.
          hips.addAll([
            RoofSegment(const RoofPoint(0, 0), RoofPoint(ridgeStart, yMid)),
            RoofSegment(RoofPoint(w, 0), RoofPoint(ridgeEnd, yMid)),
            RoofSegment(RoofPoint(0, h), RoofPoint(ridgeStart, yMid)),
            RoofSegment(RoofPoint(w, h), RoofPoint(ridgeEnd, yMid)),
          ]);
          // 4 ската: верхний, нижний, левый, правый.
          // Верхний скат — трапеция.
          slopes.add(RoofSlope(
            polygon: [
              RoofPoint(-o, -o),
              RoofPoint(w + o, -o),
              RoofPoint(ridgeEnd, yMid),
              RoofPoint(ridgeStart, yMid),
            ],
            arrowAnchor: RoofPoint(w / 2, yMid * 0.45),
            flowDirection: const RoofPoint(0, -1),
            slopeDegrees: slopeDegrees,
            slopePercent: math.tan(slopeDegrees * math.pi / 180) * 100,
          ));
          slopes.add(RoofSlope(
            polygon: [
              RoofPoint(ridgeStart, yMid),
              RoofPoint(ridgeEnd, yMid),
              RoofPoint(w + o, h + o),
              RoofPoint(-o, h + o),
            ],
            arrowAnchor: RoofPoint(w / 2, yMid + (h - yMid) * 0.55),
            flowDirection: const RoofPoint(0, 1),
            slopeDegrees: slopeDegrees,
            slopePercent: math.tan(slopeDegrees * math.pi / 180) * 100,
          ));
          // Левый скат — треугольник (вальм).
          slopes.add(RoofSlope(
            polygon: [
              RoofPoint(-o, -o),
              RoofPoint(ridgeStart, yMid),
              RoofPoint(-o, h + o),
            ],
            arrowAnchor: RoofPoint(ridgeStart * 0.5, yMid),
            flowDirection: const RoofPoint(-1, 0),
            slopeDegrees: slopeDegrees,
            slopePercent: math.tan(slopeDegrees * math.pi / 180) * 100,
          ));
          slopes.add(RoofSlope(
            polygon: [
              RoofPoint(ridgeEnd, yMid),
              RoofPoint(w + o, -o),
              RoofPoint(w + o, h + o),
            ],
            arrowAnchor: RoofPoint(ridgeEnd + (w - ridgeEnd) * 0.5, yMid),
            flowDirection: const RoofPoint(1, 0),
            slopeDegrees: slopeDegrees,
            slopePercent: math.tan(slopeDegrees * math.pi / 180) * 100,
          ));
        } else {
          final xMid = w / 2;
          final ridgeStart = w / 2;
          final ridgeEnd = h - w / 2;
          if (ridgeEnd > ridgeStart) {
            ridges.add(RoofSegment(
              RoofPoint(xMid, ridgeStart),
              RoofPoint(xMid, ridgeEnd),
            ));
          }
          hips.addAll([
            RoofSegment(const RoofPoint(0, 0), RoofPoint(xMid, ridgeStart)),
            RoofSegment(RoofPoint(0, h), RoofPoint(xMid, ridgeEnd)),
            RoofSegment(RoofPoint(w, 0), RoofPoint(xMid, ridgeStart)),
            RoofSegment(RoofPoint(w, h), RoofPoint(xMid, ridgeEnd)),
          ]);
          slopes.add(RoofSlope(
            polygon: [
              RoofPoint(-o, -o),
              RoofPoint(xMid, ridgeStart),
              RoofPoint(xMid, ridgeEnd),
              RoofPoint(-o, h + o),
            ],
            arrowAnchor: RoofPoint(xMid * 0.45, h / 2),
            flowDirection: const RoofPoint(-1, 0),
            slopeDegrees: slopeDegrees,
            slopePercent: math.tan(slopeDegrees * math.pi / 180) * 100,
          ));
          slopes.add(RoofSlope(
            polygon: [
              RoofPoint(xMid, ridgeStart),
              RoofPoint(w + o, -o),
              RoofPoint(w + o, h + o),
              RoofPoint(xMid, ridgeEnd),
            ],
            arrowAnchor: RoofPoint(xMid + (w - xMid) * 0.55, h / 2),
            flowDirection: const RoofPoint(1, 0),
            slopeDegrees: slopeDegrees,
            slopePercent: math.tan(slopeDegrees * math.pi / 180) * 100,
          ));
          slopes.add(RoofSlope(
            polygon: [
              RoofPoint(-o, -o),
              RoofPoint(w + o, -o),
              RoofPoint(xMid, ridgeStart),
            ],
            arrowAnchor: RoofPoint(w / 2, ridgeStart * 0.5),
            flowDirection: const RoofPoint(0, -1),
            slopeDegrees: slopeDegrees,
            slopePercent: math.tan(slopeDegrees * math.pi / 180) * 100,
          ));
          slopes.add(RoofSlope(
            polygon: [
              RoofPoint(xMid, ridgeEnd),
              RoofPoint(w + o, h + o),
              RoofPoint(-o, h + o),
            ],
            arrowAnchor: RoofPoint(w / 2, ridgeEnd + (h - ridgeEnd) * 0.5),
            flowDirection: const RoofPoint(0, 1),
            slopeDegrees: slopeDegrees,
            slopePercent: math.tan(slopeDegrees * math.pi / 180) * 100,
          ));
        }
        break;

      case RoofShape.flat:
        // Плоская: один «скат» со слабым уклоном к одной длинной
        // стороне. Минимальный уклон по СП 17.13330.2017 — 1.5%.
        slopes.add(RoofSlope(
          polygon: [
            RoofPoint(-o, -o),
            RoofPoint(w + o, -o),
            RoofPoint(w + o, h + o),
            RoofPoint(-o, h + o),
          ],
          arrowAnchor: RoofPoint(w / 2, h / 2),
          flowDirection: ridgeAlongX
              ? const RoofPoint(0, 1)
              : const RoofPoint(1, 0),
          slopeDegrees: slopeDegrees < 1 ? 1.5 : slopeDegrees,
          slopePercent:
              math.tan((slopeDegrees < 1 ? 1.5 : slopeDegrees) * math.pi / 180) *
                  100,
        ));
        break;

      case RoofShape.shed:
        // Односкатная: один скат от одной стены к противоположной.
        // По умолчанию стекает вниз (на юг) для солнечной ориентации.
        slopes.add(RoofSlope(
          polygon: [
            RoofPoint(-o, -o),
            RoofPoint(w + o, -o),
            RoofPoint(w + o, h + o),
            RoofPoint(-o, h + o),
          ],
          arrowAnchor: RoofPoint(w / 2, h / 2),
          flowDirection: const RoofPoint(0, 1),
          slopeDegrees: slopeDegrees,
          slopePercent: math.tan(slopeDegrees * math.pi / 180) * 100,
        ));
        break;
    }

    // --- Водосливы ---
    // По кровельному ГОСТ Р 58739-2019: 1 воронка на каждые ~80–100 м²
    // ската, минимум 2 на скате. Для частного дома ≤ 200 м² ставим
    // воронки в углах карниза.
    if (shape == RoofShape.flat) {
      // Плоская кровля: 4 воронки внутри (ближе к углам, не на свесе).
      const inset = 0.4;
      drains.add(const RoofPoint(inset, inset));
      drains.add(RoofPoint(w - inset, inset));
      drains.add(RoofPoint(w - inset, h - inset));
      drains.add(RoofPoint(inset, h - inset));
    } else {
      // Скатная: воронки на углах внешнего свеса вдоль карниза стока.
      // Для двускатной/мансардной — на всех 4 углах нижнего и верхнего ската.
      // Для вальмовой — на всех 4 углах.
      // Для односкатной — только по нижнему карнизу.
      if (shape == RoofShape.shed) {
        drains.add(RoofPoint(-o, h + o));
        drains.add(RoofPoint(w + o, h + o));
      } else {
        drains.add(RoofPoint(-o, -o));
        drains.add(RoofPoint(w + o, -o));
        drains.add(RoofPoint(-o, h + o));
        drains.add(RoofPoint(w + o, h + o));
      }
    }

    // --- Снегозадержатели ---
    // По СП 17.13330.2017 п. 9.12 при углах ≥ 5° и снеге ≥ 180 кг/м²
    // (район III и выше) — на 0.6–1 м выше карниза.
    if (slopeDegrees >= 5 && snowZone >= 3 && shape != RoofShape.flat) {
      // Линия снегозадержателей вдоль каждого карниза стока.
      // Для двускатной/мансардной (ridgeAlongX): два карниза, верхний
      // (y = -o) и нижний (y = h+o).
      if (shape == RoofShape.gable || shape == RoofShape.mansard) {
        if (ridgeAlongX) {
          snowGuards.add(RoofSegment(
            RoofPoint(-o + 0.5, -o + 0.6),
            RoofPoint(w + o - 0.5, -o + 0.6),
          ));
          snowGuards.add(RoofSegment(
            RoofPoint(-o + 0.5, h + o - 0.6),
            RoofPoint(w + o - 0.5, h + o - 0.6),
          ));
        } else {
          snowGuards.add(RoofSegment(
            RoofPoint(-o + 0.6, -o + 0.5),
            RoofPoint(-o + 0.6, h + o - 0.5),
          ));
          snowGuards.add(RoofSegment(
            RoofPoint(w + o - 0.6, -o + 0.5),
            RoofPoint(w + o - 0.6, h + o - 0.5),
          ));
        }
      } else if (shape == RoofShape.hip) {
        // Все 4 карниза.
        snowGuards.add(RoofSegment(
          RoofPoint(-o + 0.5, -o + 0.6),
          RoofPoint(w + o - 0.5, -o + 0.6),
        ));
        snowGuards.add(RoofSegment(
          RoofPoint(-o + 0.5, h + o - 0.6),
          RoofPoint(w + o - 0.5, h + o - 0.6),
        ));
        snowGuards.add(RoofSegment(
          RoofPoint(-o + 0.6, -o + 0.5),
          RoofPoint(-o + 0.6, h + o - 0.5),
        ));
        snowGuards.add(RoofSegment(
          RoofPoint(w + o - 0.6, -o + 0.5),
          RoofPoint(w + o - 0.6, h + o - 0.5),
        ));
      } else if (shape == RoofShape.shed) {
        // Только по нижнему стоку.
        snowGuards.add(RoofSegment(
          RoofPoint(-o + 0.5, h + o - 0.6),
          RoofPoint(w + o - 0.5, h + o - 0.6),
        ));
      }
    }

    // --- Дымоходы ---
    // Размещаем у конька (для лучшей тяги). По умолчанию 1 шт. сразу
    // у конька со стороны центра здания.
    if (chimneyCount > 0) {
      if (shape == RoofShape.gable ||
          shape == RoofShape.mansard ||
          shape == RoofShape.hip) {
        if (ridgeAlongX) {
          for (var i = 0; i < chimneyCount; i++) {
            final t = (i + 1) / (chimneyCount + 1);
            chimneys.add(RoofPoint(w * t, h / 2 - 0.3));
          }
        } else {
          for (var i = 0; i < chimneyCount; i++) {
            final t = (i + 1) / (chimneyCount + 1);
            chimneys.add(RoofPoint(w / 2 - 0.3, h * t));
          }
        }
      } else {
        // Для плоской — у любого края.
        for (var i = 0; i < chimneyCount; i++) {
          final t = (i + 1) / (chimneyCount + 1);
          chimneys.add(RoofPoint(w * 0.85, h * t));
        }
      }
    }

    // --- Аэраторы ---
    // По 1 на каждые 30–50 м² скатной кровли. Для частного дома ставим
    // 1–2 точечных аэратора у конька (для шевронной вентиляции
    // подкровельного пространства).
    if (aeratorCount > 0 &&
        (shape == RoofShape.gable ||
            shape == RoofShape.mansard ||
            shape == RoofShape.hip)) {
      if (ridgeAlongX) {
        for (var i = 0; i < aeratorCount; i++) {
          final t = (i + 1) / (aeratorCount + 1);
          aerators.add(RoofPoint(w * t, h / 2 + 0.3));
        }
      } else {
        for (var i = 0; i < aeratorCount; i++) {
          final t = (i + 1) / (aeratorCount + 1);
          aerators.add(RoofPoint(w / 2 + 0.3, h * t));
        }
      }
    }

    return RoofPlanGeometry(
      shape: shape,
      buildingWidth: w,
      buildingHeight: h,
      overhang: o,
      slopeDegrees: slopeDegrees,
      outerOutline: outer,
      slopes: slopes,
      ridges: ridges,
      hips: hips,
      valleys: const [],
      drains: drains,
      snowGuards: snowGuards,
      chimneys: chimneys,
      aerators: aerators,
    );
  }

  /// Phase-3b §17.2.1 next-slice: план кровли по полигональному
  /// footprint-у (L/T/U/Г-формы).
  ///
  /// Полигон раскладывается на оси-выровненные прямоугольники через
  /// [BuildingFootprint.rectangleDecomposition], и для каждого
  /// собирается своя двускатная кровля (конёк по длинной стороне
  /// прямоугольника). Свес учитывается только на сегментах outline-а,
  /// которые лежат на периметре полигона; на «общих» рёбрах между
  /// соседними прямоугольниками декомпозиции свес = 0, и эти рёбра
  /// становятся ендовами (`valleys`).
  ///
  /// Внешний контур кровли — это полигон, расширенный наружу на
  /// `overhang` по биссектрисам (для axis-aligned 90°-углов смещения
  /// тривиальны: ±overhang по обеим осям).
  ///
  /// Для `RoofShape.flat` / `RoofShape.shed` падает обратно на
  /// `compute(...)` по bbox — плоская/односкатная кровля над
  /// L-формой не требует разложения.
  ///
  /// `RoofShape.hip` и `RoofShape.mansard` пока трактуются как `gable`
  /// над каждым подпрямоугольником (упрощение «первого слайса»).
  static RoofPlanGeometry computePolygonal({
    required RoofShape shape,
    required BuildingFootprint footprint,
    required double slopeDegrees,
    double overhang = 0.5,
    int snowZone = 1,
    int chimneyCount = 0,
    int aeratorCount = 0,
  }) {
    final box = footprint.bbox;
    // Плоская и односкатная — берём bbox-овую логику; для них уступ
    // выреза не требует отдельной геометрии — это просто L-плоскость.
    if (shape == RoofShape.flat || shape == RoofShape.shed) {
      return compute(
        shape: shape,
        buildingWidth: box.width,
        buildingHeight: box.height,
        slopeDegrees: slopeDegrees,
        overhang: overhang,
        snowZone: snowZone,
        chimneyCount: chimneyCount,
        aeratorCount: aeratorCount,
      );
    }

    final rects = footprint.rectangleDecomposition();
    if (rects.length <= 1) {
      // Нет уступов — обычная прямоугольная кровля.
      // §21.1.2: для прямоугольного, но НЕ axis-aligned полигона
      // (например, эркер 45° или треугольная крыша) внешний контур
      // должен следовать форме полигона, а не bbox. Если полигон
      // нетривиально повёрнут / не axis-aligned, перекладываем
      // outerOutline на polygon offset.
      final base = compute(
        shape: shape,
        buildingWidth: box.width,
        buildingHeight: box.height,
        slopeDegrees: slopeDegrees,
        overhang: overhang,
        snowZone: snowZone,
        chimneyCount: chimneyCount,
        aeratorCount: aeratorCount,
      );
      // Если outline — простой axis-aligned прямоугольник из 4 точек,
      // bbox и полигон совпадают, и base.outerOutline уже правильный.
      // Иначе подменяем outerOutline на полигон, расширенный наружу.
      final isSimpleRect = footprint.outline.length == 4 &&
          _isAxisAligned(footprint.outline);
      if (isSimpleRect) return base;
      final outer = _offsetPolygonOutward(footprint.outline, overhang);
      return RoofPlanGeometry(
        shape: base.shape,
        buildingWidth: base.buildingWidth,
        buildingHeight: base.buildingHeight,
        overhang: base.overhang,
        slopeDegrees: base.slopeDegrees,
        outerOutline: outer,
        slopes: base.slopes,
        ridges: base.ridges,
        hips: base.hips,
        valleys: base.valleys,
        drains: base.drains,
        snowGuards: base.snowGuards,
        chimneys: base.chimneys,
        aerators: base.aerators,
      );
    }

    final o = overhang;

    // Внешний контур: полигон, расширенный наружу на `o` по
    // биссектрисам. Для CCW axis-aligned 90°-полигона: смещение
    // вершины = (signX, signY) * o, где знаки определяются
    // двумя соседними внешними нормалями.
    final outer = _offsetPolygonOutward(footprint.outline, o);

    final slopes = <RoofSlope>[];
    final ridges = <RoofSegment>[];
    final hips = <RoofSegment>[];
    final valleys = <RoofSegment>[];
    final drains = <RoofPoint>[];
    final snowGuards = <RoofSegment>[];
    final chimneys = <RoofPoint>[];
    final aerators = <RoofPoint>[];

    // Для каждого подпрямоугольника определяем, какие из 4 его сторон
    // лежат на периметре исходного полигона (есть свес `o`), а какие
    // делятся с соседним прямоугольником (свес = 0; эта сторона —
    // ендова).
    for (final r in rects) {
      final x0 = r.x;
      final y0 = r.y;
      final x1 = r.x + r.width;
      final y1 = r.y + r.height;
      // Проверка: точка чуть-чуть «снаружи» данной стороны
      // — внутри полигона или нет?
      const eps = 0.001;
      bool isShared(double tx, double ty) =>
          footprint.contains(Vec2(tx, ty));
      // Top side (y = y0): тестовая точка ниже (y - eps)
      // Wait, I need to define orientation. Let's say y0 < y1,
      // so y=y0 is bottom side, y=y1 is top side, x=x0 left, x=x1 right.
      // Test points just outside each side:
      final bottomShared = isShared((x0 + x1) / 2, y0 - eps);
      final topShared = isShared((x0 + x1) / 2, y1 + eps);
      final leftShared = isShared(x0 - eps, (y0 + y1) / 2);
      final rightShared = isShared(x1 + eps, (y0 + y1) / 2);

      final oTop = topShared ? 0.0 : o;
      final oBottom = bottomShared ? 0.0 : o;
      final oLeft = leftShared ? 0.0 : o;
      final oRight = rightShared ? 0.0 : o;

      // Конёк вдоль длинной стороны прямоугольника. Если ширина >=
      // высоты, конёк горизонтальный (вдоль x).
      final ridgeAlongX = r.width >= r.height;
      final tan = math.tan(slopeDegrees * math.pi / 180);
      if (ridgeAlongX) {
        final yMid = y0 + r.height / 2;
        ridges.add(RoofSegment(
          RoofPoint(x0 - oLeft, yMid),
          RoofPoint(x1 + oRight, yMid),
        ));
        // Верхний скат: от конька до северного карниза.
        slopes.add(RoofSlope(
          polygon: [
            RoofPoint(x0 - oLeft, y0 - oBottom),
            RoofPoint(x1 + oRight, y0 - oBottom),
            RoofPoint(x1 + oRight, yMid),
            RoofPoint(x0 - oLeft, yMid),
          ],
          arrowAnchor: RoofPoint((x0 + x1) / 2, y0 + r.height / 4),
          flowDirection: const RoofPoint(0, -1),
          slopeDegrees: slopeDegrees,
          slopePercent: tan * 100,
        ));
        // Нижний скат: от конька до южного карниза.
        slopes.add(RoofSlope(
          polygon: [
            RoofPoint(x0 - oLeft, yMid),
            RoofPoint(x1 + oRight, yMid),
            RoofPoint(x1 + oRight, y1 + oTop),
            RoofPoint(x0 - oLeft, y1 + oTop),
          ],
          arrowAnchor: RoofPoint((x0 + x1) / 2, y0 + r.height * 0.75),
          flowDirection: const RoofPoint(0, 1),
          slopeDegrees: slopeDegrees,
          slopePercent: tan * 100,
        ));
      } else {
        final xMid = x0 + r.width / 2;
        ridges.add(RoofSegment(
          RoofPoint(xMid, y0 - oBottom),
          RoofPoint(xMid, y1 + oTop),
        ));
        slopes.add(RoofSlope(
          polygon: [
            RoofPoint(x0 - oLeft, y0 - oBottom),
            RoofPoint(xMid, y0 - oBottom),
            RoofPoint(xMid, y1 + oTop),
            RoofPoint(x0 - oLeft, y1 + oTop),
          ],
          arrowAnchor: RoofPoint(x0 + r.width / 4, (y0 + y1) / 2),
          flowDirection: const RoofPoint(-1, 0),
          slopeDegrees: slopeDegrees,
          slopePercent: tan * 100,
        ));
        slopes.add(RoofSlope(
          polygon: [
            RoofPoint(xMid, y0 - oBottom),
            RoofPoint(x1 + oRight, y0 - oBottom),
            RoofPoint(x1 + oRight, y1 + oTop),
            RoofPoint(xMid, y1 + oTop),
          ],
          arrowAnchor: RoofPoint(x0 + r.width * 0.75, (y0 + y1) / 2),
          flowDirection: const RoofPoint(1, 0),
          slopeDegrees: slopeDegrees,
          slopePercent: tan * 100,
        ));
      }
    }

    // Phase-3b §17.2.3 / §21.1.2 / §21.1.3 / §21.5: hip / valley
    // геометрия по **внутренним биссектрисам** outline-а.
    //
    // Идём по вершинам outline-а:
    //   • Convex (внутренний угол < 180°) + RoofShape.hip → накос
    //     (вальмовое ребро) внутрь полигона до пересечения с
    //     ближайшим коньком ИЛИ соседним лучом.
    //   • Reflex (внутренний угол > 180°) → ендова внутрь полигона
    //     до пересечения с ближайшим коньком (или с противоположной
    //     ендовой / соседним накосом). Ендовы появляются ВСЕГДА на
    //     reflex-углах, независимо от типа кровли (gable/hip).
    //
    // §21.1.2: используем `vertexInteriorBisectorCcw` — корректно
    //          работает для любых углов, не только 90° / 270°.
    // §21.1.3: 2-проходный алгоритм. Сначала считаем луч из каждой
    //          вершины в направлении биссектрисы и расстояние minS
    //          до ближайшего конька; затем проверяем пересечения
    //          с другими лучами и обрезаем оба луча по точке встречи.
    // §21.5:   соседние накосы, конец которых близок (< 0.4 м) к
    //          одной точке на коньке, "склеиваются" в одну вершину.
    final outline = footprint.outline;
    final wantHips = shape == RoofShape.hip;
    final ccw = polygonIsCcw(outline);

    // Pass 1: подготавливаем лучи для каждой вершины.
    final rays = <_BisectorRay?>[];
    for (var i = 0; i < outline.length; i++) {
      final cur = outline[i];
      var convexity = vertexConvexity(outline, i);
      if (!ccw) {
        if (convexity == VertexConvexity.convex) {
          convexity = VertexConvexity.reflex;
        } else if (convexity == VertexConvexity.reflex) {
          convexity = VertexConvexity.convex;
        }
      }
      if (convexity == VertexConvexity.collinear) {
        rays.add(null);
        continue;
      }
      final isConvex = convexity == VertexConvexity.convex;
      final isReflex = convexity == VertexConvexity.reflex;
      var bisector = vertexInteriorBisectorCcw(outline, i);
      if (!ccw) bisector = Vec2(-bisector.x, -bisector.y);
      // Терминируем луч на пересечении с ближайшим коньком.
      var minS = double.infinity;
      for (final r in ridges) {
        final s = _intersectRayWithSegment(
          originX: cur.x,
          originY: cur.y,
          dirX: bisector.x,
          dirY: bisector.y,
          ax: r.a.x,
          ay: r.a.y,
          bx: r.b.x,
          by: r.b.y,
        );
        if (s != null && s > 0 && s < minS) minS = s;
      }
      // Phase-3b §24.7 v68: split-event detection. Reflex-биссектриса
      // может уйти к противоположному ребру outline-а раньше любого
      // конька — это и есть split-event в straight-skeleton (Aichholzer
      // 1995). Клиппинг выполняется по всем рёбрам outline-а, кроме
      // двух смежных с текущей вершиной (они «свои» и пересекаются в
      // самой вершине). Без этого клиппинга у L/T/U-форм ендова
      // «улетала» сквозь стену, если рёбро ската ещё не было
      // вычислено в `ridges`. Применяется к reflex-вершинам — для
      // convex-биссектрис split-event внутри outline-а невозможен.
      if (isReflex) {
        for (var k = 0; k < outline.length; k++) {
          // Пропускаем два ребра, которые встречаются в текущей вершине:
          //   ребро [i-1 → i] и ребро [i → i+1].
          if (k == i) continue;
          if (k == (i - 1 + outline.length) % outline.length) continue;
          final ea = outline[k];
          final eb = outline[(k + 1) % outline.length];
          final s = _intersectRayWithSegment(
            originX: cur.x,
            originY: cur.y,
            dirX: bisector.x,
            dirY: bisector.y,
            ax: ea.x,
            ay: ea.y,
            bx: eb.x,
            by: eb.y,
          );
          // Минимальное расстояние от точки попадания до origin
          // должно быть > 0.5 м, иначе это «вырожденный» split в
          // соседнюю короткую перемычку — оставляем луч как есть.
          if (s != null && s > 0.5 && s < minS) minS = s;
        }
      }
      if (minS == double.infinity) {
        // Фолбэк: длина = половина минимума соседних рёбер outline-а.
        final prev = outline[(i - 1 + outline.length) % outline.length];
        final next = outline[(i + 1) % outline.length];
        final inLen = math.sqrt((cur.x - prev.x) * (cur.x - prev.x) +
            (cur.y - prev.y) * (cur.y - prev.y));
        final outLen = math.sqrt((next.x - cur.x) * (next.x - cur.x) +
            (next.y - cur.y) * (next.y - cur.y));
        minS = math.min(inLen, outLen) / 2;
      }
      rays.add(_BisectorRay(
        index: i,
        origin: cur,
        dir: bisector,
        length: minS,
        isConvex: isConvex,
        isReflex: isReflex,
      ));
    }

    // Pass 2 (§21.1.3): обрезаем взаимно-пересекающиеся лучи и
    // запоминаем точки их встречи как «merge events» — это аналог
    // edge/split-events в полной straight-skeleton (Aichholzer/
    // Aurenhammer 1995). После обрезки от каждой такой точки идёт
    // продолжение нового объединённого фронта внутрь полигона до
    // ближайшего конька или новой встречи.
    //
    // Для каждой пары рассмотренных лучей проверяем, пересекаются ли
    // их направленные отрезки (origin → origin + dir*length) до своих
    // концов; если да — оба луча укорачиваются.
    final mergeEvents = <_MergeEvent>[];
    for (var i = 0; i < rays.length; i++) {
      final ri = rays[i];
      if (ri == null) continue;
      for (var j = i + 1; j < rays.length; j++) {
        final rj = rays[j];
        if (rj == null) continue;
        // Параметры пересечения (t для ri, u для rj).
        final det = -ri.dir.x * rj.dir.y + ri.dir.y * rj.dir.x;
        if (det.abs() < 1e-9) continue;
        final ox = rj.origin.x - ri.origin.x;
        final oy = rj.origin.y - ri.origin.y;
        final t = (-rj.dir.y * ox + rj.dir.x * oy) / det;
        final u = (-ri.dir.y * ox + ri.dir.x * oy) / det;
        if (t <= 1e-3 || u <= 1e-3) continue; // встреча сзади / в самой
        // вершине
        if (t < ri.length && u < rj.length) {
          // Лучи встречаются раньше, чем конёк → обрезаем оба.
          ri.length = t;
          rj.length = u;
          // Точка встречи в координатах плана.
          final px = ri.origin.x + ri.dir.x * t;
          final py = ri.origin.y + ri.dir.y * t;
          // Объединённое направление фронта = нормированная сумма
          // обоих направлений. Для двух convex-биссектрис на
          // соседних convex-углах это даёт направление продолжения
          // hip-ребра к коньку (вдоль главной оси полигона).
          final mx = ri.dir.x + rj.dir.x;
          final my = ri.dir.y + rj.dir.y;
          final mLen = math.sqrt(mx * mx + my * my);
          if (mLen < 1e-9) continue;
          mergeEvents.add(_MergeEvent(
            x: px,
            y: py,
            dirX: mx / mLen,
            dirY: my / mLen,
            convex: ri.isConvex && rj.isConvex,
            reflex: ri.isReflex && rj.isReflex,
          ));
        }
      }
    }

    // §21.5: для каждой пары соседних convex-лучей, если их концы
    // лежат ближе 0.4 м друг к другу, склеиваем их к среднему.
    if (wantHips) {
      const mergeEps = 0.4;
      for (var i = 0; i < rays.length; i++) {
        final a = rays[i];
        final b = rays[(i + 1) % rays.length];
        if (a == null || b == null) continue;
        if (!a.isConvex || !b.isConvex) continue;
        final ax = a.origin.x + a.dir.x * a.length;
        final ay = a.origin.y + a.dir.y * a.length;
        final bx = b.origin.x + b.dir.x * b.length;
        final by = b.origin.y + b.dir.y * b.length;
        final dx = ax - bx;
        final dy = ay - by;
        if (math.sqrt(dx * dx + dy * dy) < mergeEps) {
          final mx = (ax + bx) / 2;
          final my = (ay + by) / 2;
          // Перепроецируем длину каждого луча на новую общую точку.
          a.length = ((mx - a.origin.x) * a.dir.x +
                  (my - a.origin.y) * a.dir.y) /
              (a.dir.x * a.dir.x + a.dir.y * a.dir.y);
          b.length = ((mx - b.origin.x) * b.dir.x +
                  (my - b.origin.y) * b.dir.y) /
              (b.dir.x * b.dir.x + b.dir.y * b.dir.y);
        }
      }
    }

    // Pass 3: материализуем валидные лучи в hip/valley сегменты.
    for (final ray in rays) {
      if (ray == null) continue;
      if (ray.length < 0.1) continue; // слишком короткий — пропускаем
      final endX = ray.origin.x + ray.dir.x * ray.length;
      final endY = ray.origin.y + ray.dir.y * ray.length;
      final seg = RoofSegment(
        RoofPoint(ray.origin.x, ray.origin.y),
        RoofPoint(endX, endY),
      );
      if (ray.isReflex) {
        valleys.add(seg);
      } else if (ray.isConvex && wantHips) {
        hips.add(seg);
      }
    }

    // Pass 4 (§21.1 п. 3): straight-skeleton continuation. От каждой
    // зафиксированной точки встречи (mergeEvent) строим продолжение
    // фронта в усреднённом направлении до ближайшего конька. Это
    // отрисовывает «недостающую» линию между парой встретившихся
    // биссектрис и коньком — корректное поведение для узких T/U/+
    // участков, где две 45° линии встречаются раньше, чем одна из
    // них доходит до конька.
    //
    // Дедупликация по координате: одна и та же точка встречи может
    // быть найдена несколько раз (при пересечении 3+ лучей в общей
    // точке) — оставляем по одному продолжению на ≈ 0.4 м.
    final seenMerges = <String>{};
    for (final e in mergeEvents) {
      final key = '${(e.x * 5).round()}_${(e.y * 5).round()}';
      if (!seenMerges.add(key)) continue;
      // Длина продолжения — до пересечения с ближайшим коньком в
      // направлении (e.dirX, e.dirY). Если нет пересечения — луч
      // заканчивается на 1 м (визуальный fallback).
      var minS = double.infinity;
      for (final r in ridges) {
        final s = _intersectRayWithSegment(
          originX: e.x,
          originY: e.y,
          dirX: e.dirX,
          dirY: e.dirY,
          ax: r.a.x,
          ay: r.a.y,
          bx: r.b.x,
          by: r.b.y,
        );
        if (s != null && s > 0.05 && s < minS) minS = s;
      }
      if (minS == double.infinity) continue; // без конька — не рисуем
      if (minS < 0.05) continue;
      final endX = e.x + e.dirX * minS;
      final endY = e.y + e.dirY * minS;
      final seg = RoofSegment(
        RoofPoint(e.x, e.y),
        RoofPoint(endX, endY),
      );
      if (e.reflex) {
        valleys.add(seg);
      } else if (e.convex && wantHips) {
        hips.add(seg);
      } else if (wantHips) {
        // Смешанный случай (convex + reflex) для hip-кровли — на
        // T/U-формах это «продолжение ендовы по центральной оси
        // вдоль стержня» к концу конька. Считаем валидным накосом.
        hips.add(seg);
      }
    }

    // Снегозадержатели — по карнизам периметра (если зона >= 4).
    if (snowZone >= 4) {
      // Идём по сегментам outline-а полигона; для каждого сегмента
      // (длиннее 1.5 м) ставим линию снегозадержателей в 0.4 м от
      // карниза наружу.
      final outline = footprint.outline;
      for (var i = 0; i < outline.length; i++) {
        final p1 = outline[i];
        final p2 = outline[(i + 1) % outline.length];
        final segLen = math.sqrt(
            (p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y));
        if (segLen < 1.5) continue;
        // Внешняя нормаль для CCW.
        final nLen = segLen;
        final nx = (p2.y - p1.y) / nLen;
        final ny = -(p2.x - p1.x) / nLen;
        // Точка в 0.4 м от карниза наружу — на фактической линии
        // снегозадержателя.
        const guardOffset = 0.4;
        snowGuards.add(RoofSegment(
          RoofPoint(p1.x + nx * guardOffset, p1.y + ny * guardOffset),
          RoofPoint(p2.x + nx * guardOffset, p2.y + ny * guardOffset),
        ));
      }
    }

    // Дымоходы — у конька самой большой подкрыши (грубо).
    if (chimneyCount > 0) {
      // Ищем самый длинный конёк; ставим chimneyCount маркеров.
      RoofSegment? longestRidge;
      var longestLen = 0.0;
      for (final r in ridges) {
        final dx = r.b.x - r.a.x;
        final dy = r.b.y - r.a.y;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len > longestLen) {
          longestLen = len;
          longestRidge = r;
        }
      }
      if (longestRidge != null) {
        for (var i = 0; i < chimneyCount; i++) {
          final t = (i + 1) / (chimneyCount + 1);
          chimneys.add(RoofPoint(
            longestRidge.a.x + (longestRidge.b.x - longestRidge.a.x) * t,
            longestRidge.a.y + (longestRidge.b.y - longestRidge.a.y) * t,
          ));
        }
      }
    }

    // Аэраторы — рядом с коньками.
    if (aeratorCount > 0 && ridges.isNotEmpty) {
      for (var i = 0; i < aeratorCount; i++) {
        final ridgeIdx = i % ridges.length;
        final r = ridges[ridgeIdx];
        final t = (i + 1) / (aeratorCount + 1);
        // Чуть в сторону от конька (на 0.3 м).
        aerators.add(RoofPoint(
          r.a.x + (r.b.x - r.a.x) * t + 0.3,
          r.a.y + (r.b.y - r.a.y) * t + 0.3,
        ));
      }
    }

    return RoofPlanGeometry(
      shape: shape,
      buildingWidth: box.width,
      buildingHeight: box.height,
      overhang: o,
      slopeDegrees: slopeDegrees,
      outerOutline: outer,
      slopes: slopes,
      ridges: ridges,
      hips: hips,
      valleys: valleys,
      drains: drains,
      snowGuards: snowGuards,
      chimneys: chimneys,
      aerators: aerators,
    );
  }

  /// Phase-3b §21.1.2: пересечение луча из (originX, originY) в
  /// направлении (dirX, dirY) — единичного или нет, ЛЮБОГО — с
  /// отрезком (ax,ay)–(bx,by). Возвращает параметр t > 0 на луче, где
  /// он попал в отрезок, или null, если пересечения нет.
  ///
  /// Алгоритм — стандартный метод парных параметров: луч `O + t*D`
  /// (t > 0), отрезок `A + u*(B-A)` (u ∈ [0, 1]).
  static double? _intersectRayWithSegment({
    required double originX,
    required double originY,
    required double dirX,
    required double dirY,
    required double ax,
    required double ay,
    required double bx,
    required double by,
  }) {
    final sx = bx - ax;
    final sy = by - ay;
    final det = -dirX * sy + dirY * sx;
    if (det.abs() < 1e-9) {
      // Луч параллелен отрезку.
      return null;
    }
    final ox = ax - originX;
    final oy = ay - originY;
    final t = (-sy * ox + sx * oy) / det;
    final u = (dirX * oy - dirY * ox) / det;
    if (t <= 1e-6) return null;
    if (u < -1e-6 || u > 1 + 1e-6) return null;
    return t;
  }

  /// True, если все рёбра полигона строго горизонтальны или вертикальны
  /// (axis-aligned, типичный случай для L/T/U/+ форм). §21.1.2.
  static bool _isAxisAligned(List<Vec2> outline, {double eps = 1e-6}) {
    final n = outline.length;
    for (var i = 0; i < n; i++) {
      final a = outline[i];
      final b = outline[(i + 1) % n];
      final dx = (b.x - a.x).abs();
      final dy = (b.y - a.y).abs();
      if (dx > eps && dy > eps) return false;
    }
    return true;
  }

  /// Расширяет CCW полигон наружу на `o` (карнизный свес) по
  /// биссектрисам углов. §21.1.2 + §21.1.4:
  /// • Convex (внутренний угол < 180°): вершина смещается на `o`
  ///   наружу вдоль биссектрисы (стандартная Minkowski-расширение).
  /// • Reflex (> 180°): смещение **обнуляется** — карниз режется,
  ///   чтобы не торчал в зону встречи двух скатов (zero-overhang
  ///   на ендовах). Это даёт правильное поведение для L/T/U/+ форм
  ///   и более общих не-axis-aligned контуров.
  /// • Collinear (≈ 180°): сдвигаем по нормали одной из сторон.
  ///
  /// Для каждой convex-вершины смещение = `(nIn + nOut) * o /
  /// (1 + nIn·nOut)`, где `nIn`, `nOut` — единичные **внешние**
  /// нормали соседних рёбер.
  static List<RoofPoint> _offsetPolygonOutward(List<Vec2> outline, double o) {
    final n = outline.length;
    if (n < 3) return [];
    final ccw = polygonIsCcw(outline);
    final result = <RoofPoint>[];
    for (var i = 0; i < n; i++) {
      final prev = outline[(i - 1 + n) % n];
      final curr = outline[i];
      final next = outline[(i + 1) % n];
      final ein = Vec2(curr.x - prev.x, curr.y - prev.y);
      final eout = Vec2(next.x - curr.x, next.y - curr.y);
      final einLen = math.sqrt(ein.x * ein.x + ein.y * ein.y);
      final eoutLen = math.sqrt(eout.x * eout.x + eout.y * eout.y);
      if (einLen < 1e-9 || eoutLen < 1e-9) {
        result.add(RoofPoint(curr.x, curr.y));
        continue;
      }
      // Convex/reflex (с учётом ориентации полигона).
      var conv = vertexConvexity(outline, i);
      if (!ccw) {
        if (conv == VertexConvexity.convex) {
          conv = VertexConvexity.reflex;
        } else if (conv == VertexConvexity.reflex) {
          conv = VertexConvexity.convex;
        }
      }
      // Внешняя нормаль ребра — обратная внутренней.
      // Для CCW (signedArea > 0) внутренняя нормаль = поворот
      // ребра на +90°: (dx, dy) → (-dy, dx). Внешняя — (dy, -dx).
      // Для CW — наоборот.
      final s = ccw ? 1.0 : -1.0;
      final neinX = s * ein.y / einLen;
      final neinY = -s * ein.x / einLen;
      final neoutX = s * eout.y / eoutLen;
      final neoutY = -s * eout.x / eoutLen;
      // §21.1.4 (полная версия v66): на reflex-вершине эмитируем ТРИ
      // вершины внешнего контура — это даёт «правильный внутренний
      // угол» карниза без чамфера и без o·√2-горна.
      //   • (curr + nIn * o)   — конец карниза предыдущего ребра,
      //     остановленный на линии следующего ребра.
      //   • curr               — сама reflex-вершина (поворот к стене).
      //   • (curr + nOut * o)  — начало карниза следующего ребра,
      //     поднятый на линии предыдущего ребра.
      // Между ними outerOutline проходит двумя короткими отрезками
      // длиной o (вдоль стены), что соответствует реальной L/T/U
      // геометрии кровли с нулевым свесом во внутреннем углу.
      if (conv == VertexConvexity.reflex) {
        result.add(RoofPoint(curr.x + neinX * o, curr.y + neinY * o));
        result.add(RoofPoint(curr.x, curr.y));
        result.add(RoofPoint(curr.x + neoutX * o, curr.y + neoutY * o));
        continue;
      }
      final dot = neinX * neoutX + neinY * neoutY; // cos(угол между нормалями)
      final denom = 1 + dot;
      if (denom.abs() < 1e-6) {
        // Угол ≈ 180° — рёбра параллельны и сонаправлены.
        result.add(RoofPoint(curr.x + neinX * o, curr.y + neinY * o));
        continue;
      }
      final bx = neinX + neoutX;
      final by = neinY + neoutY;
      final scale = o / denom;
      result.add(RoofPoint(
        curr.x + bx * scale,
        curr.y + by * scale,
      ));
    }
    return result;
  }
}
