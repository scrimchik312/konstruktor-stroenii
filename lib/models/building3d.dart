/// 3D-модель здания, собранная из реальных параметров [HouseProject].
///
/// Никаких текстур / материалов в виде ассетов — только геометрия и
/// «семантические» цвета (стены, кровля, фундамент, проёмы), которые
/// рендерер интерпретирует сам.
///
/// Координаты в метрах. Ось Z направлена вверх (вверх — потолок, низ —
/// фундамент). Ось Y направлена «в глубину» здания, X — по фронту.
/// Точка (0, 0, 0) — юго-западный угол пятна на уровне ±0.000.
library;

import 'dart:math' as math;

class Vec3 {
  final double x;
  final double y;
  final double z;
  const Vec3(this.x, this.y, this.z);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );
  double get length => math.sqrt(x * x + y * y + z * z);
  Vec3 get normalized {
    final l = length;
    if (l == 0) return const Vec3(0, 0, 0);
    return Vec3(x / l, y / l, z / l);
  }

  @override
  String toString() =>
      'Vec3(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, '
      '${z.toStringAsFixed(2)})';
}

/// Семантический «слой материала» для окраски граней рендерером.
enum SurfaceKind {
  /// Подземная часть фундамента (тёмно-серый).
  foundationUnderground,

  /// Цокольная часть (видимая часть фундамента над землёй).
  foundationPlinth,

  /// Внешняя стена (цвет зависит от материала стен).
  wallExterior,

  /// Внутренняя сторона стены (для разрезов, в общем виде не видна).
  wallInterior,

  /// Перекрытие (тёмная плоскость, видна сверху на разрезе).
  slab,

  /// Стекло окна (полупрозрачный синий).
  glazing,

  /// Дверное полотно (тёмное дерево).
  door,

  /// Скат кровли.
  roofSlope,

  /// Конёк / накос — линия (рендерер не рисует фейс, только ребро).
  roofRidge,

  /// Терраса / крыльцо — настил.
  attachmentDeck,

  /// Земля (горизонтальная плоскость под зданием).
  ground,
}

/// Один треугольник — базовая единица рендеринга.
///
/// Хранит только индексы вершин в общем буфере [Building3D.vertices] для
/// экономии памяти и единообразного z-sort.
class Tri {
  final int a;
  final int b;
  final int c;
  final SurfaceKind kind;

  /// Если true, рендерер не отрисовывает заливку, только рёбра.
  /// Полезно для линий конька/накосов, без объёма.
  final bool wireframeOnly;

  const Tri(this.a, this.b, this.c, this.kind, {this.wireframeOnly = false});
}

/// Стена со списком прямоугольных вырезов под проёмы. Хранится отдельно
/// от треугольников: рендерер сам триангулирует стену, вычитая проёмы.
class Wall3D {
  /// Точка-старт стены в плане (нижний угол начала).
  final Vec3 start;

  /// Точка-конец стены в плане (нижний угол конца).
  final Vec3 end;

  /// Высота стены, м.
  final double height;

  /// Толщина стены, м (для будущей экструзии — в текущей итерации
  /// рисуется как нулевой толщины плоскость).
  final double thickness;

  /// Куда смотрит «внешняя» нормаль (нужна для отбора обращённых
  /// к камере граней). Рассчитывается от направления start→end по
  /// правилу правой руки (CCW, vertical up).
  final Vec3 outwardNormal;

  /// Проёмы на этой стене (window/door), координаты — вдоль стены.
  final List<Opening3D> openings;

  /// Семантический материал стены.
  final SurfaceKind kind;

  const Wall3D({
    required this.start,
    required this.end,
    required this.height,
    required this.thickness,
    required this.outwardNormal,
    required this.openings,
    this.kind = SurfaceKind.wallExterior,
  });

