// Phase-3b §17.2.2 + §21.3 + v68 §26: каталог из 12 готовых архетипов
// планировок с переключаемым 2D/3D-предпросмотром.
//
// v68 §26.4 (вторая итерация по жалобе «do сих пор перекрываются
// почти-непрозрачным фоном»): причины было две — (1) «scrim» от
// HintAutoShow.showDialog, срабатывавшего после того, как
// пользователь уже ушёл на каталог (починено в hints.dart §26.3),
// и (2) M3-тема давала слишком бледные варианты surface*. Сейчас
// все цвета карточек/подложки хардкодные (без surfaceTint и
// elevation overlay), чтобы карточка была явно белой на светло-
// серой подложке и читаема даже в grayscale-режиме (ОС-
// фильтр или color-blind тест). Hero-render, бывший с §26.1, в
// цвете материала — остаётся.
// Также явно добавлена кнопка «Назад» в AppBar — некоторые сборки
// MaterialPageRoute её скрывали.
//
// v68.11 §27 (правка «кнопки сливаются с фоном»): добавлена
// явная CTA-кнопка «Выбрать этот шаблон» внизу каждой карточки
// (FilledButton с primary-цветом + иконка → видна даже на
// grayscale-фильтре), подложка экрана сменена с pure-white на
// светло-лавандовую (карточки на ней не сливаются), бордер
// карточки 1.8 px primary-цвета, у выбранной — 3 px + цветная
// «шапка» 6 px. Сегментный переключатель «Базовый / VIP» получил
// плотный fill активной вкладки и более крупный шрифт.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/floor_plan_templates.dart';
import '../data/wall_materials.dart';

enum _ThumbView { topDown, isometric }

enum _CatalogTab { basic, extended }

class FloorPlanTemplatesPage extends StatefulWidget {
  /// Текущий выбранный шаблон. Если задан, его карточка визуально
  /// отмечается рамкой.
  final FloorPlanTemplate? initial;

  const FloorPlanTemplatesPage({super.key, this.initial});

  @override
  State<FloorPlanTemplatesPage> createState() =>
      _FloorPlanTemplatesPageState();
}

class _FloorPlanTemplatesPageState extends State<FloorPlanTemplatesPage> {
  // §21.3: предпросмотр — по умолчанию 3D, чтобы пользователь видел
  // дом в объёме. Можно переключить на «вид сверху» (старая 2D-форма).
  _ThumbView _view = _ThumbView.isometric;

  // §21.4: вкладка каталога — базовые 12 архетипов или расширенный
  // VIP-каталог (T/U/+ формы, большие усадьбы, нестандартные участки).
  _CatalogTab _tab = _CatalogTab.basic;

