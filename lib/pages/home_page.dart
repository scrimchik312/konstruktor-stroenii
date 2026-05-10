import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/construction_type.dart';
import '../state/auth_state.dart';
import 'admin_users_page.dart';
import 'change_password_page.dart';
import 'projects_of_type_page.dart';
import 'settings_page.dart';

const String _shareTitle =
    'Конструктор строений: проектируем дом по этапам';

const List<_LandingStep> _steps = [
  _LandingStep(
    icon: Icons.foundation_outlined,
    title: 'Выберите тип сооружения',
    description: 'Частный дом, многоквартирный, промышленное здание или '
        'металлоконструкции. Сейчас полностью реализован частный дом.',
  ),
  _LandingStep(
    icon: Icons.add_home_outlined,
    title: 'Создайте проект',
    description: 'Укажите название проекта. Все данные хранятся локально '
        'в браузере.',
  ),
  _LandingStep(
    icon: Icons.fact_check_outlined,
    title: 'Заполните техническое задание из 8 шагов',
    description: 'Участок, этажность, комнаты, материал стен, кровля, '
        'отделка, снеговой и ветровой район.',
  ),
  _LandingStep(
    icon: Icons.architecture_outlined,
    title: 'Получите состав сооружения',
    description: 'Приложение автоматически подбирает фундамент, стены, '
        'перекрытия, кровлю и лестницу по СП.',
  ),
  _LandingStep(
    icon: Icons.calculate_outlined,
    title: 'Сделайте расчёт фундамента',
    description: 'Снеговая и ветровая нагрузка, постоянная и полезная, '
        'подбор подошвы и армирования с раскрытием источников значений.',
  ),
  _LandingStep(
    icon: Icons.picture_as_pdf_outlined,
    title: 'Скачайте чертежи и ПЗ',
    description: 'План этажа в PDF/DXF (стены, двери, окна, лестница) и '
        'пояснительная записка к расчёту фундамента в PDF.',
  ),
];

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      appBar: AppBar(
        title: const _BrandTitle(),
        actions: [
          if (auth.isAdmin)
            IconButton(
              tooltip: 'Управление клиентами',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminUsersPage()),
              ),
            ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
          if (auth.signedIn)
            PopupMenuButton<String>(
              tooltip: auth.user?.email ?? 'Профиль',
              icon: const Icon(Icons.person_outline),
              onSelected: (v) async {
                switch (v) {
                  case 'change_password':
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ChangePasswordPage(),
                      ),
                    );
                    break;
                  case 'logout':
                    await context.read<AuthState>().logout();
                    break;
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(
                    auth.user?.email ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'change_password',
                  child: ListTile(
                    leading: Icon(Icons.lock_reset),
                    title: Text('Сменить пароль'),
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'logout',
                  child: ListTile(
                    leading: Icon(Icons.logout),
                    title: Text('Выйти'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: const _LandingBody(),
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.home_work_outlined,
              color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'КОНСТРУКТОР СТРОЕНИЙ',
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _LandingBody extends StatelessWidget {
  const _LandingBody();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final isWide = c.maxWidth >= 900;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Hero(),
                    const SizedBox(height: 28),
                    const _Description(),
                    const SizedBox(height: 32),
                    Text(
                      'Что вы хотите спроектировать?',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Выберите тип сооружения — откроется список ваших '
                      'проектов этого типа.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    if (isWide)
                      const _TypesGrid()
                    else
                      const _TypesList(),
                    const SizedBox(height: 40),
                    Text(
                      'Инструкция из 6 шагов',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                    const SizedBox(height: 16),
                    if (isWide)
                      const _StepsGrid()
                    else
                      const _StepsList(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _shareTitle,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'От первичных данных до готового пакета чертежей за четыре этапа. '
          'Веб-приложение, без установки.',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Description extends StatelessWidget {
  const _Description();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Конструктор ведёт пользователя по последовательности этапов: '
            'описание дома, планировка, кровля, фундамент. На '
            'каждом шаге программа задаёт только нужные на этой стадии '
            'вопросы и сразу подсказывает решения по действующим СП. По '
            'итогам формируется техническое задание и комплект чертежей.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Чтобы начать — выберите тип сооружения ниже и нажмите '
            '«Новый проект».',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LandingStep {
  const _LandingStep({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

class _StepsGrid extends StatelessWidget {
  const _StepsGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _steps.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        mainAxisExtent: 200,
      ),
      itemBuilder: (_, i) => _StepCard(index: i + 1, step: _steps[i]),
    );
  }
}

class _StepsList extends StatelessWidget {
  const _StepsList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          _StepCard(index: i + 1, step: _steps[i]),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.index, required this.step});

  final int index;
  final _LandingStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$index',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(step.icon, color: theme.colorScheme.primary),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            step.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              step.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const Map<ConstructionType, IconData> _typeIcons = {
  ConstructionType.privateHouse: Icons.cottage_outlined,
  ConstructionType.apartmentBuilding: Icons.apartment_outlined,
  ConstructionType.commercialBuilding: Icons.store_mall_directory_outlined,
  ConstructionType.commercialStructure: Icons.warehouse_outlined,
  ConstructionType.metalStructure: Icons.precision_manufacturing_outlined,
  ConstructionType.undergroundStructure: Icons.layers_outlined,
};

const Map<ConstructionType, String> _typeImages = {
  ConstructionType.privateHouse: 'assets/images/types/private_house.jpg',
  ConstructionType.apartmentBuilding:
      'assets/images/types/apartment_building.jpg',
  ConstructionType.commercialBuilding:
      'assets/images/types/commercial_building.jpg',
  ConstructionType.commercialStructure:
      'assets/images/types/commercial_structure.jpg',
  ConstructionType.metalStructure: 'assets/images/types/metal_structure.jpg',
  ConstructionType.undergroundStructure:
      'assets/images/types/underground_structure.jpg',
};

const Map<ConstructionType, String> _typeTooltips = {
  ConstructionType.privateHouse:
      'Готов: ТЗ → состав → чертежи → расчёт фундамента → ПЗ',
  ConstructionType.apartmentBuilding:
      'Скоро: жилой дом 4–10 этажей',
  ConstructionType.commercialBuilding:
      'Скоро: офис, магазин, общественное здание',
  ConstructionType.commercialStructure:
      'Скоро: склад, цех, вспомогательное сооружение',
  ConstructionType.metalStructure:
      'Скоро: каркасы, фермы, ангары из проката (СП 16)',
  ConstructionType.undergroundStructure:
      'Скоро: подвалы, цоколи, подземные паркинги, убежища (СП 63, СП 22)',
};

class _TypesGrid extends StatelessWidget {
  const _TypesGrid();

  @override
  Widget build(BuildContext context) {
    const types = ConstructionType.values;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: types.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        mainAxisExtent: 140,
      ),
      itemBuilder: (_, i) => _TypeCard(type: types[i]),
    );
  }
}

class _TypesList extends StatelessWidget {
  const _TypesList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final t in ConstructionType.values) ...[
          _TypeCard(type: t),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.type});

  final ConstructionType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final implemented = type.isImplemented;
    final imagePath = _typeImages[type];
    final auth = context.watch<AuthState>();
    final hasAccess = auth.hasProduct(type.name);
    final tooltipMessage = !hasAccess
        ? 'Этот продукт не подключён к вашему аккаунту. '
            'Свяжитесь с администратором, чтобы получить доступ.'
        : (_typeTooltips[type] ?? '');
    return Tooltip(
      message: tooltipMessage,
      preferBelow: false,
      verticalOffset: 12,
      waitDuration: const Duration(milliseconds: 250),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: theme.colorScheme.surface,
          child: InkWell(
            onTap: hasAccess && implemented
                ? () => _openType(context, type)
                : hasAccess
                    ? () => _openType(context, type) // unimplemented но видим
                    : () => _showLockedDialog(context, type),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imagePath != null)
                  Positioned.fill(
                    child: Opacity(
                      opacity: implemented ? 0.32 : 0.18,
                      child: Image.asset(
                        imagePath,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          theme.colorScheme.surface.withValues(alpha: 0.0),
                          theme.colorScheme.surface.withValues(alpha: 0.65),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: implemented
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        width: implemented ? 1.5 : 1,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _typeIcons[type] ?? Icons.business_outlined,
                            size: 32,
                            color: implemented
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 8),
                          if (!hasAccess)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_outline,
                                      size: 12,
                                      color: theme.colorScheme.outline),
                                  const SizedBox(width: 3),
                                  Text(
                                    'нет доступа',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (!implemented)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'скоро',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        type.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: implemented
                              ? null
                              : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openType(BuildContext context, ConstructionType type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectsOfTypePage(type: type),
      ),
    );
  }

  void _showLockedDialog(BuildContext context, ConstructionType type) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_outline, size: 36, color: Colors.grey),
        title: const Text('Доступ не подключён'),
        content: Text(
          'Продукт «${type.title}» не подключён к вашему аккаунту. '
          'Чтобы его получить, свяжитесь с администратором.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Понял'),
          ),
        ],
      ),
    );
  }
}

