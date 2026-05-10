import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Иконка «?» в AppBar, открывает диалог с пошаговой подсказкой по экрану.
///
/// Подсказки оформлены единообразно по всем экранам, чтобы у пользователя
/// формировалась привычная навигация: «не понятно — нажми вопросик в углу».
class HintIconButton extends StatelessWidget {
  const HintIconButton({
    super.key,
    required this.title,
    required this.sections,
    this.tooltip = 'Подсказка по этому экрану',
  });

  final String title;
  final List<HintSection> sections;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.help_outline),
      onPressed: () => showHintDialog(
        context,
        title: title,
        sections: sections,
        // Из ручного «?» можно тоже выключить экскурсию, чтобы не лазить
        // в настройки — поведение симметрично авто-показу.
        showDisableButton: true,
      ),
    );
  }
}

/// Виджет-обёртка, который при первом построении в текущей сессии
/// автоматически показывает обучающую подсказку для экрана `screenKey`.
///
/// Не вмешивается в дерево виджетов: возвращает [child] как есть.
/// Состояние «уже показывали» хранится в [AppState], сбрасывается на
/// новой загрузке страницы — пользователя «ведут за руку» при каждом
/// заходе. Когда пользователь нажимает «Не показывать подсказки» в
/// диалоге, флаг `hintsEnabled` сохраняется в SharedPreferences.
class HintAutoShow extends StatefulWidget {
  const HintAutoShow({
    super.key,
    required this.screenKey,
    required this.title,
    required this.sections,
    required this.child,
  });

  final String screenKey;
  final String title;
  final List<HintSection> sections;
  final Widget child;

  @override
  State<HintAutoShow> createState() => _HintAutoShowState();
}

