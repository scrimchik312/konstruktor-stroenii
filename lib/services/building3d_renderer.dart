/// Рендер 3D-модели здания в 2D-проекцию с алгоритмом художника
/// (back-face culling + сортировка треугольников по Z).
///
/// Не зависит от Flutter/PDF: вызывающая сторона передаёт коллбэки
/// `drawFilledPoly` и `drawLine`, которые знают, как рисовать на своём
/// холсте (Canvas / PdfGraphics).
library;

import 'dart:math' as math;

import '../models/building3d.dart';

class Camera3D {
  /// Расстояние от центра камеры до точки наблюдения, м.
  /// Для изометрии достаточно большого числа (имитация
  /// ортогональной проекции).
  final double distance;

  /// Поворот камеры вокруг вертикальной оси Z (yaw), радианы.
  final double yaw;

  /// Поворот камеры вокруг горизонтальной оси (pitch), радианы.
  /// 0 — вид сбоку (горизонтально); π/6 — стандартная изометрия;
  /// π/2 — вид сверху.
  final double pitch;

  /// Целевая точка камеры в мировых координатах.
  final Vec3 target;

  /// Если true — ортогональная проекция (изометрия). Если false —
  /// перспективная.
  final bool orthographic;

  const Camera3D({
    required this.distance,
    required this.yaw,
    required this.pitch,
    required this.target,
    this.orthographic = true,
  });

  /// Стандартная изометрия для PDF: 30°/30°.
  factory Camera3D.iso({required Vec3 target, double distance = 50}) {
    return Camera3D(
      distance: distance,
      yaw: math.pi / 4, // 45°
      pitch: math.atan(1 / math.sqrt(2)), // ≈ 35.264° (true isometric)
      target: target,
      orthographic: true,
    );
  }

  /// «Военная» (axonometric, 45°/45°) — частый российский стандарт.
  factory Camera3D.military({required Vec3 target, double distance = 50}) {
    return Camera3D(
      distance: distance,
      yaw: math.pi / 4,
      pitch: math.pi / 4,
      target: target,
      orthographic: true,
    );
  }
}

/// Двумерная точка после проекции + глубина (для z-sort).
class Projected2D {
  final double x;
  final double y;
  final double z; // глубина в координатах камеры (для sort)
  const Projected2D(this.x, this.y, this.z);
}

/// Цвет (RGB в [0..1]).
class Color3 {
  final double r;
  final double g;
  final double b;
  const Color3(this.r, this.g, this.b);

  Color3 lighten(double k) {
    if (k >= 0) {
      return Color3(
          r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k);
    } else {
      final f = 1 + k;
      return Color3(r * f, g * f, b * f);
    }
  }
}

/// Палитра по умолчанию для каждого [SurfaceKind].
class SurfacePalette {
  const SurfacePalette({
    this.foundationUnderground = const Color3(0.32, 0.32, 0.34),
    this.foundationPlinth = const Color3(0.55, 0.55, 0.58),
    this.wallExterior = const Color3(0.93, 0.91, 0.86),
    this.wallInterior = const Color3(0.85, 0.85, 0.85),
    this.slab = const Color3(0.78, 0.78, 0.80),
    this.glazing = const Color3(0.72, 0.84, 0.92),
    this.door = const Color3(0.45, 0.30, 0.20),
    this.roofSlope = const Color3(0.65, 0.32, 0.28),
    this.roofRidge = const Color3(0.30, 0.10, 0.10),
    this.attachmentDeck = const Color3(0.72, 0.55, 0.42),
    this.ground = const Color3(0.85, 0.86, 0.78),
    this.outline = const Color3(0.0, 0.0, 0.0),
  });

  /// Конструирует палитру из идентификатора стенового и кровельного
  /// материала. Используется библиотекой материалов (см.
  /// `data/material_textures.dart`) — позволяет аксонометрии сразу
  /// показывать цвет, выбранный пользователем.
  factory SurfacePalette.forMaterials({
    Color3? wallExterior,
    Color3? roofSlope,
    Color3? roofRidge,
  }) {
    return SurfacePalette(
      wallExterior: wallExterior ?? const Color3(0.93, 0.91, 0.86),
      roofSlope: roofSlope ?? const Color3(0.65, 0.32, 0.28),
      roofRidge: roofRidge ?? const Color3(0.30, 0.10, 0.10),
    );
  }

