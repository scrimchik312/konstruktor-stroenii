import 'dart:math' as math;

import 'package:pdf/pdf.dart';

import '../data/material_textures.dart';
import '../data/wall_materials.dart';
import '../models/building3d.dart';
import '../models/house_project.dart';
import 'building3d_renderer.dart';

/// Хелперы для рендера фасадных текстур, кровельных подписей и
/// расходов материалов. Вынесены из [PdfBuilder] (п.9 v43) для того,
/// чтобы основной модуль не превышал 8000 строк и был легче в навигации.
///
/// Все методы — чисто-функциональные (stateless): принимают `PdfGraphics` /
/// проект и возвращают строку или рисуют на канвасе. Стилевые
/// настройки (цвет/толщина/шрифт) задаются перед вызовом и
/// восстанавливаются вызывающим кодом.
class PdfBuilderMaterials {
  PdfBuilderMaterials._();

  /// PDF-адаптер для [Building3DRenderer]. Выполняет тесселляцию,
  /// проекцию, back-face culling и сортировку через общий движок и
  /// рисует на [PdfGraphics].
  static void renderBuilding3DToPdf({
    required PdfGraphics canvas,
    required PdfPoint size,
    required Building3D building,
    required PdfFont font,
    required String caption,
  }) {
    final wm = WallMaterial.fromName(building.wallMaterialName);
    final wallTex = MaterialTextureLibrary.wall(wm);
    final roofTex = MaterialTextureLibrary.roof(building.roofMaterialId);
    final renderer = Building3DRenderer(
      palette: SurfacePalette.forMaterials(
        wallExterior: Color3(
          wallTex.baseColor.r,
          wallTex.baseColor.g,
          wallTex.baseColor.b,
        ),
        roofSlope: Color3(
          roofTex.baseColor.r,
          roofTex.baseColor.g,
          roofTex.baseColor.b,
        ),
        roofRidge: Color3(
          roofTex.mortarColor.r,
          roofTex.mortarColor.g,
          roofTex.mortarColor.b,
        ),
      ),
    );
    final tris = renderer.tessellate(building);
    final camera = Camera3D.iso(target: building.center, distance: 200);

    // v68.11: винд канонизирован в `tessellate()` (CCW outward для
    // скатов/конька/грунта). Включаем back-face cull в screen-space,
    // как в on-screen 3D-просмотре — раньше cull выключали из-за
    // «прозрачных граней гаража» на L/T/U-формах, теперь причина
    // (некорректный винд) устранена. Cull пропускаем для grounds/slab/
    // openings: их винд может быть произвольным (горизонтальные
    // плоскости и проёмы видны с обеих сторон).
    final projected = <_Pdf3DTri>[];
    for (final t in tris) {
      final pa = renderer.project(t.a, camera, size.x, size.y);
      final pb = renderer.project(t.b, camera, size.x, size.y);
      final pc = renderer.project(t.c, camera, size.x, size.y);
      if (_cullableInPdf(t.kind)) {
        // В Projected2D ось Y направлена ВНИЗ (см. `Building3DRenderer.project`).
        // В Y-down системе CCW outward проектируется как CW в экране → cross<0.
        final c2 =
            RenderTri.cross2D(pa.x, pa.y, pb.x, pb.y, pc.x, pc.y);
        if (c2 >= 0) continue;
      }
      projected.add(_Pdf3DTri(pa, pb, pc, t));
    }
    // Стабильная сортировка: сначала по глубине (back→front), при
    // близкой глубине (Δ < 0.05 м) — по `kindLayer`, чтобы окна/двери
    // всегда поверх стен, конёк поверх скатов, скаты поверх стен,
    // а трава/грунт — самое нижнее. Без этого coplanar-грани
    // мерцают при вращении.
    projected.sort((a, b) {
      final dz = b.avgDepth - a.avgDepth;
      if (dz.abs() > 0.05) return dz.compareTo(0);
      return a.tri.layerOrder.compareTo(b.tri.layerOrder);
    });
    if (projected.isEmpty) return;

    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final p in projected) {
      for (final pt in [p.a, p.b, p.c]) {
        if (pt.x < minX) minX = pt.x;
        if (pt.x > maxX) maxX = pt.x;
        if (pt.y < minY) minY = pt.y;
        if (pt.y > maxY) maxY = pt.y;
      }
    }
    final boundsW = (maxX - minX).abs();
    final boundsH = (maxY - minY).abs();
    if (boundsW == 0 || boundsH == 0) return;
    const margin = 40.0;
    final scaleX = (size.x - margin * 2) / boundsW;
    final scaleY = (size.y - margin * 2) / boundsH;
    final scale = math.min(scaleX, scaleY);
    final cx = size.x / 2;
    final cy = size.y / 2;
    final midX = (minX + maxX) / 2;
    final midY = (minY + maxY) / 2;
    // PDF Y-инверсия: y экрана растёт вверх → зеркалим относительно центра.
    PdfPoint toScreen(Projected2D p) =>
        PdfPoint(cx + (p.x - midX) * scale, cy - (p.y - midY) * scale);

    // Грани заливаем без обводки — обводка по каждому треугольнику
    // превращала плоские стены/скаты в «штриховку», накладывая чёрные
    // линии на материал и стирая контур стен/окон/дверей. Реальные
    // рёбра (углы здания, конёк, проёмы, контуры пристроек)
    // дорисовываются отдельным слоем поверх.
    final palette = renderer.palette;
    for (final t in projected) {
      final base = palette.colorOf(t.tri.kind);
      final shaded = palette.shadeFace(base, t.tri.normal);
      final col = PdfColor(shaded.r, shaded.g, shaded.b);
      canvas.setFillColor(col);
      // Тонкая обводка тем же цветом — закрывает суб-пиксельные щели
      // между соседними треугольниками одного quad-а; они проявлялись
      // как тонкие «белые диагонали» на изометрии (Лист 16).
      canvas.setStrokeColor(col);
      canvas.setLineWidth(0.6);
      final pa = toScreen(t.a);
      final pb = toScreen(t.b);
      final pc = toScreen(t.c);
      canvas.moveTo(pa.x, pa.y);
      canvas.lineTo(pb.x, pb.y);
      canvas.lineTo(pc.x, pc.y);
      canvas.lineTo(pa.x, pa.y);
      canvas.fillAndStrokePath();
    }

    // Phase-3a: текстуры стен на аксонометрии. Перед отрисовкой
    // силуэтных рёбер кладём поверх каждой обращённой к камере
    // наружной стены процедурный рисунок материала (кирпичные ряды,
    // брус, газоблочная сетка) — тот же, что на 2D-фасаде, но с
    // правильным проектированием параллелограмма стены.
    _drawWallTexturesAxono(
      canvas: canvas,
      building: building,
      renderer: renderer,
      camera: camera,
      width: size.x,
      height: size.y,
      toScreen: toScreen,
      wallMaterial: wm,
    );