  /// Длина стены в плане.
  double get length {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// Прямоугольный вырез на стене (окно или дверь).
class Opening3D {
  /// Расстояние от [Wall3D.start] вдоль стены до левого края проёма, м.
  final double offsetAlong;

  /// Высота низа проёма от низа стены, м (для двери = 0, для окна
  /// обычно 0.9 м).
  final double bottom;

  /// Ширина проёма, м.
  final double width;

  /// Высота проёма, м.
  final double height;

  /// Тип проёма — определяет визуализацию (стекло / дверь / открытый
  /// проход).
  final OpeningKind3D kind;

  const Opening3D({
    required this.offsetAlong,
    required this.bottom,
    required this.width,
    required this.height,
    required this.kind,
  });
}

enum OpeningKind3D { window, door, archway }

/// Скат кровли — четырёхугольник или треугольник с произвольным наклоном.
class RoofSlope3D {
  /// Угловые точки ската (CCW при взгляде снаружи).
  final List<Vec3> corners;

  /// Семантика — обычная скатная грань.
  final SurfaceKind kind;

  const RoofSlope3D({
    required this.corners,
    this.kind = SurfaceKind.roofSlope,
  });
}

/// Линия конька / накоса / карниза (рисуется как линия, без заливки).
class RoofEdge3D {
  final Vec3 a;
  final Vec3 b;
  final SurfaceKind kind;
  const RoofEdge3D(this.a, this.b, {this.kind = SurfaceKind.roofRidge});
}

/// Сегмент перекрытия / плиты на отметке.
class Slab3D {
  /// Контур плиты в плане (точки замкнутого многоугольника CCW сверху).
  final List<Vec3> outline;

  /// Толщина плиты, м (от верха книзу).
  final double thicknessM;

  /// Семантика.
  final SurfaceKind kind;

  const Slab3D({
    required this.outline,
    required this.thicknessM,
    this.kind = SurfaceKind.slab,
  });
}

/// Уровень / этаж — собирает стены, перекрытие.
class Floor3D {
  /// Отметка верха перекрытия этого уровня (отметка пола следующего
  /// этажа), м.
  final double elevationM;

  /// Высота этажа в свету, м.
  final double heightM;

  /// Стены этажа.
  final List<Wall3D> walls;

  /// Перекрытие над этажом (опционально — для верхнего этажа отсутствует,
  /// если кровля без чердака).
  final Slab3D? ceilingSlab;

  /// Лейбл этажа («1 этаж», «Мансарда» и т. п.).
  final String label;

  const Floor3D({
    required this.elevationM,
    required this.heightM,
    required this.walls,
    required this.label,
    this.ceilingSlab,
  });
}

/// Фундамент в 3D — параллелепипед или плита.
class Foundation3D {
  /// Контур пятна фундамента в плане (CCW сверху).
  final List<Vec3> outline;

  /// Глубина заложения от уровня земли, м (положительное число).
  final double depthM;

  /// Высота цокольной части над землёй, м (обычно 0.3…0.6 для ленты,
  /// 0.1 для плиты).
  final double plinthHeightM;

  /// Тип в человекочитаемом виде («Ленточный фундамент»).
  final String typeLabel;

  const Foundation3D({
    required this.outline,
    required this.depthM,
    required this.plinthHeightM,
    required this.typeLabel,
  });
}

/// Кровля в 3D — несколько скатов + рёбра (конёк/накосы/карниз).
class Roof3D {
  final List<RoofSlope3D> slopes;
  final List<RoofEdge3D> edges;

  /// Тип (плоская / двускатная / вальмовая / односкатная).
  final String typeLabel;

  /// Угол ската, °.
  final double slopeDegrees;

  const Roof3D({
    required this.slopes,
    required this.edges,
    required this.typeLabel,
    required this.slopeDegrees,
  });
}

/// Пристройка (крыльцо / терраса) — простой блок.
class Attachment3D {
  /// Контур настила в плане (CCW сверху).
  final List<Vec3> outline;

  /// Высота настила над землёй, м.
  final double heightM;

  /// Тип («Крыльцо» / «Терраса»).
  final String typeLabel;

  const Attachment3D({
    required this.outline,
    required this.heightM,
    required this.typeLabel,
  });
}

/// Главный агрегат — здание целиком.
class Building3D {
  /// Имя проекта (для подписи в чертеже).
  final String projectName;

  /// Габариты пятна, м (для подбора масштаба и центра камеры).
  final double footprintWidth;
  final double footprintLength;

  /// Полная высота от низа фундамента до конька, м.
  final double totalHeight;

  final Foundation3D foundation;
  final List<Floor3D> floors;
  final Roof3D roof;
  final List<Attachment3D> attachments;

  /// Имя материала стен (см. WallMaterial.name) — для подбора текстуры
  /// при рендеринге аксонометрии и фасадов. Может быть null для старых
  /// проектов; рендерер тогда использует материал по умолчанию.
  final String? wallMaterialName;

  /// Идентификатор кровельного материала (см. roof_page _RoofingOption.id).
  final String? roofMaterialId;

  const Building3D({
    required this.projectName,
    required this.footprintWidth,
    required this.footprintLength,
    required this.totalHeight,
    required this.foundation,
    required this.floors,
    required this.roof,
    required this.attachments,
    this.wallMaterialName,
    this.roofMaterialId,
  });

  /// Геометрический центр здания в плане + по высоте середина — для
  /// центровки камеры orbit-режима.
  Vec3 get center {
    final cz = totalHeight / 2 - foundation.depthM;
    return Vec3(footprintWidth / 2, footprintLength / 2, cz);
  }
}