  final Color3 foundationUnderground;
  final Color3 foundationPlinth;
  final Color3 wallExterior;
  final Color3 wallInterior;
  final Color3 slab;
  final Color3 glazing;
  final Color3 door;
  final Color3 roofSlope;
  final Color3 roofRidge;
  final Color3 attachmentDeck;
  final Color3 ground;
  final Color3 outline;

  Color3 colorOf(SurfaceKind kind) {
    switch (kind) {
      case SurfaceKind.foundationUnderground:
        return foundationUnderground;
      case SurfaceKind.foundationPlinth:
        return foundationPlinth;
      case SurfaceKind.wallExterior:
        return wallExterior;
      case SurfaceKind.wallInterior:
        return wallInterior;
      case SurfaceKind.slab:
        return slab;
      case SurfaceKind.glazing:
        return glazing;
      case SurfaceKind.door:
        return door;
      case SurfaceKind.roofSlope:
        return roofSlope;
      case SurfaceKind.roofRidge:
        return roofRidge;
      case SurfaceKind.attachmentDeck:
        return attachmentDeck;
      case SurfaceKind.ground:
        return ground;
    }
  }

  /// Тенирование по нормали грани относительно стандартного источника
  /// света + полусферического ambient (небо сверху → лёгкий
  /// холодный отсвет, земля снизу → более тёплый тёмный).
  ///
  /// Модель освещения:
  ///   • directional sun: (−0.4, −0.4, +1.0) (юго-запад сверху).
  ///   • hemispheric ambient: грани, смотрящие вверх, получают
  ///     слабый «небесный» бонус, грани вниз — слегка темнее.
  ///   • контраст немного увеличен по сравнению с прежней моделью —
  ///     это придаёт зданию объём без «заваливания» в чёрный.
  Color3 shadeFace(Color3 base, Vec3 normal) {
    final n = normal.normalized;
    final light = const Vec3(-0.4, -0.4, 1.0).normalized;
    final ndl = n.dot(light); // [-1..1]
    // Diffuse component: 0..1 (плоское усреднение на затенённой стороне).
    final diffuse = ((ndl + 1) * 0.5).clamp(0.0, 1.0);
    // Hemisphere ambient: грани, смотрящие вверх, светлее на 8 %,
    // вниз — темнее на 8 %.
    final hemi = 1.0 + n.z * 0.08;
    // Итоговый коэффициент: 0.55..1.18 (диапазон шире прежнего 0.55..1.15
    // на +0.03 для большего контраста).
    final k = (0.55 + 0.63 * diffuse) * hemi;
    return Color3(
      (base.r * k).clamp(0.0, 1.0),
      (base.g * k).clamp(0.0, 1.0),
      (base.b * k).clamp(0.0, 1.0),
    );
  }
}

/// Готовый треугольник для рендеринга (после сборки геометрии).
class RenderTri {
  final Vec3 a;
  final Vec3 b;
  final Vec3 c;
  final SurfaceKind kind;
  final bool wireframeOnly;
  const RenderTri(this.a, this.b, this.c, this.kind,
      {this.wireframeOnly = false});

  Vec3 get normal => (b - a).cross(c - a).normalized;
  Vec3 get centroid => Vec3(
        (a.x + b.x + c.x) / 3,
        (a.y + b.y + c.y) / 3,
        (a.z + b.z + c.z) / 3,
      );

  /// «Слой» для стабильной сортировки painter's-algorithm. Если два
  /// треугольника имеют близкую глубину (Δz < ε) — побеждает тот, у
  /// кого выше [layerOrder]. Это убирает мерцание между coplanar-
  /// гранями (стена дома + торец гаража, скат + конёк, окно + стена).
  int get layerOrder => kindLayer(kind);