    // §16/§8 пункт 6 — векторные текстуры кровли (металлочерепица,
    // фальц, шифер, керамика, битум) на каждом обращённом к камере
    // скате. Аналогично стенам: проектируем 4 угла ската, в локальных
    // uv рисуем линии раскладки, переводим обратно в экран.
    _drawRoofTexturesAxono(
      canvas: canvas,
      building: building,
      renderer: renderer,
      camera: camera,
      width: size.x,
      height: size.y,
      toScreen: toScreen,
      roofTex: roofTex,
    );

    // v68.11: обналичка вокруг проёмов и водосточные трубы по углам
    // здания. Это переносит детали с on-screen 3D на PDF-аксонометрию,
    // делая лист «АР — общий вид» визуально согласованным с просмотром
    // в приложении (раньше пользователь видел красивый дом со ставнями
    // на экране и «голый» куб в PDF — это и было основной жалобой
    // про синхронизацию).
    _drawArchitecturalDetailsAxono(
      canvas: canvas,
      building: building,
      renderer: renderer,
      camera: camera,
      toScreen: toScreen,
      projected: projected,
    );

    // Линии конька / накосов / контуров проёмов поверх граней — каждая
    // со своей толщиной (углы здания, конёк — толще; контуры окон,
    // ребра пристройки — тоньше). Перед отрисовкой каждое ребро
    // проверяется на загораживание ближестоящими гранями: если
    // середина и/или треть ребра по глубине лежат ЗА любой передней
    // гранью — фрагмент скрывается. Так силуэт остаётся, а лишние
    // линии «заднего» каркаса не пробивают стены/кровлю.
    canvas.setStrokeColor(const PdfColor(0.10, 0.10, 0.10));
    for (final e in renderer.collectEdges(building)) {
      final pa = renderer.project(e.a, camera, size.x, size.y);
      final pb = renderer.project(e.b, camera, size.x, size.y);
      // Проверка по 5 точкам вдоль ребра: если ≥3 точек скрыто за
      // другими гранями — пропускаем целиком. Иначе пытаемся подрезать.
      var hidden = 0;
      const steps = 5;
      for (var i = 1; i <= steps; i++) {
        final t = i / (steps + 1);
        final px = pa.x + (pb.x - pa.x) * t;
        final py = pa.y + (pb.y - pa.y) * t;
        final pz = pa.z + (pb.z - pa.z) * t;
        if (_pointOccluded(px, py, pz, projected)) hidden++;
      }
      if (hidden >= 4) continue;
      final sa = toScreen(pa);
      final sb = toScreen(pb);
      canvas.setLineWidth(e.widthPt);
      canvas.drawLine(sa.x, sa.y, sb.x, sb.y);
      canvas.strokePath();
    }