  @override
  Widget build(BuildContext context) {
    final templates = _tab == _CatalogTab.basic
        ? FloorPlanTemplateLibrary.all
        : FloorPlanTemplateLibrary.extended;
    // §26.5 (третья итерация): пользователь жалуется на «серый фон».
    // Дело в активном grayscale-фильтре на его стороне (мы это
    // подтвердили попиксельным анализом — R=G=B во всех образцах).
    // Поэтому ЛЮБОЙ цветной AppBar на его экране = серая полоса. Делаем
    // экран как home_page: AppBar на M3 default (светло-белый surface),
    // подложка — белая (surface), карточки на pure white, бордер
    // primary как в _TypeCard. На grayscale это будет белая страница
    // с белыми карточками и тонкой рамкой — то есть «полностью
    // светлый», как просил.
    const cardBg = Color(0xFFFFFFFF);
    const titleClr = Color(0xFF1A1C20);
    const tabIdleClr = Color(0xFF6B6E76);
    const tabActiveClr = Color(0xFF3D2D6E);
    // v68.11 §27: подложка не белая, а светло-лавандовая —
    // карточки на ней визуально «приподняты» и не сливаются.
    const screenBg = Color(0xFFF1EEF8);
    return Scaffold(
      backgroundColor: screenBg,
      appBar: AppBar(
        // §26.2: явная кнопка «Назад», чтобы пользователь всегда видел
        // выход из каталога. Закрывает страницу без выбора.
        leading: IconButton(
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'Каталог планировок',
          style: TextStyle(
            color: titleClr,
            fontWeight: FontWeight.w700,
          ),
        ),
        // §26.5: НЕ устанавливаем backgroundColor — пусть AppBar будет
        // как у home_page (M3 default — surface ~белый), чтобы при
        // grayscale-фильтре он не превращался в тёмно-серую полосу.
        // surfaceTint выключаем, чтобы при скролле не появлялся
        // подкрашенный фон.
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // v68.11 §27: вместо TabBar — сегментная кнопка с плотной
        // подложкой на активной вкладке. Намного контрастнее и
        // читается как «кнопка», а не как «вкладка».
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                _CatalogTabButton(
                  label:
                      'Базовый (${FloorPlanTemplateLibrary.all.length})',
                  icon: Icons.dashboard,
                  active: _tab == _CatalogTab.basic,
                  onTap: () => setState(() => _tab = _CatalogTab.basic),
                ),
                const SizedBox(width: 12),
                _CatalogTabButton(
                  label:
                      'VIP / расширенный (${FloorPlanTemplateLibrary.extended.length})',
                  icon: Icons.workspace_premium,
                  active: _tab == _CatalogTab.extended,
                  onTap: () => setState(() => _tab = _CatalogTab.extended),
                ),
              ],
            ),
          ),
        ),
        actions: [
          // Переключатель 2D / 3D миниатюры — на светлом AppBar его
          // делаем тёмным.
          ToggleButtons(
            isSelected: [
              _view == _ThumbView.topDown,
              _view == _ThumbView.isometric,
            ],
            onPressed: (i) {
              setState(() {
                _view = i == 0 ? _ThumbView.topDown : _ThumbView.isometric;
              });
            },
            color: tabIdleClr,
            selectedColor: cardBg,
            fillColor: tabActiveClr,
            borderColor: tabIdleClr.withValues(alpha: 0.5),
            selectedBorderColor: tabActiveClr,
            constraints:
                const BoxConstraints(minWidth: 56, minHeight: 36),
            children: const [
              Tooltip(message: 'Вид сверху', child: Icon(Icons.crop_square)),
              Tooltip(
                  message: '3D-аксонометрия',
                  child: Icon(Icons.view_in_ar)),
            ],
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Адаптивная сетка: 1 колонка на узком экране, 2/3 — на широких.
          final cols = constraints.maxWidth < 720
              ? 1
              : constraints.maxWidth < 1180
                  ? 2
                  : 3;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                // §26.1: hero-render над текстом → высокая карточка.
                // v68.11 §27: добавлена CTA-кнопка внизу + цветная
                // шапка сверху → ещё чуть выше.
                childAspectRatio: 0.78,
              ),
              itemCount: templates.length,
              itemBuilder: (context, i) {
                final t = templates[i];
                final isSelected = widget.initial?.id == t.id;
                return _TemplateCard(
                  template: t,
                  isSelected: isSelected,
                  view: _view,
                  onTap: () => Navigator.pop(context, t),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final FloorPlanTemplate template;
  final bool isSelected;
  final _ThumbView view;
  final VoidCallback onTap;
  const _TemplateCard({
    required this.template,
    required this.isSelected,
    required this.view,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = template;
    // §26.5 (третья итерация): пользователь жалуется на «серый фон»
    // даже после §26.4, потому что у него активен системный grayscale-
    // фильтр и любой dark color (тень, тёмный AppBar, dark border)
    // превращается в средний серый. Делаем страницу как home_page —
    // максимум БЕЛОГО, минимум тёмных пятен. Нет тяжёлой тени
    // (BoxShadow убрана), бордер только тонкий primary, hero-зона
    // тоже белая (без голубого неба).
    //
    // v68.11 §27: подложка экрана теперь светло-лавандовая (см.
    // build выше), поэтому белая карточка визуально «приподнята».
    // Бордер всегда primary-цвета (не серый!) — чтобы карточка
    // воспринималась как кнопка. У выбранной — толще 3 px и
    // дополнительная «шапка» 6 px цветной полосы сверху.
    const cardBg = Color(0xFFFFFFFF); // pure white
    const borderSel = Color(0xFF3D2D6E); // фиолет (как primary M3)
    const borderIdle = Color(0xFFB7AED9); // приглушённая лаванда (видно даже на ч/б)
    const titleClr = Color(0xFF1A1C20);
    const subtitleClr = Color(0xFF5A5E66);
    const descClr = Color(0xFF2E3138);
    const badgeBg = Color(0xFF3D2D6E);
    const badgeFg = Color(0xFFFFFFFF);
    return Material(
      color: cardBg,
      elevation: isSelected ? 4 : 2,
      shadowColor: borderSel.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? borderSel : borderIdle,
              width: isSelected ? 3 : 1.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // v68.11 §27: цветная «шапка» 6 px сверху карточки —
              // ярко-фиолетовая для выбранного, светло-лавандовая
              // для остальных. Превращает карточку в чёткий «таб»,
              // что видно даже периферийным зрением.
              Container(
                height: 6,
                color: isSelected ? borderSel : borderIdle,
              ),
              // ─── HERO-render ────────────────────────────────────────
              // Превью дома 180 px поверх белого фона (без голубого
              // неба, чтобы при grayscale-режиме hero-зона не
              // воспринималась серой полоской).
              SizedBox(
                height: 174,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Чисто белый фон hero-зоны.
                    const ColoredBox(color: cardBg),
                    // Сам дом.
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: CustomPaint(
                        painter: view == _ThumbView.isometric
                            ? _Iso3DHeroPainter(template: t)
                            : _TopDownHeroPainter(template: t),
                      ),
                    ),
                    // Бейдж тарифа (VIP / базовый) — справа сверху.
                    if (t.footprint != null ||
                        t.hasMansard ||
                        t.hasBasement ||
                        t.hasGarage)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                t.footprint != null
                                    ? Icons.architecture
                                    : Icons.star,
                                size: 12,
                                color: badgeFg,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                t.footprint != null ? 'L/T/U' : 'PRO',
                                style: const TextStyle(
                                  color: badgeFg,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // «Птичка», что выбран — слева сверху.
                    if (isSelected)
                      const Positioned(
                        top: 10,
                        left: 10,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: borderSel,
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.check,
                              size: 14,
                              color: badgeFg,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // ─── Текст и теги ───────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: titleClr,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.tagline,
                        style: const TextStyle(
                          fontSize: 12,
                          color: subtitleClr,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Text(
                          t.description,
                          style: const TextStyle(
                            fontSize: 12,
                            color: descClr,
                            height: 1.35,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _Tag(
                              '${t.footprintWidth.toStringAsFixed(0)}×${t.footprintLength.toStringAsFixed(0)} м'),
                          _Tag('${t.floors} эт.'),
                          if (t.hasMansard) const _Tag('+мансарда'),
                          if (t.hasBasement) const _Tag('+подвал'),
                          if (t.hasGarage) const _Tag('+гараж'),
                          if (t.footprint != null) const _Tag('L-форма'),
                          if (t.targetArea != null)
                            _Tag('${t.targetArea!.toStringAsFixed(0)} м²'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // v68.11 §27: явная CTA-кнопка «Выбрать этот
                      // шаблон». До этого карточка тапалась целиком,
                      // но без видимой кнопки пользователь не знал,
                      // что нужно нажать. Теперь кнопка занимает
                      // полную ширину карточки и видна даже на
                      // ч/б-фильтре.
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: FilledButton.icon(
                          onPressed: onTap,
                          icon: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.arrow_forward_rounded,
                            size: 18,
                          ),
                          label: Text(
                            isSelected ? 'Выбрано' : 'Выбрать шаблон',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: borderSel,
                            foregroundColor: badgeFg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// v68.11 §27: «таб»-кнопка для переключателя «Базовый / VIP».
/// Заменяет прежний `TabBar` на видную сегментную кнопку с
/// плотным fill-ом активной вкладки и крупным шрифтом.
class _CatalogTabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _CatalogTabButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const activeBg = Color(0xFF3D2D6E);
    const activeFg = Color(0xFFFFFFFF);
    const idleBg = Color(0xFFFFFFFF);
    const idleFg = Color(0xFF3D2D6E);
    const idleBorder = Color(0xFFB7AED9);
    return Expanded(
      child: Material(
        color: active ? activeBg : idleBg,
        elevation: active ? 3 : 1,
        shadowColor: activeBg.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? activeBg : idleBorder,
                width: active ? 0 : 1.6,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: active ? activeFg : idleFg),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? activeFg : idleFg,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// §26.1 — увеличенная изометрическая 3D-картинка для hero-зоны
/// карточки. Существенно отличается от старого `_Iso3DThumbPainter`:
///
///  * Стены окрашиваются в **реальный цвет материала** (кирпич — терракота,
///    газобетон — светло-серый, брус — медовый, каркас — бежевый и т.д.),
///    а не abstract `theme.colorScheme.primary` с alpha=0.18.
///  * Кровля — серовато-коричневая (цвет металлочерепицы по умолчанию).
///  * Подвал/цоколь — тёмная полоска под нулём.
///  * Мансарда — увеличенная высота кровли (1.5×), чтобы было видно
///    «жилое подкровельное пространство».
///  * Гараж — пристройка справа (4×6 м) с собственной двускатной
///    крышей, окрашен в чуть более тёмный тон.
///  * Тёмная полоса земли — основание под домом (ground-shadow).
///
/// Изометрия: x' = (x − y) · cos30°, y' = −z + (x + y) · sin30°.
class _Iso3DHeroPainter extends CustomPainter {
  final FloorPlanTemplate template;
  _Iso3DHeroPainter({required this.template});

  static const double _cosA = 0.866; // cos 30°
  static const double _sinA = 0.5; // sin 30°

  Offset _project(double x, double y, double z, double scale, Offset origin) {
    final px = (x - y) * _cosA * scale;
    final py = (-z + (x + y) * _sinA) * scale;
    return Offset(origin.dx + px, origin.dy + py);
  }

  /// Цвета материала стен. Цвета подобраны под российскую палитру:
  /// кирпич — типичный лицевой М-150, газобетон — D500 серый,
  /// керамзитоблок — желтоватый бетон, брус — медовая сосна,
  /// каркас — окрашенная штукатурка / сайдинг бежевый.
  ({Color side, Color top}) _wallColors() {
    switch (template.wallMaterial) {
      case WallMaterial.brick:
        return (
          side: const Color(0xFFB55A47), // лицевой кирпич
          top: const Color(0xFF8C3D2E),
        );
      case WallMaterial.aerated:
        return (
          side: const Color(0xFFD9D6CF),
          top: const Color(0xFFA9A6A0),
        );
      case WallMaterial.expandedClay:
        return (
          side: const Color(0xFFC9B783),
          top: const Color(0xFF8E7C56),
        );
      case WallMaterial.timber:
        return (
          side: const Color(0xFFC58E4F),
          top: const Color(0xFF8C6432),
        );
      case WallMaterial.frame:
        return (
          side: const Color(0xFFE6D7B0),
          top: const Color(0xFFB6A67E),
        );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = template;
    final fp = t.footprint;
    final w = t.footprintWidth;
    final l = t.footprintLength;
    final outline = fp != null
        ? fp.outline.map((v) => Offset(v.x, v.y)).toList()
        : <Offset>[
            const Offset(0, 0),
            Offset(w, 0),
            Offset(w, l),
            Offset(0, l),
          ];
    const hFloor = 3.0;
    final hWall = t.floors * hFloor;
    // Если есть мансарда — крыша выше, иначе — пропорциональная пятну.
    final mansardBoost = t.hasMansard ? 1.5 : 1.0;
    final zBase = t.hasBasement ? -0.6 : 0.0;
    const slopeDeg = 35.0;
    const slopeRad = slopeDeg * math.pi / 180.0;

    var minX = double.infinity,
        minY = double.infinity,
        maxX = -double.infinity,
        maxY = -double.infinity;
    for (final p in outline) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    // Если есть гараж — нарисуем его справа от пятна (4×6 м).
    final hasGarage = t.hasGarage;
    const garageW = 4.0;
    const garageH = 6.0;
    final garageX0 = maxX; // примыкает справа
    final garageY0 = maxY - garageH;
    final garageX1 = maxX + garageW;
    final garageY1 = maxY;

    final bboxW = (hasGarage ? garageX1 : maxX) - minX;
    final bboxH = maxY - minY;

    // Высота крыши = (минимальная сторона) / 2 · tan α · boost.
    final hRoof =
        (math.min(bboxW, bboxH) / 2) * math.tan(slopeRad) * mansardBoost;
    final zTop = zBase + hWall + hRoof;

    // Подбираем масштаб так, чтобы 3D-bbox после проекции вписался
    // в canvas.size с padding-ом.
    const pad = 8.0;
    final probes = <Offset>[];
    final probeMinX = minX, probeMaxX = hasGarage ? garageX1 : maxX;
    final probeMinY = minY, probeMaxY = maxY;
    for (final z in [zBase - 0.1, zTop]) {
      probes.add(_project(probeMinX, probeMinY, z, 1.0, Offset.zero));
      probes.add(_project(probeMaxX, probeMinY, z, 1.0, Offset.zero));
      probes.add(_project(probeMaxX, probeMaxY, z, 1.0, Offset.zero));
      probes.add(_project(probeMinX, probeMaxY, z, 1.0, Offset.zero));
    }
    var pminX = double.infinity, pmaxX = -double.infinity;
    var pminY = double.infinity, pmaxY = -double.infinity;
    for (final p in probes) {
      if (p.dx < pminX) pminX = p.dx;
      if (p.dx > pmaxX) pmaxX = p.dx;
      if (p.dy < pminY) pminY = p.dy;
      if (p.dy > pmaxY) pmaxY = p.dy;
    }
    final pW = pmaxX - pminX, pH = pmaxY - pminY;
    final scale = math.min(
      (size.width - 2 * pad) / pW,
      (size.height - 2 * pad) / pH,
    );
    final origin = Offset(
      (size.width - (pmaxX + pminX) * scale) / 2,
      (size.height - (pmaxY + pminY) * scale) / 2 + 4,
    );

    Offset prj(double x, double y, double z) =>
        _project(x, y, z, scale, origin);

    final wallC = _wallColors();
    final fillSide = Paint()
      ..color = wallC.side
      ..style = PaintingStyle.fill;
    final fillSideShaded = Paint()
      ..color = wallC.top
      ..style = PaintingStyle.fill;
    final fillRoof = Paint()
      ..color = const Color(0xFF7E6F5A) // металлочерепица серо-коричневая
      ..style = PaintingStyle.fill;
    final fillRoofLit = Paint()
      ..color = const Color(0xFF9E8E78)
      ..style = PaintingStyle.fill;
    final fillBasement = Paint()
      ..color = const Color(0xFF6B6260)
      ..style = PaintingStyle.fill;
    final groundShadow = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    final strokeThin = Paint()
      ..color = const Color(0xFF3D3D3D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // ─── Тень на земле (овал под домом). ──────────────────────────
    {
      final shadowCenter = prj((minX + probeMaxX) / 2,
          (minY + maxY) / 2, zBase - 0.05);
      final shadowRect = Rect.fromCenter(
        center: shadowCenter,
        width: (probeMaxX - minX) * scale * 1.05,
        height: (maxY - minY) * scale * 0.55,
      );
      canvas.drawOval(shadowRect, groundShadow);
    }

    // ─── Цоколь / подвал (тонкая полоска под стенами). ────────────
    if (t.hasBasement) {
      _drawExtrusion(
        canvas,
        outline,
        zLo: zBase,
        zHi: 0.0,
        prj: prj,
        sideFill: fillBasement,
        topFill: fillBasement,
        stroke: strokeThin,
      );
    }

    // ─── Стены основного объёма. ───────────────────────────────────
    _drawExtrusion(
      canvas,
      outline,
      zLo: math.max(zBase, 0.0),
      zHi: hWall,
      prj: prj,
      sideFill: fillSide,
      sideFillShaded: fillSideShaded,
      topFill: fillSide,
      stroke: stroke,
    );

    // ─── Окна (черно-голубые квадраты на видимых гранях). ─────────
    _drawWindows(
      canvas,
      outline,
      hWall: hWall,
      floors: t.floors + (t.hasMansard ? 1 : 0),
      prj: prj,
    );

    // ─── Кровля (двускатная, конёк по длинной стороне bbox-а). ───
    final ridgeAlongX = (maxX - minX) >= (maxY - minY);
    final cy = (minY + maxY) / 2;
    final cx = (minX + maxX) / 2;
    final zRidge = zBase + hWall + hRoof;
    if (ridgeAlongX) {
      final r1 = prj(minX, cy, zRidge);
      final r2 = prj(maxX, cy, zRidge);
      final c1 = prj(minX, minY, zBase + hWall);
      final c2 = prj(maxX, minY, zBase + hWall);
      final c3 = prj(maxX, maxY, zBase + hWall);
      final c4 = prj(minX, maxY, zBase + hWall);
      // Передний скат (более освещённый).
      final pFront = Path()
        ..moveTo(c4.dx, c4.dy)
        ..lineTo(c3.dx, c3.dy)
        ..lineTo(r2.dx, r2.dy)
        ..lineTo(r1.dx, r1.dy)
        ..close();
      canvas.drawPath(pFront, fillRoofLit);
      canvas.drawPath(pFront, stroke);
      // Задний скат (тёмный, частично закрыт).
      final pBack = Path()
        ..moveTo(c1.dx, c1.dy)
        ..lineTo(c2.dx, c2.dy)
        ..lineTo(r2.dx, r2.dy)
        ..lineTo(r1.dx, r1.dy)
        ..close();
      canvas.drawPath(pBack, fillRoof);
      canvas.drawPath(pBack, stroke);
      canvas.drawLine(r1, r2, stroke);
    } else {
      final r1 = prj(cx, minY, zRidge);
      final r2 = prj(cx, maxY, zRidge);
      final c1 = prj(minX, minY, zBase + hWall);
      final c2 = prj(maxX, minY, zBase + hWall);
      final c3 = prj(maxX, maxY, zBase + hWall);
      final c4 = prj(minX, maxY, zBase + hWall);
      final pFront = Path()
        ..moveTo(c2.dx, c2.dy)
        ..lineTo(c3.dx, c3.dy)
        ..lineTo(r2.dx, r2.dy)
        ..lineTo(r1.dx, r1.dy)
        ..close();
      canvas.drawPath(pFront, fillRoofLit);
      canvas.drawPath(pFront, stroke);
      final pBack = Path()
        ..moveTo(c1.dx, c1.dy)
        ..lineTo(c4.dx, c4.dy)
        ..lineTo(r2.dx, r2.dy)
        ..lineTo(r1.dx, r1.dy)
        ..close();
      canvas.drawPath(pBack, fillRoof);
      canvas.drawPath(pBack, stroke);
      canvas.drawLine(r1, r2, stroke);
    }

    // ─── Гараж справа (если есть). ─────────────────────────────────
    if (hasGarage) {
      const gFloor = 3.0;
      final garageOutline = <Offset>[
        Offset(garageX0, garageY0),
        Offset(garageX1, garageY0),
        Offset(garageX1, garageY1),
        Offset(garageX0, garageY1),
      ];
      // Стены гаража (чуть темнее основного объёма).
      _drawExtrusion(
        canvas,
        garageOutline,
        zLo: 0.0,
        // ignore: prefer_const_declarations
        zHi: gFloor,
        prj: prj,
        sideFill: fillSideShaded,
        topFill: fillSideShaded,
        stroke: stroke,
      );
      // Двускатная крыша гаража.
      final gRoofH = garageW / 2 * math.tan(slopeRad);
      final gZRidge = gFloor + gRoofH;
      final gcx = (garageX0 + garageX1) / 2;
      final r1 = prj(gcx, garageY0, gZRidge);
      final r2 = prj(gcx, garageY1, gZRidge);
      final c1 = prj(garageX0, garageY0, gFloor);
      final c2 = prj(garageX1, garageY0, gFloor);
      final c3 = prj(garageX1, garageY1, gFloor);
      final c4 = prj(garageX0, garageY1, gFloor);
      final pFront = Path()
        ..moveTo(c2.dx, c2.dy)
        ..lineTo(c3.dx, c3.dy)
        ..lineTo(r2.dx, r2.dy)
        ..lineTo(r1.dx, r1.dy)
        ..close();
      canvas.drawPath(pFront, fillRoofLit);
      canvas.drawPath(pFront, stroke);
      final pBack = Path()
        ..moveTo(c1.dx, c1.dy)
        ..lineTo(c4.dx, c4.dy)
        ..lineTo(r2.dx, r2.dy)
        ..lineTo(r1.dx, r1.dy)
        ..close();
      canvas.drawPath(pBack, fillRoof);
      canvas.drawPath(pBack, stroke);
      canvas.drawLine(r1, r2, stroke);
      // Дверь гаража.
      const doorW = garageW * 0.7;
      const doorH = gFloor * 0.75;
      final dx0 = garageX0 + (garageW - doorW) / 2;
      final dx1 = dx0 + doorW;
      final dy0 = garageY0;
      final d1 = prj(dx0, dy0, 0.05);
      final d2 = prj(dx1, dy0, 0.05);
      final d3 = prj(dx1, dy0, doorH);
      final d4 = prj(dx0, dy0, doorH);
      final pDoor = Path()
        ..moveTo(d1.dx, d1.dy)
        ..lineTo(d2.dx, d2.dy)
        ..lineTo(d3.dx, d3.dy)
        ..lineTo(d4.dx, d4.dy)
        ..close();
      canvas.drawPath(
        pDoor,
        Paint()
          ..color = const Color(0xFF3A3936)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(pDoor, stroke);
    }

    // zTop вычисляется на случай, если в будущем понадобится клиппинг
    // по облачной/sky-зоне; сейчас используется только как отметка
    // верхней высоты в логе ─ см. ассерт ниже.
    assert(zTop >= zBase);
  }

  /// Рисует «коробку» — extrude outline-а от `zLo` до `zHi`. Сначала
  /// рисуются грани (видимые с виртуального угла обзора), затем верх
  /// (как «крыша» куба, перекрывает спрятанные рёбра).
  void _drawExtrusion(
    Canvas canvas,
    List<Offset> outline, {
    required double zLo,
    required double zHi,
    required Offset Function(double, double, double) prj,
    required Paint sideFill,
    Paint? sideFillShaded,
    required Paint topFill,
    required Paint stroke,
  }) {
    // Грани: для каждого ребра outline-а — четырёхугольник между
    // нижним и верхним уровнем.
    for (var i = 0; i < outline.length; i++) {
      final a = outline[i];
      final b = outline[(i + 1) % outline.length];
      final p1 = prj(a.dx, a.dy, zLo);
      final p2 = prj(b.dx, b.dy, zLo);
      final p3 = prj(b.dx, b.dy, zHi);
      final p4 = prj(a.dx, a.dy, zHi);
      // У 30°-изометрии «передними» считаем грани, обращённые к
      // зрителю; решаем по нормали ребра. Проще: ребро «передняя
      // сторона», если y-координаты обоих концов больше другой пары.
      // Используем простую эвристику: ребро видимо, если a.dy > b.dy
      // (диагональ от низа к верху изометрии) ИЛИ a.dx > b.dx.
      final isFront = (a.dy >= b.dy) || (a.dx > b.dx);
      final paint = isFront ? sideFill : (sideFillShaded ?? sideFill);
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..lineTo(p4.dx, p4.dy)
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawPath(path, stroke);
    }
    // Верх (закрашиваем «крышку» extrude-а).
    final topPath = Path();
    for (var i = 0; i < outline.length; i++) {
      final p = outline[i];
      final q = prj(p.dx, p.dy, zHi);
      if (i == 0) {
        topPath.moveTo(q.dx, q.dy);
      } else {
        topPath.lineTo(q.dx, q.dy);
      }
    }
    topPath.close();
    canvas.drawPath(topPath, topFill);
    canvas.drawPath(topPath, stroke);
  }

  /// Рисует ряды окон на видимых гранях extrude. Грубая декорация —
  /// нужно лишь намекнуть пользователю, что у дома есть окна.
  void _drawWindows(
    Canvas canvas,
    List<Offset> outline, {
    required double hWall,
    required int floors,
    required Offset Function(double, double, double) prj,
  }) {
    if (floors <= 0) return;
    final winFill = Paint()
      ..color = const Color(0xFF8FB7D9)
      ..style = PaintingStyle.fill;
    final winStroke = Paint()
      ..color = const Color(0xFF2D4D6E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final hFloor = hWall / floors;
    for (var i = 0; i < outline.length; i++) {
      final a = outline[i];
      final b = outline[(i + 1) % outline.length];
      // Только «передние» грани (y от низа к верху).
      final isFront = (a.dy >= b.dy) || (a.dx > b.dx);
      if (!isFront) continue;
      // Длина ребра.
      final len = math.sqrt(
          (b.dx - a.dx) * (b.dx - a.dx) + (b.dy - a.dy) * (b.dy - a.dy));
      if (len < 2.5) continue;
      final winCount = math.max(1, (len / 3.0).floor());
      for (var f = 0; f < floors; f++) {
        final z0 = f * hFloor + 0.9;
        final z1 = z0 + 1.4;
        for (var w = 0; w < winCount; w++) {
          final tStart = (w + 0.5) / winCount - 0.12;
          final tEnd = (w + 0.5) / winCount + 0.12;
          final x0 = a.dx + (b.dx - a.dx) * tStart;
          final y0 = a.dy + (b.dy - a.dy) * tStart;
          final x1 = a.dx + (b.dx - a.dx) * tEnd;
          final y1 = a.dy + (b.dy - a.dy) * tEnd;
          final p1 = prj(x0, y0, z0);
          final p2 = prj(x1, y1, z0);
          final p3 = prj(x1, y1, z1);
          final p4 = prj(x0, y0, z1);
          final path = Path()
            ..moveTo(p1.dx, p1.dy)
            ..lineTo(p2.dx, p2.dy)
            ..lineTo(p3.dx, p3.dy)
            ..lineTo(p4.dx, p4.dy)
            ..close();
          canvas.drawPath(path, winFill);
          canvas.drawPath(path, winStroke);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_Iso3DHeroPainter oldDelegate) =>
      oldDelegate.template.id != template.id;
}

/// «Вид сверху» hero-render для случаев, когда пользователь
/// переключил toggle на 2D. Цвет стен — материал, кровля — серо-
/// коричневая контурная заливка над пятном.
class _TopDownHeroPainter extends CustomPainter {
  final FloorPlanTemplate template;
  _TopDownHeroPainter({required this.template});

  ({Color side}) _wallColor() {
    switch (template.wallMaterial) {
      case WallMaterial.brick:
        return (side: const Color(0xFFB55A47));
      case WallMaterial.aerated:
        return (side: const Color(0xFFD9D6CF));
      case WallMaterial.expandedClay:
        return (side: const Color(0xFFC9B783));
      case WallMaterial.timber:
        return (side: const Color(0xFFC58E4F));
      case WallMaterial.frame:
        return (side: const Color(0xFFE6D7B0));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = template;
    final fp = t.footprint;
    final w = t.footprintWidth;
    final l = t.footprintLength;
    final outline = fp != null
        ? fp.outline.map((v) => Offset(v.x, v.y)).toList()
        : <Offset>[
            const Offset(0, 0),
            Offset(w, 0),
            Offset(w, l),
            Offset(0, l),
          ];

    var minX = double.infinity,
        minY = double.infinity,
        maxX = -double.infinity,
        maxY = -double.infinity;
    for (final p in outline) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final hasGarage = t.hasGarage;
    final garageX0 = maxX, garageX1 = maxX + 4.0;
    final garageY0 = maxY - 6.0, garageY1 = maxY;
    final bboxW = (hasGarage ? garageX1 : maxX) - minX;
    final bboxH = maxY - minY;
    const pad = 12.0;
    final scale = math.min(
      (size.width - 2 * pad) / bboxW,
      (size.height - 2 * pad) / bboxH,
    );
    final ox = (size.width - bboxW * scale) / 2 - minX * scale;
    final oy = (size.height - bboxH * scale) / 2 - minY * scale;

    final wallC = _wallColor();
    final fillBuilding = Paint()
      ..color = wallC.side
      ..style = PaintingStyle.fill;
    final fillRoof = Paint()
      ..color = const Color(0xFF7E6F5A)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0xFF2A2A2A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    Offset toPx(Offset p) => Offset(ox + p.dx * scale, oy + p.dy * scale);

    final path = Path();
    for (var i = 0; i < outline.length; i++) {
      final p = toPx(outline[i]);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, fillRoof);
    canvas.drawPath(path, stroke);

    // Внутренний контур — стены (отступ 0.4 м).
    final inner = Path();
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    for (var i = 0; i < outline.length; i++) {
      final p = outline[i];
      final dx = p.dx - cx, dy = p.dy - cy;
      final len = math.sqrt(dx * dx + dy * dy);
      final shrunk = len > 0
          ? Offset(cx + dx * (len - 0.4) / len, cy + dy * (len - 0.4) / len)
          : Offset(cx, cy);
      final q = toPx(shrunk);
      if (i == 0) {
        inner.moveTo(q.dx, q.dy);
      } else {
        inner.lineTo(q.dx, q.dy);
      }
    }
    inner.close();
    canvas.drawPath(inner, fillBuilding);
    canvas.drawPath(inner, stroke);

    // Гараж как пристройка справа.
    if (hasGarage) {
      final gOutline = <Offset>[
        Offset(garageX0, garageY0),
        Offset(garageX1, garageY0),
        Offset(garageX1, garageY1),
        Offset(garageX0, garageY1),
      ];
      final gPath = Path();
      for (var i = 0; i < gOutline.length; i++) {
        final p = toPx(gOutline[i]);
        if (i == 0) {
          gPath.moveTo(p.dx, p.dy);
        } else {
          gPath.lineTo(p.dx, p.dy);
        }
      }
      gPath.close();
      canvas.drawPath(gPath, fillRoof);
      canvas.drawPath(gPath, stroke);
    }
  }

  @override
  bool shouldRepaint(_TopDownHeroPainter oldDelegate) =>
      oldDelegate.template.id != template.id;
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);
  @override
  Widget build(BuildContext context) {
    // §26.4: хардкод-цвета — независимы от M3-темы.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEFEAFB), // бледно-фиолетовый
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF7E6DC0), width: 0.8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF2A1F5C),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