  /// Знак 2D-cross-product для треугольника после проекции на экран.
  /// Положительный → CCW при взгляде на лицевую сторону → грань видна.
  /// Используется как back-face cull-test, не зависящий от 3D-винда:
  /// если 2D-cross ≤ 0 — треугольник обращён к камере «спиной» в
  /// экранных координатах и его можно пропустить. Передаются точки
  /// уже после проецирования (но ДО отзеркаливания по Y, иначе знак
  /// инвертируется).
  static double cross2D(double ax, double ay,
      double bx, double by, double cx, double cy) {
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  }

  /// Слой painter's-algorithm для каждого [SurfaceKind]. Большее
  /// значение → ближе к зрителю при равной глубине. Без этого
  /// последовательность отрисовки coplanar-граней непредсказуема и
  /// при вращении часть стены/окна периодически «исчезает» —
  /// классическое z-fighting на canvas без z-buffer-а.
  static int kindLayer(SurfaceKind kind) {
    switch (kind) {
      case SurfaceKind.ground:
        return -1;
      case SurfaceKind.foundationUnderground:
        return 0;
      case SurfaceKind.foundationPlinth:
        return 1;
      case SurfaceKind.wallExterior:
      case SurfaceKind.wallInterior:
      case SurfaceKind.slab:
      case SurfaceKind.attachmentDeck:
        return 2;
      case SurfaceKind.door:
        return 3;
      case SurfaceKind.glazing:
        return 4;
      case SurfaceKind.roofSlope:
        return 5;
      case SurfaceKind.roofRidge:
        return 6;
    }
  }
}

/// Линия для рендеринга (рёбра, конёк и т. п.).
class RenderEdge {
  final Vec3 a;
  final Vec3 b;
  final SurfaceKind kind;
  final double widthPt;
  const RenderEdge(this.a, this.b, this.kind, {this.widthPt = 0.5});
}

/// Главный движок: принимает список треугольников/линий и рисует их.
class Building3DRenderer {
  Building3DRenderer({
    this.palette = const SurfacePalette(),
    this.outlineWidth = 0.4,
    this.silhouetteWidth = 0.9,
  });

  final SurfacePalette palette;
  final double outlineWidth;
  final double silhouetteWidth;