    // Подпись.
    canvas.setFillColor(PdfColors.black);
    canvas.drawString(font, 11, caption, margin, margin / 2);
  }

  /// Код материала наружных стен (проект → brief).
  static String wallMaterialCode(HouseProject project) {
    final wallCode =
        project.walls.material ?? project.brief.wallMaterial?.name ?? 'brick';
    return wallCode;
  }

  /// Накладывает на стену прямоугольника `(x,y,w,h)` процедурную
  /// текстуру (кирпичные ряды, блочную сетку, доски бруса), которая
  /// соответствует выбранному пользователем материалу. Все цвета и
  /// размеры — из централизованной библиотеки материалов
  /// [MaterialTextureLibrary], так что новый материал автоматически
  /// получит корректную текстуру.
  static void paintWallTextureOverlay(
    PdfGraphics canvas,
    double x,
    double y,
    double w,
    double h,
    WallMaterial? mat,
    double scaleMperPt,
  ) {
    if (mat == null) return;
    final tex = MaterialTextureLibrary.wall(mat);
    // Шаг шва в pt = размер плитки [м] · масштаб.
    final tile = (tex.tileMeters * scaleMperPt).clamp(8.0, 80.0);
    canvas.setStrokeColor(PdfColor(
      tex.mortarColor.r,
      tex.mortarColor.g,
      tex.mortarColor.b,
    ));
    canvas.setLineWidth(0.35);
    switch (tex.pattern) {
      case MaterialPattern.brick:
        // Горизонтальные ряды + сдвинутые вертикальные швы (перевязка ½).
        for (var ry = y; ry <= y + h; ry += tile * 0.4) {
          canvas.drawLine(x, ry, x + w, ry);
        }
        canvas.strokePath();
        var row = 0;
        for (var ry = y; ry <= y + h; ry += tile * 0.4) {
          final offset = (row.isEven ? 0 : tile / 2);
          for (var rx = x + offset; rx <= x + w; rx += tile) {
            canvas.drawLine(rx, ry, rx, ry + tile * 0.4);
          }
          row++;
        }
        canvas.strokePath();
        break;
      case MaterialPattern.block:
        for (var ry = y; ry <= y + h; ry += tile * 0.42) {
          canvas.drawLine(x, ry, x + w, ry);
        }
        canvas.strokePath();
        for (var rx = x; rx <= x + w; rx += tile) {
          canvas.drawLine(rx, y, rx, y + h);
        }
        canvas.strokePath();
        break;
      case MaterialPattern.timberLog:
        for (var ry = y; ry <= y + h; ry += tile * 0.9) {
          canvas.drawLine(x, ry, x + w, ry);
        }
        canvas.strokePath();
        break;
      case MaterialPattern.timberBeam:
        for (var ry = y; ry <= y + h; ry += tile * 0.7) {
          canvas.drawLine(x, ry, x + w, ry);
        }
        canvas.strokePath();
        break;
      case MaterialPattern.frame:
        // Большие панели + центральная вертикаль.
        for (var rx = x; rx <= x + w; rx += tile) {
          canvas.drawLine(rx, y, rx, y + h);
        }
        canvas.strokePath();
        break;
      case MaterialPattern.flat:
      default:
        break;
    }
  }

  static PdfColor facadeWallFill(String code) {
    switch (code) {
      case 'aeratedConcrete':
      case 'foamConcrete':
        return const PdfColor(0.88, 0.92, 0.80);
      case 'timber':
      case 'glulam':
      case 'log':
        return const PdfColor(0.86, 0.70, 0.50);
      case 'frame':
        return const PdfColor(0.90, 0.85, 0.75);
      case 'brick':
      default:
        return const PdfColor(0.82, 0.60, 0.50);
    }
  }

  /// Рисует текстуру кровли поверх залитого полигона (п.4 v40).
  /// Полигон [poly] задан в pdf-координатах (точки уже трансформированы).
  ///
  /// Для каждого материала кровли рисуется характерная для него фактура:
  ///   • metal_tile / profile_sheet — вертикальные «рёбра» (слойка),
  ///   • soft_tile — горизонтальные ряды волнистой плитки,
  ///   • ceramic_tile / cement_tile — горизонтальные шихтованные ряды,
  ///   • rolled_bitumen — широкие горизонтальные полосы,
  ///   • pvc/tpo — крест-накрест.
  static void drawFacadeRoofTexture(
    PdfGraphics canvas,
    List<PdfPoint> poly,
    String? materialKey,
  ) {
    if (poly.length < 3) return;
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in poly) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    canvas.saveContext();
    canvas.moveTo(poly.first.x, poly.first.y);
    for (var i = 1; i < poly.length; i++) {
      canvas.lineTo(poly[i].x, poly[i].y);
    }
    canvas.closePath();
    canvas.clipPath();
    final fill = facadeRoofFill(materialKey);
    final dark = PdfColor(
      math.max(0.0, fill.red - 0.10),
      math.max(0.0, fill.green - 0.10),
      math.max(0.0, fill.blue - 0.10),
    );
    final light = PdfColor(
      math.min(1.0, fill.red + 0.10),
      math.min(1.0, fill.green + 0.10),
      math.min(1.0, fill.blue + 0.10),
    );
    switch (materialKey) {
      case 'metal_tile':
      case 'profile_sheet':
        // Вертикальные рёбра (~140 мм в реале, ~3-5 pt здесь).
        canvas.setStrokeColor(dark);
        canvas.setLineWidth(0.45);
        const ribStepPx = 5.0;
        for (var x = minX; x <= maxX; x += ribStepPx) {
          canvas.drawLine(x, minY, x, maxY);
        }
        canvas.strokePath();
        // Поперечные «модули» для металлочерепицы (горизонтальные складки).
        if (materialKey == 'metal_tile') {
          canvas.setStrokeColor(light);
          canvas.setLineWidth(0.3);
          const modH = 12.0;
          for (var y = minY; y <= maxY; y += modH) {
            canvas.drawLine(minX, y, maxX, y);
          }
          canvas.strokePath();
        }
        break;
      case 'soft_tile':
        // Битумная (гибкая) черепица — горизонтальные ряды с нижним
        // волнистым (зубчатым) краем.
        canvas.setStrokeColor(dark);
        canvas.setFillColor(dark);
        canvas.setLineWidth(0.3);
        const rowH = 6.0;
        const lobeW = 5.0;
        for (var y = minY; y <= maxY; y += rowH) {
          canvas.drawLine(minX, y, maxX, y);
          // Зубчатые «лопасти» нижнего края очередного ряда.
          for (var x = minX; x < maxX; x += lobeW) {
            canvas.drawLine(x, y, x + lobeW / 2, y - rowH * 0.45);
            canvas.drawLine(x + lobeW / 2, y - rowH * 0.45, x + lobeW, y);
          }
        }
        canvas.strokePath();
        break;
      case 'ceramic_tile':
      case 'cement_tile':
        // Керамика / цементно-песчаная — горизонтальные ряды
        // с шихтованной разбивкой по столбцам.
        canvas.setStrokeColor(dark);
        canvas.setLineWidth(0.4);
        const tH = 8.0;
        const tW = 11.0;
        var rowIdx = 0;
        for (var y = minY; y <= maxY; y += tH) {
          // Горизонтальная линия ряда.
          canvas.drawLine(minX, y, maxX, y);
          // Вертикальные швы — со сдвигом на полшага в каждом ряду.
          final off = rowIdx.isOdd ? tW / 2 : 0.0;
          for (var x = minX + off; x <= maxX; x += tW) {
            canvas.drawLine(x, y, x, y + tH);
          }
          rowIdx++;
        }
        canvas.strokePath();
        break;
      case 'rolled_bitumen':
        // Рулонная битумно-полимерная — широкие горизонтальные полосы.
        canvas.setStrokeColor(dark);
        canvas.setLineWidth(0.5);
        const rolledStep = 14.0;
        for (var y = minY; y <= maxY; y += rolledStep) {
          canvas.drawLine(minX, y, maxX, y);
        }
        canvas.strokePath();
        break;
      case 'pvc_membrane':
      case 'tpo_membrane':
        // ПВХ / ТПО мембраны — крест-накрест.
        canvas.setStrokeColor(dark);
        canvas.setLineWidth(0.3);
        const ms = 10.0;
        for (var x = minX - 50; x <= maxX + 50; x += ms) {
          canvas.drawLine(x, minY, x + (maxY - minY), maxY);
        }
        for (var x = minX - 50; x <= maxX + 50; x += ms) {
          canvas.drawLine(x, maxY, x + (maxY - minY), minY);
        }
        canvas.strokePath();
        break;
      default:
        // Без выбора — лёгкая горизонтальная плотница.
        canvas.setStrokeColor(dark);
        canvas.setLineWidth(0.3);
        const defStep = 9.0;
        for (var y = minY; y <= maxY; y += defStep) {
          canvas.drawLine(minX, y, maxX, y);
        }
        canvas.strokePath();
        break;
    }
    canvas.restoreContext();
  }

  /// Цвет кровли на фасаде — по выбранному материалу
  /// (см. `roofMaterialsLibrary` в `materials_library.dart`).
  static PdfColor facadeRoofFill(String? key) {
    switch (key) {
      case 'metal_tile':
      case 'profile_sheet':
        // Металлочерепица / профлист — глубокий бордовый (RAL 3005).
        return const PdfColor(0.43, 0.13, 0.18);
      case 'soft_tile':
        // Битумная гибкая черепица — тёмно-серый.
        return const PdfColor(0.25, 0.25, 0.27);
      case 'ceramic_tile':
      case 'cement_tile':
        // Керамика / цементно-песчаная — терракотовый.
        return const PdfColor(0.72, 0.42, 0.30);
      case 'rolled_bitumen':
        // Рулонная битумная — чёрный с тонким блеском.
        return const PdfColor(0.18, 0.18, 0.20);
      case 'pvc_membrane':
      case 'tpo_membrane':
        // ПВХ / ТПО мембраны — светло-серый.
        return const PdfColor(0.78, 0.80, 0.78);
      default:
        // Без выбора — нейтральный коричневый.
        return const PdfColor(0.55, 0.35, 0.27);
    }
  }

  /// Подпись материала кровли для легенды на фасаде.
  static String facadeRoofLabel(String? key) {
    switch (key) {
      case 'metal_tile':
        return 'Металлочерепица';
      case 'profile_sheet':
        return 'Профлист';
      case 'soft_tile':
        return 'Гибкая черепица';
      case 'ceramic_tile':
        return 'Керамическая черепица';
      case 'cement_tile':
        return 'Цементно-песчаная черепица';
      case 'rolled_bitumen':
        return 'Рулонная битумно-полимерная';
      case 'pvc_membrane':
        return 'ПВХ-мембрана';
      case 'tpo_membrane':
        return 'ТПО-мембрана';
      default:
        return 'Кровля';
    }
  }

  /// Элемент дома, в котором используется заданный материал стен
  /// (для столбца «Элемент дома» в табл. 4 «Стеновые материалы», п.5 v40).
  ///
  /// В одном проекте обычно используется 1–3 материала стен:
  ///   • Основной (кладка/брус/каркас) → «Наружные стены»;
  ///   • Облегчённый (пустотелый кирпич / D500 / лёгкие блоки) →
  ///     «Перегородки + простенки»;
  ///   • Каркас лёгкой конструкции (clt / SIP / brick_hollow) → может
  ///     идти на «Фронтон + второстепенные стены».
  ///
  /// Алгоритм:
  ///   1. Если у материала ключ соответствует «лёгкой» вариации (hollow,
  ///      D500, foam) → перегородки/простенки.
  ///   2. Brick_solid / aerated_d600 / log / timber_solid / frame_sip →
  ///      основной материал → «Наружные стены».
  ///   3. timber_glulam (клееный брус) → если кровля скатная — «Фронтон»,
  ///      иначе — «Опорные элементы».
  static String wallMaterialElement(String key, HouseProject project) {
    final tLower = (project.roof.type ?? 'gable').toLowerCase();
    final hasGable = tLower.contains('gable') ||
        tLower.contains('двуск') ||
        tLower.contains('hip');
    switch (key) {
      case 'brick_solid':
        return 'Наружные стены';
      case 'brick_hollow':
        return 'Перегородки, простенки';
      case 'aerated_d500':
        return 'Перегородки';
      case 'aerated_d600':
        return 'Наружные стены';
      case 'foam_d600':
        return 'Перегородки';
      case 'expanded_clay':
        return 'Наружные стены';
      case 'timber_solid':
        return 'Наружные стены';
      case 'timber_glulam':
        return hasGable ? 'Фронтон, простенки' : 'Опоры, простенки';
      case 'log':
        return 'Наружные стены';
      case 'frame_sip':
        return 'Наружные стены, перегородки';
      default:
        return 'Стеновой элемент';
    }
  }

  /// Расход стенового материала с учётом отходов (п.4 v43).
  ///
  /// Возвращает строку вида «4 720 шт. + 5%» / «120 мешков 25 кг + 5%» /
  /// «42.5 м³ + 7%». Нормы взяты из ФССЦ-2020 / ГЭСНм:
  ///
  ///   • полнотелый кирпич (250×120×65 мм) — 410 шт./м³, отходы 5%
  ///     (бой при кладке);
  ///   • пустотелый кирпич (250×120×88 мм) — 380 шт./м³, отходы 5%;
  ///   • газобетон D500/D600 (600×300×250 мм = 0.045 м³) —
  ///     22.2 шт./м³ → ≈22 блока, отходы 5%;
  ///   • пенобетон (600×300×200 мм = 0.036 м³) — 27.8 шт./м³,
  ///     отходы 5%;
  ///   • керамзитобетон (390×190×188 мм = 0.0139 м³) — 71.9 шт./м³,
  ///     отходы 5%;
  ///   • брус/клеёный брус — м³ + 7% (раскрой);
  ///   • бревно (брёвна) — м³ + 7%;
  ///   • каркас SIP — площадь × 1.05 (отходы при стыковке).
  ///
  /// Кладочный раствор (М100) — отдельной строкой не выводится; смету
  /// он закрывает в табл. бетонов. Если ключ неизвестен — возвращаем
  /// просто «<V> м³ + 7%».
  static String wallMaterialConsumption(
    String key,
    double volumeM3,
    double areaM2,
  ) {
    if (volumeM3 <= 0 && areaM2 <= 0) return '—';
    int? piecesPerM3;
    String? unit;
    switch (key) {
      case 'brick_solid':
        piecesPerM3 = 410;
        unit = 'шт.';
        break;
      case 'brick_hollow':
        piecesPerM3 = 380;
        unit = 'шт.';
        break;
      case 'aerated_d500':
      case 'aerated_d600':
        piecesPerM3 = 22; // 600×300×250 мм
        unit = 'блок.';
        break;
      case 'foam_d600':
        piecesPerM3 = 28;
        unit = 'блок.';
        break;
      case 'expanded_clay':
        piecesPerM3 = 72;
        unit = 'блок.';
        break;
      case 'timber_solid':
      case 'timber_glulam':
      case 'log':
        // Дерево: расход в м³ с раскроечным запасом 7%.
        return '${(volumeM3 * 1.07).toStringAsFixed(1)} м³ (+7%)';
      case 'frame_sip':
        return '${(areaM2 * 1.05).toStringAsFixed(1)} м² панелей (+5%)';
    }
    if (piecesPerM3 != null && unit != null) {
      final qty = (volumeM3 * piecesPerM3 * 1.05).round();
      return '$qty $unit (+5%)';
    }
    return '${(volumeM3 * 1.07).toStringAsFixed(1)} м³ (+7%)';
  }

  /// Расход кровельного материала с учётом отходов (п.4 v43).
  ///
  /// Нормы (ФССЦ-2020 / ГЭСНм-12):
  ///   • металлочерепица — м² × 1.10 (раскрой по скатам, нахлёст);
  ///   • профлист — м² × 1.12;
  ///   • мягкая (битумная) черепица — пачки 3 м²/пач, расход × 1.10;
  ///   • керамическая — 10–13 шт./м², возьмём 11, × 1.07 (бой);
  ///   • цементно-песчаная (slate-tile) — то же, что керамика;
  ///   • рулонный битумный — 10 м/рул × 1 м, площадь × 1.15 (нахлёст);
  ///   • мембрана — м² × 1.10 (сварка швов, обрезка).
  static String roofMaterialConsumption(String key, double areaM2) {
    if (areaM2 <= 0) return '—';
    final low = key.toLowerCase();
    if (low.contains('metal_tile') || low.contains('metal') ||
        low.contains('профил') || low.contains('profile')) {
      // Профлист отдельно ловим по 'profile'.
      if (low.contains('profile') || low.contains('профил')) {
        return '${(areaM2 * 1.12).toStringAsFixed(1)} м² (+12%)';
      }
      return '${(areaM2 * 1.10).toStringAsFixed(1)} м² (+10%)';
    }
    if (low.contains('shingle') || low.contains('soft') ||
        low.contains('бит') || low.contains('гибк')) {
      // Гибкая (битумная) черепица — пачки по 3 м² (типовой).
      final m2 = areaM2 * 1.10;
      final packs = (m2 / 3.0).ceil();
      return '${m2.toStringAsFixed(1)} м² ($packs пач.) (+10%)';
    }
    if (low.contains('ceramic') || low.contains('керам')) {
      final pieces = (areaM2 * 11 * 1.07).round();
      return '$pieces шт. (+7%)';
    }
    if (low.contains('slate') || low.contains('cement')) {
      final pieces = (areaM2 * 10 * 1.07).round();
      return '$pieces шт. (+7%)';
    }
    if (low.contains('roll') || low.contains('рулон')) {
      final m2 = areaM2 * 1.15;
      final rolls = (m2 / 10.0).ceil();
      return '${m2.toStringAsFixed(1)} м² ($rolls рул.) (+15%)';
    }
    if (low.contains('membrane') || low.contains('мембран')) {
      return '${(areaM2 * 1.10).toStringAsFixed(1)} м² (+10%)';
    }
    return '${(areaM2 * 1.10).toStringAsFixed(1)} м² (+10%)';
  }

  /// Расход утеплителя с учётом отходов (п.4 v43).
  ///
  /// Нормы:
  ///   • минеральная/каменная вата (Rockwool/ТехноНиколь) —
  ///     рулоны/плиты, м³ × 1.05 (раскрой);
  ///   • стекловата — м³ × 1.07;
  ///   • EPS / пенополистирол / пеноплэкс — м³ × 1.05;
  ///   • эковата (целлюлоза) — кг × 1.05 (плотность ~50 кг/м³).
  ///
  /// Если ключ неизвестен, выводим м³ × 1.05.
  static String insulationConsumption(
    String key,
    double volumeM3,
    double areaM2,
  ) {
    if (volumeM3 <= 0 && areaM2 <= 0) return '—';
    final low = key.toLowerCase();
    if (low.contains('eco') || low.contains('эковат') ||
        low.contains('cellulose')) {
      final mass = (volumeM3 * 50 * 1.05).round();
      return '$mass кг (+5%)';
    }
    if (low.contains('glass') || low.contains('стеклов')) {
      return '${(volumeM3 * 1.07).toStringAsFixed(1)} м³ (+7%)';
    }
    return '${(volumeM3 * 1.05).toStringAsFixed(1)} м³ (+5%)';
  }

  /// Штриховка стены в разрезе по материалу (ГОСТ 2.306-68):
  /// кирпич — диагональная решётка, газобетон — мелкая квадратная сетка,
  /// брус/бревно — горизонтальные слои (укладка), каркас — вертикальные стойки.
  static void drawSectionWallHatch(
    PdfGraphics canvas, {
    required double x,
    required double y,
    required double w,
    required double h,
    required String material,
  }) {
    canvas.setStrokeColor(PdfColors.grey700);
    canvas.setLineWidth(0.25);
    switch (material) {
      case 'aeratedConcrete':
      case 'foamConcrete':
        // Газобетон: мелкая квадратная сетка с шагом 4 пт.
        const stepCell = 4.5;
        for (var hy = y; hy < y + h; hy += stepCell) {
          canvas.drawLine(x + 0.5, hy, x + w - 0.5, hy);
        }
        for (var hx = x; hx < x + w; hx += stepCell) {
          canvas.drawLine(hx, y + 0.5, hx, y + h - 0.5);
        }
        canvas.strokePath();
        break;
      case 'timber':
      case 'glulam':
      case 'log':
        // Брус / бревно: горизонтальные линии — швы укладки 200 мм.
        const stepLog = 5.5;
        for (var hy = y + stepLog; hy < y + h; hy += stepLog) {
          canvas.drawLine(x + 0.5, hy, x + w - 0.5, hy);
        }
        canvas.strokePath();
        break;
      case 'frame':
        // Каркас: вертикальные «стойки» с шагом 3.5 пт + горизонтальные
        // обвязки сверху/снизу.
        const stepStud = 3.5;
        for (var hx = x + stepStud; hx < x + w; hx += stepStud) {
          canvas.drawLine(hx, y + 1, hx, y + h - 1);
        }
        canvas.drawLine(x + 0.5, y + 1, x + w - 0.5, y + 1);
        canvas.drawLine(x + 0.5, y + h - 1, x + w - 0.5, y + h - 1);
        canvas.strokePath();
        break;
      case 'brick':
      default:
        // Кирпич: диагональная штриховка через всю толщину.
        const stepBrick = 4.0;
        for (var hy = y; hy < y + h; hy += stepBrick) {
          final dx = math.min(w, y + h - hy);
          canvas.drawLine(x, hy, x + dx, hy + dx);
        }
        canvas.strokePath();
        break;
    }
  }

  /// Подпись материала наружных стен для легенды.
  static String facadeWallLabel(String code) {
    switch (code) {
      case 'aeratedConcrete':
        return 'Газобетон';
      case 'foamConcrete':
        return 'Пенобетон';
      case 'timber':
        return 'Брус';
      case 'glulam':
        return 'Клееный брус';
      case 'log':
        return 'Сруб (бревно)';
      case 'frame':
        return 'Каркас';
      case 'brick':
        return 'Кирпич';
      default:
        return 'Кладка';
    }
  }
}

