import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/organization_settings.dart';
import '../state/app_state.dart';

/// Страница настроек.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.lightbulb_outline),
            title: const Text('Показывать обучающие подсказки'),
            subtitle: const Text(
              'Авто-диалог с подсказкой при первом открытии каждого экрана '
              'в текущей сессии. Иконка «?» в углу остаётся доступной всегда.',
            ),
            isThreeLine: true,
            value: state.hintsEnabled,
            onChanged: (v) => state.setHintsEnabled(v),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.business_outlined),
            title: const Text('Организация (для штампа чертежей)'),
            subtitle: Text(
              state.organization.companyName.isEmpty
                  ? 'Не заполнено — в штампе будет подставлено значение по умолчанию'
                  : '${state.organization.companyName} · '
                      'стадия ${state.organization.stage} · '
                      'подписантов: ${state.organization.signatories.length}',
            ),
            trailing: const Icon(Icons.chevron_right),
            isThreeLine: true,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OrganizationSettingsPage(),
                ),
              );
            },
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('О приложении'),
            subtitle: Text(
              'Калькулятор проектировщика · версия 0.1.0\n'
              'Локальное хранение проектов на устройстве.',
            ),
            isThreeLine: true,
          ),
        ],
      ),
    );
  }
}

/// Экран редактирования реквизитов организации для штампа (ГОСТ Р 21.101).
class OrganizationSettingsPage extends StatefulWidget {
  const OrganizationSettingsPage({super.key});

  @override
  State<OrganizationSettingsPage> createState() =>
      _OrganizationSettingsPageState();
}

class _OrganizationSettingsPageState extends State<OrganizationSettingsPage> {
  late TextEditingController _nameCtrl;
  late TextEditingController _contactsCtrl;
  late TextEditingController _stageCtrl;
  late List<_SignatoryDraft> _signatories;

  @override
  void initState() {
    super.initState();
    final org = context.read<AppState>().organization;
    _nameCtrl = TextEditingController(text: org.companyName);
    _contactsCtrl = TextEditingController(text: org.companyContacts);
    _stageCtrl = TextEditingController(text: org.stage);
    _signatories = [
      for (final s in org.signatories) _SignatoryDraft.fromModel(s),
    ];
    if (_signatories.isEmpty) {
      _signatories = [
        _SignatoryDraft(role: 'Разраб.'),
        _SignatoryDraft(role: 'Пров.'),
        _SignatoryDraft(role: 'Н.контр.'),
        _SignatoryDraft(role: 'Утв.'),
      ];
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactsCtrl.dispose();
    _stageCtrl.dispose();
    for (final s in _signatories) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final org = OrganizationSettings(
      companyName: _nameCtrl.text.trim(),
      companyContacts: _contactsCtrl.text.trim(),
      stage: _stageCtrl.text.trim().isEmpty ? 'РП' : _stageCtrl.text.trim(),
      signatories: [
        for (final s in _signatories)
          if (s.roleCtrl.text.trim().isNotEmpty ||
              s.nameCtrl.text.trim().isNotEmpty)
            OrganizationSignatory(
              role: s.roleCtrl.text.trim(),
              name: s.nameCtrl.text.trim(),
              date: s.dateCtrl.text.trim(),
            ),
      ],
    );
    await context.read<AppState>().setOrganization(org);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Настройки организации сохранены')),
    );
    Navigator.pop(context);
  }

  void _addSignatory() {
    setState(() => _signatories.add(_SignatoryDraft()));
  }

  void _removeSignatory(int index) {
    setState(() {
      _signatories[index].dispose();
      _signatories.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Организация'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Сохранить',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Эти данные подставляются в штамп чертежа (ГОСТ Р 21.101 форма 3) '
            'при выгрузке PDF.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Наименование организации',
              hintText: 'ООО «Стройпроект»',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contactsCtrl,
            decoration: const InputDecoration(
              labelText: 'Контакты (телефон, сайт, email)',
              hintText: '+7 (495) 000-00-00 · stroyproekt.ru',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _stageCtrl,
            decoration: const InputDecoration(
              labelText: 'Стадия проектирования',
              hintText: 'РП / Р / П',
              helperText: 'По ГОСТ Р 21.101: П — проектная, Р — рабочая, РП — рабочий проект',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Подписанты (строки в штампе)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'ГОСТ Р 21.101 предусматривает до 4 подписантов: Разработал, '
            'Проверил, Нормоконтроль, Утвердил. При необходимости можно '
            'добавить ГИП, ГАП и другие роли.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _signatories.length; i++) ...[
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _signatories[i].roleCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Должность',
                              hintText: 'Разраб.',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Удалить',
                          onPressed: () => _removeSignatory(i),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _signatories[i].nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Фамилия И.О.',
                        hintText: 'Иванов И.И.',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _signatories[i].dateCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Дата (необязательно)',
                        hintText: 'ММ.ГГ',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addSignatory,
            icon: const Icon(Icons.add),
            label: const Text('Добавить подписанта'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}

class _SignatoryDraft {
  final TextEditingController roleCtrl;
  final TextEditingController nameCtrl;
  final TextEditingController dateCtrl;

  _SignatoryDraft({
    String role = '',
    String name = '',
    String date = '',
  })  : roleCtrl = TextEditingController(text: role),
        nameCtrl = TextEditingController(text: name),
        dateCtrl = TextEditingController(text: date);

  factory _SignatoryDraft.fromModel(OrganizationSignatory s) =>
      _SignatoryDraft(role: s.role, name: s.name, date: s.date);

  void dispose() {
    roleCtrl.dispose();
    nameCtrl.dispose();
    dateCtrl.dispose();
  }
}