  /// Из готовой [Building3D] строит плоский список рендер-треугольников
  /// (с триангуляцией стен и проёмов).
  List<RenderTri> tessellate(Building3D b) {
    final tris = <RenderTri>[];

    // 1. Земля (большая горизонтальная плоскость) — для контекста.
    final groundSize = math.max(b.footprintWidth, b.footprintLength) * 1.6;
    final cx = b.footprintWidth / 2;
    final cy = b.footprintLength / 2;
    const groundZ = -0.001; // чуть ниже отметки 0, чтобы не «z-fight»
    final g0 = Vec3(cx - groundSize / 2, cy - groundSize / 2, groundZ);
    final g1 = Vec3(cx + groundSize / 2, cy - groundSize / 2, groundZ);
    final g2 = Vec3(cx + groundSize / 2, cy + groundSize / 2, groundZ);
    final g3 = Vec3(cx - groundSize / 2, cy + groundSize / 2, groundZ);
    tris.add(RenderTri(g0, g1, g2, SurfaceKind.ground));
    tris.add(RenderTri(g0, g2, g3, SurfaceKind.ground));

    // 2. Фундамент: подземная часть (от -depth до 0) и цоколь
    // (от 0 до plinthHeight). Рисуем как параллелепипед по контуру.
    _addPrism(
      tris,
      outline: b.foundation.outline,
      bottomZ: -b.foundation.depthM,
      topZ: 0,
      kind: SurfaceKind.foundationUnderground,
    );
    if (b.foundation.plinthHeightM > 0) {
      _addPrism(
        tris,
        outline: b.foundation.outline,
        bottomZ: 0,
        topZ: b.foundation.plinthHeightM,
        kind: SurfaceKind.foundationPlinth,
      );
    }

    // 3. Этажи: для каждой стены — триангуляция с прорезями под проёмы.
    for (final f in b.floors) {
      for (final w in f.walls) {
        _tessellateWall(tris, w, f.elevationM);
      }
      // Перекрытие над этажом (опционально).
      final ceiling = f.ceilingSlab;
      if (ceiling != null) {
        _addSlab(tris, ceiling,
            zTop: f.elevationM + f.heightM,
            kind: SurfaceKind.slab);
      }
    }

    // 4. Кровля.
    for (final slope in b.roof.slopes) {
      _addPolygon(tris, slope.corners, slope.kind);
    }

    // 5. Пристройки. Гараж — это полноценное помещение со стенами и
    // собственной кровлей. Раньше весь объём гаража закрашивался одним
    // материалом `attachmentDeck` (бежевый), и крыша гаража визуально
    // отсутствовала: пользователь жаловался по правке листа 16.
    // Теперь:
    //   • стены гаража рисуем как `wallExterior` (тот же материал, что
    //     и стены дома);
    //   • верх гаража — отдельная плоскость `roofSlope` (терракотовый
    //     цвет); чтобы крыша была не плоской, поднимаем середину одной
    //     из сторон на ridgeRise (0.4 м);
    //   • Терраса/крыльцо остаются как настил (`attachmentDeck`).
    for (final att in b.attachments) {
      final isGarage = att.typeLabel.toLowerCase().contains('гараж');
      if (!isGarage) {
        _addPrism(
          tris,
          outline: att.outline,
          bottomZ: 0,
          topZ: att.heightM,
          kind: SurfaceKind.attachmentDeck,
        );
        continue;
      }
      // Стены гаража.
      final out = att.outline;
      for (var i = 0; i < out.length; i++) {
        final p0 = out[i];
        final p1 = out[(i + 1) % out.length];
        final a = Vec3(p0.x, p0.y, 0);
        final b1 = Vec3(p1.x, p1.y, 0);
        final c = Vec3(p1.x, p1.y, att.heightM);
        final d = Vec3(p0.x, p0.y, att.heightM);
        tris.add(RenderTri(a, b1, c, SurfaceKind.wallExterior));
        tris.add(RenderTri(a, c, d, SurfaceKind.wallExterior));
      }
      // Кровля гаража — двускатная по короткой стороне. Определяем
      // ось конька как среднюю линию по самой длинной стороне контура.
      // Для прямоугольного контура из 4 углов ставим конёк по середине.
      if (out.length == 4) {
        // Пары сторон 0-1 и 2-3 параллельны.
        final s01 = math.sqrt(math.pow(out[1].x - out[0].x, 2) +
            math.pow(out[1].y - out[0].y, 2));
        final s12 = math.sqrt(math.pow(out[2].x - out[1].x, 2) +
            math.pow(out[2].y - out[1].y, 2));
        const ridgeRise = 0.6; // высота конька над стеной, м
        final ridgeZ = att.heightM + ridgeRise;
        if (s01 >= s12) {
          // Конёк параллелен 0-1 (длинная сторона). Ставим середины
          // сторон 1-2 и 3-0.
          final mid12 = Vec3(
            (out[1].x + out[2].x) / 2,
            (out[1].y + out[2].y) / 2,
            ridgeZ,
          );
          final mid30 = Vec3(
            (out[3].x + out[0].x) / 2,
            (out[3].y + out[0].y) / 2,
            ridgeZ,
          );
          // Скат 1: 0-1 → конёк (mid30 — mid12).
          final p0 = Vec3(out[0].x, out[0].y, att.heightM);
          final p1 = Vec3(out[1].x, out[1].y, att.heightM);
          final p2 = Vec3(out[2].x, out[2].y, att.heightM);
          final p3 = Vec3(out[3].x, out[3].y, att.heightM);
          // Передний скат: p0 → p1 → mid12 → mid30
          _addPolygon(tris, [p0, p1, mid12, mid30], SurfaceKind.roofSlope);
          // Задний скат: p2 → p3 → mid30 → mid12
          _addPolygon(tris, [p2, p3, mid30, mid12], SurfaceKind.roofSlope);
          // Торцы (фронтоны) — закрываем треугольниками.
          tris.add(RenderTri(p1, p2, mid12, SurfaceKind.wallExterior));
          tris.add(RenderTri(p3, p0, mid30, SurfaceKind.wallExterior));
        } else {
          // Конёк по 1-2 / 3-0 (длинные стороны).
          final mid01 = Vec3(
            (out[0].x + out[1].x) / 2,
            (out[0].y + out[1].y) / 2,
            ridgeZ,
          );
          final mid23 = Vec3(
            (out[2].x + out[3].x) / 2,
            (out[2].y + out[3].y) / 2,
            ridgeZ,
          );
          final p0 = Vec3(out[0].x, out[0].y, att.heightM);
          final p1 = Vec3(out[1].x, out[1].y, att.heightM);
          final p2 = Vec3(out[2].x, out[2].y, att.heightM);
          final p3 = Vec3(out[3].x, out[3].y, att.heightM);
          _addPolygon(tris, [p1, p2, mid23, mid01], SurfaceKind.roofSlope);
          _addPolygon(tris, [p3, p0, mid01, mid23], SurfaceKind.roofSlope);
          tris.add(RenderTri(p0, p1, mid01, SurfaceKind.wallExterior));
          tris.add(RenderTri(p2, p3, mid23, SurfaceKind.wallExterior));
        }
      } else {
        // Нестандартный контур — оставляем плоскую крышу.
        final topPolyTris =
            _triangulateConvex(out, att.heightM);
        for (final t in topPolyTris) {
          tris.add(RenderTri(t[0], t[1], t[2], SurfaceKind.roofSlope));
        }
      }
    }

    // v68.11: пост-обработка винда. Для kind-ов, у которых нормаль
    // обязана смотреть «вверх» (скаты кровли, конёк, грунт, верх
    // плиты — но плита одновременно перекрытие, не трогаем), а также
    // кровельных частей пристроек принудительно ставим CCW так, чтобы
    // computed-normal.z был положительным. Это закрывает «прозрачные
    // грани гаража и часть кровли» (Лист 16) — корневая причина была
    // в том, что несколько `_addPolygon`-ов на нестандартных
    // полигонах L/T/U-форм отдавали corners в обратном порядке.
    final canon = <RenderTri>[];
    for (final t in tris) {
      canon.add(_canonicalizeWinding(t));
    }
    return canon;
  }