/// Phase-3a: текстуры наружных стен на аксонометрии. Кладёт поверх
/// уже залитых граней процедурный паттерн материала (кирпич/брус/блок).
/// Проектирует прямоугольную стену в параллелограмм через `renderer`,
/// в локальных uv-координатах (u — вдоль стены, v — снизу вверх)
/// рисует линии раскладки и пересчитывает их концы обратно в экран.
void _drawWallTexturesAxono({
  required PdfGraphics canvas,
  required Building3D building,
  required Building3DRenderer renderer,
  required Camera3D camera,
  required double width,
  required double height,
  required PdfPoint Function(Projected2D) toScreen,
  required WallMaterial? wallMaterial,
}) {
  if (wallMaterial == null) return;
  final tex = MaterialTextureLibrary.wall(wallMaterial);
  if (tex.pattern == MaterialPattern.flat) return;

  // Направление «к камере» (через target). Для ортогональной изометрии
  // достаточно одного фиксированного вектора, т.к. все лучи параллельны.
  final yaw = camera.yaw;
  final pit = camera.pitch;
  final camDir = Vec3(
    -math.sin(yaw) * math.cos(pit),
    -math.cos(yaw) * math.cos(pit),
    math.sin(pit),
  );

  canvas.setStrokeColor(PdfColor(
    tex.mortarColor.r, tex.mortarColor.g, tex.mortarColor.b,
  ));
  canvas.setLineWidth(0.25);

  for (final floor in building.floors) {
    for (final wall in floor.walls) {
      if (wall.kind != SurfaceKind.wallExterior) continue;
      // Видимость: стена обращена к камере, если её внешняя нормаль
      // имеет положительную проекцию на направление к камере.
      final n = wall.outwardNormal;
      final dot = n.x * camDir.x + n.y * camDir.y + n.z * camDir.z;
      if (dot <= 0.05) continue;

      final L = wall.length;
      if (L < 0.2) continue;
      final z0 = floor.elevationM;
      final z1 = z0 + wall.height;

      // Углы стены (CCW при взгляде снаружи): tl, tr, bl в 3D.
      // br не нужен — параллелограмм задаётся тремя углами.
      final tl3 = Vec3(wall.start.x, wall.start.y, z1);
      final tr3 = Vec3(wall.end.x, wall.end.y, z1);
      final bl3 = Vec3(wall.start.x, wall.start.y, z0);

      final ptl = toScreen(renderer.project(tl3, camera, width, height));
      final ptr = toScreen(renderer.project(tr3, camera, width, height));
      final pbl = toScreen(renderer.project(bl3, camera, width, height));
      // br — не нужен явно, mapUV использует только tl/tr/bl как базис.

      // Линейная карта из локальных (u in [0..L], v in [0..H]) в экран.
      // (u/L, v/H) → tl + uNorm·(tr-tl) + vNorm·(bl-tl).
      final ux = (ptr.x - ptl.x) / L;
      final uy = (ptr.y - ptl.y) / L;
      final H = wall.height;
      final vx = (pbl.x - ptl.x) / H;
      final vy = (pbl.y - ptl.y) / H;
      PdfPoint mapUV(double u, double v) =>
          PdfPoint(ptl.x + u * ux + v * vx, ptl.y + u * uy + v * vy);

      // Шаг текстуры в метрах от паттерна.
      final tile = tex.tileMeters; // длина «плитки», м

      // Список «вырезов» под проёмы — для пропуска текстуры внутри
      // окон/дверей. Координаты (u_lo, u_hi, v_lo, v_hi) в м.
      final cuts = <_UvRect>[];
      for (final o in wall.openings) {
        cuts.add(_UvRect(
          o.offsetAlong, o.offsetAlong + o.width,
          // v=0 наверху (tl), v=H внизу (bl). bottom от низа стены —
          // переводим в v: v_top_of_opening = H - (bottom + opHeight).
          H - (o.bottom + o.height), H - o.bottom,
        ));
      }
      bool inCut(double u, double v) {
        for (final c in cuts) {
          if (u >= c.uLo && u <= c.uHi && v >= c.vLo && v <= c.vHi) return true;
        }
        return false;
      }

      switch (tex.pattern) {
        case MaterialPattern.brick:
          // Горизонтальные ряды через 0.075 м (0.4·tile).
          final rowH = tile * 0.4;
          for (var v = rowH; v < H; v += rowH) {
            _drawSegmentSkippingCuts(canvas, mapUV, 0, v, L, v, inCut);
          }
          // Вертикальные швы через tile с шахматным сдвигом.
          var row = 0;
          for (var v = 0.0; v < H - 0.001; v += rowH) {
            final off = (row.isEven ? 0.0 : tile / 2);
            for (var u = off; u < L; u += tile) {
              if (inCut(u, v + rowH / 2)) continue;
              final pa = mapUV(u, v);
              final pb = mapUV(u, v + rowH);
              canvas.drawLine(pa.x, pa.y, pb.x, pb.y);
            }
            row++;
          }
          canvas.strokePath();
          break;
        case MaterialPattern.block:
          final rowH = tile * 0.42;
          for (var v = rowH; v < H; v += rowH) {
            _drawSegmentSkippingCuts(canvas, mapUV, 0, v, L, v, inCut);
          }
          for (var u = tile; u < L; u += tile) {
            _drawSegmentSkippingCuts(canvas, mapUV, u, 0, u, H, inCut);
          }
          break;
        case MaterialPattern.timberLog:
          final rowH = tile * 0.9;
          for (var v = rowH; v < H; v += rowH) {
            _drawSegmentSkippingCuts(canvas, mapUV, 0, v, L, v, inCut);
          }
          break;
        case MaterialPattern.timberBeam:
          final rowH = tile * 0.7;
          for (var v = rowH; v < H; v += rowH) {
            _drawSegmentSkippingCuts(canvas, mapUV, 0, v, L, v, inCut);
          }
          break;
        case MaterialPattern.frame:
          for (var u = tile; u < L; u += tile) {
            _drawSegmentSkippingCuts(canvas, mapUV, u, 0, u, H, inCut);
          }
          break;
        // Кровельные/нестенные паттерны не применяются к стенам.
        // ignore: no_default_cases
        default:
          break;
      }
    }
  }
}

