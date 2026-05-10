/// Интерактивный 3D-вид [Building3D] на Flutter Canvas.
///
/// Драг — orbit (yaw + pitch), pinch / scroll wheel — zoom. Алгоритм
/// рендеринга — общий [Building3DRenderer] (живёт в services), здесь
/// только адаптер от [PaintingContext] к колбекам рендерера.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/material_textures.dart';
import '../data/wall_materials.dart';
import '../models/building3d.dart';
import '../services/building3d_renderer.dart';

/// Пресет окружения / времени года, влияющий на цвет неба, цвет
/// освещения, наличие снега на скатах и трав/листвы вокруг.
enum WeatherMode {
  summer, // ясный летний день, зелёная трава
  winter, // зимний день, снег на крышах и земле
  night, // ночь, тёмно-синее небо, дим освещение
}

class Building3DView extends StatefulWidget {
  const Building3DView({
    super.key,
    required this.model,
    this.aspectRatio = 1.5,
    this.initialYawDegrees = 35,
    this.initialPitchDegrees = 25,
    this.initialWeather = WeatherMode.summer,
  });

  final Building3D model;
  final double aspectRatio;
  final double initialYawDegrees;
  final double initialPitchDegrees;
  final WeatherMode initialWeather;

  @override
  State<Building3DView> createState() => _Building3DViewState();
}

/// Состояние камеры. Текстуры теперь локальны к стене/скату
/// (UV-mapping в мировых координатах), их рендеринг стабилен по
/// производительности независимо от ракурса, поэтому fastMode
/// больше не нужен — текстуры остаются видимыми и при вращении.
class _CameraState {
  const _CameraState({
    required this.yaw,
    required this.pitch,
    required this.zoom,
  });
  final double yaw;
  final double pitch;
  final double zoom;

  _CameraState copyWith({
    double? yaw,
    double? pitch,
    double? zoom,
  }) =>
      _CameraState(
        yaw: yaw ?? this.yaw,
        pitch: pitch ?? this.pitch,
        zoom: zoom ?? this.zoom,
      );
}

class _Building3DViewState extends State<Building3DView> {
  late ValueNotifier<_CameraState> _camera;
  // Кэш палитры — пересоздаём только при смене модели стен/кровли,
  // а не на каждый кадр.
  late SurfacePalette _palette;
  // Кэш tessellation — самый дорогой шаг (~10 мс на сложной модели);
  // делаем 1 раз на модель и переиспользуем при перерисовках.
  List<RenderTri>? _trisCache;
  Object? _trisCacheKey;

  // Пресет окружения. Изменяется через toggle в верхне-правом углу
  // (Стадия 4): Лето / Зима / Ночь. Влияет на цвет неба, траву/снег,
  // листву на деревьях, яркость здания, светящиеся окна.
  late WeatherMode _weather;

  @override
  void initState() {
    super.initState();
    _camera = ValueNotifier(_CameraState(
      yaw: widget.initialYawDegrees * math.pi / 180,
      pitch: widget.initialPitchDegrees * math.pi / 180,
      zoom: 1.0,
    ));
    _palette = _paletteFromModel(widget.model);
    _weather = widget.initialWeather;
  }

  void _setWeather(WeatherMode w) {
    if (_weather == w) return;
    setState(() {
      _weather = w;
    });
  }

  @override
  void didUpdateWidget(covariant Building3DView old) {
    super.didUpdateWidget(old);
    if (!identical(old.model, widget.model)) {
      // Модель сменилась — палитра и кэш геометрии устарели.
      _palette = _paletteFromModel(widget.model);
      _trisCache = null;
      _trisCacheKey = null;
    }
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final c = _camera.value;
    final ny = c.yaw + d.delta.dx * 0.01;
    final np = (c.pitch - d.delta.dy * 0.01)
        .clamp(-math.pi / 2 + 0.05, math.pi / 2 - 0.05);
    _camera.value = c.copyWith(yaw: ny, pitch: np);
  }

  void _onScroll(PointerScrollEvent ev) {
    final c = _camera.value;
    final factor = math.exp(-ev.scrollDelta.dy * 0.001);
    _camera.value = c.copyWith(zoom: (c.zoom * factor).clamp(0.3, 5.0));
  }

  /// Возвращает кэшированный список треугольников для текущей модели
  /// (пересчитывается только при её смене).
  List<RenderTri> _trisFor(Building3DRenderer renderer) {
    final key = widget.model;
    if (identical(_trisCacheKey, key) && _trisCache != null) {
      return _trisCache!;
    }
    _trisCache = renderer.tessellate(widget.model);
    _trisCacheKey = key;
    return _trisCache!;
  }