  /// Если у треугольника заведомо «вверх-смотрящий» kind, а
  /// computed-normal.z < 0 — переставляем (b, c) местами. Это
  /// инвертирует винд и нормаль, не меняя точек.
  static RenderTri _canonicalizeWinding(RenderTri t) {
    bool shouldFaceUp;
    switch (t.kind) {
      case SurfaceKind.roofSlope:
      case SurfaceKind.roofRidge:
      case SurfaceKind.ground:
        shouldFaceUp = true;
        break;
      default:
        shouldFaceUp = false;
    }
    if (!shouldFaceUp) return t;
    final n = t.normal;
    if (n.z < 0) {
      return RenderTri(t.a, t.c, t.b, t.kind,
          wireframeOnly: t.wireframeOnly);
    }
    return t;
  }

  /// Линии-рёбра (конёк, накосы) + контуры стен, проёмов, пристроек,
  /// цоколя — без них на изометрии плоскости сливаются и теряются
  /// детали (стены/окна/двери/гаражи/террасы).
  List<RenderEdge> collectEdges(Building3D b) {
    final edges = <RenderEdge>[];
    // 1. Кровля (конёк, накосы, карниз).
    for (final e in b.roof.edges) {
      edges.add(RenderEdge(e.a, e.b, e.kind, widthPt: 1.2));
    }
    // 2. Контуры этажей: вертикальные углы и горизонтальные пояса
    //   (пол + потолок). Рисуем по периметру наружного контура.
    for (final f in b.floors) {
      // Внешний контур стен этажа собираем из первой стены каждого
      // ортогонального направления — для прямоугольного пятна это
      // 4 угла. Берём общий outline из любого из stenok.
      final corners = _floorOutline(f);
      if (corners.length >= 3) {
        final zBot = f.elevationM;
        final zTop = f.elevationM + f.heightM;
        for (var i = 0; i < corners.length; i++) {
          final c = corners[i];
          final n = corners[(i + 1) % corners.length];
          // Вертикальное ребро угла.
          edges.add(RenderEdge(
            Vec3(c.x, c.y, zBot),
            Vec3(c.x, c.y, zTop),
            SurfaceKind.wallExterior,
            widthPt: 0.7,
          ));
          // Горизонтальная линия по полу/потолку (контур этажа).
          edges.add(RenderEdge(
            Vec3(c.x, c.y, zBot),
            Vec3(n.x, n.y, zBot),
            SurfaceKind.wallExterior,
            widthPt: 0.5,
          ));
          edges.add(RenderEdge(
            Vec3(c.x, c.y, zTop),
            Vec3(n.x, n.y, zTop),
            SurfaceKind.wallExterior,
            widthPt: 0.5,
          ));
        }
      }
      // 3. Контуры проёмов: четырёхугольник для каждого окна и
      //   наружной двери — становятся хорошо видимыми поверх стены.
      for (final w in f.walls) {
        for (final op in w.openings) {
          final uStart = op.offsetAlong;
          final uEnd = op.offsetAlong + op.width;
          final zBot = f.elevationM + op.bottom;
          final zTop = zBot + op.height;
          final p1 = _wallPoint(w, uStart, zBot);
          final p2 = _wallPoint(w, uEnd, zBot);
          final p3 = _wallPoint(w, uEnd, zTop);
          final p4 = _wallPoint(w, uStart, zTop);
          const k = SurfaceKind.wallExterior;
          edges.add(RenderEdge(p1, p2, k, widthPt: 0.6));
          edges.add(RenderEdge(p2, p3, k, widthPt: 0.6));
          edges.add(RenderEdge(p3, p4, k, widthPt: 0.6));
          edges.add(RenderEdge(p4, p1, k, widthPt: 0.6));
        }
      }
    }
    // 4. Пристройки (гараж/терраса/крыльцо) — контуры их объёма.
    for (final att in b.attachments) {
      final out = att.outline;
      if (out.length < 3) continue;
      for (var i = 0; i < out.length; i++) {
        final c = out[i];
        final n = out[(i + 1) % out.length];
        edges.add(RenderEdge(
          Vec3(c.x, c.y, 0),
          Vec3(c.x, c.y, att.heightM),
          SurfaceKind.attachmentDeck,
          widthPt: 0.7,
        ));
        edges.add(RenderEdge(
          Vec3(c.x, c.y, 0),
          Vec3(n.x, n.y, 0),
          SurfaceKind.attachmentDeck,
          widthPt: 0.5,
        ));
        edges.add(RenderEdge(
          Vec3(c.x, c.y, att.heightM),
          Vec3(n.x, n.y, att.heightM),
          SurfaceKind.attachmentDeck,
          widthPt: 0.7,
        ));
      }
    }
    // 5. Цоколь — линия по верху цоколя (отметка 0 → +plinthHeight).
    if (b.foundation.plinthHeightM > 0 && b.foundation.outline.length >= 3) {
      final out = b.foundation.outline;
      for (var i = 0; i < out.length; i++) {
        final c = out[i];
        final n = out[(i + 1) % out.length];
        edges.add(RenderEdge(
          Vec3(c.x, c.y, b.foundation.plinthHeightM),
          Vec3(n.x, n.y, b.foundation.plinthHeightM),
          SurfaceKind.foundationPlinth,
          widthPt: 0.6,
        ));
      }
    }
    return edges;
  }