/// Рисует линию из (uA,vA) → (uB,vB) в uv-координатах стены,
/// пропуская участки, попавшие в любой `inCut`.
void _drawSegmentSkippingCuts(
  PdfGraphics canvas,
  PdfPoint Function(double, double) mapUV,
  double uA, double vA, double uB, double vB,
  bool Function(double, double) inCut,
) {
  const N = 60;
  double? segStart;
  for (var i = 0; i <= N; i++) {
    final t = i / N;
    final u = uA + (uB - uA) * t;
    final v = vA + (vB - vA) * t;
    final hit = inCut(u, v);
    if (!hit && segStart == null) segStart = t;
    if ((hit || i == N) && segStart != null) {
      final tEnd = hit ? (t - 1.0 / N).clamp(segStart, 1.0) : t;
      final p0 = mapUV(uA + (uB - uA) * segStart, vA + (vB - vA) * segStart);
      final p1 = mapUV(uA + (uB - uA) * tEnd, vA + (vB - vA) * tEnd);
      canvas.drawLine(p0.x, p0.y, p1.x, p1.y);
      segStart = null;
    }
  }
  canvas.strokePath();
}

/// Прямоугольник «выреза под проём» в uv-координатах стены.
class _UvRect {
  final double uLo, uHi, vLo, vHi;
  const _UvRect(this.uLo, this.uHi, this.vLo, this.vHi);
}