class _HintAutoShowState extends State<HintAutoShow> {
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    final state = context.read<AppState>();
    if (!state.shouldAutoShowHint(widget.screenKey)) return;
    _scheduled = true;
    state.markHintShown(widget.screenKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // v68 §26.3: пользователь мог уйти на другой роут (например,
      // открыть каталог шаблонов) до того, как post-frame callback
      // успел сработать. В этом случае showDialog по нашему context-у
      // повесит alert поверх НОВОГО экрана, и его scrim перекроет
      // каталог почти-непрозрачной серой плёнкой. Защищаемся
      // проверкой ModalRoute.isCurrent — если наш экран уже не
      // верхний, подсказку не показываем.
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      showHintDialog(
        context,
        title: widget.title,
        sections: widget.sections,
        showDisableButton: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Один раздел подсказки. Может быть либо текстовым абзацем (через [body]),
/// либо нумерованным/маркированным списком (через [bullets]).
class HintSection {
  const HintSection({
    required this.heading,
    this.body,
    this.bullets = const [],
    this.icon,
  });

  final String heading;
  final String? body;
  final List<String> bullets;
  final IconData? icon;
}

Future<void> showHintDialog(
  BuildContext context, {
  required String title,
  required List<HintSection> sections,
  bool showDisableButton = false,
}) {
  final theme = Theme.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        icon: const Icon(Icons.lightbulb_outline),
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in sections) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (s.icon != null) ...[
                        Icon(
                          s.icon,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          s.heading,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (s.body != null) ...[
                    Text(
                      s.body!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  if (s.bullets.isNotEmpty) ...[
                    for (final b in s.bullets)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6, right: 8),
                              child: Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                b,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (showDisableButton)
            TextButton(
              onPressed: () async {
                // Снимаем экскурсию глобально и закрываем диалог. Используем
                // context самой страницы (он переживает закрытие диалога),
                // чтобы безопасно дёрнуть AppState.
                final state = context.read<AppState>();
                Navigator.pop(dialogContext);
                await state.setHintsEnabled(false);
              },
              child: const Text('Не показывать подсказки'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Понятно'),
          ),
        ],
      );
    },
  );
}

/// Все тексты подсказок собраны в одном месте — проще править формулировки
/// без обхода экранов. Каждый метод возвращает список секций для диалога.
class Hints {
  const Hints._();

  static const List<HintSection> projectCreate = [
    HintSection(
      heading: 'Создание проекта',
      icon: Icons.add,
      body: 'Два поля: название и тип сооружения. Название можно поменять '
          'позже — это просто метка для списка проектов.',
    ),
    HintSection(
      heading: 'Тип сооружения',
      icon: Icons.home_work_outlined,
      bullets: [
        'Частный дом — основной сценарий: фундамент, стены, крыша, '
            'опционально лестница и мансарда.',
        'Многоквартирный дом — заглушка («скоро»), пока не используется.',
        'Металлоконструкция — заглушка («скоро»), пока не используется.',
      ],
    ),
    HintSection(
      heading: 'Что дальше',
      icon: Icons.arrow_forward,
      body: 'После «Создать проект» откроется экран проекта с тремя '
          'разделами: техническое задание, состав, чертежи. Стартуйте с технического задания.',
    ),
  ];

  static const List<HintSection> home = [
    HintSection(
      heading: 'Что это за экран?',
      icon: Icons.architecture_outlined,
      body: 'Главный экран — короткая инструкция и выбор того, что вы '
          'хотите спроектировать. Ниже — ваши уже созданные проекты, '
          'если они есть.',
    ),
    HintSection(
      heading: 'Как создать проект',
      icon: Icons.add,
      bullets: [
        'Выберите тип сооружения в блоке «Что вы хотите спроектировать?».',
        'Введите название проекта и нажмите «Создать».',
        'После создания откроется проект — там техническое задание, состав и чертежи.',
      ],
    ),
    HintSection(
      heading: 'Поделиться приложением',
      icon: Icons.share_outlined,
      body: 'Кнопки сверху (WhatsApp, Telegram, ВКонтакте, Одноклассники) '
          'отправят ссылку на это приложение в выбранный мессенджер или '
          'соцсеть.',
    ),
    HintSection(
      heading: 'Удалить или переименовать',
      icon: Icons.more_vert,
      body: 'Меню «⋮» справа на карточке проекта — переименовать или '
          'удалить. Удаление необратимо.',
    ),
  ];

  static const List<HintSection> projectDetails = [
    HintSection(
      heading: 'Четыре последовательных этапа',
      icon: Icons.account_tree_outlined,
      body: 'Каждый следующий этап открывается только после завершения '
          'предыдущего — это нужно, чтобы подбор материалов и фундамента '
          'опирался на уже зафиксированные исходные данные.',
    ),
    HintSection(
      heading: '1. Начальные данные',
      icon: Icons.assignment_outlined,
      body: 'Площадь, число и состав комнат, этажность, ориентировочный '
          'материал стен. Никаких вопросов о грунте и климате — они '
          'появятся ровно тогда, когда понадобятся (этап «Фундамент»).',
    ),
    HintSection(
      heading: '2. Планировка',
      icon: Icons.draw_outlined,
      body: 'Четыре подраздела: планировка по этажам, стены, перекрытия, '
          'лестница (если этажей больше одного). Все материалы выбираются '
          'здесь, до расчёта нагрузок на фундамент.',
    ),
    HintSection(
      heading: '3. Фундамент',
      icon: Icons.foundation_outlined,
      body: 'Четыре шага: тип фундамента → инженерно-геология (грунт, '
          'снеговой и ветровой район) → устройство → расчётный результат '
          'с пояснительной запиской.',
    ),
    HintSection(
      heading: '4. Кровля',
      icon: Icons.roofing_outlined,
      body: 'Тип кровли, угол ската, покрытие. Для плоской кровли угол '
          'не запрашивается.',
    ),
    HintSection(
      heading: 'Техническое задание',
      icon: Icons.description_outlined,
      body: 'После всех четырёх этапов появится финальная карточка — '
          'автоматически собранное техзадание со всеми данными и '
          'возможностью скачать комплект чертежей PDF/DXF.',
    ),
  ];

  static const List<HintSection> stagePlanning = [
    HintSection(
      heading: 'Этап 2: что заполняем',
      icon: Icons.draw_outlined,
      body: 'Этот этап определяет геометрию дома и материалы строения. '
          'После него фундамент будет известно «как нагружать», а кровля — '
          '«какую опору она имеет».',
    ),
    HintSection(
      heading: 'Планировка',
      icon: Icons.crop_square,
      body: 'Если плана ещё нет, нажмите «Сгенерировать» — состав комнат '
          'из этапа 1 разместится по этажам автоматически. Дальше открывается '
          'редактор: тащите комнаты, ставьте двери/окна, сохраняйте версию.',
    ),
    HintSection(
      heading: 'Стены',
      icon: Icons.view_column_outlined,
      body: 'Уточняем материал и толщину наружных стен. На этапе 1 был '
          'только ориентир — здесь делаем окончательный выбор.',
    ),
    HintSection(
      heading: 'Перекрытия',
      icon: Icons.horizontal_rule_outlined,
      body: 'Монолит, сборное ж/б, деревянные или металлические балки. '
          'Сечения и армирование подберёт расчётный движок при формировании '
          'чертежей.',
    ),
    HintSection(
      heading: 'Лестница',
      icon: Icons.stairs_outlined,
      body: 'Появляется автоматически, если этажей больше одного, '
          'есть мансарда или подвал. Тип, число ступеней, высота.',
    ),
  ];

  static const List<HintSection> technicalSpec = [
    HintSection(
      heading: 'Что такое «Техническое задание»',
      icon: Icons.description_outlined,
      body: 'Это итоговый документ проекта: исходные данные клиента, '
          'выбранные материалы, расчёты по фундаменту и кровле, плюс '
          'комплект планов этажей. Собирается автоматически из ответов на '
          'четырёх этапах — отдельно ничего заполнять не нужно.',
    ),
    HintSection(
      heading: 'Что скачивается сейчас',
      icon: Icons.download,
      body: 'Кнопка ниже открывает раздел чертежей: оттуда можно выгрузить '
          'PDF (по листу на этаж) и DXF (для AutoCAD/QCAD/LibreCAD).',
    ),
    HintSection(
      heading: 'Что появится дальше',
      icon: Icons.update,
      body: 'Полная пояснительная записка с титулом и расчётами в одном '
          'PDF — следующая фаза разработки.',
    ),
  ];

  static const List<HintSection> composition = [
    HintSection(
      heading: 'Состав сооружения',
      icon: Icons.account_tree_outlined,
      body: 'Список конструктивных элементов, подобранных по техническому заданию.',
    ),
    HintSection(
      heading: 'Режим «Клиент»',
      icon: Icons.person_outline,
      body: 'Список — только для просмотра. Чтобы поменять рекомендацию, '
          'отредактируйте техническое задание (например, измените тип грунта или этажность). '
          'После этого нажмите «Перегенерировать» внизу — состав и чертежи '
          'обновятся.',
    ),
    HintSection(
      heading: 'Режим «Проектировщик»',
      icon: Icons.engineering_outlined,
      bullets: [
        'Каждый элемент списка кликабельный — открывается визард с '
            'параметрами (тип фундамента, материал стен и т. д.).',
        '«Перегенерировать чертежи» создаёт новую партию эскизов с '
            'учётом текущего состава. Старые партии остаются в истории.',
        '«Сбросить к авторасчёту» — вернуть рекомендацию движка правил.',
      ],
    ),
    HintSection(
      heading: 'Обоснование выбора фундамента',
      icon: Icons.fact_check_outlined,
      body: 'Под карточкой фундамента — короткий список «почему именно '
          'такой» (со ссылками на СП). Полезно показать клиенту.',
    ),
  ];

  static const List<HintSection> briefWizard = [
    HintSection(
      heading: 'Этап 1 в 6 шагов',
      icon: Icons.assignment_outlined,
      body: 'Стрелки внизу — «Назад / Далее». Прогресс сохраняется после '
          'каждого шага: можно безопасно закрыть приложение.',
    ),
    HintSection(
      heading: 'Шаги',
      icon: Icons.list_alt,
      bullets: [
        '1. Этажность + мансарда / цокольный или подвальный этаж.',
        '2. Целевая площадь и габариты здания (ширина × длина).',
        '3. Комнаты — выберите, сколько каких типов нужно.',
        '4. Дополнения — гараж, терраса, балкон, эркер, второй свет, '
            'лестница.',
        '5. Ориентировочный материал стен (кирпич, газобетон, дерево…). '
            'Точная толщина и марка выбираются на этапе «Стены».',
        '6. Особые пожелания — свободный текст.',
      ],
    ),
    HintSection(
      heading: 'Что НЕ спрашиваем здесь',
      icon: Icons.do_not_disturb_alt_outlined,
      body: 'Грунт, снеговой и ветровой район — эти вопросы появятся '
          'на этапе «Фундамент», когда они действительно понадобятся '
          'для расчёта.',
    ),
    HintSection(
      heading: 'После «Завершить»',
      icon: Icons.check_circle_outline,
      body: 'Откроется этап 2 — «Планировка»: сгенерируем '
          'планы по этажам и подберём стены, перекрытия, лестницу.',
    ),
  ];

  static const List<HintSection> staircase = [
    HintSection(
      heading: 'Когда нужна лестница',
      icon: Icons.stairs_outlined,
      body: 'Подраздел появляется, если в проекте больше одного этажа, '
          'есть мансарда или подвальный этаж. На одноэтажный дом без '
          'подвала лестница не запрашивается.',
    ),
    HintSection(
      heading: 'Тип лестницы',
      icon: Icons.architecture_outlined,
      body: 'Маршевая — самая удобная, требует 4–6 м². Поворотная — '
          'экономит место за счёт забежных ступеней. Винтовая — самая '
          'компактная (от 1.5 м²), но не для постоянного использования.',
    ),
    HintSection(
      heading: 'Расчёт ступеней',
      icon: Icons.calculate_outlined,
      body: 'Высота этажа задаётся слайдером, количество ступеней '
          'считается автоматически по комфортной высоте подступёнка '
          '(165 мм для маршевой/поворотной, 180 мм для винтовой). '
          'Точный расчёт по СП 54.13330.2022 — позже.',
    ),
  ];

  static const List<HintSection> roof = [
    HintSection(
      heading: 'Этап 4: что выбираем',
      icon: Icons.roofing_outlined,
      body: 'Тип кровли, угол ската и материал покрытия. Эти данные '
          'влияют и на расчёт ветровой/снеговой нагрузки, и на спецификацию '
          'материалов в техническом задании.',
    ),
    HintSection(
      heading: 'Угол ската',
      icon: Icons.architecture_outlined,
      body: 'Для скатной кровли — от 5° до 60°. Для плоской — поле '
          'не запрашивается (по нормам уклон ≤ 5° считается плоским). '
          'Чем круче скат, тем меньше задерживается снег.',
    ),
    HintSection(
      heading: 'Покрытие',
      icon: Icons.layers_outlined,
      body: 'Металлочерепица — самое распространённое. Мягкая (битумная) — '
          'для сложных форм. Керамическая — долговечно и тяжело. '
          'Шифер — бюджетно. Фальцевая — для современной архитектуры.',
    ),
    HintSection(
      heading: 'Утеплённая крыша',
      icon: Icons.thermostat_outlined,
      body: 'Этот переключатель появляется только если на этапе 1 была '
          'отмечена мансарда — для жилого пространства под кровлей нужно '
          'утепление.',
    ),
  ];

  static const List<HintSection> sitePreliminaries = [
    HintSection(
      heading: 'Зачем нужны эти данные',
      icon: Icons.terrain_outlined,
      body: 'Тип фундамента и его глубина зависят от трёх параметров '
          'участка: климат (снеговой и ветровой район), глубина промерзания '
          '(определяется регионом) и тип грунта.',
    ),
    HintSection(
      heading: 'Регион',
      icon: Icons.location_on_outlined,
      body: 'Выберите ближайший город из каталога — снеговой и ветровой '
          'районы заполнятся автоматически по СП 20.13330.2016. Эти показания '
          'используются дальше при подборе свайного поля и расчёте '
          'нагрузок от снега на кровлю.',
    ),
    HintSection(
      heading: 'Грунт',
      icon: Icons.layers_outlined,
      body: 'Выберите тип верхнего слоя грунта. Для базового подбора '
          'этого достаточно. Если у вас есть полный геологический отчёт '
          '(c физико-механическими показателями), его можно ввести в '
          'расширенной форме на следующем шаге.',
    ),
  ];

  static const List<HintSection> foundationWizard = [
    HintSection(
      heading: 'Параметры фундамента',
      icon: Icons.foundation_outlined,
      body: 'Подобранный по техническому заданию тип уже выбран. Можно поменять, если '
          'у вас есть основания (геология участка, опыт стройки).',
    ),
    HintSection(
      heading: 'Что выбираем',
      icon: Icons.checklist,
      bullets: [
        'Тип: ленточный, плита, сваи, столбчатый, ростверк.',
        'Устройство: монолит / сборные блоки.',
        'Материал и марка бетона.',
        'Глубина заложения — связана с глубиной промерзания (зависит от '
            'региона).',
      ],
    ),
    HintSection(
      heading: 'Обоснование выбора',
      icon: Icons.menu_book_outlined,
      body: 'Под параметрами — список причин «почему именно так» со '
          'ссылками на СП. Полезно объяснить клиенту.',
    ),
    HintSection(
      heading: 'Расчёт нагрузок',
      icon: Icons.calculate_outlined,
      body: 'Кнопка «Рассчитать нагрузки» — открывает страницу с полным '
          'расчётом по СП 20.13330.2016: снег, ветер, постоянная и полезная '
          'нагрузки. Видно каждую формулу и подстановку значений.',
    ),
  ];

  static const List<HintSection> foundationDesign = [
    HintSection(
      heading: 'Что подбираем',
      icon: Icons.architecture_outlined,
      body: 'Сечение ленточного фундамента: ширину подошвы b, высоту '
          'ленты h, глубину заложения d. Плюс базовое армирование '
          'продольной арматурой и хомутами по СП 63.13330.2018.',
    ),
    HintSection(
      heading: 'Как считаем',
      icon: Icons.functions,
      bullets: [
        'R — расчётное сопротивление грунта (СП 22.13330.2016, табл. В.3).',
        'A — площадь застройки из технического задания.',
        'L — длина несущих стен (периметр + поперечные).',
        'N = q · A / L — погонная нагрузка на ленту.',
        'b ≥ N · γc / R — требуемая ширина подошвы.',
        'd ≥ df + 0.1 м — глубина заложения от поверхности земли.',
      ],
    ),
    HintSection(
      heading: 'Откуда берётся каждое значение',
      icon: Icons.info_outline,
      body: 'Под каждой формулой раскрывающийся блок «Откуда взяты '
          'значения» — там видно, что взято из технического задания, что из расчёта '
          'нагрузок, что из СП. Удобно проверять.',
    ),
    HintSection(
      heading: 'Что дальше',
      icon: Icons.arrow_forward,
      body: 'Эти параметры пойдут в пояснительную записку (ПЗ), узел '
          'фундамента в DXF и строку ВОР: бетон м³, арматура кг по '
          'диаметрам, опалубка м².',
    ),
  ];

  static const List<HintSection> foundationLoads = [
    HintSection(
      heading: 'Что считаем',
      icon: Icons.calculate_outlined,
      body: 'Расчёт нагрузок на фундамент по СП 20.13330.2016. '
          'На входе — данные из технического задания: снеговой и ветровой районы, '
          'этажность, материал стен и кровли. На выходе — суммарная '
          'вертикальная нагрузка на 1 м² застройки и ветровое давление.',
    ),
    HintSection(
      heading: 'Что увидите ниже',
      icon: Icons.list_alt,
      bullets: [
        'Снеговая нагрузка S = µ · Sg · γf — с расшифровкой коэффициентов.',
        'Ветровая нагрузка wm = w0 · k(z) · c · γf.',
        'Постоянные нагрузки от стен, перекрытий и кровли.',
        'Полезная нагрузка для жилых помещений (СП 20, табл. 8.3).',
        'Сумма по СП 20, разд. 6 (сочетание нагрузок).',
      ],
    ),
    HintSection(
      heading: 'Что дальше',
      icon: Icons.arrow_forward,
      body: 'В следующей итерации эти нагрузки уйдут в подбор подошвы '
          'и армирование (СП 22 + СП 63), а потом — в пояснительную '
          'записку и строку ВОР. Сейчас можно проверить корректность '
          'входных данных.',
    ),
  ];

  static const List<HintSection> drawings = [
    HintSection(
      heading: 'История чертежей',
      icon: Icons.history,
      body: 'Каждое сохранение — отдельная партия (версия). Свежие сверху, '
          'старые ниже. Ничего не теряется.',
    ),
    HintSection(
      heading: 'Что можно сделать',
      icon: Icons.touch_app_outlined,
      bullets: [
        'Скачать партию в PDF — все этажи одним файлом, шрифт с '
            'кириллицей, толстые стены / двери / окна как на экране.',
        'Скачать в DXF — каждый этаж отдельным файлом для AutoCAD.',
        'В режиме «Проектировщик» — открыть план этажа в редакторе '
            '(карандаш на карточке плана).',
      ],
    ),
    HintSection(
      heading: 'Перегенерация',
      icon: Icons.refresh,
      body: 'Если вы поменяли техническое задание или состав сооружения — вернитесь в '
          '«Состав» и нажмите «Перегенерировать». Появится новая партия, '
          'старая останется ниже.',
    ),
  ];

  static const List<HintSection> floorPlanEditor = [
    HintSection(
      heading: 'Редактор плана',
      icon: Icons.draw_outlined,
      body: 'Подвинуть комнаты, поменять размеры, добавить двери и окна. '
          'Изменения округляются до сетки 0.1 м, минимальная сторона — 1 м.',
    ),
    HintSection(
      heading: 'Режим «Комнаты»',
      icon: Icons.crop_square,
      bullets: [
        'Касание — выделить.',
        'Тащить за тело — переместить.',
        'Тащить за угловую ручку — изменить размеры (от противоположного '
            'угла).',
        'Кнопки в AppBar: «+» — добавить комнату, корзина — удалить '
            'выделенную.',
      ],
    ),
    HintSection(
      heading: 'Режим «Двери и окна»',
      icon: Icons.door_sliding_outlined,
      bullets: [
        'Касание по проёму — выделить.',
        'Тащить за тело — двигать вдоль стены.',
        'Тащить за концы — менять длину проёма.',
        'Кнопки: дверь / окно / входная дверь / удалить выделенный.',
        'Минимальная длина проёма — 0.6 м (СП 55.13330.2017).',
      ],
    ),
    HintSection(
      heading: 'Сохранение',
      icon: Icons.save_outlined,
      body: 'Дискета — сохранить как новую версию (старые планы не '
          'затираются, остаются в истории на вкладке «Чертежи»). Стрелка '
          'обновления — сбросить ручные правки и вернуться к авторасчёту. '
          'Если есть пересечения комнат — кнопка сохранения заблокирована.',
    ),
  ];
}