  /// Собирает плоскую цепочку точек по периметру стен этажа. Для
  /// прямоугольного пятна возвращает 4 угла; для произвольного
  /// контура — все уникальные начала и концы стен.
  List<Vec3> _floorOutline(Floor3D f) {
    if (f.walls.isEmpty) return const [];
    final pts = <Vec3>[];
    for (final w in f.walls) {
      pts.add(Vec3(w.start.x, w.start.y, 0));
    }
    return pts;
  }

  /// Точка в плоскости стены [w] с координатой [u] вдоль стены и [z]
  /// по вертикали.
  Vec3 _wallPoint(Wall3D w, double u, double z) {
    final dx = w.end.x - w.start.x;
    final dy = w.end.y - w.start.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return Vec3(w.start.x, w.start.y, z);
    final t = (u / len).clamp(0.0, 1.0);
    return Vec3(
      w.start.x + dx * t,
      w.start.y + dy * t,
      z,
    );
  }

  /// Проецирует точку через камеру на 2D.
  Projected2D project(Vec3 p, Camera3D camera, double width, double height) {
    // 1. Перевод в координаты камеры (target в начало, поворот yaw, потом pitch).
    final t = p - camera.target;
    final cy = math.cos(camera.yaw);
    final sy = math.sin(camera.yaw);
    final x1 = t.x * cy - t.y * sy;
    final y1 = t.x * sy + t.y * cy;
    final z1 = t.z;
    final cp = math.cos(camera.pitch);
    final sp = math.sin(camera.pitch);
    final y2 = y1 * cp - z1 * sp;
    final z2 = y1 * sp + z1 * cp;
    // y2 = depth (вглубь), x1 = horizontal, z2 = vertical (up).
    if (camera.orthographic) {
      // Простая ортогональная: x' = x1, y' = -z2 (экран Y вниз), depth = y2.
      // Масштаб подбирается потом во внешнем коде.
      return Projected2D(x1, -z2, y2);
    } else {
      // Перспективная.
      final d = camera.distance + y2;
      if (d <= 0.01) return Projected2D(x1, -z2, y2);
      final f = camera.distance / d;
      return Projected2D(x1 * f, -z2 * f, y2);
    }
  }