/// §16/§8 пункт 6 — векторные текстуры кровли на аксонометрии.
///
/// Каждый скат кровли — четырёхугольник в 3D (`RoofSlope3D.corners`).
/// Если скат обращён к камере, проектируем его 4 угла в экран и в
/// локальных uv (u — вдоль карниза, v — вдоль ската) рисуем линии
/// раскладки выбранного материала: горизонтальные ряды
/// (металлочерепица, керамика, шифер), вертикальные швы
/// (фальцевая, профлист), мелкая зернистость (битум).
void _drawRoofTexturesAxono({
  required PdfGraphics canvas,
  required Building3D building,
  required Building3DRenderer renderer,
  required Camera3D camera,
  required double width,
  required double height,
  required PdfPoint Function(Projected2D) toScreen,
  required MaterialTexture roofTex,
}) {
  if (roofTex.pattern == MaterialPattern.flat) return;

  // Направление камеры (для отсечения скатов «спиной» к зрителю).
  final yaw = camera.yaw;
  final pit = camera.pitch;
  final camDir = Vec3(
    -math.sin(yaw) * math.cos(pit),
    -math.cos(yaw) * math.cos(pit),
    math.sin(pit),
  );

  canvas.setStrokeColor(PdfColor(
    roofTex.mortarColor.r, roofTex.mortarColor.g, roofTex.mortarColor.b,
  ));
  canvas.setLineWidth(0.25);

  for (final slope in building.roof.slopes) {
    final c = slope.corners;
    if (c.length < 3) continue;
    // Нормаль ската (CCW при взгляде снаружи).
    final ux = c[1].x - c[0].x,
        uy = c[1].y - c[0].y,
        uz = c[1].z - c[0].z;
    final vx = c[2].x - c[1].x,
        vy = c[2].y - c[1].y,
        vz = c[2].z - c[1].z;
    final nx = uy * vz - uz * vy;
    final ny = uz * vx - ux * vz;
    final nz = ux * vy - uy * vx;
    final nLen = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (nLen < 1e-9) continue;
    final dot = (nx / nLen) * camDir.x +
        (ny / nLen) * camDir.y +
        (nz / nLen) * camDir.z;
    if (dot <= 0.05) continue;

    // Длины двух базовых сторон ската (тривиальный случай — 4 угла,
    // карниз = c[0]→c[1], скат = c[0]→c[3]).
    if (c.length != 4) continue;
    final L = math.sqrt(ux * ux + uy * uy + uz * uz); // вдоль карниза
    final wx = c[3].x - c[0].x,
        wy = c[3].y - c[0].y,
        wz = c[3].z - c[0].z;
    final H = math.sqrt(wx * wx + wy * wy + wz * wz); // вдоль ската
    if (L < 0.5 || H < 0.5) continue;

    final p00 = toScreen(renderer.project(c[0], camera, width, height));
    final p10 = toScreen(renderer.project(c[1], camera, width, height));
    final p01 = toScreen(renderer.project(c[3], camera, width, height));
    // Линейная карта uv→экран: u in [0..L], v in [0..H].
    final uxS = (p10.x - p00.x) / L, uyS = (p10.y - p00.y) / L;
    final vxS = (p01.x - p00.x) / H, vyS = (p01.y - p00.y) / H;
    PdfPoint mapUV(double u, double v) =>
        PdfPoint(p00.x + u * uxS + v * vxS, p00.y + u * uyS + v * vyS);

    final tile = roofTex.tileMeters;
    switch (roofTex.pattern) {
      case MaterialPattern.metalTile:
      case MaterialPattern.ceramicTile:
        // Горизонтальные ряды + вертикальные швы (со сдвигом для керамики).
        final rowH = tile * 0.5;
        for (var v = rowH; v < H; v += rowH) {
          final pa = mapUV(0, v);
          final pb = mapUV(L, v);
          canvas.drawLine(pa.x, pa.y, pb.x, pb.y);
        }
        var row = 0;
        for (var v = 0.0; v < H - 0.001; v += rowH) {
          final off = (row.isEven ? 0.0 : tile / 2);
          for (var u = off; u < L; u += tile) {
            final pa = mapUV(u, v);
            final pb = mapUV(u, v + rowH);
            canvas.drawLine(pa.x, pa.y, pb.x, pb.y);
          }
          row++;
        }
        canvas.strokePath();
        break;
      case MaterialPattern.slate:
        // Шифер — широкие горизонтальные волны (только горизонтали).
        final rowH = tile * 0.6;
        for (var v = rowH; v < H; v += rowH) {
          final pa = mapUV(0, v);
          final pb = mapUV(L, v);
          canvas.drawLine(pa.x, pa.y, pb.x, pb.y);
        }
        canvas.strokePath();
        break;
      case MaterialPattern.seam:
      case MaterialPattern.profileSheet:
        // Фальц / профлист — вертикальные швы вдоль ската.
        for (var u = tile; u < L; u += tile) {
          final pa = mapUV(u, 0);
          final pb = mapUV(u, H);
          canvas.drawLine(pa.x, pa.y, pb.x, pb.y);
        }
        canvas.strokePath();
        break;
      case MaterialPattern.bitumen:
        // Мягкая кровля — крестовая сетка через 0.5 м.
        const grid = 0.5;
        for (var v = grid; v < H; v += grid) {
          final pa = mapUV(0, v);
          final pb = mapUV(L, v);
          canvas.drawLine(pa.x, pa.y, pb.x, pb.y);
        }
        for (var u = grid; u < L; u += grid) {
          final pa = mapUV(u, 0);
          final pb = mapUV(u, H);
          canvas.drawLine(pa.x, pa.y, pb.x, pb.y);
        }
        canvas.strokePath();
        break;
      default:
        // Остальные паттерны не предусмотрены для кровли.
        break;
    }
  }
}