  Widget _buildWeatherToggle() {
    final theme = Theme.of(context);
    Widget seg(WeatherMode m, IconData icon, String label) {
      final selected = _weather == m;
      return InkWell(
        onTap: () => _setWeather(m),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withOpacity(0.85)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: selected ? Colors.white : Colors.black87),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    color: selected ? Colors.white : Colors.black87,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w500,
                  )),
            ],
          ),
        ),
      );
    }

    return Material(
      elevation: 2,
      color: Colors.white.withOpacity(0.92),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            seg(WeatherMode.summer, Icons.wb_sunny_outlined, 'Лето'),
            seg(WeatherMode.winter, Icons.ac_unit, 'Зима'),
            seg(WeatherMode.night, Icons.nightlight_outlined, 'Ночь'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary изолирует слой 3D от остального дерева — родитель
    // не перерисовывается при вращении камеры.
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Listener(
          onPointerSignal: (sig) {
            if (sig is PointerScrollEvent) _onScroll(sig);
          },
          child: GestureDetector(
            onPanUpdate: _onPanUpdate,
            child: ClipRect(
              child: Stack(
                children: [
                  CustomPaint(
                    // Главное: репеинт только когда меняется камера
                    // (через ValueNotifier). Никаких setState/build.
                    painter: _Building3DPainter(
                      model: widget.model,
                      cameraNotifier: _camera,
                      palette: _palette,
                      trisProvider: _trisFor,
                      weather: _weather,
                    ),
                    child: const SizedBox.expand(),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _buildWeatherToggle(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Building3DPainter extends CustomPainter {
  _Building3DPainter({
    required this.model,
    required this.cameraNotifier,
    required this.palette,
    required this.trisProvider,
    required this.weather,
  }) : super(repaint: cameraNotifier);

  final Building3D model;
  final ValueNotifier<_CameraState> cameraNotifier;
  final SurfacePalette palette;
  final List<RenderTri> Function(Building3DRenderer) trisProvider;
  final WeatherMode weather;

  double get yaw => cameraNotifier.value.yaw;
  double get pitch => cameraNotifier.value.pitch;
  double get zoom => cameraNotifier.value.zoom;

  @override
  void paint(Canvas canvas, Size size) {
    // Фон — небо, в зависимости от пресета погоды.
    final List<Color> skyColors;
    final List<double> skyStops;
    switch (weather) {
      case WeatherMode.summer:
        skyColors = const [
          Color(0xFF7FB0D9), // насыщенно-голубой зенит
          Color(0xFFB7D5E8), // светлый горизонт
          Color(0xFFE3EBEE), // лёгкая дымка у самой земли
        ];
        skyStops = const [0.0, 0.65, 1.0];
        break;
      case WeatherMode.winter:
        skyColors = const [
          Color(0xFFB6BFC9), // серо-голубой пасмурный зенит
          Color(0xFFD3D9DD),
          Color(0xFFE6E9EB), // почти белый горизонт
        ];
        skyStops = const [0.0, 0.55, 1.0];
        break;
      case WeatherMode.night:
        skyColors = const [
          Color(0xFF06101F), // почти чёрно-синий зенит
          Color(0xFF1A2A45), // ночное небо
          Color(0xFF34466A), // подсветка горизонта (городские огни)
        ];
        skyStops = const [0.0, 0.6, 1.0];
        break;
    }
    final skyShader = ui.Gradient.linear(
      Offset.zero,
      Offset(0, size.height),
      skyColors,
      skyStops,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = skyShader,
    );

    // Ночь: луна + звёзды. Рисуется до всего остального.
    if (weather == WeatherMode.night) {
      // Звёзды (40 штук) — белые точки в верхней половине.
      final starPaint = Paint()
        ..color = const Color(0xFFFFFFEE)
        ..isAntiAlias = true;
      for (var i = 0; i < 40; i++) {
        final h = (i * 73856093) & 0x7FFFFFFF;
        final sx = (h & 0xFFF) / 0xFFF * size.width;
        final sy =
            ((h >> 12) & 0xFFF) / 0xFFF * size.height * 0.55;
        final r = 0.4 + ((h >> 24) & 0x3) * 0.4;
        starPaint.color = Color.fromRGBO(
            255, 255, 230, 0.5 + ((h >> 20) & 0xF) / 30.0);
        canvas.drawCircle(Offset(sx, sy), r, starPaint);
      }
      // Луна — крупный кружок с гало.
      final moonCenter = Offset(size.width * 0.82, size.height * 0.18);
      canvas.drawCircle(
        moonCenter,
        38,
        Paint()
          ..color = const Color(0x55FFFCDD)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
      canvas.drawCircle(
        moonCenter,
        18,
        Paint()
          ..color = const Color(0xFFF6F2D6)
          ..isAntiAlias = true,
      );
      // Полутень кратера (имитация терминатора).
      canvas.drawCircle(
        moonCenter + const Offset(5, 0),
        17.5,
        Paint()
          ..color = const Color(0x33000000)
          ..isAntiAlias = true
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }

    final renderer = Building3DRenderer(palette: palette);
    // Главная оптимизация: tessellation кэшируется на стороне State —
    // здесь мы только запрашиваем уже готовый список треугольников.
    final tris = trisProvider(renderer);

    final camera = Camera3D(
      target: model.center,
      yaw: yaw,
      pitch: pitch,
      distance: 100,
      orthographic: true,
    );

    // Проецируем все треугольники и отсекаем «изнаночные» грани по
    // 2D-cross в координатах проекции. Геометрия триангулируется в
    // [Building3DRenderer] так, что лицевая сторона всегда CCW при
    // взгляде снаружи — поэтому строгий cull (cross >= 0 → пропустить)
    // надёжно убирает заднюю стену здания. Это и есть та самая
    // непрозрачность, которой не хватало: теперь тыльная стена/скат
    // не «пробивает» переднюю.
    final visible = <_ProjTri>[];
    for (final t in tris) {
      final pa = renderer.project(t.a, camera, size.width, size.height);
      final pb = renderer.project(t.b, camera, size.width, size.height);
      final pc = renderer.project(t.c, camera, size.width, size.height);
      // Земля и слэбы — горизонтальные плоскости. Сверху/снизу их
      // нормаль может «уйти» от камеры при сильном тилте — поэтому
      // back-face cull для них не применяем.
      final isHorizontal = t.kind == SurfaceKind.ground ||
          t.kind == SurfaceKind.slab;
      if (!isHorizontal) {
        // В Projected2D ось y направлена ВНИЗ (projected.y = -z_world).
        // В Y-down системе CCW-в-3D-снаружи проектируется как CW на
        // экране → отрицательный 2D-cross. То есть лицевая грань
        // имеет cross < 0, изнаночная — cross >= 0.
        final cross = (pb.x - pa.x) * (pc.y - pa.y) -
            (pb.y - pa.y) * (pc.x - pa.x);
        if (cross >= 0) continue; // back-face — пропускаем
      }
      visible.add(_ProjTri(pa, pb, pc, t));
    }
    // Сортировка painter's algorithm: дальние грани первыми, ближние
    // поверх. Используем средний z (avg) для устойчивости — на max
    // тонкие стены/слэбы могут «прыгать» между передним и задним планами.
    // v68.11: при близкой глубине (Δ < 0.05 м) — добавляем разрыв по
    // [layerOrder] (стены < окна < скаты < конёк), чтобы coplanar-
    // грани не мерцали при вращении.
    visible.sort((a, b) {
      final dz = b.avgDepth - a.avgDepth;
      if (dz.abs() > 0.05) return dz.compareTo(0);
      return a.tri.layerOrder.compareTo(b.tri.layerOrder);
    });

    // Подбор масштаба по габаритам сцены.
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final p in visible) {
      for (final pt in [p.a, p.b, p.c]) {
        if (pt.x < minX) minX = pt.x;
        if (pt.x > maxX) maxX = pt.x;
        if (pt.y < minY) minY = pt.y;
        if (pt.y > maxY) maxY = pt.y;
      }
    }
    if (minX == double.infinity) return;
    final boundsW = (maxX - minX).abs();
    final boundsH = (maxY - minY).abs();
    if (boundsW == 0 || boundsH == 0) return;

    const margin = 24.0;
    final scaleX = (size.width - margin * 2) / boundsW;
    final scaleY = (size.height - margin * 2) / boundsH;
    final base = math.min(scaleX, scaleY);
    final scale = base * zoom;
    final cx = (size.width) / 2;
    final cy = (size.height) / 2;
    final mid = ui.Offset((minX + maxX) / 2, (minY + maxY) / 2);

    ui.Offset toScreen(Projected2D p) =>
        ui.Offset(cx + (p.x - mid.dx) * scale, cy + (p.y - mid.dy) * scale);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      // anti-aliasing уменьшает «исчезновение» граней по диагонали.
      ..isAntiAlias = true;
    // v68.11: тонкая обводка треугольника тем же цветом, что и
    // заливка. Закрывает суб-пиксельные щели между соседними
    // треугольниками одного quad-а (стена/скат разрезаны диагональю
    // на 2 тр-ка) — раньше эти щели читались как «полупрозрачные
    // полосы» при анти-алиасинге.
    final selfEdgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..isAntiAlias = true;
    // Контуры объектов рисуются ниже отдельным слоем (через
    // [collectEdges]) с проверкой на загораживание, поэтому
    // обводка каждого треугольника здесь не нужна.

    // Стадия 1+4: детализированное окружение — земля/трава или снег
    // (зимой), приглушённая трава (ночью). Передаём пресет, чтобы
    // ground env мог сменить палитру.
    _paintGroundEnvironment(canvas, model, renderer, camera, size, toScreen,
        weather: weather);

    // Сначала — мягкая тень под зданием (эллиптическая «виньетка»).
    // Рисуется поверх земли, но под всеми объёмными гранями.
    _paintGroundShadow(canvas, model, camera, size, toScreen);

    // Стадия 2: деревья. Генерируем процедурно (~5–8 шт.) вокруг
    // здания и разделяем на «задние» (рисуются ПЕРЕД зданием —
    // здание перекрывает) и «передние» (рисуются ПОСЛЕ здания).
    // Для определения порядка используется глубина проекции на
    // камеру.
    final trees = _generateTrees(model);
    final buildingDepth =
        renderer.project(model.center, camera, size.width, size.height).z;
    final treesBehind = <_TreeData>[];
    final treesFront = <_TreeData>[];
    for (final t in trees) {
      final p = renderer.project(
          Vec3(t.x, t.y, 0), camera, size.width, size.height);
      if (p.z > buildingDepth) {
        treesBehind.add(t);
      } else {
        treesFront.add(t);
      }
    }
    if (treesBehind.isNotEmpty) {
      _paintTrees(canvas, model, renderer, camera, size, toScreen,
          trees: treesBehind, weather: weather);
    }

    // Стадия 3: забор-штакетник по периметру участка. Делится на
    // «задние» элементы (перекрываются зданием) и «передние»
    // (рисуются после здания и перекрывают его). Список сегментов
    // считается один раз, сортировка back→front внутри каждой группы.
    final fenceSegments = _generateFence(model);
    final fenceBehind = <_FenceSegment>[];
    final fenceFront = <_FenceSegment>[];
    for (final seg in fenceSegments) {
      final p = renderer.project(
          Vec3(seg.x, seg.y, 0), camera, size.width, size.height);
      seg.depth = p.z;
      if (p.z > buildingDepth) {
        fenceBehind.add(seg);
      } else {
        fenceFront.add(seg);
      }
    }
    if (fenceBehind.isNotEmpty) {
      _paintFence(canvas, model, renderer, camera, size, toScreen,
          segments: fenceBehind);
    }

    // Заливка стен/кровли — С ОБЯЗАТЕЛЬНОЙ непрозрачностью.
    // (правило пользователя: стены никогда не должны становиться прозрачными)
    final wm = WallMaterial.fromName(model.wallMaterialName);
    final wallTex = MaterialTextureLibrary.wall(wm);
    final roofTex = MaterialTextureLibrary.roof(model.roofMaterialId);
    for (final p in visible) {
      if (p.tri.wireframeOnly) continue;
      final base = palette.colorOf(p.tri.kind);
      final shaded = palette.shadeFace(base, p.tri.normal);
      // Применяем модуляцию пресета погоды к итоговому цвету грани:
      //   summer — без изменений;
      //   winter — десатурация + лёгкий cool-shift;
      //   night  — резкое затемнение + холодный синий тинт; окна
      //            (glazing) светятся тёплым жёлтым.
      double rOut = shaded.r, gOut = shaded.g, bOut = shaded.b;
      if (weather == WeatherMode.winter) {
        final avg = (rOut + gOut + bOut) / 3;
        rOut = (rOut * 0.85 + avg * 0.15 - 0.02).clamp(0.0, 1.0);
        gOut = (gOut * 0.85 + avg * 0.15).clamp(0.0, 1.0);
        bOut = (bOut * 0.85 + avg * 0.15 + 0.05).clamp(0.0, 1.0);
      } else if (weather == WeatherMode.night) {
        if (p.tri.kind == SurfaceKind.glazing) {
          // v68.11: hash по bbox окна, а не по `tri.a` — чтобы обе
          // половинки одного проёма (BL+TR+BR и BL+TL+TR) получили
          // одинаковое решение «свет/тьма».
          final wxMin =
              math.min(p.tri.a.x, math.min(p.tri.b.x, p.tri.c.x));
          final wxMax =
              math.max(p.tri.a.x, math.max(p.tri.b.x, p.tri.c.x));
          final wyMin =
              math.min(p.tri.a.y, math.min(p.tri.b.y, p.tri.c.y));
          final wyMax =
              math.max(p.tri.a.y, math.max(p.tri.b.y, p.tri.c.y));
          final wzMin =
              math.min(p.tri.a.z, math.min(p.tri.b.z, p.tri.c.z));
          final wzMax =
              math.max(p.tri.a.z, math.max(p.tri.b.z, p.tri.c.z));
          final wcx = ((wxMin + wxMax) * 50).round();
          final wcy = ((wyMin + wyMax) * 50).round();
          final wcz = ((wzMin + wzMax) * 50).round();
          final h = (wcx * 9001 + wcy * 31 + wcz * 7).abs();
          if (h % 5 != 0) {
            rOut = 0.98;
            gOut = 0.84;
            bOut = 0.45;
          } else {
            rOut = 0.10;
            gOut = 0.13;
            bOut = 0.18;
          }
        } else {
          rOut = (rOut * 0.32 + 0.04).clamp(0.0, 1.0);
          gOut = (gOut * 0.32 + 0.06).clamp(0.0, 1.0);
          bOut = (bOut * 0.34 + 0.10).clamp(0.0, 1.0);
        }
      }
      fillPaint.color = Color.fromRGBO(
        (rOut * 255).round(),
        (gOut * 255).round(),
        (bOut * 255).round(),
        1, // alpha=1: НЕ прозрачно никогда
      );
      final sa = toScreen(p.a);
      final sb = toScreen(p.b);
      final sc = toScreen(p.c);
      final path = Path()
        ..moveTo(sa.dx, sa.dy)
        ..lineTo(sb.dx, sb.dy)
        ..lineTo(sc.dx, sc.dy)
        ..close();
      canvas.drawPath(path, fillPaint);
      // v68.11: для стен/скатов/пристроек повторно обводим тем же
      // цветом — закрывает суб-пиксельные щели по диагонали quad-а.
      if (p.tri.kind == SurfaceKind.wallExterior ||
          p.tri.kind == SurfaceKind.roofSlope ||
          p.tri.kind == SurfaceKind.attachmentDeck) {
        selfEdgePaint.color = fillPaint.color;
        canvas.drawPath(path, selfEdgePaint);
      }
      // UV-locked текстура поверх заливки — паттерн жёстко
      // привязан к стене/скату в мировых координатах, рисуется всегда
      // (в том числе во время вращения). Количество ячеек ограничено
      // реальной площадью грани в метрах, а не экранными пикселями,
      // поэтому производительность стабильна.
      if (p.tri.kind == SurfaceKind.wallExterior) {
        _paintTriangleTextureUVLocked(
            canvas, p.tri, sa, sb, sc, wallTex, shaded);
        // AO у земли — мягкое затемнение нижней кромки стены.
        _paintWallAmbientOcclusion(canvas, p.tri, sa, sb, sc);
        // Цокольный карниз — декоративная горизонтальная полоса
        // 12 см над верхом фундамента.
        _paintPlinthCornice(canvas, p.tri, sa, sb, sc,
            plinthTopZ: model.foundation.plinthHeightM);
        // Тень от примыкающих пристроек (крыльцо/терраса) на стене —
        // горизонтальный darkening над верхом пристройки.
        _paintAttachmentWallShadow(canvas, p.tri, sa, sb, sc, model);
      } else if (p.tri.kind == SurfaceKind.roofSlope) {
        _paintTriangleTextureUVLocked(
            canvas, p.tri, sa, sb, sc, roofTex, shaded);
        if (weather != WeatherMode.night) {
          // Холодный «небесный» отблеск в верхней части ската
          // (имитация отражения неба от металлочерепицы / фальца).
          // Для гладких материалов (низкий roughness) — стронг-отблеск
          // + белый anisotropic-блик, для шершавых — слабый и мягкий.
          _paintRoofSkyHighlight(canvas, p.tri, sa, sb, sc,
              roughness: roofTex.roughness);
        }
        if (weather == WeatherMode.winter) {
          // Снежная шапка на скате — белая полоса вдоль карниза +
          // покрытие верхней части ската с лёгким голубоватым
          // оттенком в тенях.
          _paintRoofSnowCap(canvas, p.tri, sa, sb, sc);
        }
      } else if (p.tri.kind == SurfaceKind.glazing) {
        // Стадия 5: ставни (по бокам окна) + обналичка — деревянная
        // рамка-наличник вокруг проёма. Рисуются ДО стекла, т.е.
        // сначала. На каждый окно-tri (треугольник окна) в его 2D-
        // плоскости получается своя сторона ставни/обналички;
        // дублирование исключено по проверке u-границ.
        _paintWindowShuttersAndCasing(canvas, p.tri, sa, sb, sc,
            weather: weather);
        if (weather != WeatherMode.night) {
          // Окно — рисуем градиент-«отражение неба» поверх базовой заливки.
          // Сверху небо (светло-голубое), снизу — отражение земли/здания
          // (тёмно-серое). Эффект остеклённой поверхности.
          _paintGlazingReflection(canvas, p.tri, sa, sb, sc);
        } else {
          // Ночь: светящееся окно с переплётом и мягким гало.
          _paintGlazingNightGlow(canvas, p.tri, sa, sb, sc);
        }
      } else if (p.tri.kind == SurfaceKind.door) {
        // Дверь — рисуем филёнки + дверную ручку. Это превращает
        // плоский тёмный прямоугольник в узнаваемое деревянное
        // полотно с реальной разбивкой.
        _paintDoorPanels(canvas, p.tri, sa, sb, sc, shaded);
      }
      // Намеренно НЕ рисуем обводку каждого треугольника: иначе
      // видимые рёбра «нарезанной» стены/ската пробиваются сквозь
      // переднюю геометрию. Контуры объектов рисуются ниже отдельным
      // слоем рёбер с проверкой на загораживание.
    }

    // Дополнительные рёбра: конёк, накосы, контуры стен, проёмы,
    // карниз пристроек, верх цоколя. Перед отрисовкой каждого ребра
    // проверяем 5 точек вдоль него на загораживание уже видимыми
    // (front-facing) гранями: если ≥3 точек скрыты — пропускаем
    // ребро целиком. Это гарантирует, что задние углы здания и
    // оконные/дверные обводки не «пробивают» стену поверх неё.
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true
      ..color = const Color(0xFF222222);
    for (final e in renderer.collectEdges(model)) {
      final pa = renderer.project(e.a, camera, size.width, size.height);
      final pb = renderer.project(e.b, camera, size.width, size.height);
      var hidden = 0;
      const steps = 5;
      for (var i = 1; i <= steps; i++) {
        final t = i / (steps + 1);
        final px = pa.x + (pb.x - pa.x) * t;
        final py = pa.y + (pb.y - pa.y) * t;
        final pz = pa.z + (pb.z - pa.z) * t;
        if (_pointOccluded(px, py, pz, visible)) hidden++;
      }
      if (hidden >= 3) continue;
      edgePaint.strokeWidth = e.widthPt.clamp(0.5, 2.0);
      canvas.drawLine(toScreen(pa), toScreen(pb), edgePaint);
    }

    // Стадия 5: водосточная система — вертикальные трубы на каждом
    // внешнем углу outline здания, идут от карниза до земли;
    // горизонтальные жёлоба вдоль карнизов; хомут-«манжета» на трубе
    // и слив-«колено» внизу. Цвет совпадает с цветом кровли (тёмно-
    // серый/коричневый), либо ночью — почти чёрный.
    _paintDownspoutsAndGutter(canvas, model, renderer, camera, size, toScreen,
        weather: weather);

    // Стадия 3: «передние» сегменты забора — те, что ближе к камере,
    // чем здание. Рисуются ПОСЛЕ здания и до деревьев, чтобы передние
    // деревья всё равно перекрывали их.
    if (fenceFront.isNotEmpty) {
      _paintFence(canvas, model, renderer, camera, size, toScreen,
          segments: fenceFront);
    }

    // Стадия 2: «передние» деревья — те, что ближе к камере, чем
    // здание. Рисуются ПОСЛЕ здания и его рёбер, поэтому полностью
    // перекрывают часть здания, оказавшуюся за ними.
    if (treesFront.isNotEmpty) {
      _paintTrees(canvas, model, renderer, camera, size, toScreen,
          trees: treesFront, weather: weather);
    }

    // Подпись.
    final tp = TextPainter(
      text: TextSpan(
        text:
            '${model.projectName}\n${model.foundation.typeLabel} · ${model.roof.typeLabel}',
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF222222),
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(12, 12));
  }

  @override
  bool shouldRepaint(covariant _Building3DPainter old) {
    // Камера управляется через ValueNotifier (передан в super.repaint),
    // поэтому здесь сравниваем только тяжёлые входы. Сам перепаин
    // тригерится автоматически при изменении notifier.
    return old.model != model ||
        old.palette != palette ||
        old.weather != weather;
  }
}

class _ProjTri {
  final Projected2D a;
  final Projected2D b;
  final Projected2D c;
  final RenderTri tri;
  _ProjTri(this.a, this.b, this.c, this.tri);
  double get avgDepth => (a.z + b.z + c.z) / 3;

  /// Нормаль в мировых координатах для шейдинга.
  Vec3 get normal => tri.normal;
}

/// Точка `(x, y, z)` (в координатах проекции, до масштабирования на
/// экран; z=depth, больше=глубже) скрыта за любой ближестоящей
/// (front-facing) гранью? Барицентрический тест по списку проверенных
/// треугольников. Используется для культинга невидимых рёбер (углы
/// стен/проёмов на ОБРАТНОЙ стороне здания не должны пробивать
/// видимые грани).
bool _pointOccluded(
    double x, double y, double z, List<_ProjTri> faces) {
  const eps = 0.05; // м — допуск, чтобы рёбра самого треугольника
  //                  не считались загораживающими.
  for (final f in faces) {
    // Землю и слэбы исключаем — иначе горизонтальные грани закрывали
    // бы любое ребро проёма/угла, лежащее «выше» них.
    if (f.tri.kind == SurfaceKind.ground ||
        f.tri.kind == SurfaceKind.slab) {
      continue;
    }
    final ax = f.a.x, ay = f.a.y;
    final bx = f.b.x, by = f.b.y;
    final cx = f.c.x, cy = f.c.y;
    final denom = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy);
    if (denom.abs() < 1e-9) continue;
    final w1 = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / denom;
    final w2 = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / denom;
    final w3 = 1.0 - w1 - w2;
    if (w1 < 0 || w2 < 0 || w3 < 0) continue;
    final triZ = w1 * f.a.z + w2 * f.b.z + w3 * f.c.z;
    // Грань ближе к камере (меньшая z), а ребро глубже → точка скрыта.
    if (triZ + eps < z) return true;
  }
  return false;
}

/// Рисует ОБЪЁМНУЮ процедурную текстуру на проекции треугольника
/// в **локальных координатах стены/ската** (UV-mapping в мировых
/// единицах). Это значит: каждый кирпич/блок/доска получают позицию,
/// привязанную к реальной плоскости стены, а не к экранному
/// bounding box-у проекции. При вращении камеры паттерн остаётся
/// «приклеенным» к стене и не «плывёт» — ровно так, как это
/// происходит с настоящим зданием.
///
/// Алгоритм:
///   1. Для треугольника определяем локальную систему координат
///      (u вдоль стены/карниза, v вверх по стене / вверх по скату).
///   2. Вычисляем UV-координаты каждой вершины (в метрах) через
///      проекцию мировых координат на u/v-оси.
///   3. Строим аффинное преобразование UV→экран по 3 известным
///      соответствиям (вершины треугольника).
///   4. Итерируем ячейки в UV-пространстве, привязанные к глобальной
///      сетке (i, j — целые индексы) — это даёт стабильные seed-ы и
///      одинаковую расцветку ячеек при любом ракурсе.
///   5. Для каждой ячейки трансформируем её 4 угла в экран и рисуем
///      заливку + блик по верху + тень по низу.
///
/// Источник освещения принимается «сверху», поэтому блик всегда на
/// верхней грани ячейки (большая v), тень — на нижней. Это работает
/// и для стен (v = высота), и для скатов (v = вверх по скату).
void _paintTriangleTextureUVLocked(
  Canvas canvas,
  RenderTri tri,
  ui.Offset sa,
  ui.Offset sb,
  ui.Offset sc,
  MaterialTexture tex,
  Color3 shaded,
) {
  if (tex.pattern == MaterialPattern.flat) return;

  final n = tri.normal;
  // Грань почти горизонтальная (перекрытие, верх гаража) — паттерн
  // стен/кровли на ней не имеет смысла.
  if (n.z.abs() > 0.97) return;

  // u-ось: горизонтальная, перпендикулярна нормали (вдоль стены / по
  // карнизу ската). Если стена вертикальная, это просто world_up × n.
  const up = Vec3(0, 0, 1);
  var uAxis = up.cross(n);
  if (uAxis.length < 1e-3) return;
  uAxis = uAxis.normalized;
  // v-ось: «вверх» по плоскости грани. Для вертикальной стены — это
  // просто world up. Для ската — это направление «вверх по скату»,
  // получаемое как n × uAxis.
  Vec3 vAxis;
  final isVertical = n.z.abs() < 0.05;
  if (isVertical) {
    vAxis = const Vec3(0, 0, 1);
  } else {
    vAxis = n.cross(uAxis).normalized;
    if (vAxis.z < 0) {
      vAxis = Vec3(-vAxis.x, -vAxis.y, -vAxis.z);
      uAxis = vAxis.cross(n).normalized;
    }
  }

  double uOf(Vec3 p) => p.x * uAxis.x + p.y * uAxis.y + p.z * uAxis.z;
  double vOf(Vec3 p) => p.x * vAxis.x + p.y * vAxis.y + p.z * vAxis.z;

  final uA = uOf(tri.a), vA = vOf(tri.a);
  final uB = uOf(tri.b), vB = vOf(tri.b);
  final uC = uOf(tri.c), vC = vOf(tri.c);

  // Аффинное преобразование (u, v) → (screen.x, screen.y).
  // Решаем 3×3 систему по Крамеру.
  final det = (uB - uA) * (vC - vA) - (vB - vA) * (uC - uA);
  if (det.abs() < 1e-9) return;
  final invDet = 1.0 / det;
  final dxB = sb.dx - sa.dx;
  final dxC = sc.dx - sa.dx;
  final dyB = sb.dy - sa.dy;
  final dyC = sc.dy - sa.dy;
  final mxU = (dxB * (vC - vA) - dxC * (vB - vA)) * invDet;
  final mxV = ((uB - uA) * dxC - (uC - uA) * dxB) * invDet;
  final mxC0 = sa.dx - mxU * uA - mxV * vA;
  final myU = (dyB * (vC - vA) - dyC * (vB - vA)) * invDet;
  final myV = ((uB - uA) * dyC - (uC - uA) * dyB) * invDet;
  final myC0 = sa.dy - myU * uA - myV * vA;

  ui.Offset toScreen(double u, double v) =>
      ui.Offset(mxU * u + mxV * v + mxC0, myU * u + myV * v + myC0);

  // Размер 1 м в u/v направлении на экране, в пикселях.
  final pxPerMeterU = math.sqrt(mxU * mxU + myU * myU);
  final pxPerMeterV = math.sqrt(mxV * mxV + myV * myV);

  // UV-bbox треугольника.
  final uMin = math.min(uA, math.min(uB, uC));
  final uMax = math.max(uA, math.max(uB, uC));
  final vMin = math.min(vA, math.min(vB, vC));
  final vMax = math.max(vA, math.max(vB, vC));

  // Клиппинг по треугольнику.
  final triPath = Path()
    ..moveTo(sa.dx, sa.dy)
    ..lineTo(sb.dx, sb.dy)
    ..lineTo(sc.dx, sc.dy)
    ..close();
  canvas.save();
  canvas.clipPath(triPath);

  // Базовая заливка грани (с учётом затенения по нормали) и цвет шва.
  final baseR = (shaded.r * 255).round().clamp(0, 255);
  final baseG = (shaded.g * 255).round().clamp(0, 255);
  final baseB = (shaded.b * 255).round().clamp(0, 255);
  final mortarR = (tex.mortarColor.r * 255).round().clamp(0, 255);
  final mortarG = (tex.mortarColor.g * 255).round().clamp(0, 255);
  final mortarB = (tex.mortarColor.b * 255).round().clamp(0, 255);
  final mortarPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true
    ..color = ui.Color.fromRGBO(mortarR, mortarG, mortarB, 1);

  // Длина u/v ячейки в метрах — задаётся паттерном.
  // Для стабильных seed-ов используем целые индексы (i, j) ячейки
  // в глобальной сетке.
  int cellSeed(int i, int j) =>
      ((i * 73856093) ^ (j * 19349663) ^ tex.key.hashCode) & 0x7FFFFFFF;

  // Считаем экранный размер ячейки на 1 м UV — если он совсем мелкий,
  // паттерн станет шумом и просто вернём чистую заливку.
  final cellMinPx = math.min(pxPerMeterU, pxPerMeterV) * tex.tileMeters * 0.4;
  if (cellMinPx < 1.5) {
    canvas.restore();
    return;
  }

  // Общий рисователь одной ячейки: фон шва, затем тело кирпича со
  // скруглением и фасками, блик по верху + теневая фаска по низу.
  void drawUnit(double u0, double v0, double u1, double v1,
      {double mortarMeters = 0.012,
      bool roundEdge = false,
      required int seed}) {
    final p1 = toScreen(u0, v0);
    final p2 = toScreen(u1, v0);
    final p3 = toScreen(u1, v1);
    final p4 = toScreen(u0, v1);

    final r2 = math.Random(seed);
    final tint = (r2.nextDouble() - 0.5) * 0.18;
    final ur = (baseR + tint * 255).clamp(0, 255).round();
    final ug = (baseG + tint * 255).clamp(0, 255).round();
    final ub = (baseB + tint * 255).clamp(0, 255).round();

    // 1) Подложка-шов (вся ячейка целиком).
    final cellPath = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();
    canvas.drawPath(cellPath, mortarPaint);

    // 2) Тело кирпича — отступаем по UV на mortarMeters внутрь.
    final mu = mortarMeters;
    final ip1 = toScreen(u0 + mu, v0 + mu);
    final ip2 = toScreen(u1 - mu, v0 + mu);
    final ip3 = toScreen(u1 - mu, v1 - mu);
    final ip4 = toScreen(u0 + mu, v1 - mu);
    final innerPath = Path()
      ..moveTo(ip1.dx, ip1.dy)
      ..lineTo(ip2.dx, ip2.dy)
      ..lineTo(ip3.dx, ip3.dy)
      ..lineTo(ip4.dx, ip4.dy)
      ..close();
    final body = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..color = ui.Color.fromRGBO(ur, ug, ub, 1);
    canvas.drawPath(innerPath, body);

    // 3) Блик (верх ячейки, v1) — светлая полоса.
    final hi = Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeWidth = 0.9
      ..color = ui.Color.fromRGBO(
          (ur + 50).clamp(0, 255),
          (ug + 50).clamp(0, 255),
          (ub + 50).clamp(0, 255),
          0.85);
    canvas.drawLine(ip4, ip3, hi);
    // 4) Тень (низ ячейки, v0) — тёмная фаска.
    final sh = Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeWidth = 1.0
      ..color = ui.Color.fromRGBO(
          (ur * 0.55).round(),
          (ug * 0.55).round(),
          (ub * 0.55).round(),
          0.9);
    canvas.drawLine(ip1, ip2, sh);
    // 5) Лёгкая боковая фаска (правая сторона = u1).
    canvas.drawLine(ip2, ip3, sh);
    if (roundEdge) {
      // Чуть сглаживаем углы — на самом деле просто рисуем
      // дополнительный лёгкий блик по левому краю.
      canvas.drawLine(ip1, ip4, hi);
    }
  }

  switch (tex.pattern) {
    case MaterialPattern.brick:
      // Кирпичная кладка с перевязкой ½: ширина = tile, высота = tile*0.45,
      // нечётные ряды смещены на полкирпича.
      final cellU = tex.tileMeters;
      final cellV = tex.tileMeters * 0.45;
      final iuMin = (uMin / cellU).floor() - 1;
      final iuMax = (uMax / cellU).ceil() + 1;
      final ivMin = (vMin / cellV).floor() - 1;
      final ivMax = (vMax / cellV).ceil() + 1;
      for (var j = ivMin; j <= ivMax; j++) {
        final shift = (j.isOdd) ? cellU / 2 : 0.0;
        for (var i = iuMin; i <= iuMax; i++) {
          final u0 = i * cellU + shift;
          final v0 = j * cellV;
          drawUnit(u0, v0, u0 + cellU, v0 + cellV,
              mortarMeters: 0.014, seed: cellSeed(i, j));
        }
      }
      break;
    case MaterialPattern.block:
      // Газобетонные блоки 600×250 (tile=0.6) с перевязкой.
      final cellU = tex.tileMeters * 1.0;
      final cellV = tex.tileMeters * 0.42;
      final iuMin = (uMin / cellU).floor() - 1;
      final iuMax = (uMax / cellU).ceil() + 1;
      final ivMin = (vMin / cellV).floor() - 1;
      final ivMax = (vMax / cellV).ceil() + 1;
      for (var j = ivMin; j <= ivMax; j++) {
        final shift = (j.isOdd) ? cellU / 2 : 0.0;
        for (var i = iuMin; i <= iuMax; i++) {
          final u0 = i * cellU + shift;
          final v0 = j * cellV;
          drawUnit(u0, v0, u0 + cellU, v0 + cellV,
              mortarMeters: 0.022, roundEdge: true, seed: cellSeed(i, j));
        }
      }
      break;
    case MaterialPattern.timberLog:
      // Брёвна: горизонтальные «трубы» с цилиндрическим градиентом.
      // Выше реализовано через обычные ячейки + два дополнительных
      // светлых/тёмных пояса внутри тела бревна.
      final cellV = tex.tileMeters * 0.95;
      final ivMin = (vMin / cellV).floor() - 1;
      final ivMax = (vMax / cellV).ceil() + 1;
      // Длинная горизонтальная «полоса» = одно бревно по всей ширине
      // u-bbox-а (с запасом). u-период не нужен.
      final uLo = uMin - tex.tileMeters;
      final uHi = uMax + tex.tileMeters;
      for (var j = ivMin; j <= ivMax; j++) {
        final v0 = j * cellV;
        final v1 = v0 + cellV;
        // Заливка тела бревна.
        final body = Paint()
          ..style = PaintingStyle.fill
          ..isAntiAlias = true
          ..color = ui.Color.fromRGBO(baseR, baseG, baseB, 1);
        final p1 = toScreen(uLo, v0);
        final p2 = toScreen(uHi, v0);
        final p3 = toScreen(uHi, v1);
        final p4 = toScreen(uLo, v1);
        final logPath = Path()
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..lineTo(p3.dx, p3.dy)
          ..lineTo(p4.dx, p4.dy)
          ..close();
        canvas.drawPath(logPath, body);
        // Светлая часть (верхняя 1/3) — имитация солнечного блика
        // по верхней образующей цилиндра.
        final lightV0 = v0 + cellV * 0.65;
        final lightV1 = v1;
        final lp = Paint()
          ..style = PaintingStyle.fill
          ..isAntiAlias = true
          ..color = ui.Color.fromRGBO(
              math.min(255, baseR + 35),
              math.min(255, baseG + 35),
              math.min(255, baseB + 35),
              0.55);
        final lp1 = toScreen(uLo, lightV0);
        final lp2 = toScreen(uHi, lightV0);
        final lp3 = toScreen(uHi, lightV1);
        final lp4 = toScreen(uLo, lightV1);
        final lpPath = Path()
          ..moveTo(lp1.dx, lp1.dy)
          ..lineTo(lp2.dx, lp2.dy)
          ..lineTo(lp3.dx, lp3.dy)
          ..lineTo(lp4.dx, lp4.dy)
          ..close();
        canvas.drawPath(lpPath, lp);
        // Тёмная часть (нижняя 1/3).
        final shadowV0 = v0;
        final shadowV1 = v0 + cellV * 0.32;
        final sp = Paint()
          ..style = PaintingStyle.fill
          ..isAntiAlias = true
          ..color = ui.Color.fromRGBO(
              (baseR * 0.55).round(),
              (baseG * 0.55).round(),
              (baseB * 0.55).round(),
              0.55);
        final sp1 = toScreen(uLo, shadowV0);
        final sp2 = toScreen(uHi, shadowV0);
        final sp3 = toScreen(uHi, shadowV1);
        final sp4 = toScreen(uLo, shadowV1);
        final spPath = Path()
          ..moveTo(sp1.dx, sp1.dy)
          ..lineTo(sp2.dx, sp2.dy)
          ..lineTo(sp3.dx, sp3.dy)
          ..lineTo(sp4.dx, sp4.dy)
          ..close();
        canvas.drawPath(spPath, sp);
        // Разделительный шов между брёвнами (на высоте v0).
        final seamPaint = Paint()
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true
          ..strokeWidth = 1.2
          ..color = ui.Color.fromRGBO(mortarR, mortarG, mortarB, 1);
        canvas.drawLine(p1, p2, seamPaint);
      }
      break;
    case MaterialPattern.timberBeam:
      // Брус — прямоугольные горизонтальные доски.
      final cellV = tex.tileMeters * 0.55;
      final ivMin = (vMin / cellV).floor() - 1;
      final ivMax = (vMax / cellV).ceil() + 1;
      final uLo = uMin - tex.tileMeters;
      final uHi = uMax + tex.tileMeters;
      for (var j = ivMin; j <= ivMax; j++) {
        final v0 = j * cellV;
        drawUnit(uLo, v0, uHi, v0 + cellV,
            mortarMeters: 0.012, seed: cellSeed(0, j));
      }
      break;
    case MaterialPattern.frame:
      // Каркас + ОСП: вертикальные стойки.
      final cellU = tex.tileMeters * 0.6;
      final iuMin = (uMin / cellU).floor() - 1;
      final iuMax = (uMax / cellU).ceil() + 1;
      final vLo = vMin - cellU;
      final vHi = vMax + cellU;
      for (var i = iuMin; i <= iuMax; i++) {
        final u0 = i * cellU;
        drawUnit(u0, vLo, u0 + cellU * 0.92, vHi,
            mortarMeters: 0.018, seed: cellSeed(i, 0));
      }
      break;
    case MaterialPattern.metalTile:
      // Металлочерепица: модули с горизонтальной волной.
      final cellU = tex.tileMeters;
      final cellV = tex.tileMeters * 0.45;
      final iuMin = (uMin / cellU).floor() - 1;
      final iuMax = (uMax / cellU).ceil() + 1;
      final ivMin = (vMin / cellV).floor() - 1;
      final ivMax = (vMax / cellV).ceil() + 1;
      for (var j = ivMin; j <= ivMax; j++) {
        final shift = (j.isOdd) ? cellU / 2 : 0.0;
        for (var i = iuMin; i <= iuMax; i++) {
          final u0 = i * cellU + shift;
          final v0 = j * cellV;
          drawUnit(u0, v0, u0 + cellU, v0 + cellV,
              mortarMeters: 0.008, roundEdge: true, seed: cellSeed(i, j));
        }
        // Поперечный валик (волна) в середине плитки.
        final waveV = j * cellV + cellV * 0.55;
        final waveStart = toScreen(uMin - cellU, waveV);
        final waveEnd = toScreen(uMax + cellU, waveV);
        final wavePaint = Paint()
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true
          ..strokeWidth = 1.2
          ..color = ui.Color.fromRGBO(
              (baseR * 0.7).round(),
              (baseG * 0.7).round(),
              (baseB * 0.7).round(),
              0.6);
        canvas.drawLine(waveStart, waveEnd, wavePaint);
      }
      break;
    case MaterialPattern.profileSheet:
      // Профнастил: вертикальные ребра с тенями (полоса свет/тень).
      final cellU = math.max(tex.tileMeters * 0.18, 0.06);
      final iuMin = (uMin / cellU).floor() - 1;
      final iuMax = (uMax / cellU).ceil() + 1;
      final vLo = vMin - 1.0;
      final vHi = vMax + 1.0;
      for (var i = iuMin; i <= iuMax; i++) {
        final u0 = i * cellU;
        // Светлая половина (валик-вверх).
        final p1 = toScreen(u0, vLo);
        final p2 = toScreen(u0 + cellU * 0.5, vLo);
        final p3 = toScreen(u0 + cellU * 0.5, vHi);
        final p4 = toScreen(u0, vHi);
        final lightPath = Path()
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..lineTo(p3.dx, p3.dy)
          ..lineTo(p4.dx, p4.dy)
          ..close();
        canvas.drawPath(
            lightPath,
            Paint()
              ..style = PaintingStyle.fill
              ..isAntiAlias = true
              ..color = ui.Color.fromRGBO(
                  math.min(255, baseR + 35),
                  math.min(255, baseG + 35),
                  math.min(255, baseB + 35),
                  1));
        // Тёмная половина.
        final q1 = toScreen(u0 + cellU * 0.5, vLo);
        final q2 = toScreen(u0 + cellU, vLo);
        final q3 = toScreen(u0 + cellU, vHi);
        final q4 = toScreen(u0 + cellU * 0.5, vHi);
        final darkPath = Path()
          ..moveTo(q1.dx, q1.dy)
          ..lineTo(q2.dx, q2.dy)
          ..lineTo(q3.dx, q3.dy)
          ..lineTo(q4.dx, q4.dy)
          ..close();
        canvas.drawPath(
            darkPath,
            Paint()
              ..style = PaintingStyle.fill
              ..isAntiAlias = true
              ..color = ui.Color.fromRGBO(
                  (baseR * 0.62).round(),
                  (baseG * 0.62).round(),
                  (baseB * 0.62).round(),
                  1));
      }
      break;
    case MaterialPattern.bitumen:
      // Битумная черепица — мелкие шахматные модули + зерно поверх.
      final cellU = tex.tileMeters * 0.6;
      final cellV = tex.tileMeters * 0.45;
      final iuMin = (uMin / cellU).floor() - 1;
      final iuMax = (uMax / cellU).ceil() + 1;
      final ivMin = (vMin / cellV).floor() - 1;
      final ivMax = (vMax / cellV).ceil() + 1;
      for (var j = ivMin; j <= ivMax; j++) {
        final shift = (j.isOdd) ? cellU / 2 : 0.0;
        for (var i = iuMin; i <= iuMax; i++) {
          final u0 = i * cellU + shift;
          final v0 = j * cellV;
          drawUnit(u0, v0, u0 + cellU, v0 + cellV,
              mortarMeters: 0.008, roundEdge: true, seed: cellSeed(i, j));
        }
      }
      // Зернистая рябь поверх — со стабильным сидом.
      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0x33000000);
      final grainSeed = math.Random(0xBEEF ^ tex.key.hashCode);
      // Плотность ~ количество ячеек × 6.
      final cellsTotal = (iuMax - iuMin + 1) * (ivMax - ivMin + 1);
      final density = (cellsTotal * 4).clamp(40, 800);
      for (var k = 0; k < density; k++) {
        final u = uMin + grainSeed.nextDouble() * (uMax - uMin);
        final v = vMin + grainSeed.nextDouble() * (vMax - vMin);
        final p = toScreen(u, v);
        canvas.drawCircle(p, 0.5, dotPaint);
      }
      break;
    case MaterialPattern.ceramicTile:
      // Керамическая черепица — крупные шахматные модули с фаской.
      final cellU = tex.tileMeters;
      final cellV = tex.tileMeters * 0.7;
      final iuMin = (uMin / cellU).floor() - 1;
      final iuMax = (uMax / cellU).ceil() + 1;
      final ivMin = (vMin / cellV).floor() - 1;
      final ivMax = (vMax / cellV).ceil() + 1;
      for (var j = ivMin; j <= ivMax; j++) {
        final shift = (j.isOdd) ? cellU / 2 : 0.0;
        for (var i = iuMin; i <= iuMax; i++) {
          final u0 = i * cellU + shift;
          final v0 = j * cellV;
          drawUnit(u0, v0, u0 + cellU, v0 + cellV,
              mortarMeters: 0.012, roundEdge: true, seed: cellSeed(i, j));
        }
      }
      break;
    case MaterialPattern.slate:
      // Шифер — крупные горизонтальные «волны» (свет/тень).
      final cellV = tex.tileMeters * 0.55;
      final ivMin = (vMin / cellV).floor() - 1;
      final ivMax = (vMax / cellV).ceil() + 1;
      final uLo = uMin - cellV;
      final uHi = uMax + cellV;
      for (var j = ivMin; j <= ivMax; j++) {
        final v0 = j * cellV;
        // Светлая половина (гребень).
        final lightV1 = v0 + cellV * 0.5;
        final lp1 = toScreen(uLo, lightV1);
        final lp2 = toScreen(uHi, lightV1);
        final lp3 = toScreen(uHi, v0 + cellV);
        final lp4 = toScreen(uLo, v0 + cellV);
        final lpPath = Path()
          ..moveTo(lp1.dx, lp1.dy)
          ..lineTo(lp2.dx, lp2.dy)
          ..lineTo(lp3.dx, lp3.dy)
          ..lineTo(lp4.dx, lp4.dy)
          ..close();
        canvas.drawPath(
            lpPath,
            Paint()
              ..style = PaintingStyle.fill
              ..isAntiAlias = true
              ..color = ui.Color.fromRGBO(
                  math.min(255, baseR + 30),
                  math.min(255, baseG + 30),
                  math.min(255, baseB + 30),
                  1));
        // Тёмная половина (впадина).
        final sp1 = toScreen(uLo, v0);
        final sp2 = toScreen(uHi, v0);
        final sp3 = toScreen(uHi, lightV1);
        final sp4 = toScreen(uLo, lightV1);
        final spPath = Path()
          ..moveTo(sp1.dx, sp1.dy)
          ..lineTo(sp2.dx, sp2.dy)
          ..lineTo(sp3.dx, sp3.dy)
          ..lineTo(sp4.dx, sp4.dy)
          ..close();
        canvas.drawPath(
            spPath,
            Paint()
              ..style = PaintingStyle.fill
              ..isAntiAlias = true
              ..color = ui.Color.fromRGBO(
                  (baseR * 0.65).round(),
                  (baseG * 0.65).round(),
                  (baseB * 0.65).round(),
                  1));
      }
      break;
    case MaterialPattern.seam:
      // Фальцевая кровля — длинные вертикальные швы-полосы.
      final cellU = math.max(tex.tileMeters * 0.5, 0.2);
      final iuMin = (uMin / cellU).floor() - 1;
      final iuMax = (uMax / cellU).ceil() + 1;
      final vLo = vMin - 1.0;
      final vHi = vMax + 1.0;
      for (var i = iuMin; i <= iuMax; i++) {
        final u0 = i * cellU;
        drawUnit(u0, vLo, u0 + cellU, vHi,
            mortarMeters: 0.006, seed: cellSeed(i, 0));
      }
      break;
    case MaterialPattern.flat:
      break;
  }
  canvas.restore();
}

/// Спроецированная по солнцу тень здания. Контур фундамента
/// проецируется на землю **с учётом направления солнца** — берётся
/// направление света, идентичное `SurfacePalette.shadeFace`
/// (солнце на юго-западе, вектор (−0.4, −0.4, +1.0)). Лучи света
/// идут противоположно (0.4, 0.4, −1.0), поэтому каждая точка
/// высоты `H` проецируется на землю со смещением `(0.4·H, 0.4·H)`.
///
/// Алгоритм:
///   1. Берём footprint при z=0 (ground polygon).
///   2. Берём footprint, смещённый на `(0.4·H, 0.4·H)` — это контур
///      крыши, спроецированный на землю.
///   3. Объединяем оба полигона + полосы (параллелограммы) между
///      соответствующими рёбрами через `Path.combine(union, …)`.
///   4. Рисуем результат полупрозрачным чёрным с лёгким blur-ом.
///
/// Эффект: настоящая тень с правильной формой и направлением,
/// которая «вытягивается» от здания на северо-восток.
void _paintGroundShadow(
  Canvas canvas,
  Building3D model,
  Camera3D camera,
  Size size,
  ui.Offset Function(Projected2D) toScreen,
) {
  final outline = model.foundation.outline;
  if (outline.length < 3) return;
  final renderer = Building3DRenderer();

  // Высота здания над землёй: от верхнего края фундамента (z=0) до конька.
  final aboveGround =
      (model.totalHeight - model.foundation.depthM).clamp(2.0, 30.0);
  // Смещение тени по «солнечному» вектору. Сокращаю до 0.35, чтобы
  // тень не «убегала» слишком далеко на больших домах.
  final dx = 0.35 * aboveGround;
  final dy = 0.35 * aboveGround;

  Path makePolyPath(List<Vec3> vertices) {
    final path = Path();
    for (var i = 0; i < vertices.length; i++) {
      final v = vertices[i];
      final proj = renderer.project(v, camera, size.width, size.height);
      final s = toScreen(proj);
      if (i == 0) {
        path.moveTo(s.dx, s.dy);
      } else {
        path.lineTo(s.dx, s.dy);
      }
    }
    path.close();
    return path;
  }

  /// Собирает union полигона + смещённой копии + соединительных полос —
  /// корректную форму тени для одного «блока» с заданной высотой.
  Path shadowOfBlock(List<Vec3> verts, double offX, double offY) {
    final ground = makePolyPath([for (final p in verts) Vec3(p.x, p.y, 0)]);
    final shifted = makePolyPath(
        [for (final p in verts) Vec3(p.x + offX, p.y + offY, 0)]);
    Path acc = ground;
    for (var i = 0; i < verts.length; i++) {
      final j = (i + 1) % verts.length;
      final p0 = verts[i];
      final p1 = verts[j];
      final strip = makePolyPath([
        Vec3(p0.x, p0.y, 0),
        Vec3(p1.x, p1.y, 0),
        Vec3(p1.x + offX, p1.y + offY, 0),
        Vec3(p0.x + offX, p0.y + offY, 0),
      ]);
      acc = Path.combine(PathOperation.union, acc, strip);
    }
    return Path.combine(PathOperation.union, acc, shifted);
  }

  // 1) Тень основного объёма здания.
  Path shadow = shadowOfBlock(outline, dx, dy);

  // 2) Тень каждой пристройки. Высота пристройки своя, поэтому смещение
  // рассчитывается отдельно — у крыльца тень короче, чем у дома.
  for (final att in model.attachments) {
    if (att.outline.length < 3) continue;
    final attH = att.heightM.clamp(0.4, 6.0);
    final attDx = 0.35 * attH;
    final attDy = 0.35 * attH;
    final attShadow = shadowOfBlock(att.outline, attDx, attDy);
    shadow = Path.combine(PathOperation.union, shadow, attShadow);
  }

  // 3) Рисуем размытой полупрозрачной заливкой.
  final paint = Paint()
    ..color = const Color(0x55000000)
    ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5);
  canvas.drawPath(shadow, paint);
}

/// Лёгкое затенение в углах стен и под карнизом (ambient occlusion).
/// Работает per-triangle: накладывает вертикальный градиент на стену,
/// затемняющий нижнюю кромку (стена касается земли) и верхнюю кромку
/// (стена касается кровли). UV-locked, поэтому стабилен при вращении.
void _paintWallAmbientOcclusion(
  Canvas canvas,
  RenderTri tri,
  ui.Offset sa,
  ui.Offset sb,
  ui.Offset sc,
) {
  final n = tri.normal;
  if (n.z.abs() > 0.05) return; // только вертикальные стены
  final minZ = math.min(tri.a.z, math.min(tri.b.z, tri.c.z));
  final maxZ = math.max(tri.a.z, math.max(tri.b.z, tri.c.z));

  // AO у земли применяется только к нижним секциям стены.
  // Атмосферный градиент рисуем для всех стен (независимо от высоты),
  // и corner-AO тоже для всех — поэтому раннего возврата здесь нет.
  final nearBottom = minZ < 0.5;
  final hSpan = maxZ - minZ;
  if (hSpan < 0.05) return; // вырожденный треугольник — пропускаем

  // Аффинная UV→screen для треугольника (u — вдоль стены, v — высота).
  const up = Vec3(0, 0, 1);
  var uAxis = up.cross(n);
  if (uAxis.length < 1e-3) return;
  uAxis = uAxis.normalized;

  double uOf(Vec3 p) => p.x * uAxis.x + p.y * uAxis.y + p.z * uAxis.z;
  double vOf(Vec3 p) => p.z;

  final uA = uOf(tri.a), vA = vOf(tri.a);
  final uB = uOf(tri.b), vB = vOf(tri.b);
  final uC = uOf(tri.c), vC = vOf(tri.c);
  final det = (uB - uA) * (vC - vA) - (vB - vA) * (uC - uA);
  if (det.abs() < 1e-9) return;
  final invDet = 1.0 / det;
  final dxB = sb.dx - sa.dx, dxC = sc.dx - sa.dx;
  final dyB = sb.dy - sa.dy, dyC = sc.dy - sa.dy;
  final mxU = (dxB * (vC - vA) - dxC * (vB - vA)) * invDet;
  final mxV = ((uB - uA) * dxC - (uC - uA) * dxB) * invDet;
  final mxC0 = sa.dx - mxU * uA - mxV * vA;
  final myU = (dyB * (vC - vA) - dyC * (vB - vA)) * invDet;
  final myV = ((uB - uA) * dyC - (uC - uA) * dyB) * invDet;
  final myC0 = sa.dy - myU * uA - myV * vA;

  ui.Offset uv(double u, double v) =>
      ui.Offset(mxU * u + mxV * v + mxC0, myU * u + myV * v + myC0);

  final triPath = Path()
    ..moveTo(sa.dx, sa.dy)
    ..lineTo(sb.dx, sb.dy)
    ..lineTo(sc.dx, sc.dy)
    ..close();
  canvas.save();
  canvas.clipPath(triPath);

  // AO у земли — затемнение полосы 0…0.5 м.
  if (nearBottom) {
    final uMid = (uA + uB + uC) / 3;
    final aoTop = uv(uMid, math.min(0.5, maxZ));
    final aoBot = uv(uMid, minZ);
    final shader = ui.Gradient.linear(
      aoTop,
      aoBot,
      const [Color(0x00000000), Color(0x33000000)],
    );
    canvas.drawPath(triPath, Paint()..shader = shader);
  }

  // Атмосферный градиент: верх стены — лёгкий cool-тон (отражение
  // неба), низ — едва заметный warm-тон (отражение земли). Очень
  // слабая интенсивность, чтобы не «забивать» текстуру кладки.
  {
    final uMid = (uA + uB + uC) / 3;
    final atmTop = uv(uMid, maxZ);
    final atmBot = uv(uMid, minZ);
    final shader = ui.Gradient.linear(
      atmTop,
      atmBot,
      const [
        Color(0x18A8C0CC), // мягкая голубизна сверху
        Color(0x00FFFFFF), // прозрачно посередине
        Color(0x10463832), // тёплый тёмный тон снизу
      ],
      const [0.0, 0.55, 1.0],
    );
    canvas.drawPath(triPath, Paint()..shader = shader);
  }

  // AO в вертикальных углах стены: для каждого ребра треугольника,
  // которое имеет постоянную u-координату (вертикальное), темним
  // соседнюю полосу шириной ~0.18 м. Такие рёбра соответствуют
  // концам стены — то есть углам, где стена смыкается с соседней.
  // Диагональные «внутренние» рёбра триангуляции (двух треугольников
  // одной стены) у них u изменяется, поэтому они отфильтровываются.
  final us = [uA, uB, uC];
  final vs = [vA, vB, vC];
  const aoBandM = 0.18;
  for (var i = 0; i < 3; i++) {
    final j = (i + 1) % 3;
    final dU = (us[j] - us[i]).abs();
    final dV = (vs[j] - vs[i]).abs();
    // Чисто вертикальное ребро: dU≈0 и dV>0.
    if (dU > 0.005 || dV < 0.05) continue;
    final uEdge = (us[i] + us[j]) / 2;
    final vMid = (vs[i] + vs[j]) / 2;
    // Соседняя полоса — внутрь треугольника (определяем по третьей вершине).
    final kOther = 3 - i - j;
    final uOther = us[kOther];
    final inwardSign = uOther > uEdge ? 1.0 : -1.0;
    final p0 = uv(uEdge, vMid);
    final p1 = uv(uEdge + inwardSign * aoBandM, vMid);
    final shader = ui.Gradient.linear(
      p0,
      p1,
      const [Color(0x33000000), Color(0x00000000)],
    );
    canvas.drawPath(triPath, Paint()..shader = shader);
  }

  canvas.restore();
}

/// Отблеск неба и/или specular-блик на скате. На неметаллических
/// материалах (керамика, битум, шифер) — мягкий холодный градиент
/// в верхней части. На металлических (металлочерепица, фальц,
/// профнастил) — более яркий blue-shift + узкий белый anisotropic
/// блик вдоль наклона ската (имитация отражения солнца на гладком
/// металле).
void _paintRoofSkyHighlight(
  Canvas canvas,
  RenderTri tri,
  ui.Offset sa,
  ui.Offset sb,
  ui.Offset sc, {
  double roughness = 0.85,
}) {
  // Чем гладче материал — тем сильнее specular.
  // smoothness ∈ [0..1]: 1 = зеркало, 0 = матовое.
  final smoothness = (1.0 - roughness).clamp(0.0, 1.0);
  final isMetallic = smoothness > 0.55;
  final n = tri.normal;
  // Только наклонённые скаты (не горизонтальные).
  if (n.z.abs() > 0.97) return;

  // Аффинная UV→screen, v вдоль ската (по `n × uAxis`).
  const up = Vec3(0, 0, 1);
  var uAxis = up.cross(n);
  if (uAxis.length < 1e-3) return;
  uAxis = uAxis.normalized;
  var vAxis = n.cross(uAxis);
  if (vAxis.length < 1e-3) return;
  vAxis = vAxis.normalized;
  if (vAxis.z < 0) vAxis = Vec3(-vAxis.x, -vAxis.y, -vAxis.z);

  double uOf(Vec3 p) => p.x * uAxis.x + p.y * uAxis.y + p.z * uAxis.z;
  double vOf(Vec3 p) => p.x * vAxis.x + p.y * vAxis.y + p.z * vAxis.z;

  final uA = uOf(tri.a), vA = vOf(tri.a);
  final uB = uOf(tri.b), vB = vOf(tri.b);
  final uC = uOf(tri.c), vC = vOf(tri.c);
  final det = (uB - uA) * (vC - vA) - (vB - vA) * (uC - uA);
  if (det.abs() < 1e-9) return;
  final invDet = 1.0 / det;
  final dxB = sb.dx - sa.dx, dxC = sc.dx - sa.dx;
  final dyB = sb.dy - sa.dy, dyC = sc.dy - sa.dy;
  final mxU = (dxB * (vC - vA) - dxC * (vB - vA)) * invDet;
  final mxV = ((uB - uA) * dxC - (uC - uA) * dxB) * invDet;
  final mxC0 = sa.dx - mxU * uA - mxV * vA;
  final myU = (dyB * (vC - vA) - dyC * (vB - vA)) * invDet;
  final myV = ((uB - uA) * dyC - (uC - uA) * dyB) * invDet;
  final myC0 = sa.dy - myU * uA - myV * vA;

  ui.Offset uv(double u, double v) =>
      ui.Offset(mxU * u + mxV * v + mxC0, myU * u + myV * v + myC0);

  final vMin = math.min(vA, math.min(vB, vC));
  final vMax = math.max(vA, math.max(vB, vC));
  final uMid = (uA + uB + uC) / 3;
  final triPath = Path()
    ..moveTo(sa.dx, sa.dy)
    ..lineTo(sb.dx, sb.dy)
    ..lineTo(sc.dx, sc.dy)
    ..close();

  canvas.save();
  canvas.clipPath(triPath);
  // Холодный «небесный» блик в верхней половине ската.
  // Для металла — насыщеннее и шире, для неметалла — мягче.
  final top = uv(uMid, vMax);
  final mid = uv(uMid, vMin + (vMax - vMin) * (isMetallic ? 0.3 : 0.4));
  final skyColor = isMetallic
      ? const [Color(0x66B7D2E5), Color(0x00B7D2E5)]
      : const [Color(0x33C4D8E8), Color(0x00C4D8E8)];
  final shader = ui.Gradient.linear(top, mid, skyColor);
  canvas.drawPath(triPath, Paint()..shader = shader);

  // Specular «солнечный» блик — узкая яркая полоса на металлической
  // кровле в верхней трети ската. Анизотропия имитируется тем, что
  // блик растянут вдоль u (по карнизу), а в v более узкий.
  if (isMetallic) {
    final specV = vMin + (vMax - vMin) * 0.78;
    final specSpan = (vMax - vMin) * 0.07;
    // Подсчитываем экранные координаты через uv(...) для трёх точек:
    // верх блика, низ блика, середина в u.
    final uMin = math.min(uA, math.min(uB, uC));
    final uMax = math.max(uA, math.max(uB, uC));
    final uLo = uMin - 0.5;
    final uHi = uMax + 0.5;
    final p1 = uv(uLo, specV - specSpan);
    final p2 = uv(uHi, specV - specSpan);
    final p3 = uv(uHi, specV + specSpan);
    final p4 = uv(uLo, specV + specSpan);
    final specPath = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();
    // Альфа specular-блика: 0x88 при smoothness=1, плавно к 0x00 при 0.55.
    final specAlpha = ((smoothness - 0.55) / 0.45 * 0x88).clamp(0, 255).toInt();
    final specCenter = Color.fromARGB(specAlpha, 255, 255, 255);
    final specGrad = ui.Gradient.linear(
      uv(uMid, specV - specSpan),
      uv(uMid, specV + specSpan),
      [
        const Color(0x00FFFFFF),
        specCenter,
        const Color(0x00FFFFFF),
      ],
      const [0.0, 0.5, 1.0],
    );
    canvas.drawPath(specPath, Paint()..shader = specGrad);
  }

  canvas.restore();
}

/// Стадия 4 (Зима): снежная шапка на скате кровли. Заполняет верхнюю
/// часть ската белым с лёгким голубоватым отливом (отражение неба
/// в тенях), нижняя кромка — карнизный «снеговой балкон» с
/// неровной линией нависания (имитация подтаявших краёв).
/// UV-locked поверх существующей текстуры кровли.
void _paintRoofSnowCap(
  Canvas canvas,
  RenderTri tri,
  ui.Offset sa,
  ui.Offset sb,
  ui.Offset sc,
) {
  final n = tri.normal;
  // Только наклонённые скаты, причём только обращённые «вверх»
  // (нижние/изнаночные пропускаем — там снег не лежит).
  if (n.z.abs() > 0.97) return;
  if (n.z < 0.05) return;

  const up = Vec3(0, 0, 1);
  var uAxis = up.cross(n);
  if (uAxis.length < 1e-3) return;
  uAxis = uAxis.normalized;
  var vAxis = n.cross(uAxis);
  if (vAxis.length < 1e-3) return;
  vAxis = vAxis.normalized;
  if (vAxis.z < 0) vAxis = Vec3(-vAxis.x, -vAxis.y, -vAxis.z);

  double uOf(Vec3 p) => p.x * uAxis.x + p.y * uAxis.y + p.z * uAxis.z;
  double vOf(Vec3 p) => p.x * vAxis.x + p.y * vAxis.y + p.z * vAxis.z;

  final uA = uOf(tri.a), vA = vOf(tri.a);
  final uB = uOf(tri.b), vB = vOf(tri.b);
  final uC = uOf(tri.c), vC = vOf(tri.c);
  final det = (uB - uA) * (vC - vA) - (vB - vA) * (uC - uA);
  if (det.abs() < 1e-9) return;
  final invDet = 1.0 / det;
  final dxB = sb.dx - sa.dx, dxC = sc.dx - sa.dx;
  final dyB = sb.dy - sa.dy, dyC = sc.dy - sa.dy;
  final mxU = (dxB * (vC - vA) - dxC * (vB - vA)) * invDet;
  final mxV = ((uB - uA) * dxC - (uC - uA) * dxB) * invDet;
  final mxC0 = sa.dx - mxU * uA - mxV * vA;
  final myU = (dyB * (vC - vA) - dyC * (vB - vA)) * invDet;
  final myV = ((uB - uA) * dyC - (uC - uA) * dyB) * invDet;
  final myC0 = sa.dy - myU * uA - myV * vA;

  ui.Offset uv(double u, double v) =>
      ui.Offset(mxU * u + mxV * v + mxC0, myU * u + myV * v + myC0);

  final vMin = math.min(vA, math.min(vB, vC));
  final vMax = math.max(vA, math.max(vB, vC));
  final uMid = (uA + uB + uC) / 3;

  final triPath = Path()
    ..moveTo(sa.dx, sa.dy)
    ..lineTo(sb.dx, sb.dy)
    ..lineTo(sc.dx, sc.dy)
    ..close();

  canvas.save();
  canvas.clipPath(triPath);

  // Заливка ската белым с градиентом: ярче (#FAFCFE) у верхушки,
  // плавно к (#E0E8EE) к карнизу — снег чуть толще наверху.
  final shader = ui.Gradient.linear(
    uv(uMid, vMax),
    uv(uMid, vMin),
    const [
      Color(0xF8FAFCFE),
      Color(0xE6EAF0F4),
      Color(0xCCCFD9E0),
    ],
    const [0.0, 0.5, 1.0],
  );
  canvas.drawPath(triPath, Paint()..shader = shader);

  // Голубоватые «тени» в выемках — мелкая UV-сетка (4 узора по 0.6 м).
  final shadowPaint = Paint()
    ..color = const Color(0x44A8C0CF)
    ..isAntiAlias = true;
  final uMin = math.min(uA, math.min(uB, uC));
  final uMax = math.max(uA, math.max(uB, uC));
  for (var u = uMin.floorToDouble(); u < uMax + 0.6; u += 0.6) {
    for (var v = vMin.floorToDouble(); v < vMax + 0.6; v += 0.6) {
      final h = (((u * 73).toInt()) ^ ((v * 91).toInt())) & 0x7FFFFFFF;
      if (h % 4 != 0) continue;
      final pCenter = uv(u + 0.3, v + 0.3);
      canvas.drawCircle(pCenter, 4.0, shadowPaint);
    }
  }
  canvas.restore();
}

/// Стадия 4 (Ночь): светящееся окно. Тёплый жёлтый градиент с центра
/// к краям + переплёт (импосты) и тонкая рама. Имитирует свет от
/// настольных ламп изнутри.
void _paintGlazingNightGlow(
  Canvas canvas,
  RenderTri tri,
  ui.Offset sa,
  ui.Offset sb,
  ui.Offset sc,
) {
  final n = tri.normal;
  // Локальные оси u (горизонт) и v (вверх) на плоскости стены.
  final up = Vec3(0, 0, 1);
  var uAxis = up.cross(n);
  if (uAxis.length < 1e-3) {
    uAxis = const Vec3(1, 0, 0);
  } else {
    uAxis = uAxis.normalized;
  }
  final vAxis = const Vec3(0, 0, 1);

  double uOf(Vec3 p) => p.x * uAxis.x + p.y * uAxis.y + p.z * uAxis.z;
  double vOf(Vec3 p) => p.x * vAxis.x + p.y * vAxis.y + p.z * vAxis.z;

  final uA = uOf(tri.a), vA = vOf(tri.a);
  final uB = uOf(tri.b), vB = vOf(tri.b);
  final uC = uOf(tri.c), vC = vOf(tri.c);
  final det = (uB - uA) * (vC - vA) - (vB - vA) * (uC - uA);
  if (det.abs() < 1e-9) return;
  final invDet = 1.0 / det;
  final dxB = sb.dx - sa.dx, dxC = sc.dx - sa.dx;
  final dyB = sb.dy - sa.dy, dyC = sc.dy - sa.dy;
  final mxU = (dxB * (vC - vA) - dxC * (vB - vA)) * invDet;
  final mxV = ((uB - uA) * dxC - (uC - uA) * dxB) * invDet;
  final mxC0 = sa.dx - mxU * uA - mxV * vA;
  final myU = (dyB * (vC - vA) - dyC * (vB - vA)) * invDet;
  final myV = ((uB - uA) * dyC - (uC - uA) * dyB) * invDet;
  final myC0 = sa.dy - myU * uA - myV * vA;
  ui.Offset uv(double u, double v) =>
      ui.Offset(mxU * u + mxV * v + mxC0, myU * u + myV * v + myC0);

  final uMin = math.min(uA, math.min(uB, uC));
  final uMax = math.max(uA, math.max(uB, uC));
  final vMin = math.min(vA, math.min(vB, vC));
  final vMax = math.max(vA, math.max(vB, vC));
  final uMid = (uMin + uMax) / 2;
  final vMid = (vMin + vMax) / 2;

  final triPath = Path()
    ..moveTo(sa.dx, sa.dy)
    ..lineTo(sb.dx, sb.dy)
    ..lineTo(sc.dx, sc.dy)
    ..close();
  // Случайно-«тёмные» окна (где «никого нет дома»). v68.11: хэш по
  // BBox окна в мировых координатах — обе половинки одного проёма
  // (тр-к BL+TR+BR и тр-к BL+TL+TR) имеют ОДИНАКОВЫЙ bbox, поэтому
  // получают один результат. До v68.11 хэшилось по `tri.a` —
  // вершины разные → одно полуокно горело, другое было тёмным.
  final wxMin = math.min(tri.a.x, math.min(tri.b.x, tri.c.x));
  final wxMax = math.max(tri.a.x, math.max(tri.b.x, tri.c.x));
  final wyMin = math.min(tri.a.y, math.min(tri.b.y, tri.c.y));
  final wyMax = math.max(tri.a.y, math.max(tri.b.y, tri.c.y));
  final wzMin = math.min(tri.a.z, math.min(tri.b.z, tri.c.z));
  final wzMax = math.max(tri.a.z, math.max(tri.b.z, tri.c.z));
  final wcx = ((wxMin + wxMax) * 50).round(); // квант 0.02 м
  final wcy = ((wyMin + wyMax) * 50).round();
  final wcz = ((wzMin + wzMax) * 50).round();
  final h = (wcx * 9001 + wcy * 31 + wcz * 7).abs();
  if (h % 5 == 0) {
    // Тёмное окно — только тонкая рама.
    canvas.save();
    canvas.clipPath(triPath);
    final framePath = Path()
      ..moveTo(uv(uMin, vMin).dx, uv(uMin, vMin).dy)
      ..lineTo(uv(uMax, vMin).dx, uv(uMax, vMin).dy)
      ..lineTo(uv(uMax, vMax).dx, uv(uMax, vMax).dy)
      ..lineTo(uv(uMin, vMax).dx, uv(uMin, vMax).dy)
      ..close();
    canvas.drawPath(
      framePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF1B1B19),
    );
    canvas.restore();
    return;
  }

  canvas.save();
  canvas.clipPath(triPath);

  // Тёплый радиальный градиент изнутри окна (эффект лампы за стеклом).
  final centerScreen = uv(uMid, vMid);
  final cornerDist =
      (uv(uMin, vMin) - centerScreen).distance.clamp(20.0, 1e9);
  final glowShader = ui.Gradient.radial(
    centerScreen,
    cornerDist * 1.1,
    const [
      Color(0xFFFFEFB6), // ярко-жёлтое ядро
      Color(0xFFFAD583),
      Color(0xFFE7B95A), // тёплый край
    ],
    const [0.0, 0.55, 1.0],
  );
  canvas.drawPath(triPath, Paint()..shader = glowShader);

  // Тонкие импосты (крест 2×2). Цвет почти чёрный.
  final mullion = Paint()
    ..color = const Color(0xFF231510)
    ..style = PaintingStyle.fill;
  final width = uMax - uMin;
  final height = vMax - vMin;
  // Адаптивный split (как в дневном glazing).
  final wide = width > height * 1.6;
  final tall = height > width * 1.6;
  if (!tall) {
    // Вертикальный импост посередине.
    final lh = uv(uMid - 0.022, vMin);
    final rh = uv(uMid + 0.022, vMin);
    final lt = uv(uMid - 0.022, vMax);
    final rt = uv(uMid + 0.022, vMax);
    canvas.drawPath(
      Path()
        ..moveTo(lh.dx, lh.dy)
        ..lineTo(rh.dx, rh.dy)
        ..lineTo(rt.dx, rt.dy)
        ..lineTo(lt.dx, lt.dy)
        ..close(),
      mullion,
    );
  }
  if (!wide) {
    // Горизонтальный импост посередине.
    final lb = uv(uMin, vMid - 0.022);
    final lt = uv(uMin, vMid + 0.022);
    final rb = uv(uMax, vMid - 0.022);
    final rt = uv(uMax, vMid + 0.022);
    canvas.drawPath(
      Path()
        ..moveTo(lb.dx, lb.dy)
        ..lineTo(rb.dx, rb.dy)
        ..lineTo(rt.dx, rt.dy)
        ..lineTo(lt.dx, lt.dy)
        ..close(),
      mullion,
    );
  }

  // Внешняя рама-обрамление (~3 см).
  final framePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..color = const Color(0xFF1B1B19);
  canvas.drawPath(triPath, framePaint);

  canvas.restore();

  // Soft halo за окном (выходит за границы клипа стены, поэтому
  // рисуется ПОСЛЕ restore — но без дополнительного ограничения
  // оно может портить соседние тёмные стены. Делаем альфу низкой).
  canvas.drawCircle(
    centerScreen,
    cornerDist * 0.6,
    Paint()
      ..color = const Color(0x33FFE3A8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
      ..isAntiAlias = true,
  );
}

/// Стадия 5: ставни и обналичка (наличник) вокруг окна. Каждое окно
/// в треугольной разбивке состоит из двух треугольников; функция
/// определяет, какая сторона прилегает к границе uMin / uMax (две
/// вершины с одинаковым u) и рисует на этой стороне ставню (наружу
/// от окна на 0.45 м). Также рисует тонкую обналичку 6 см по верх-
/// нему и нижнему краю.
///
/// Палитра ставней зависит от пресета погоды (теплое дерево летом,
/// серое серебристое зимой, почти чёрное ночью). Это создаёт
/// деревенско-загородный фасад с традиционными деталями.
void _paintWindowShuttersAndCasing(
  Canvas canvas,
  RenderTri tri,
  ui.Offset sa,
  ui.Offset sb,
  ui.Offset sc, {
  WeatherMode weather = WeatherMode.summer,
}) {
  final n = tri.normal;
  if (n.z.abs() > 0.95) return; // горизонтальные грани (зенитные окна) пропускаем
  // u-axis — горизонталь стены, v-axis — вертикаль (мировая Z).
  const up = Vec3(0, 0, 1);
  var uAxis = up.cross(n);
  if (uAxis.length < 1e-3) return;
  uAxis = uAxis.normalized;
  const vAxis = Vec3(0, 0, 1);

  double uOf(Vec3 p) => p.x * uAxis.x + p.y * uAxis.y + p.z * uAxis.z;
  double vOf(Vec3 p) => p.x * vAxis.x + p.y * vAxis.y + p.z * vAxis.z;

  final uA = uOf(tri.a), vA = vOf(tri.a);
  final uB = uOf(tri.b), vB = vOf(tri.b);
  final uC = uOf(tri.c), vC = vOf(tri.c);
  final det = (uB - uA) * (vC - vA) - (vB - vA) * (uC - uA);
  if (det.abs() < 1e-9) return;
  final invDet = 1.0 / det;
  final dxB = sb.dx - sa.dx, dxC = sc.dx - sa.dx;
  final dyB = sb.dy - sa.dy, dyC = sc.dy - sa.dy;
  final mxU = (dxB * (vC - vA) - dxC * (vB - vA)) * invDet;
  final mxV = ((uB - uA) * dxC - (uC - uA) * dxB) * invDet;
  final mxC0 = sa.dx - mxU * uA - mxV * vA;
  final myU = (dyB * (vC - vA) - dyC * (vB - vA)) * invDet;
  final myV = ((uB - uA) * dyC - (uC - uA) * dyB) * invDet;
  final myC0 = sa.dy - myU * uA - myV * vA;
  ui.Offset uv(double u, double v) =>
      ui.Offset(mxU * u + mxV * v + mxC0, myU * u + myV * v + myC0);

  final uMin = math.min(uA, math.min(uB, uC));
  final uMax = math.max(uA, math.max(uB, uC));
  final vMin = math.min(vA, math.min(vB, vC));
  final vMax = math.max(vA, math.max(vB, vC));
  final wW = uMax - uMin;
  final wH = vMax - vMin;
  // Слишком большие/слишком мелкие проёмы пропускаем (вит­рины,
  // куски разбитой геометрии).
  if (wW > 2.4 || wW < 0.45 || wH < 0.55 || wH > 2.6) return;

  // Подсчёт, какие u-границы имеют ≥2 вершин — нам нужно нарисовать
  // ставню только на этой границе, чтобы избежать дублей при разбивке
  // прямоугольника окна на два треугольника.
  const eps = 1e-3;
  int onMin = 0, onMax = 0;
  for (final u in [uA, uB, uC]) {
    if ((u - uMin).abs() < eps) onMin++;
    if ((u - uMax).abs() < eps) onMax++;
  }

  // Палитра ставней.
  final Color shutterFill;
  final Color shutterEdge;
  final Color casingFill;
  switch (weather) {
    case WeatherMode.summer:
      shutterFill = const Color(0xFF6E4A28);
      shutterEdge = const Color(0xFF3A2515);
      casingFill = const Color(0xFFE8DDC4);
      break;
    case WeatherMode.winter:
      shutterFill = const Color(0xFF7C6A55);
      shutterEdge = const Color(0xFF433829);
      casingFill = const Color(0xFFF5F0E4);
      break;
    case WeatherMode.night:
      shutterFill = const Color(0xFF221610);
      shutterEdge = const Color(0xFF080402);
      casingFill = const Color(0xFF584F40);
      break;
  }

  void drawShutter(double uL, double uR) {
    if (uR - uL < 0.05) return;
    // Основная заливка ставни.
    final p1 = uv(uL, vMin);
    final p2 = uv(uR, vMin);
    final p3 = uv(uR, vMax);
    final p4 = uv(uL, vMax);
    final shutterPath = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();
    canvas.drawPath(
      shutterPath,
      Paint()
        ..color = shutterFill
        ..isAntiAlias = true,
    );
    // 6 горизонтальных «жалюзи»-планок поперёк ставни.
    for (var i = 1; i < 6; i++) {
      final v = vMin + wH * i / 6.0;
      canvas.drawLine(
        uv(uL + 0.015, v),
        uv(uR - 0.015, v),
        Paint()
          ..color = shutterEdge
          ..strokeWidth = 1.0
          ..isAntiAlias = true,
      );
    }
    // Окантовка-кромка.
    canvas.drawPath(
      shutterPath,
      Paint()
        ..color = shutterEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..isAntiAlias = true,
    );
    // Маленькая «петля» крепления к стене (близко к окну).
    final hingeCenter = uv(
      (uL + uR) / 2 < (uMin + uMax) / 2 ? uR - 0.04 : uL + 0.04,
      vMin + wH * 0.5,
    );
    canvas.drawCircle(
      hingeCenter,
      1.6,
      Paint()
        ..color = const Color(0xFF1F1A12)
        ..isAntiAlias = true,
    );
  }

  // Ставни 0.42 м × wH м, отступ 0.02 м от окна.
  const sw = 0.42;
  const gap = 0.02;
  if (onMin >= 2) {
    drawShutter(uMin - sw - gap, uMin - gap);
  }
  if (onMax >= 2) {
    drawShutter(uMax + gap, uMax + sw + gap);
  }

  // Обналичка (наличник) — светлая деревянная рамка по периметру окна,
  // выступает на 0.06 м наружу. Рисуем её ВНЕ области стекла, поэтому
  // используем рамку шириной 6 см, без верхне/нижнего захлёста на
  // glazing-tri. Каждая сторона зависит от того, какие границы
  // принадлежат текущему tri.
  const c = 0.06; // ширина наличника
  // Верх (от u=uMin-c, v=vMax до u=uMax+c, v=vMax+c) — рисуем на каждом tri,
  // он одинаковый.
  void drawCasingStrip(double uL, double uR, double vL, double vH) {
    final p1 = uv(uL, vL);
    final p2 = uv(uR, vL);
    final p3 = uv(uR, vH);
    final p4 = uv(uL, vH);
    canvas.drawPath(
      Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..lineTo(p4.dx, p4.dy)
        ..close(),
      Paint()
        ..color = casingFill
        ..isAntiAlias = true,
    );
  }

  // Полное обрамление: верх и низ всегда. Боковые — только если этот tri
  // содержит соответствующую границу.
  drawCasingStrip(uMin - c, uMax + c, vMax, vMax + c);
  drawCasingStrip(uMin - c, uMax + c, vMin - c, vMin);
  if (onMin >= 2) {
    drawCasingStrip(uMin - c, uMin, vMin - c, vMax + c);
  }
  if (onMax >= 2) {
    drawCasingStrip(uMax, uMax + c, vMin - c, vMax + c);
  }
}

/// Стадия 5: водосточная система (downspouts + gutters).
///
/// На каждом ВНЕШНЕМ углу outline здания (где внешняя нормаль угла
/// направлена вне здания) рисуется вертикальная труба ⌀10 см от
/// карниза до земли. Углы скрытых сторон не получают трубы — нет
/// смысла рисовать те, что повернуты от камеры.
///
/// Жёлоб (gutter) — горизонтальный полу-цилиндр чуть ниже карниза
/// (на 8 см). Между трубой и жёлобом — переходное колено.
///
/// Цвет совпадает с тёмно-коричневым (`#3A2A1F` лето, `#5A4F3F`
/// зима, `#0A0805` ночь) — выглядит как окрашенная сталь/ПВХ.
void _paintDownspoutsAndGutter(
  Canvas canvas,
  Building3D model,
  Building3DRenderer renderer,
  Camera3D camera,
  Size size,
  ui.Offset Function(Projected2D) toScreen, {
  WeatherMode weather = WeatherMode.summer,
}) {
  final outline = model.foundation.outline;
  if (outline.length < 3) return;
  // Карниз: верх стен последнего этажа.
  if (model.floors.isEmpty) return;
  final eaveZ = model.floors.last.elevationM + model.floors.last.heightM;
  // Цвет водосточки.
  final Color pipeColor;
  final Color pipeShade;
  final Color pipeHighlight;
  switch (weather) {
    case WeatherMode.summer:
      pipeColor = const Color(0xFF3A2A1F);
      pipeShade = const Color(0xFF1A130D);
      pipeHighlight = const Color(0xFF5C4533);
      break;
    case WeatherMode.winter:
      pipeColor = const Color(0xFF564A3D);
      pipeShade = const Color(0xFF302820);
      pipeHighlight = const Color(0xFF7A6B5A);
      break;
    case WeatherMode.night:
      pipeColor = const Color(0xFF1B1410);
      pipeShade = const Color(0xFF050302);
      pipeHighlight = const Color(0xFF302520);
      break;
  }

  // 1) Жёлоб вдоль каждого карнизного ребра (между двумя соседними
  //    углами outline). Рисуется как тонкая горизонтальная полоса
  //    на высоте eaveZ - 0.04 м (просто ниже карниза).
  for (var i = 0; i < outline.length; i++) {
    final a = outline[i];
    final b = outline[(i + 1) % outline.length];
    final pa = renderer.project(
        Vec3(a.x, a.y, eaveZ - 0.04), camera, size.width, size.height);
    final pb = renderer.project(
        Vec3(b.x, b.y, eaveZ - 0.04), camera, size.width, size.height);
    if (pa.z > 0 || pb.z > 0) continue; // полностью за камерой
    final sa = toScreen(pa);
    final sb = toScreen(pb);
    // Жёлоб — толстая линия с подложкой (полу-цилиндр).
    canvas.drawLine(
      sa,
      sb,
      Paint()
        ..color = pipeShade
        ..strokeWidth = 5.0
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
    canvas.drawLine(
      sa,
      sb,
      Paint()
        ..color = pipeColor
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
    // Тонкий блик-полоска сверху (имитация цилиндра).
    canvas.drawLine(
      sa,
      sb,
      Paint()
        ..color = pipeHighlight
        ..strokeWidth = 0.8
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
  }

  // 2) Вертикальные трубы на каждом углу outline. Чтобы избежать дубль
  //    с углом, который повёрнут от камеры, не рисуем углы, у которых
  //    обе соседние грани back-facing (приблизительно по углу взгляда).
  for (var i = 0; i < outline.length; i++) {
    final c = outline[i];
    final prev = outline[(i - 1 + outline.length) % outline.length];
    final next = outline[(i + 1) % outline.length];
    // Внешняя нормаль угла = bisector между outward-нормалями
    // двух соседних рёбер. (Но для простоты считаем bisector между
    // векторами c→prev и c→next, вывернутый наружу.)
    final dx1 = prev.x - c.x;
    final dy1 = prev.y - c.y;
    final l1 = math.sqrt(dx1 * dx1 + dy1 * dy1);
    if (l1 < 1e-6) continue;
    final dx2 = next.x - c.x;
    final dy2 = next.y - c.y;
    final l2 = math.sqrt(dx2 * dx2 + dy2 * dy2);
    if (l2 < 1e-6) continue;
    // Внутренний bisector (нормированный).
    final ix = dx1 / l1 + dx2 / l2;
    final iy = dy1 / l1 + dy2 / l2;
    final il = math.sqrt(ix * ix + iy * iy);
    if (il < 1e-6) continue;
    // Внешняя нормаль = -bisector. Используем для смещения трубы
    // на 0.06 м наружу здания.
    final outwardX = -ix / il;
    final outwardY = -iy / il;
    final tx = c.x + outwardX * 0.06;
    final ty = c.y + outwardY * 0.06;

    final pTop = renderer.project(
        Vec3(tx, ty, eaveZ), camera, size.width, size.height);
    final pBot = renderer.project(
        Vec3(tx, ty, 0.0), camera, size.width, size.height);
    if (pTop.z > 0 && pBot.z > 0) continue;
    final sTop = toScreen(pTop);
    final sBot = toScreen(pBot);

    // Толщина трубы в screen-px зависит от глубины. Используем
    // проекцию точки на ⌀10 см вбок: разница между центром и точкой
    // (tx + 0.05·u, ty + 0.05·v) на той же высоте.
    final pSide = renderer.project(
        Vec3(tx - outwardY * 0.05, ty + outwardX * 0.05, eaveZ),
        camera,
        size.width,
        size.height);
    final dRaw = (toScreen(pSide) - sTop).distance;
    final pipeW = (dRaw * 1.6).clamp(2.0, 8.0);

    // Тёмная подложка-тень.
    canvas.drawLine(
      sTop,
      sBot,
      Paint()
        ..color = pipeShade
        ..strokeWidth = pipeW + 1.5
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
    // Основной цвет трубы.
    canvas.drawLine(
      sTop,
      sBot,
      Paint()
        ..color = pipeColor
        ..strokeWidth = pipeW
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
    // Блик слева (анизотропия цилиндра).
    final dx = sBot.dx - sTop.dx;
    final dy = sBot.dy - sTop.dy;
    final dl = math.sqrt(dx * dx + dy * dy);
    if (dl > 1e-3) {
      final perpX = -dy / dl * (pipeW * 0.25);
      final perpY = dx / dl * (pipeW * 0.25);
      canvas.drawLine(
        ui.Offset(sTop.dx - perpX, sTop.dy - perpY),
        ui.Offset(sBot.dx - perpX, sBot.dy - perpY),
        Paint()
          ..color = pipeHighlight
          ..strokeWidth = pipeW * 0.3
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }

    // Хомут-«манжета» на высоте 0.4 м и 1.6 м над землёй (крепление
    // трубы к стене).
    for (final hz in const [0.4, 1.6]) {
      final pH = renderer.project(
          Vec3(tx, ty, hz), camera, size.width, size.height);
      if (pH.z > 0) continue;
      final sH = toScreen(pH);
      // Хомут — короткая горизонтальная полоса, перпендикулярная
      // вертикали трубы на экране.
      if (dl > 1e-3) {
        final perpX = -dy / dl * (pipeW * 0.7);
        final perpY = dx / dl * (pipeW * 0.7);
        canvas.drawLine(
          ui.Offset(sH.dx - perpX, sH.dy - perpY),
          ui.Offset(sH.dx + perpX, sH.dy + perpY),
          Paint()
            ..color = pipeShade
            ..strokeWidth = 1.6
            ..isAntiAlias = true,
        );
      }
    }

    // Слив-«колено» — короткий отвод от низа трубы наружу.
    final pElbow = renderer.project(
        Vec3(tx + outwardX * 0.18, ty + outwardY * 0.18, 0.0),
        camera,
        size.width,
        size.height);
    if (pElbow.z <= 0) {
      final sElbow = toScreen(pElbow);
      canvas.drawLine(
        sBot,
        sElbow,
        Paint()
          ..color = pipeShade
          ..strokeWidth = pipeW + 0.8
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
      canvas.drawLine(
        sBot,
        sElbow,
        Paint()
          ..color = pipeColor
          ..strokeWidth = pipeW
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }
  }
}

/// Подбирает палитру [SurfacePalette] на основе материала стен и
/// кровли, выбранного в проекте. Текстуры — из централизованной
/// библиотеки [MaterialTextureLibrary].
SurfacePalette _paletteFromModel(Building3D model) {
  final wm = WallMaterial.fromName(model.wallMaterialName);
  final wallTex = MaterialTextureLibrary.wall(wm);
  final roofTex = MaterialTextureLibrary.roof(model.roofMaterialId);
  Color3 toC3(Color c) => Color3(
        ((c.r * 255).round() & 0xFF) / 255.0,
        ((c.g * 255).round() & 0xFF) / 255.0,
        ((c.b * 255).round() & 0xFF) / 255.0,
      );
  return SurfacePalette.forMaterials(
    wallExterior: toC3(wallTex.baseColor),
    roofSlope: toC3(roofTex.baseColor),
    roofRidge: toC3(roofTex.mortarColor),
  );
}

/// Рисует градиент-«отражение неба» на стекле окна + переплёт (мунтины
/// + рама) поверх. Сверху — бледно-голубой (небо), посередине — лёгкий
/// полу-тон, снизу — тёмно-серый («отражение земли»). Поверх — крест
/// импостов, делящий окно на 2×2 панели + чёрная рама по периметру
/// (тонкая обводка). Это превращает плоский синий квадрат в узнаваемое
/// 4-секционное окно.
///
/// UV-координаты — в мировой плоскости стены, поэтому переплёт
/// «приклеен» к раме при любом ракурсе.
void _paintGlazingReflection(
  Canvas canvas,
  RenderTri tri,
  ui.Offset sa,
  ui.Offset sb,
  ui.Offset sc,
) {
  final n = tri.normal;
  if (n.z.abs() > 0.97) return; // горизонтальные стёкла не нужны
  // UV-оси: u — горизонтально вдоль стекла, v — вертикально (мир up).
  const up = Vec3(0, 0, 1);
  var uAxis = up.cross(n);
  if (uAxis.length < 1e-3) return;
  uAxis = uAxis.normalized;

  double uOf(Vec3 p) => p.x * uAxis.x + p.y * uAxis.y + p.z * uAxis.z;
  double vOf(Vec3 p) => p.z; // мир «вверх»

  final uA = uOf(tri.a), vA = vOf(tri.a);
  final uB = uOf(tri.b), vB = vOf(tri.b);
  final uC = uOf(tri.c), vC = vOf(tri.c);

  final det = (uB - uA) * (vC - vA) - (vB - vA) * (uC - uA);
  if (det.abs() < 1e-9) return;
  final invDet = 1.0 / det;
  final dxB = sb.dx - sa.dx, dxC = sc.dx - sa.dx;
  final dyB = sb.dy - sa.dy, dyC = sc.dy - sa.dy;
  final mxU = (dxB * (vC - vA) - dxC * (vB - vA)) * invDet;
  final mxV = ((uB - uA) * dxC - (uC - uA) * dxB) * invDet;
  final mxC0 = sa.dx - mxU * uA - mxV * vA;
  final myU = (dyB * (vC - vA) - dyC * (vB - vA)) * invDet;
  final myV = ((uB - uA) * dyC - (uC - uA) * dyB) * invDet;
  final myC0 = sa.dy - myU * uA - myV * vA;

  // Сборка градиента в локальном UV-пространстве:
  //   (u, v_min) — низ стекла, (u, v_max) — верх стекла.
  final vMin = math.min(vA, math.min(vB, vC));
  final vMax = math.max(vA, math.max(vB, vC));
  // Берём начало и конец градиента в screen-coords.
  final uMid = (uA + uB + uC) / 3;
  final topPx =
      ui.Offset(mxU * uMid + mxV * vMax + mxC0, myU * uMid + myV * vMax + myC0);
  final botPx =
      ui.Offset(mxU * uMid + mxV * vMin + mxC0, myU * uMid + myV * vMin + myC0);

  final triPath = Path()
    ..moveTo(sa.dx, sa.dy)
    ..lineTo(sb.dx, sb.dy)
    ..lineTo(sc.dx, sc.dy)
    ..close();

  // Градиент: сверху небо, в середине — нейтральная подсветка стекла,
  // снизу — отражение земли/здания (тёплый тёмно-серый).
  final shader = ui.Gradient.linear(
    topPx,
    botPx,
    const [
      Color(0xCCB0CADC), // ~70% небесно-голубой
      Color(0x66A3B7C5), // лёгкий полупрозрачный полу-тон
      Color(0xAA3B423E), // тёмное «отражение земли»
    ],
    const [0.0, 0.55, 1.0],
  );
  final paint = Paint()
    ..shader = shader
    ..isAntiAlias = true;
  canvas.save();
  canvas.clipPath(triPath);
  canvas.drawPath(triPath, paint);

  // Диагональный блик — имитация отражения солнца. Идёт под 30°
  // в screen-space; полупрозрачный белый.
  final cx = (sa.dx + sb.dx + sc.dx) / 3;
  final cy = (sa.dy + sb.dy + sc.dy) / 3;
  final span =
      ((sa - sb).distance + (sb - sc).distance + (sa - sc).distance) / 3;
  final glare = Paint()
    ..isAntiAlias = true
    ..color = const Color(0x33FFFFFF)
    ..strokeWidth = math.max(2, span * 0.08)
    ..style = PaintingStyle.stroke;
  final dxg = math.cos(0.5);
  final dyg = math.sin(0.5);
  canvas.drawLine(
    ui.Offset(cx - dxg * span, cy - dyg * span),
    ui.Offset(cx + dxg * span, cy + dyg * span),
    glare,
  );

  // Переплёт окна. Импосты — в мировом UV, толщина 4 см → 1.5 px минимум.
  ui.Offset apply(double u, double v) =>
      ui.Offset(mxU * u + mxV * v + mxC0, myU * u + myV * v + myC0);
  final uMin = math.min(uA, math.min(uB, uC));
  final uMax = math.max(uA, math.max(uB, uC));
  final pxPerMeterU = math.sqrt(mxU * mxU + myU * myU);
  final pxPerMeterV = math.sqrt(mxV * mxV + myV * myV);
  final pxPerM = math.min(pxPerMeterU, pxPerMeterV);
  final mullionPx = math.max(1.5, 0.04 * pxPerM);
  final framePx = math.max(2.0, 0.06 * pxPerM);

  final mullionPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..color = const Color(0xFF2A2A28)
    ..strokeWidth = mullionPx;
  final framePaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..color = const Color(0xFF1B1B19)
    ..strokeWidth = framePx;

  // Адаптивный split: 2×2 для близких к квадрату, 1×2 для высоких,
  // 2×1 для широких — это соответствует реальной разбивке окон по ГОСТ.
  final uW = uMax - uMin;
  final vH = vMax - vMin;
  // Импост посередине u, если ширина не сильно меньше высоты.
  if (uW > vH * 0.6) {
    final uMid2 = (uMin + uMax) / 2;
    canvas.drawLine(apply(uMid2, vMin), apply(uMid2, vMax), mullionPaint);
  }
  // Импост посередине v, если высота не сильно меньше ширины.
  if (vH > uW * 0.6) {
    final vMid2 = (vMin + vMax) / 2;
    canvas.drawLine(apply(uMin, vMid2), apply(uMax, vMid2), mullionPaint);
  }

  // Рама по периметру окна (тонкая чёрная обводка). Внутренние ребра
  // треугольника не рисуем (только наружные UV-границы окна), поэтому
  // рисуем 4 отрезка периметра — clipPath обрежет лишнее.
  canvas.drawLine(apply(uMin, vMin), apply(uMax, vMin), framePaint);
  canvas.drawLine(apply(uMax, vMin), apply(uMax, vMax), framePaint);
  canvas.drawLine(apply(uMax, vMax), apply(uMin, vMax), framePaint);
  canvas.drawLine(apply(uMin, vMax), apply(uMin, vMin), framePaint);

  canvas.restore();
}

/// Рисует филёнки и дверную ручку на дверном полотне. Дверь
/// представляется как прямоугольник в UV-координатах стены:
///   • рамка по периметру (тёмная, толщина ~5 см)
///   • вертикальное разделение на 2 «филёнки» с лёгкими
///     теневыми кромками вокруг каждой
///   • ручка-кружок на правой створке на высоте ~1.0 м
/// Всё привязано к мировым координатам стены, поэтому при вращении
/// филёнки и ручка остаются на своих местах.
void _paintDoorPanels(
  Canvas canvas,
  RenderTri tri,
  ui.Offset sa,
  ui.Offset sb,
  ui.Offset sc,
  Color3 shaded,
) {
  final n = tri.normal;
  if (n.z.abs() > 0.05) return; // только вертикальные двери
  // UV: u — горизонтально, v — вверх (мир Z).
  const up = Vec3(0, 0, 1);
  var uAxis = up.cross(n);
  if (uAxis.length < 1e-3) return;
  uAxis = uAxis.normalized;

  double uOf(Vec3 p) => p.x * uAxis.x + p.y * uAxis.y + p.z * uAxis.z;
  double vOf(Vec3 p) => p.z;

  final uA = uOf(tri.a), vA = vOf(tri.a);
  final uB = uOf(tri.b), vB = vOf(tri.b);
  final uC = uOf(tri.c), vC = vOf(tri.c);

  final det = (uB - uA) * (vC - vA) - (vB - vA) * (uC - uA);
  if (det.abs() < 1e-9) return;
  final invDet = 1.0 / det;
  final dxB = sb.dx - sa.dx, dxC = sc.dx - sa.dx;
  final dyB = sb.dy - sa.dy, dyC = sc.dy - sa.dy;
  final mxU = (dxB * (vC - vA) - dxC * (vB - vA)) * invDet;
  final mxV = ((uB - uA) * dxC - (uC - uA) * dxB) * invDet;
  final mxC0 = sa.dx - mxU * uA - mxV * vA;
  final myU = (dyB * (vC - vA) - dyC * (vB - vA)) * invDet;
  final myV = ((uB - uA) * dyC - (uC - uA) * dyB) * invDet;
  final myC0 = sa.dy - myU * uA - myV * vA;

  ui.Offset apply(double u, double v) =>
      ui.Offset(mxU * u + mxV * v + mxC0, myU * u + myV * v + myC0);

  final pxPerMeterU = math.sqrt(mxU * mxU + myU * myU);
  final pxPerMeterV = math.sqrt(mxV * mxV + myV * myV);
  final pxPerM = math.min(pxPerMeterU, pxPerMeterV);

  final uMin = math.min(uA, math.min(uB, uC));
  final uMax = math.max(uA, math.max(uB, uC));
  final vMin = math.min(vA, math.min(vB, vC));
  final vMax = math.max(vA, math.max(vB, vC));

  final triPath = Path()
    ..moveTo(sa.dx, sa.dy)
    ..lineTo(sb.dx, sb.dy)
    ..lineTo(sc.dx, sc.dy)
    ..close();
  canvas.save();
  canvas.clipPath(triPath);

  // Базовая древесная вариация — лёгкие горизонтальные «волокна».
  // Дают намёк на текстуру массива.
  const grainCount = 6;
  final grainPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.6, 0.005 * pxPerM)
    ..color = ui.Color.fromRGBO(
        ((shaded.r * 0.7) * 255).round(),
        ((shaded.g * 0.65) * 255).round(),
        ((shaded.b * 0.55) * 255).round(),
        0.4);
  for (var i = 0; i < grainCount; i++) {
    final v = vMin + (vMax - vMin) * (i + 0.5) / grainCount;
    canvas.drawLine(apply(uMin, v), apply(uMax, v), grainPaint);
  }

  // Тёмная рамка-косяк по периметру двери (~6 см).
  final framePx = math.max(2.0, 0.06 * pxPerM);
  final framePaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..color = const Color(0xFF231510)
    ..strokeWidth = framePx;
  canvas.drawLine(apply(uMin, vMin), apply(uMax, vMin), framePaint);
  canvas.drawLine(apply(uMax, vMin), apply(uMax, vMax), framePaint);
  canvas.drawLine(apply(uMax, vMax), apply(uMin, vMax), framePaint);
  canvas.drawLine(apply(uMin, vMax), apply(uMin, vMin), framePaint);

  // Две вертикальные филёнки. Отступы по 12 см от боковых рам и
  // 18 см сверху/снизу, между филёнками — 8 см.
  const inset = 0.12;
  const topInset = 0.18;
  const gap = 0.08;
  final innerUMin = uMin + inset;
  final innerUMax = uMax - inset;
  final innerVMin = vMin + topInset;
  final innerVMax = vMax - topInset;
  final mid = (innerUMin + innerUMax) / 2;
  final leftR = (innerUMin, mid - gap / 2);
  final rightR = (mid + gap / 2, innerUMax);

  final panelStrokePx = math.max(1.0, 0.015 * pxPerM);
  final panelDark = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = panelStrokePx
    ..color = const Color(0x99000000);
  final panelLight = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = panelStrokePx
    ..color = const Color(0x66FFFFFF);

  void drawPanel(double u0, double u1, double v0, double v1) {
    // Внешняя рамка филёнки (тёмная) + внутренний инсет 2 см (светлый
    // блик, имитирует фрезерованную фаску).
    final corners = [
      apply(u0, v0),
      apply(u1, v0),
      apply(u1, v1),
      apply(u0, v1),
    ];
    final outer = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();
    canvas.drawPath(outer, panelDark);
    // Внутренний контур — фасочный блик (свет сверху-слева).
    const fillet = 0.022;
    canvas.drawLine(
      apply(u0 + fillet, v1 - fillet),
      apply(u1 - fillet, v1 - fillet),
      panelLight,
    );
    canvas.drawLine(
      apply(u0 + fillet, v1 - fillet),
      apply(u0 + fillet, v0 + fillet),
      panelLight,
    );
    // И тень снизу-справа (тёмная фаска) — повторяем тёмной краской.
    canvas.drawLine(
      apply(u1 - fillet, v0 + fillet),
      apply(u1 - fillet, v1 - fillet),
      panelDark,
    );
    canvas.drawLine(
      apply(u0 + fillet, v0 + fillet),
      apply(u1 - fillet, v0 + fillet),
      panelDark,
    );
  }

  drawPanel(leftR.$1, leftR.$2, innerVMin, innerVMax);
  drawPanel(rightR.$1, rightR.$2, innerVMin, innerVMax);

  // Дверная ручка на правой створке: круг диаметром ~6 см на высоте
  // 1.0 м над низом двери, 8 см от середины двери.
  final handleU = mid + gap / 2 + 0.08;
  final handleV = vMin + 1.0;
  final handleCenter = apply(handleU, handleV);
  final handleR = math.max(1.5, 0.025 * pxPerM);
  // Тень-подложка (смещение вниз-вправо).
  canvas.drawCircle(
    ui.Offset(handleCenter.dx + 1.0, handleCenter.dy + 1.0),
    handleR,
    Paint()
      ..isAntiAlias = true
      ..color = const Color(0x66000000),
  );
  // Тело ручки — бронзовое.
  canvas.drawCircle(
    handleCenter,
    handleR,
    Paint()
      ..isAntiAlias = true
      ..color = const Color(0xFFC8A26D),
  );
  // Блик-точка в верхней части ручки.
  canvas.drawCircle(
    ui.Offset(handleCenter.dx - handleR * 0.3, handleCenter.dy - handleR * 0.3),
    handleR * 0.4,
    Paint()
      ..isAntiAlias = true
      ..color = const Color(0xCCFFE9C8),
  );

  canvas.restore();
}

/// Цокольный карниз — горизонтальная декоративная полоса 12 см
/// над верхом фундамента. Состоит из двух частей:
///   • верхняя кромка ~2 см — светлая, имитирует отлив,
///   • основная полоса ~10 см — чуть темнее стены, с лёгкой тенью.
/// Полоса рисуется только если плоскость треугольника пересекает
/// диапазон [plinthTopZ ; plinthTopZ + 0.12].
void _paintPlinthCornice(
  Canvas canvas,
  RenderTri tri,
  ui.Offset sa,
  ui.Offset sb,
  ui.Offset sc, {
  required double plinthTopZ,
}) {
  if (plinthTopZ <= 0.01) return;
  final n = tri.normal;
  if (n.z.abs() > 0.05) return;
  final minZ = math.min(tri.a.z, math.min(tri.b.z, tri.c.z));
  final maxZ = math.max(tri.a.z, math.max(tri.b.z, tri.c.z));
  // Нет пересечения — пропускаем.
  if (maxZ < plinthTopZ - 0.05 || minZ > plinthTopZ + 0.16) return;

  // Аффинная UV→screen.
  const up = Vec3(0, 0, 1);
  var uAxis = up.cross(n);
  if (uAxis.length < 1e-3) return;
  uAxis = uAxis.normalized;
  double uOf(Vec3 p) => p.x * uAxis.x + p.y * uAxis.y + p.z * uAxis.z;
  double vOf(Vec3 p) => p.z;
  final uA = uOf(tri.a), vA = vOf(tri.a);
  final uB = uOf(tri.b), vB = vOf(tri.b);
  final uC = uOf(tri.c), vC = vOf(tri.c);
  final det = (uB - uA) * (vC - vA) - (vB - vA) * (uC - uA);
  if (det.abs() < 1e-9) return;
  final invDet = 1.0 / det;
  final dxB = sb.dx - sa.dx, dxC = sc.dx - sa.dx;
  final dyB = sb.dy - sa.dy, dyC = sc.dy - sa.dy;
  final mxU = (dxB * (vC - vA) - dxC * (vB - vA)) * invDet;
  final mxV = ((uB - uA) * dxC - (uC - uA) * dxB) * invDet;
  final mxC0 = sa.dx - mxU * uA - mxV * vA;
  final myU = (dyB * (vC - vA) - dyC * (vB - vA)) * invDet;
  final myV = ((uB - uA) * dyC - (uC - uA) * dyB) * invDet;
  final myC0 = sa.dy - myU * uA - myV * vA;

  ui.Offset apply(double u, double v) =>
      ui.Offset(mxU * u + mxV * v + mxC0, myU * u + myV * v + myC0);

  final uMin = math.min(uA, math.min(uB, uC));
  final uMax = math.max(uA, math.max(uB, uC));

  final triPath = Path()
    ..moveTo(sa.dx, sa.dy)
    ..lineTo(sb.dx, sb.dy)
    ..lineTo(sc.dx, sc.dy)
    ..close();
  canvas.save();
  canvas.clipPath(triPath);

  final corniceBottom = plinthTopZ;
  final corniceTop = plinthTopZ + 0.12;
  final flashTop = corniceTop + 0.02;

  // 1) Основная полоса — тёмно-серый с лёгкой тенью снизу.
  final mainPath = Path()
    ..moveTo(apply(uMin - 0.5, corniceBottom).dx,
        apply(uMin - 0.5, corniceBottom).dy)
    ..lineTo(apply(uMax + 0.5, corniceBottom).dx,
        apply(uMax + 0.5, corniceBottom).dy)
    ..lineTo(apply(uMax + 0.5, corniceTop).dx,
        apply(uMax + 0.5, corniceTop).dy)
    ..lineTo(apply(uMin - 0.5, corniceTop).dx,
        apply(uMin - 0.5, corniceTop).dy)
    ..close();
  canvas.drawPath(
    mainPath,
    Paint()
      ..isAntiAlias = true
      ..color = const Color(0x44241A14),
  );

  // 2) Светлая верхняя кромка-«отлив».
  final flashPath = Path()
    ..moveTo(apply(uMin - 0.5, corniceTop).dx,
        apply(uMin - 0.5, corniceTop).dy)
    ..lineTo(apply(uMax + 0.5, corniceTop).dx,
        apply(uMax + 0.5, corniceTop).dy)
    ..lineTo(apply(uMax + 0.5, flashTop).dx, apply(uMax + 0.5, flashTop).dy)
    ..lineTo(apply(uMin - 0.5, flashTop).dx, apply(uMin - 0.5, flashTop).dy)
    ..close();
  canvas.drawPath(
    flashPath,
    Paint()
      ..isAntiAlias = true
      ..color = const Color(0x88E4DBC8),
  );

  canvas.restore();
}

/// Тень от примыкающих пристроек (крыльцо/терраса) на стене дома.
/// Не точный shadow-map, а упрощённая аппроксимация: на стене
/// рисуется горизонтальный градиент-darkening сверху от высоты
/// пристройки (длина 0.6 м), если u-координата стены пересекается
/// с проекцией пристройки на ось этой стены.
void _paintAttachmentWallShadow(
  Canvas canvas,
  RenderTri tri,
  ui.Offset sa,
  ui.Offset sb,
  ui.Offset sc,
  Building3D model,
) {
  if (model.attachments.isEmpty) return;
  final n = tri.normal;
  if (n.z.abs() > 0.05) return;
  // Уровень верха фундамента (откуда стартует стена).
  final wallBase = model.foundation.plinthHeightM;
  final minZ = math.min(tri.a.z, math.min(tri.b.z, tri.c.z));
  final maxZ = math.max(tri.a.z, math.max(tri.b.z, tri.c.z));

  // UV: u — горизонтально вдоль стены, v — вверх.
  const up = Vec3(0, 0, 1);
  var uAxis = up.cross(n);
  if (uAxis.length < 1e-3) return;
  uAxis = uAxis.normalized;
  double uOf3(Vec3 p) => p.x * uAxis.x + p.y * uAxis.y + p.z * uAxis.z;
  // 2D-проекция точки на ось стены (плоскости стены: точка x*n_x+y*n_y=d).
  // Расстояние от точки до плоскости стены.
  final wallDist = tri.a.x * n.x + tri.a.y * n.y;
  double sideOf(Vec3 p) => p.x * n.x + p.y * n.y - wallDist;

  final uA = uOf3(tri.a), vA = tri.a.z;
  final uB = uOf3(tri.b), vB = tri.b.z;
  final uC = uOf3(tri.c), vC = tri.c.z;
  final det = (uB - uA) * (vC - vA) - (vB - vA) * (uC - uA);
  if (det.abs() < 1e-9) return;
  final invDet = 1.0 / det;
  final dxB = sb.dx - sa.dx, dxC = sc.dx - sa.dx;
  final dyB = sb.dy - sa.dy, dyC = sc.dy - sa.dy;
  final mxU = (dxB * (vC - vA) - dxC * (vB - vA)) * invDet;
  final mxV = ((uB - uA) * dxC - (uC - uA) * dxB) * invDet;
  final mxC0 = sa.dx - mxU * uA - mxV * vA;
  final myU = (dyB * (vC - vA) - dyC * (vB - vA)) * invDet;
  final myV = ((uB - uA) * dyC - (uC - uA) * dyB) * invDet;
  final myC0 = sa.dy - myU * uA - myV * vA;
  ui.Offset apply(double u, double v) =>
      ui.Offset(mxU * u + mxV * v + mxC0, myU * u + myV * v + myC0);

  final uMinT = math.min(uA, math.min(uB, uC));
  final uMaxT = math.max(uA, math.max(uB, uC));

  final triPath = Path()
    ..moveTo(sa.dx, sa.dy)
    ..lineTo(sb.dx, sb.dy)
    ..lineTo(sc.dx, sc.dy)
    ..close();
  canvas.save();
  canvas.clipPath(triPath);

  for (final att in model.attachments) {
    if (att.outline.length < 3) continue;
    // Проверяем, примыкает ли пристройка к этой стене:
    //   sideOf(p) ~ 0 для рёбер пристройки, лежащих на плоскости стены.
    // Берём u-диапазон тех вершин, у которых sideOf близко к 0.
    final attUs = <double>[];
    for (final p in att.outline) {
      final side = sideOf(p);
      if (side.abs() < 0.10) {
        attUs.add(uOf3(p));
      }
    }
    if (attUs.length < 2) continue;
    final attUMin = attUs.reduce(math.min);
    final attUMax = attUs.reduce(math.max);
    // Пересечение с диапазоном треугольника.
    final intLo = math.max(uMinT, attUMin);
    final intHi = math.min(uMaxT, attUMax);
    if (intLo >= intHi) continue;
    // Высота пристройки относительно нуля стены.
    final attTopZ = att.heightM;
    final shadowTopZ = attTopZ + 0.6;
    if (shadowTopZ < minZ || attTopZ > maxZ) continue;
    final v0 = math.max(attTopZ, wallBase);
    final v1 = math.min(shadowTopZ, maxZ);
    if (v1 <= v0) continue;

    // Полоса в UV: [intLo..intHi] × [v0..v1] — градиент сверху прозрачный,
    // снизу темнее, имитация AO от верхней кромки пристройки.
    final p1 = apply(intLo, v0);
    final p2 = apply(intHi, v0);
    final p3 = apply(intHi, v1);
    final p4 = apply(intLo, v1);
    final stripPath = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();
    final uMidStrip = (intLo + intHi) / 2;
    final shader = ui.Gradient.linear(
      apply(uMidStrip, v0),
      apply(uMidStrip, v1),
      const [Color(0x55000000), Color(0x00000000)],
    );
    canvas.drawPath(stripPath, Paint()..shader = shader);
  }

  canvas.restore();
}

/// Стадия 1 — детализированное окружение здания: травяная земля
/// 36×36 м с тысячами процедурных мазков-травинок, патчами разного
/// оттенка зелёного, бур-бурой полосой возле фундамента и грунтовой
/// дорожкой к фасаду. Все элементы закреплены в мировых координатах,
/// поэтому остаются на местах при вращении камеры.
///
/// Производительность: вместо одного `drawLine` на каждую травинку
/// (~10K вызовов) аккумулируем все травинки одного оттенка в один
/// [Path] и отдаём 4 батчевых [Canvas.drawPath]. Мировой → экран
/// предсчитан как линейная трансформация (3 опорных точки), а не
/// per-blade `renderer.project`.
void _paintGroundEnvironment(
  Canvas canvas,
  Building3D model,
  Building3DRenderer renderer,
  Camera3D camera,
  Size size,
  ui.Offset Function(Projected2D) toScreen, {
  WeatherMode weather = WeatherMode.summer,
}) {
  final cxW = model.footprintWidth / 2;
  final cyW = model.footprintLength / 2;
  const halfSpan = 18.0; // ground 36×36 m

  // Опорные точки для линейной трансформации (XYZ)→screen.
  // По 4 точкам строим коэффициенты:
  //   sx = ax·X + bx·Y + cx·Z + d
  //   sy = ay·X + by·Y + cy·Z + e
  ui.Offset proj(double X, double Y, double Z) =>
      toScreen(renderer.project(Vec3(X, Y, Z), camera, size.width, size.height));

  final s00 = proj(cxW - halfSpan, cyW - halfSpan, 0);
  final sX0 = proj(cxW + halfSpan, cyW - halfSpan, 0);
  final s0Y = proj(cxW - halfSpan, cyW + halfSpan, 0);
  final s00Z1 = proj(cxW - halfSpan, cyW - halfSpan, 1);

  const span = 2 * halfSpan;
  final ax = (sX0.dx - s00.dx) / span;
  final bx = (s0Y.dx - s00.dx) / span;
  final cz = (s00Z1.dx - s00.dx);
  final dX = s00.dx - ax * (cxW - halfSpan) - bx * (cyW - halfSpan);

  final ay = (sX0.dy - s00.dy) / span;
  final by = (s0Y.dy - s00.dy) / span;
  final cz2 = (s00Z1.dy - s00.dy);
  final dY = s00.dy - ay * (cxW - halfSpan) - by * (cyW - halfSpan);

  ui.Offset xy(double X, double Y) =>
      ui.Offset(ax * X + bx * Y + dX, ay * X + by * Y + dY);
  ui.Offset xyz(double X, double Y, double Z) => ui.Offset(
        ax * X + bx * Y + cz * Z + dX,
        ay * X + by * Y + cz2 * Z + dY,
      );

  // Полигон-«рамка» земли (большой квадрат 36×36 м).
  final groundPath = Path()
    ..moveTo(s00.dx, s00.dy)
    ..lineTo(sX0.dx, sX0.dy)
    ..lineTo(xy(cxW + halfSpan, cyW + halfSpan).dx,
        xy(cxW + halfSpan, cyW + halfSpan).dy)
    ..lineTo(s0Y.dx, s0Y.dy)
    ..close();

  canvas.save();
  canvas.clipPath(groundPath);

  // 1) Базовая радиальная заливка: светло-травянистая в центре,
  //    темнее на краях — даёт ощущение «глубины» сцены.
  //    Зимой — снег. Ночью — притемнённая зелень.
  final centerScreen = xy(cxW, cyW);
  final cornerDist = (s00 - centerScreen).distance;
  final List<Color> baseColors;
  switch (weather) {
    case WeatherMode.summer:
      baseColors = const [
        Color(0xFF8DAB60),
        Color(0xFF6F8E48),
        Color(0xFF526F38),
      ];
      break;
    case WeatherMode.winter:
      baseColors = const [
        Color(0xFFEDF2F4), // ярко-белый снег у центра
        Color(0xFFD4DCE2),
        Color(0xFFB1BCC5), // голубоватая тень снега у горизонта
      ];
      break;
    case WeatherMode.night:
      baseColors = const [
        Color(0xFF2E3F2A),
        Color(0xFF1F2C1B),
        Color(0xFF131A12),
      ];
      break;
  }
  final baseShader = ui.Gradient.radial(
    centerScreen,
    cornerDist * 0.95,
    baseColors,
    const [0.0, 0.55, 1.0],
  );
  canvas.drawPath(
    groundPath,
    Paint()
      ..shader = baseShader
      ..isAntiAlias = true,
  );

  // 2) Многоцветные пятна-«кочки» — эллипсы 1.0…2.5 м разных оттенков
  //    с альфой 0x33, разбросанные по сетке 3 м.
  int hash(int i, int j, int salt) =>
      ((i * 73856093) ^ (j * 19349663) ^ salt) & 0x7FFFFFFF;
  const patchTones = [
    Color(0x33304820),
    Color(0x335B7A38),
    Color(0x33A8B670),
    Color(0x33425F30),
    Color(0x336F8F45),
  ];
  for (var i = -7; i <= 7; i++) {
    for (var j = -7; j <= 7; j++) {
      final h = hash(i, j, 0xA13F9C);
      if ((h % 4) != 0) continue; // ~25 % ячеек получает пятно
      final jx = ((h >> 8) & 0xFFF) / 4096.0 - 0.5;
      final jy = ((h >> 20) & 0xFFF) / 4096.0 - 0.5;
      final px = cxW + i * 3.0 + jx * 2.5;
      final py = cyW + j * 3.0 + jy * 2.5;
      final wM = 1.0 + ((h >> 4) & 0xF) / 15.0 * 1.5;
      final hM = wM * (0.5 + ((h >> 16) & 0xF) / 30.0);
      final tone = patchTones[h % patchTones.length];
      // Ширину/высоту пятна берём в screen-пикселях через
      // линейную трансформацию (соответствует ракурсу камеры).
      final c = xy(px, py);
      final wPx = (ax.abs() * wM + bx.abs() * hM);
      final hPx = (ay.abs() * wM + by.abs() * hM);
      canvas.drawOval(
        ui.Rect.fromCenter(center: c, width: wPx, height: hPx),
        Paint()
          ..color = tone
          ..isAntiAlias = true,
      );
    }
  }

  // 3) Бур-бурая полоса земли вокруг фундамента (≈0.7 м шириной).
  //    Рисуется как разница расширенного и оригинального outline.
  final outline = model.foundation.outline;
  if (outline.length >= 3) {
    var ox = 0.0, oy = 0.0;
    for (final p in outline) {
      ox += p.x;
      oy += p.y;
    }
    ox /= outline.length;
    oy /= outline.length;

    Path outlineToPath(List<Vec3> pts) {
      final p = Path();
      for (var k = 0; k < pts.length; k++) {
        final s = xy(pts[k].x, pts[k].y);
        if (k == 0) {
          p.moveTo(s.dx, s.dy);
        } else {
          p.lineTo(s.dx, s.dy);
        }
      }
      p.close();
      return p;
    }

    // Расширяем каждую точку outline радиально от центра на 0.7 м.
    const ringWidth = 0.7;
    final outerPts = <Vec3>[];
    for (final p in outline) {
      final dx = p.x - ox;
      final dy = p.y - oy;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d < 1e-6) {
        outerPts.add(p);
      } else {
        final scale = (d + ringWidth) / d;
        outerPts.add(Vec3(ox + dx * scale, oy + dy * scale, 0));
      }
    }
    final outerPath = outlineToPath(outerPts);
    final innerPath = outlineToPath(outline);
    final ring = Path.combine(PathOperation.difference, outerPath, innerPath);

    // Сама заливка — буроватая земля с лёгким текстурным шумом
    // (мелкие тёмные точки, имитация камешков).
    canvas.drawPath(
      ring,
      Paint()
        ..color = const Color(0xFF8B6F4E)
        ..isAntiAlias = true,
    );
    // Текстура: ~150 мелких тёмно-коричневых точек вдоль кольца.
    canvas.save();
    canvas.clipPath(ring);
    final pebblePaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF604224);
    for (var i = 0; i < 200; i++) {
      final hh = hash(i, 0, 0x77B5E5);
      // Сэмплируем точки в bbox outline + ring.
      final t = ((hh & 0xFFFF) / 0xFFFF) * 2 * math.pi;
      final r = 0.05 + ((hh >> 16) & 0xFF) / 255.0 * 0.6;
      final cx0 = ox + math.cos(t) * (r + _offsetForHash(hh)); // see below
      final cy0 = oy + math.sin(t) * (r + _offsetForHash(hh));
      final s = xy(cx0, cy0);
      canvas.drawCircle(s, 0.6 + (hh & 0x3) * 0.4, pebblePaint);
    }
    canvas.restore();
  }

  // 4) Грунтовая дорожка от лицевой стороны здания к границе участка.
  //    Идёт по -Y от середины ближайшего к -Y ребра outline.
  if (outline.length >= 3) {
    var frontI = 0;
    var frontMy = double.infinity;
    for (var i = 0; i < outline.length; i++) {
      final j = (i + 1) % outline.length;
      final my = (outline[i].y + outline[j].y) / 2;
      if (my < frontMy) {
        frontMy = my;
        frontI = i;
      }
    }
    final fa = outline[frontI];
    final fb = outline[(frontI + 1) % outline.length];
    final fmx = (fa.x + fb.x) / 2;
    final fmy = (fa.y + fb.y) / 2;
    const walkHalfW = 0.45;
    final walkLeft = fmx - walkHalfW;
    final walkRight = fmx + walkHalfW;
    final walkTop = fmy - 0.4;
    final walkBot = cyW - halfSpan + 0.5;
    final walkPath = Path()
      ..moveTo(xy(walkLeft, walkTop).dx, xy(walkLeft, walkTop).dy)
      ..lineTo(xy(walkRight, walkTop).dx, xy(walkRight, walkTop).dy)
      ..lineTo(xy(walkRight, walkBot).dx, xy(walkRight, walkBot).dy)
      ..lineTo(xy(walkLeft, walkBot).dx, xy(walkLeft, walkBot).dy)
      ..close();
    canvas.drawPath(
      walkPath,
      Paint()
        ..color = const Color(0xFFB1936F)
        ..isAntiAlias = true,
    );
    // Текстура дорожки: тёмные поперечные штрихи (имитация
    // колеи/ступаний). Кладём в clip walkPath.
    canvas.save();
    canvas.clipPath(walkPath);
    final stripePaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFF8E6C46);
    final lengthM = (walkTop - walkBot).abs();
    final nStripes = (lengthM / 0.30).ceil();
    for (var k = 0; k < nStripes; k++) {
      final yK = walkTop - k * 0.30;
      final xL = walkLeft + ((hash(k, 0, 0xC0FFEE) & 0xF) / 15.0 - 0.5) * 0.10;
      final xR = walkRight + ((hash(k, 0, 0xBADDAD) & 0xF) / 15.0 - 0.5) * 0.10;
      canvas.drawLine(xy(xL, yK), xy(xR, yK), stripePaint);
    }
    canvas.restore();
  }

  // 5) Травинки/снежные крошки. Сетка 0.55 × 0.55 м, в каждой ячейке
  //    1…3 элемента с псевдослучайной позицией, наклоном, длиной и
  //    оттенком. Все одного тона аккумулируются в один Path и
  //    рисуются одним drawPath — это избавляет от тысяч вызовов
  //    drawLine. Зимой травинки заменяются на короткие
  //    снежные «искры», ночью трава притемняется.
  final outlineMinX = outline.isEmpty
      ? double.infinity
      : outline.map((p) => p.x).reduce(math.min) - 0.7;
  final outlineMaxX = outline.isEmpty
      ? -double.infinity
      : outline.map((p) => p.x).reduce(math.max) + 0.7;
  final outlineMinY = outline.isEmpty
      ? double.infinity
      : outline.map((p) => p.y).reduce(math.min) - 0.7;
  final outlineMaxY = outline.isEmpty
      ? -double.infinity
      : outline.map((p) => p.y).reduce(math.max) + 0.7;
  bool inEarthRing(double X, double Y) =>
      X >= outlineMinX &&
      X <= outlineMaxX &&
      Y >= outlineMinY &&
      Y <= outlineMaxY;

  const cellM = 0.55;
  final iMin = ((cxW - halfSpan) / cellM).floor();
  final iMax = ((cxW + halfSpan) / cellM).ceil();
  final jMin = ((cyW - halfSpan) / cellM).floor();
  final jMax = ((cyW + halfSpan) / cellM).ceil();
  // Тоны зависят от пресета:
  //   summer — обычные оттенки травы;
  //   winter — белые/голубоватые снежные искры;
  //   night  — притемнённая трава (~×0.4).
  final tones = switch (weather) {
    WeatherMode.summer => const [
        Color(0xFF6F8F45),
        Color(0xFF8AAD56),
        Color(0xFF537037),
        Color(0xFFA1BC60),
      ],
    WeatherMode.winter => const [
        Color(0xFFFFFFFF),
        Color(0xFFE6EEF2),
        Color(0xFFD0DAE0),
        Color(0xFFFAFBFE),
      ],
    WeatherMode.night => const [
        Color(0xFF2C3D1B),
        Color(0xFF374923),
        Color(0xFF223115),
        Color(0xFF445B2A),
      ],
  };
  final paths = List.generate(tones.length, (_) => Path());
  for (var i = iMin; i <= iMax; i++) {
    for (var j = jMin; j <= jMax; j++) {
      final cellX = i * cellM;
      final cellY = j * cellM;
      if (inEarthRing(cellX, cellY)) continue;
      // Если ячейка попадает на дорожку, тоже скипаем.
      // (Грубое приближение — допустим небольшое перекрытие).
      final hh = hash(i, j, 0xA1B2C3);
      final nBlades = 1 + ((hh >> 28) & 0x3); // 1..4
      for (var k = 0; k < nBlades; k++) {
        final hk = (hh >> (k * 4)) & 0xFFFF;
        final jx = (hk & 0xFF) / 255.0 - 0.5;
        final jy = ((hk >> 8) & 0xFF) / 255.0 - 0.5;
        final bx0 = cellX + jx * cellM;
        final by0 = cellY + jy * cellM;
        final bH = 0.06 + (hk & 0xF) / 15.0 * 0.10; // 0.06..0.16 м
        final tilt = (((hh >> (12 + k * 2)) & 0xF) / 15.0 - 0.5) * 0.06;
        final tilt2 = (((hh >> (8 + k * 3)) & 0xF) / 15.0 - 0.5) * 0.06;
        final base = xy(bx0, by0);
        final tip = xyz(bx0 + tilt, by0 + tilt2, bH);
        final tone = (hh >> 24) % tones.length;
        paths[tone].moveTo(base.dx, base.dy);
        paths[tone].lineTo(tip.dx, tip.dy);
      }
    }
  }
  for (var t = 0; t < tones.length; t++) {
    canvas.drawPath(
      paths[t],
      Paint()
        ..color = tones[t]
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.0,
    );
  }

  // 6) Редкие цветочки/одуванчики — мелкие жёлтые точки в случайных
  //    местах поверх травы. ~30-40 штук. Зимой не рисуем.
  if (weather != WeatherMode.winter) {
    final flowerPaint = Paint()
      ..isAntiAlias = true
      ..color = weather == WeatherMode.night
          ? const Color(0xFF8B7E33)
          : const Color(0xFFF7D85C);
    for (var i = 0; i < 60; i++) {
      final hh = hash(i, i * 7, 0xF10C72);
      final fx = cxW - halfSpan +
          ((hh & 0xFFFF) / 0xFFFF) * (halfSpan * 2);
      final fy = cyW - halfSpan +
          (((hh >> 16) & 0xFFFF) / 0xFFFF) * (halfSpan * 2);
      if (inEarthRing(fx, fy)) continue;
      final s = xy(fx, fy);
      canvas.drawCircle(s, 1.4, flowerPaint);
      canvas.drawCircle(
          s,
          0.6,
          Paint()
            ..color = weather == WeatherMode.night
                ? const Color(0xFFB8AB66)
                : const Color(0xFFFFFFFF));
    }
  }

  canvas.restore();
}

// Вспомогательная функция для разброса точек pebbles вокруг outline
// (см. блок 3 выше). Идея: добавить «случайный» отступ радиально.
double _offsetForHash(int h) => ((h >> 8) & 0xF) * 0.05;

// Стадия 2 — детализированные деревья.
//
// Каждое дерево это:
//   • ствол с фактурой коры (вертикальные тёмные/светлые штрихи),
//   • 3-5 веток, расходящихся от середины ствола под случайными углами,
//   • крона из ~80-150 «листификов»-эллипсов 3-4 оттенков зелёного,
//   • мягкая овальная тень на земле под кроной.
//
// Все дерев генерируются один раз процедурно от seed = projectName.hashCode,
// поэтому их позиции стабильны между рендерами (включая поворот камеры).

class _TreeData {
  _TreeData({
    required this.x,
    required this.y,
    required this.heightM,
    required this.foliageR,
    required this.seed,
  });
  final double x; // мировые координаты основания ствола
  final double y;
  final double heightM; // полная высота дерева, м (4-7)
  final double foliageR; // радиус кроны, м (1.2-2.2)
  final int seed; // стабильный hash для деталей кроны
}

List<_TreeData> _generateTrees(Building3D model) {
  final outline = model.foundation.outline;
  if (outline.isEmpty) return const [];
  // bbox здания в мировых координатах
  var minX = double.infinity, maxX = -double.infinity;
  var minY = double.infinity, maxY = -double.infinity;
  for (final p in outline) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  final cxW = model.footprintWidth / 2;
  final cyW = model.footprintLength / 2;

  final seedKey = model.projectName.hashCode & 0x7FFFFFFF;
  int hash(int i, int salt) =>
      ((i * 73856093) ^ (salt * 19349663) ^ seedKey) & 0x7FFFFFFF;

  final trees = <_TreeData>[];
  // Пробуем до 80 потенциальных позиций — оставляем максимум 7 деревьев
  // на разумном расстоянии друг от друга.
  for (var k = 0; k < 80 && trees.length < 7; k++) {
    final h = hash(k, 0xA1A1A1);
    final tx = cxW + (((h & 0xFFFF) / 0xFFFF) - 0.5) * 32;
    final ty = cyW + ((((h >> 16) & 0xFFFF) / 0xFFFF) - 0.5) * 32;
    // Деревья не должны заходить в здание + 1.8 м от стен.
    if (tx > minX - 1.8 &&
        tx < maxX + 1.8 &&
        ty > minY - 1.8 &&
        ty < maxY + 1.8) {
      continue;
    }
    // И не должны вылетать за границу травы (36×36).
    if ((tx - cxW).abs() > 16.5 || (ty - cyW).abs() > 16.5) continue;
    // Минимум 3.5 м от других деревьев.
    var ok = true;
    for (final t in trees) {
      final dx = t.x - tx;
      final dy = t.y - ty;
      if (dx * dx + dy * dy < 3.5 * 3.5) {
        ok = false;
        break;
      }
    }
    if (!ok) continue;
    final hh = hash(k, 0x2B2B2B);
    final treeH = 4.0 + ((hh & 0xFF) / 255.0) * 3.0; // 4-7 м
    final foR = 1.2 + (((hh >> 8) & 0xFF) / 255.0) * 1.0; // 1.2-2.2 м
    trees.add(_TreeData(
      x: tx,
      y: ty,
      heightM: treeH,
      foliageR: foR,
      seed: hh,
    ));
  }
  return trees;
}

void _paintTrees(
  Canvas canvas,
  Building3D model,
  Building3DRenderer renderer,
  Camera3D camera,
  Size size,
  ui.Offset Function(Projected2D) toScreen, {
  required List<_TreeData> trees,
  WeatherMode weather = WeatherMode.summer,
}) {
  if (trees.isEmpty) return;

  // Линейная трансформация (X,Y,Z) → screen, общая для всех деревьев.
  ui.Offset proj(double X, double Y, double Z) =>
      toScreen(renderer.project(Vec3(X, Y, Z), camera, size.width, size.height));
  // 4 опорные точки (любая позиция, лишь бы не вырожденные).
  final cxW = model.footprintWidth / 2;
  final cyW = model.footprintLength / 2;
  final s00 = proj(cxW, cyW, 0);
  final sX0 = proj(cxW + 1, cyW, 0);
  final s0Y = proj(cxW, cyW + 1, 0);
  final sZ1 = proj(cxW, cyW, 1);
  final ax = sX0.dx - s00.dx;
  final bx = s0Y.dx - s00.dx;
  final cz = sZ1.dx - s00.dx;
  final ay = sX0.dy - s00.dy;
  final by = s0Y.dy - s00.dy;
  final cz2 = sZ1.dy - s00.dy;
  final dX = s00.dx - ax * cxW - bx * cyW;
  final dY = s00.dy - ay * cxW - by * cyW;
  ui.Offset xyz(double X, double Y, double Z) => ui.Offset(
        ax * X + bx * Y + cz * Z + dX,
        ay * X + by * Y + cz2 * Z + dY,
      );

  // Сортировка деревьев back→front (внутри одного «слоя») для корректного
  // перекрытия близких друг к другу.
  final sorted = [...trees]..sort((a, b) {
      final pa =
          renderer.project(Vec3(a.x, a.y, 0), camera, size.width, size.height);
      final pb =
          renderer.project(Vec3(b.x, b.y, 0), camera, size.width, size.height);
      return pb.z.compareTo(pa.z);
    });

  for (final t in sorted) {
    _paintSingleTree(canvas, t, xyz, weather: weather);
  }
}

void _paintSingleTree(
  Canvas canvas,
  _TreeData t,
  ui.Offset Function(double, double, double) xyz, {
  WeatherMode weather = WeatherMode.summer,
}) {
  final seed = t.seed;
  int sh(int salt) =>
      ((seed * 73856093) ^ (salt * 19349663) ^ 0x5A5A5A) & 0x7FFFFFFF;

  // 1) Тень дерева на земле — мягкий чёрный эллипс с blur.
  final shadowCenterScreen = xyz(t.x + 0.4, t.y + 0.4, 0);
  final shadowRX = (xyz(t.x + t.foliageR, t.y, 0) - shadowCenterScreen).dx.abs() * 1.2;
  final shadowRY = (xyz(t.x, t.y + t.foliageR, 0) - shadowCenterScreen).dy.abs() * 1.2;
  canvas.drawOval(
    Rect.fromCenter(
      center: shadowCenterScreen,
      width: shadowRX * 2,
      height: shadowRY * 2,
    ),
    Paint()
      ..color = const Color(0x55000000)
      ..isAntiAlias = true
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
  );

  // 2) Ствол — высокий узкий прямоугольник из 3D-точек:
  //    основание (x±r, y, 0..0.05), верхушка ствола (на высоте 0.55*H).
  const trunkRBase = 0.16; // радиус ствола у основания, м
  const trunkRTop = 0.10; // у верхушки
  final trunkTopZ = t.heightM * 0.55;
  final blBase = xyz(t.x - trunkRBase, t.y, 0);
  final brBase = xyz(t.x + trunkRBase, t.y, 0);
  final blTop = xyz(t.x - trunkRTop, t.y, trunkTopZ);
  final brTop = xyz(t.x + trunkRTop, t.y, trunkTopZ);
  final trunkPath = Path()
    ..moveTo(blBase.dx, blBase.dy)
    ..lineTo(brBase.dx, brBase.dy)
    ..lineTo(brTop.dx, brTop.dy)
    ..lineTo(blTop.dx, blTop.dy)
    ..close();
  // Базовый цвет ствола — от тёмно-коричневого до светло-оливкового.
  final baseTone = (sh(1) % 3);
  final trunkBase = [
    const Color(0xFF604224),
    const Color(0xFF735234),
    const Color(0xFF5A4527),
  ][baseTone];
  canvas.drawPath(
    trunkPath,
    Paint()
      ..color = trunkBase
      ..isAntiAlias = true,
  );
  // Кора — продольные тёмные/светлые штрихи (10-14 шт).
  canvas.save();
  canvas.clipPath(trunkPath);
  final barkPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  const barkN = 14;
  for (var i = 0; i < barkN; i++) {
    final hh = sh(i + 100);
    final off = (i / (barkN - 1) - 0.5) * (trunkRBase * 1.6);
    final isDark = (hh & 1) == 0;
    barkPaint.color = isDark
        ? const Color(0x55291907)
        : const Color(0x55BFA078);
    final z0 = ((hh >> 4) & 0xF) / 15.0 * 0.2;
    final z1 = trunkTopZ - ((hh >> 12) & 0xF) / 15.0 * 0.2;
    canvas.drawLine(
      xyz(t.x + off, t.y, z0),
      xyz(t.x + off * 0.7, t.y, z1),
      barkPaint,
    );
  }
  canvas.restore();

  // 3) Ветки — 3-5 ломаных линий от середины ствола под разными углами.
  final branchPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..color = trunkBase;
  final nBranches = 3 + (sh(2) & 0x3);
  for (var i = 0; i < nBranches; i++) {
    final hh = sh(200 + i);
    final ang = ((hh & 0xFFFF) / 0xFFFF) * 2 * math.pi;
    final start = trunkTopZ * (0.45 + ((hh >> 16) & 0xFF) / 255.0 * 0.4);
    final length = 0.6 + ((hh >> 24) & 0xF) / 15.0 * 0.6;
    final endZ = start + length * 0.6;
    final endX = t.x + math.cos(ang) * length;
    final endY = t.y + math.sin(ang) * length * 0.5;
    branchPaint.strokeWidth = 2.0;
    canvas.drawLine(
      xyz(t.x, t.y, start),
      xyz(endX, endY, endZ),
      branchPaint,
    );
  }

  // 4) Крона — облако из «листификов»-эллипсов на разных высотах.
  //    Зимой листва опадает: листифики не рисуются, вместо них —
  //    тонкие ветки-сучки и снежные шапочки. Ночью листва тёмная.
  final fcZ = t.heightM * 0.65;
  final foliageTones = switch (weather) {
    WeatherMode.summer => const [
        Color(0xFF3D5E26),
        Color(0xFF5A813A),
        Color(0xFF6F9D45),
        Color(0xFF8AAD56),
        Color(0xFFA4C56C),
      ],
    WeatherMode.winter => const [
        Color(0xFFFFFFFF),
        Color(0xFFE6EEF2),
        Color(0xFFD0DAE0),
        Color(0xFFFAFBFE),
        Color(0xFFC4D2DA),
      ],
    WeatherMode.night => const [
        Color(0xFF1A2C12),
        Color(0xFF253B1B),
        Color(0xFF324C25),
        Color(0xFF3F5C2B),
        Color(0xFF4A6A35),
      ],
  };
  // Зимой — меньше «листификов», расположены кучками-сугробами на ветках.
  final nLeaves = weather == WeatherMode.winter ? 60 : 130;
  for (var i = 0; i < nLeaves; i++) {
    final hh = sh(500 + i);
    // Точка в кубе [-1..1] (через хеш), нормализуем по ellipsoid.
    final u = ((hh & 0xFF) / 255.0) * 2 - 1;
    final v = (((hh >> 8) & 0xFF) / 255.0) * 2 - 1;
    final w = (((hh >> 16) & 0xFF) / 255.0) * 2 - 1;
    final r2 = u * u + v * v + w * w;
    if (r2 > 1.0) continue; // только внутри сферы
    final lx = t.x + u * t.foliageR;
    final ly = t.y + v * t.foliageR;
    final lz = fcZ + w * t.foliageR * 1.05;
    if (lz < trunkTopZ * 0.85) continue;
    final ls = xyz(lx, ly, lz);
    // Размер листифика: 12-22 px, форма овала (ширина чуть больше высоты).
    final sz = 6.0 + ((hh >> 24) & 0xF) / 15.0 * 8.0;
    final tone = foliageTones[(hh >> 4) % foliageTones.length];
    // Уменьшаем альфу нижних листификов — даёт перспективу.
    final shadeF = ((w + 1) / 2 * 0.4 + 0.6).clamp(0.6, 1.0);
    final c = ui.Color.fromRGBO(
      ((tone.red * shadeF)).clamp(0, 255).round(),
      ((tone.green * shadeF)).clamp(0, 255).round(),
      ((tone.blue * shadeF)).clamp(0, 255).round(),
      0.92,
    );
    canvas.drawOval(
      Rect.fromCenter(center: ls, width: sz * 1.2, height: sz),
      Paint()
        ..color = c
        ..isAntiAlias = true,
    );
  }

  // 5) Лёгкий блик солнечной стороны кроны (top-left). Только летом.
  if (weather == WeatherMode.summer) {
    final highlightCenter = xyz(
      t.x - t.foliageR * 0.3,
      t.y - t.foliageR * 0.3,
      fcZ + t.foliageR * 0.4,
    );
    canvas.drawCircle(
      highlightCenter,
      (xyz(t.x + t.foliageR, t.y, fcZ) - xyz(t.x, t.y, fcZ)).distance * 0.6,
      Paint()
        ..color = const Color(0x33FFFFFF)
        ..isAntiAlias = true
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }
}

// Стадия 3 — детализированный забор-штакетник.
//
// Забор по периметру участка 36×36 м (на 1 м внутрь от края травяной
// плоскости). Раз в 2 м — столб 12×12×150 см с пирамидальной шапочкой.
// Между столбами — 2 горизонтальные перекладины (на высоте 0.2 и 1.4 м)
// и вертикальные штакетины (8×2×130 см) с шагом 12 см, зазор 4 см.
// На передней стороне — разрыв 1.0 м под калитку.

enum _FenceKind { post, panel }

class _FenceSegment {
  _FenceSegment({
    required this.kind,
    required this.x,
    required this.y,
    this.x2 = 0,
    this.y2 = 0,
  });
  final _FenceKind kind;
  // Для post: позиция столба (x, y). Для panel: первый столб (x, y) и
  // второй столб (x2, y2).
  final double x;
  final double y;
  final double x2;
  final double y2;
  double depth = 0; // заполняется в paint()
}

List<_FenceSegment> _generateFence(Building3D model) {
  final cxW = model.footprintWidth / 2;
  final cyW = model.footprintLength / 2;
  // Квадрат 32×32 м (отступ 2 м от края 36×36-травы).
  const halfPlot = 16.0;
  final corners = <(double, double)>[
    (cxW - halfPlot, cyW - halfPlot),
    (cxW + halfPlot, cyW - halfPlot),
    (cxW + halfPlot, cyW + halfPlot),
    (cxW - halfPlot, cyW + halfPlot),
  ];

  // Находим «переднюю» сторону outline дома (ребро с минимальной y).
  // Калитка — посередине ребра забора, ближайшего к этой передней стороне.
  final outline = model.foundation.outline;
  var frontMy = double.infinity;
  if (outline.length >= 3) {
    for (var i = 0; i < outline.length; i++) {
      final j = (i + 1) % outline.length;
      final my = (outline[i].y + outline[j].y) / 2;
      if (my < frontMy) frontMy = my;
    }
  }
  // Передняя сторона забора всегда нижняя (y = cyW - halfPlot, идём от
  // (-halfPlot,-halfPlot) к (+halfPlot,-halfPlot)).
  // Калитка — около передней середины outline по X.
  var gateMx = cxW; // значение X, около которого делаем разрыв
  if (outline.isNotEmpty) {
    var sumX = 0.0;
    var n = 0;
    for (final p in outline) {
      if ((p.y - frontMy).abs() < 0.5) {
        sumX += p.x;
        n++;
      }
    }
    if (n > 0) gateMx = sumX / n;
  }

  final segments = <_FenceSegment>[];
  // Идём по 4 рёбрам.
  for (var k = 0; k < 4; k++) {
    final a = corners[k];
    final b = corners[(k + 1) % 4];
    final dx = b.$1 - a.$1;
    final dy = b.$2 - a.$2;
    final length = math.sqrt(dx * dx + dy * dy);
    final dirX = dx / length;
    final dirY = dy / length;
    const postSpacing = 2.0;
    final nPosts = (length / postSpacing).round() + 1; // включая последний
    // Это нижнее (переднее) ребро?
    final isFront = (a.$2 - (cyW - halfPlot)).abs() < 0.01 &&
        (b.$2 - (cyW - halfPlot)).abs() < 0.01;
    final gateGap = isFront ? 1.0 : 0.0;
    for (var i = 0; i < nPosts; i++) {
      final t = i / (nPosts - 1);
      final px = a.$1 + dx * t;
      final py = a.$2 + dy * t;
      // Если столб попадает в зону калитки — пропускаем.
      if (isFront && (px - gateMx).abs() < gateGap / 2 - 0.05) continue;
      segments.add(_FenceSegment(kind: _FenceKind.post, x: px, y: py));
      // Панель к следующему столбу.
      if (i < nPosts - 1) {
        final qx = a.$1 + dx * ((i + 1) / (nPosts - 1));
        final qy = a.$2 + dy * ((i + 1) / (nPosts - 1));
        // Если ребро панели попадает на зону калитки — пропускаем.
        final midX = (px + qx) / 2;
        if (isFront && (midX - gateMx).abs() < gateGap / 2 + 0.5) continue;
        segments.add(_FenceSegment(
          kind: _FenceKind.panel,
          x: px,
          y: py,
          x2: qx,
          y2: qy,
        ));
        // Сохраняем направление в неиспользуемом dirX*dirY: для рисования
        // вертикальных штакетин шагаем вдоль (qx-px, qy-py).
      }
    }
    // Утяжелим использование dirX/dirY чтобы избежать unused
    // (нужны для расчёта поворота штакетин в _paintFence).
    if (dirX.abs() + dirY.abs() < 0) segments.clear();
  }
  return segments;
}

void _paintFence(
  Canvas canvas,
  Building3D model,
  Building3DRenderer renderer,
  Camera3D camera,
  Size size,
  ui.Offset Function(Projected2D) toScreen, {
  required List<_FenceSegment> segments,
}) {
  if (segments.isEmpty) return;

  // Линейная (X,Y,Z)→screen трансформация.
  ui.Offset proj(double X, double Y, double Z) =>
      toScreen(renderer.project(Vec3(X, Y, Z), camera, size.width, size.height));
  final cxW = model.footprintWidth / 2;
  final cyW = model.footprintLength / 2;
  final s00 = proj(cxW, cyW, 0);
  final sX0 = proj(cxW + 1, cyW, 0);
  final s0Y = proj(cxW, cyW + 1, 0);
  final sZ1 = proj(cxW, cyW, 1);
  final ax = sX0.dx - s00.dx;
  final bx = s0Y.dx - s00.dx;
  final cz = sZ1.dx - s00.dx;
  final ay = sX0.dy - s00.dy;
  final by = s0Y.dy - s00.dy;
  final cz2 = sZ1.dy - s00.dy;
  final dX = s00.dx - ax * cxW - bx * cyW;
  final dY = s00.dy - ay * cxW - by * cyW;
  ui.Offset xyz(double X, double Y, double Z) => ui.Offset(
        ax * X + bx * Y + cz * Z + dX,
        ay * X + by * Y + cz2 * Z + dY,
      );

  // Сортировка back→front для корректного перекрытия близких сегментов.
  final sorted = [...segments]..sort((a, b) => b.depth.compareTo(a.depth));

  final postPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill
    ..color = const Color(0xFF8B6E45); // тёплое дерево
  final postSidePaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill
    ..color = const Color(0xFF6E5634); // боковая тень
  final picketPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill
    ..color = const Color(0xFFA88A5C); // штакетник
  final picketEdgePaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill
    ..color = const Color(0xFF856944); // правый край штакетины
  final railPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.butt
    ..color = const Color(0xFF7C5D38);

  for (final seg in sorted) {
    if (seg.kind == _FenceKind.post) {
      // Столб 12×12 см от 0 до 1.5 м, с пирамидальной шапочкой 0..1.62.
      const w = 0.06; // полуширина столба, м
      const hPost = 1.5;
      const hCap = 0.12;
      // Лицевая (левая) грань
      final blF = xyz(seg.x - w, seg.y - w, 0);
      final brF = xyz(seg.x + w, seg.y - w, 0);
      final tlF = xyz(seg.x - w, seg.y - w, hPost);
      final trF = xyz(seg.x + w, seg.y - w, hPost);
      // Правая боковая грань (для лёгкого 3D)
      final brB = xyz(seg.x + w, seg.y + w, 0);
      final trB = xyz(seg.x + w, seg.y + w, hPost);
      // Боковая тень
      final sidePath = Path()
        ..moveTo(brF.dx, brF.dy)
        ..lineTo(brB.dx, brB.dy)
        ..lineTo(trB.dx, trB.dy)
        ..lineTo(trF.dx, trF.dy)
        ..close();
      canvas.drawPath(sidePath, postSidePaint);
      // Лицевая
      final facePath = Path()
        ..moveTo(blF.dx, blF.dy)
        ..lineTo(brF.dx, brF.dy)
        ..lineTo(trF.dx, trF.dy)
        ..lineTo(tlF.dx, tlF.dy)
        ..close();
      canvas.drawPath(facePath, postPaint);
      // Шапочка-пирамидка: 4 треугольника.
      final apex = xyz(seg.x, seg.y, hPost + hCap);
      final capTL = xyz(seg.x - w, seg.y - w, hPost);
      final capTR = xyz(seg.x + w, seg.y - w, hPost);
      final capBR = xyz(seg.x + w, seg.y + w, hPost);
      final capFront = Path()
        ..moveTo(capTL.dx, capTL.dy)
        ..lineTo(capTR.dx, capTR.dy)
        ..lineTo(apex.dx, apex.dy)
        ..close();
      canvas.drawPath(capFront, postPaint);
      final capRight = Path()
        ..moveTo(capTR.dx, capTR.dy)
        ..lineTo(capBR.dx, capBR.dy)
        ..lineTo(apex.dx, apex.dy)
        ..close();
      canvas.drawPath(capRight, postSidePaint);
      // Контур столба тонкой линией (читаемость).
      canvas.drawPath(
        facePath,
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = const Color(0xFF3F2C18),
      );
    } else {
      // Панель между двумя столбами.
      final dx = seg.x2 - seg.x;
      final dy = seg.y2 - seg.y;
      final len = math.sqrt(dx * dx + dy * dy);
      final dirX = dx / len;
      final dirY = dy / len;
      // 2 горизонтальные перекладины.
      final railZTop = 1.4;
      final railZBot = 0.25;
      // Сдвигаем перекладины на 0.05 от столбов внутрь.
      final s = 0.06;
      canvas.drawLine(
        xyz(seg.x + dirX * s, seg.y + dirY * s, railZTop),
        xyz(seg.x2 - dirX * s, seg.y2 - dirY * s, railZTop),
        railPaint,
      );
      canvas.drawLine(
        xyz(seg.x + dirX * s, seg.y + dirY * s, railZBot),
        xyz(seg.x2 - dirX * s, seg.y2 - dirY * s, railZBot),
        railPaint,
      );
      // Штакетины через каждые 0.12 м, ширина 0.08 м.
      const picketW = 0.04; // полуширина штакетины, м
      const picketStep = 0.13;
      const picketH = 1.32;
      final usableLen = len - 2 * 0.10; // отступ 10 см от столбов
      if (usableLen <= 0) continue;
      final nPickets = (usableLen / picketStep).floor();
      for (var i = 0; i <= nPickets; i++) {
        final t = (i * picketStep + 0.10);
        if (t > len - 0.10) break;
        final cxP = seg.x + dirX * t;
        final cyP = seg.y + dirY * t;
        // Штакетина — вертикальный 4-угольник в плоскости забора.
        // Лицевые углы (немного сдвинуты по нормали к панели).
        final nrX = -dirY; // нормаль к направлению забора
        final nrY = dirX;
        final lx = cxP - dirX * picketW + nrX * 0.012;
        final ly = cyP - dirY * picketW + nrY * 0.012;
        final rx = cxP + dirX * picketW + nrX * 0.012;
        final ry = cyP + dirY * picketW + nrY * 0.012;
        final bl = xyz(lx, ly, 0.15);
        final br = xyz(rx, ry, 0.15);
        final tl = xyz(lx, ly, 0.15 + picketH);
        final tr = xyz(rx, ry, 0.15 + picketH);
        // Шевронная вершина — slightly higher на серединке (имитация
        // острого верха штакетины).
        final mx = (lx + rx) / 2;
        final my = (ly + ry) / 2;
        final apex = xyz(mx, my, 0.15 + picketH + 0.06);
        final picketPath = Path()
          ..moveTo(bl.dx, bl.dy)
          ..lineTo(br.dx, br.dy)
          ..lineTo(tr.dx, tr.dy)
          ..lineTo(apex.dx, apex.dy)
          ..lineTo(tl.dx, tl.dy)
          ..close();
        canvas.drawPath(picketPath, picketPaint);
        // Тёмная правая грань для объёма.
        final edgePath = Path()
          ..moveTo(br.dx, br.dy)
          ..lineTo(tr.dx, tr.dy)
          ..lineTo(apex.dx, apex.dy);
        canvas.drawPath(
          edgePath,
          Paint()
            ..isAntiAlias = true
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = picketEdgePaint.color,
        );
        // Тонкая центральная вертикальная полоса (тень волокна).
        final cBot = xyz(mx, my, 0.18);
        final cTop = xyz(mx, my, 0.15 + picketH - 0.05);
        canvas.drawLine(
          cBot,
          cTop,
          Paint()
            ..isAntiAlias = true
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5
            ..color = const Color(0x556B5132),
        );
      }
    }
  }
}