  // -- helpers ------------------------------------------------------------

  void _addPrism(
    List<RenderTri> tris, {
    required List<Vec3> outline,
    required double bottomZ,
    required double topZ,
    required SurfaceKind kind,
  }) {
    if (outline.length < 3) return;
    // Боковые стенки.
    for (var i = 0; i < outline.length; i++) {
      final p0 = outline[i];
      final p1 = outline[(i + 1) % outline.length];
      final a = Vec3(p0.x, p0.y, bottomZ);
      final b = Vec3(p1.x, p1.y, bottomZ);
      final c = Vec3(p1.x, p1.y, topZ);
      final d = Vec3(p0.x, p0.y, topZ);
      tris.add(RenderTri(a, b, c, kind));
      tris.add(RenderTri(a, c, d, kind));
    }
    // Верхняя крышка (если topZ выше bottomZ — она видна сверху).
    final topPolyTris = _triangulateConvex(outline, topZ);
    for (final t in topPolyTris) {
      tris.add(RenderTri(t[0], t[1], t[2], kind));
    }
    // Низ: опускаем (обычно в землю или закрыт другими гранями).
  }

  void _addSlab(List<RenderTri> tris, Slab3D slab,
      {required double zTop, required SurfaceKind kind}) {
    final outline = slab.outline;
    final zBot = zTop - slab.thicknessM;
    _addPrism(tris,
        outline: outline,
        bottomZ: zBot,
        topZ: zTop,
        kind: kind);
  }

  void _addPolygon(
      List<RenderTri> tris, List<Vec3> corners, SurfaceKind kind) {
    if (corners.length < 3) return;
    // Триангуляция fan.
    for (var i = 1; i < corners.length - 1; i++) {
      tris.add(RenderTri(corners[0], corners[i], corners[i + 1], kind));
    }
  }

  List<List<Vec3>> _triangulateConvex(List<Vec3> outline, double z) {
    final result = <List<Vec3>>[];
    for (var i = 1; i < outline.length - 1; i++) {
      result.add([
        Vec3(outline[0].x, outline[0].y, z),
        Vec3(outline[i].x, outline[i].y, z),
        Vec3(outline[i + 1].x, outline[i + 1].y, z),
      ]);
    }
    return result;
  }