/// Точка `(x, y, z)` (в координатах проекции, до масштабирования на
/// экран) скрыта за любой ближестоящей гранью (z=depth, больше=глубже).
/// Проверяется барицентрически по списку треугольников. Используется
/// для культинга невидимых рёбер (углы стен/проёмов на ОБРАТНОЙ стороне
/// здания не должны пробивать видимые грани).
bool _pointOccluded(
    double x, double y, double z, List<_Pdf3DTri> faces) {
  const eps = 0.05; // м — допуск, чтобы рёбра самого треугольника не считались
  for (final f in faces) {
    final ax = f.a.x, ay = f.a.y;
    final bx = f.b.x, by = f.b.y;
    final cx = f.c.x, cy = f.c.y;
    // Барицентрические координаты точки (x,y) в треугольнике (A,B,C).
    final denom = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy);
    if (denom.abs() < 1e-9) continue;
    final w1 = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / denom;
    final w2 = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / denom;
    final w3 = 1.0 - w1 - w2;
    if (w1 < 0 || w2 < 0 || w3 < 0) continue;
    final triZ = w1 * f.a.z + w2 * f.b.z + w3 * f.c.z;
    // Если треугольник ближе к камере (меньшая z), а ребро глубже —
    // точка скрыта.
    if (triZ + eps < z) return true;
  }
  return false;
}

/// Спроецированный треугольник для PDF-адаптера 3D-движка
/// ([PdfBuilderMaterials.renderBuilding3DToPdf]).
class _Pdf3DTri {
  final Projected2D a;
  final Projected2D b;
  final Projected2D c;
  final RenderTri tri;
  _Pdf3DTri(this.a, this.b, this.c, this.tri);
  double get avgDepth => (a.z + b.z + c.z) / 3;
}

/// v68.11: обналичка проёмов + водосточные трубы для PDF-аксонометрии.
///
/// Это «облегчённая» версия `_paintWindowShuttersAndCasing` /
/// `_paintDownspoutsAndGutter` из `building3d_view.dart`. Полный
/// перенос с теневыми петлями ставен и т.д. — в v68.12. Здесь
/// рисуем только то, что видно на расстоянии и хорошо смотрится
/// на A3-листе:
///   • Обналичка (наличник): рамка 6 см вокруг каждого окна/двери,
///     оливкового цвета, чтобы контур окна на изометрии был сразу
///     заметен (раньше — только заливка-glazing, тонула в стене).
///   • Водосточные трубы: вертикальные линии Ø100 мм по углам
///     здания от уровня кровли до отметки 0.0.
void _drawArchitecturalDetailsAxono({
  required PdfGraphics canvas,
  required Building3D building,
  required Building3DRenderer renderer,
  required Camera3D camera,
  required PdfPoint Function(Projected2D) toScreen,
  required List<_Pdf3DTri> projected,
}) {
  // ---- Обналичка вокруг проёмов ----
  const casingW = 0.06; // 6 см
  canvas.setStrokeColor(const PdfColor(0.55, 0.50, 0.40));
  canvas.setLineWidth(0.7);
  canvas.setFillColor(const PdfColor(0.85, 0.82, 0.74));
  for (final f in building.floors) {
    for (final w in f.walls) {
      if (w.kind != SurfaceKind.wallExterior) continue;
      // Видимость стены — её внешняя нормаль смотрит к камере.
      final yaw = camera.yaw;
      final pit = camera.pitch;
      final camDir = Vec3(
        -math.sin(yaw) * math.cos(pit),
        -math.cos(yaw) * math.cos(pit),
        math.sin(pit),
      );
      final n = w.outwardNormal;
      final dot = n.x * camDir.x + n.y * camDir.y + n.z * camDir.z;
      if (dot <= 0.05) continue;
      final L = w.length;
      if (L < 0.2) continue;
      final dx = (w.end.x - w.start.x) / L;
      final dy = (w.end.y - w.start.y) / L;
      final z0 = f.elevationM;
      Vec3 wp(double off, double z) =>
          Vec3(w.start.x + dx * off, w.start.y + dy * off, z);
      for (final op in w.openings) {
        final u0 = math.max(0.0, op.offsetAlong - casingW);
        final u1 = math.min(L, op.offsetAlong + op.width + casingW);
        final v0 = math.max(0.0, op.bottom - casingW);
        final v1 = op.bottom + op.height + casingW;
        // 4 угла рамки.
        final c0 = renderer.project(
            wp(u0, z0 + v0), camera, double.infinity, double.infinity);
        final c1 = renderer.project(
            wp(u1, z0 + v0), camera, double.infinity, double.infinity);
        final c2 = renderer.project(
            wp(u1, z0 + v1), camera, double.infinity, double.infinity);
        final c3 = renderer.project(
            wp(u0, z0 + v1), camera, double.infinity, double.infinity);
        // Окклюзия — если рамка ЗА другими гранями, не рисуем.
        final mid = Projected2D((c0.x + c2.x) / 2, (c0.y + c2.y) / 2,
            (c0.z + c2.z) / 2);
        if (_pointOccluded(mid.x, mid.y, mid.z, projected)) continue;
        final s0 = toScreen(c0);
        final s1 = toScreen(c1);
        final s2 = toScreen(c2);
        final s3 = toScreen(c3);
        canvas.moveTo(s0.x, s0.y);
        canvas.lineTo(s1.x, s1.y);
        canvas.lineTo(s2.x, s2.y);
        canvas.lineTo(s3.x, s3.y);
        canvas.lineTo(s0.x, s0.y);
        canvas.strokePath();
      }
    }
  }

  // ---- Водосточные трубы по углам здания ----
  // Берём контур фундамента и в каждом углу опускаем вертикаль от
  // верха стен (carniz) до отметки 0. Цвет — графитовый, как в Ral 7016.
  final out = building.foundation.outline;
  if (out.isEmpty) return;
  // Высота карниза = верх стен последнего этажа.
  final lastFloor = building.floors.isNotEmpty ? building.floors.last : null;
  if (lastFloor == null) return;
  final eaveZ = lastFloor.elevationM + lastFloor.heightM;
  canvas.setStrokeColor(const PdfColor(0.20, 0.22, 0.24));
  canvas.setLineWidth(1.2);
  for (final corner in out) {
    // Чуть выносим трубу за угол (на 8 см) — иначе труба сливается со
    // стеной и не видна.
    final cx = building.center.x;
    final cy = building.center.y;
    final dx = corner.x - cx;
    final dy = corner.y - cy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 0.01) continue;
    final ox = corner.x + dx / len * 0.08;
    final oy = corner.y + dy / len * 0.08;
    final top = renderer.project(
        Vec3(ox, oy, eaveZ), camera, double.infinity, double.infinity);
    final bot = renderer.project(
        Vec3(ox, oy, 0), camera, double.infinity, double.infinity);
    // Окклюзия — оцениваем по середине; если за стеной — пропускаем.
    final midZ = (top.z + bot.z) / 2;
    if (_pointOccluded(
        (top.x + bot.x) / 2, (top.y + bot.y) / 2, midZ, projected)) {
      continue;
    }
    final st = toScreen(top);
    final sb = toScreen(bot);
    canvas.moveTo(st.x, st.y);
    canvas.lineTo(sb.x, sb.y);
    canvas.strokePath();
  }
}

/// Можно ли отсечь треугольник по 2D-back-face-cull-у. Грунт/слэбы/
/// окна/двери — горизонтальные/прозрачные плоскости, видны с обеих
/// сторон, отсечение их убирает.
bool _cullableInPdf(SurfaceKind kind) {
  switch (kind) {
    case SurfaceKind.ground:
    case SurfaceKind.slab:
    case SurfaceKind.glazing:
    case SurfaceKind.door:
      return false;
    default:
      return true;
  }
}