  /// Триангулирует стену с прорезями под проёмы.
  ///
  /// Алгоритм: разбиваем стену по горизонтальным «лентам»
  /// (низ-под-проёмами / зона проёмов / верх-над-проёмами / справа/слева
  /// от проёмов). Это простой подход для прямоугольной стены с
  /// прямоугольными проёмами.
  void _tessellateWall(List<RenderTri> tris, Wall3D w, double floorElevation) {
    final start = w.start;
    final end = w.end;
    final L = w.length;
    if (L == 0) return;
    final dx = (end.x - start.x) / L;
    final dy = (end.y - start.y) / L;
    final z0 = floorElevation;
    final z1 = floorElevation + w.height;

    // Точка на стене (offset вдоль) → 3D.
    Vec3 wallPoint(double off, double z) =>
        Vec3(start.x + dx * off, start.y + dy * off, z);

    // Если нет проёмов — два треугольника.
    // Winding: CCW при взгляде СНАРУЖИ. Это нужно для строгого
    // back-face culling по 2D-cross в `Building3DRenderer.cull2D`
    // и для того, чтобы computed normal совпадал с
    // `Wall3D.outwardNormal` (используется при шейдинге).
    if (w.openings.isEmpty) {
      final a = wallPoint(0, z0);
      final b = wallPoint(L, z0);
      final c = wallPoint(L, z1);
      final d = wallPoint(0, z1);
      tris.add(RenderTri(a, c, b, w.kind));
      tris.add(RenderTri(a, d, c, w.kind));
      return;
    }

    // Сортируем проёмы по offset.
    final ops = [...w.openings]..sort((x, y) => x.offsetAlong.compareTo(y.offsetAlong));
    var cursor = 0.0;
    for (final op in ops) {
      // Полоса слева от проёма (всё высота стены).
      if (op.offsetAlong > cursor) {
        _addQuad(tris,
            wallPoint(cursor, z0),
            wallPoint(op.offsetAlong, z0),
            wallPoint(op.offsetAlong, z1),
            wallPoint(cursor, z1),
            w.kind);
      }
      // Полоска снизу проёма.
      if (op.bottom > 0) {
        _addQuad(tris,
            wallPoint(op.offsetAlong, z0),
            wallPoint(op.offsetAlong + op.width, z0),
            wallPoint(op.offsetAlong + op.width, z0 + op.bottom),
            wallPoint(op.offsetAlong, z0 + op.bottom),
            w.kind);
      }
      // Сам проём — рисуем как полупрозрачное стекло / тёмное полотно.
      final glazingKind = op.kind == OpeningKind3D.door
          ? SurfaceKind.door
          : SurfaceKind.glazing;
      _addQuad(tris,
          wallPoint(op.offsetAlong, z0 + op.bottom),
          wallPoint(op.offsetAlong + op.width, z0 + op.bottom),
          wallPoint(op.offsetAlong + op.width, z0 + op.bottom + op.height),
          wallPoint(op.offsetAlong, z0 + op.bottom + op.height),
          glazingKind);
      // Полоска сверху проёма.
      final topOfOpening = z0 + op.bottom + op.height;
      if (topOfOpening < z1) {
        _addQuad(tris,
            wallPoint(op.offsetAlong, topOfOpening),
            wallPoint(op.offsetAlong + op.width, topOfOpening),
            wallPoint(op.offsetAlong + op.width, z1),
            wallPoint(op.offsetAlong, z1),
            w.kind);
      }
      cursor = op.offsetAlong + op.width;
    }
    // Полоса справа от последнего проёма.
    if (cursor < L) {
      _addQuad(tris,
          wallPoint(cursor, z0),
          wallPoint(L, z0),
          wallPoint(L, z1),
          wallPoint(cursor, z1),
          w.kind);
    }
  }

  /// Добавляет 4-угольник как два треугольника. Параметры [a..d] — углы
  /// в порядке BL → BR → TR → TL (как они идут на стене). Для CCW
  /// при взгляде СНАРУЖИ результат — (a, c, b) и (a, d, c).
  void _addQuad(List<RenderTri> tris, Vec3 a, Vec3 b, Vec3 c, Vec3 d,
      SurfaceKind kind) {
    tris.add(RenderTri(a, c, b, kind));
    tris.add(RenderTri(a, d, c, kind));
  }
}
