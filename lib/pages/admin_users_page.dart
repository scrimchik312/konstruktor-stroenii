/// Админ-панель: управление пользователями и их доступами к продуктам.
///
/// Доступна только пользователям с `is_admin=true`. Показывает список
/// зарегистрированных клиентов; для каждого видны выданные продукты
/// (chips), кнопки выдачи/отзыва, сброса пароля, блокировки/удаления.
///
/// Кнопка «Создать клиента» открывает диалог с email + список галочек
/// продуктов; после создания временный пароль показывается один раз —
/// его нужно успеть скопировать и передать клиенту защищённым
/// каналом.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/auth.dart';
import '../services/auth_api.dart';
import '../state/auth_state.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  bool _loading = true;
  String? _error;
  List<AdminUser> _users = const [];
  List<ProductInfo> _products = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  AuthApi get _api => context.read<AuthState>().api;
  String get _token => context.read<AuthState>().token!;

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await _api.listUsers(_token);
      final products = await _api.listProducts(_token);
      if (!mounted) return;
      setState(() {
        _users = users;
        _products = products;
        _loading = false;
      });
    } on AuthApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка: $e';
        _loading = false;
      });
    }
  }

  String _productTitle(String code) {
    return _products.firstWhere(
      (p) => p.code == code,
      orElse: () => ProductInfo(code: code, title: code),
    ).title;
  }

  Future<void> _showCreateDialog() async {
    final result = await showDialog<CreateUserResult>(
      context: context,
      builder: (_) => _CreateUserDialog(api: _api, token: _token, products: _products),
    );
    if (result == null) return;
    await _showTempPasswordDialog(
      title: 'Клиент создан',
      email: result.user.email,
      tempPassword: result.temporaryPassword,
    );
    await _reload();
  }

  Future<void> _showTempPasswordDialog({
    required String title,
    required String email,
    required String tempPassword,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Скопируйте временный пароль и передайте его клиенту '
                'защищённым каналом. Этот пароль больше нигде не '
                'хранится — после закрытия окна вы его не увидите.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              _Row(label: 'Email', value: email),
              const SizedBox(height: 8),
              _Row(label: 'Пароль', value: tempPassword, mono: true),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                      text: '$email / $tempPassword'));
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Скопировано в буфер')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Скопировать email + пароль'),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }

  Future<void> _grant(AdminUser user, String code) async {
    try {
      await _api.grantProduct(token: _token, userId: user.id, productCode: code);
      await _reload();
    } on AuthApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _revoke(AdminUser user, String code) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отозвать продукт?'),
        content: Text(
          'У пользователя ${user.email} будет отозван доступ '
          'к продукту «${_productTitle(code)}». '
          'При следующем входе клиент его не увидит.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Отозвать'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.revokeProduct(
        token: _token,
        userId: user.id,
        productCode: code,
      );
      await _reload();
    } on AuthApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _resetPassword(AdminUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить пароль?'),
        content: Text(
          'Будет сгенерирован новый временный пароль для ${user.email}. '
          'Старый пароль перестанет работать.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final pwd =
          await _api.resetPassword(token: _token, userId: user.id);
      await _showTempPasswordDialog(
        title: 'Пароль сброшен',
        email: user.email,
        tempPassword: pwd,
      );
      await _reload();
    } on AuthApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _toggleActive(AdminUser user) async {
    try {
      await _api.updateUser(
        token: _token,
        userId: user.id,
        isActive: !user.isActive,
      );
      await _reload();
    } on AuthApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _deleteUser(AdminUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить пользователя?'),
        content: Text(
          'Пользователь ${user.email} и все его доступы будут удалены '
          'без возможности восстановления. Это действие необратимо.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteUser(token: _token, userId: user.id);
      await _reload();
    } on AuthApiException catch (e) {
      _snack(e.message);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление клиентами'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Выйти',
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Создать клиента'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 8),
                        Text(_error!),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: _reload,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : _users.isEmpty
                  ? const Center(child: Text('Пока нет клиентов'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: _users.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final u = _users[i];
                        return _UserCard(
                          user: u,
                          allProducts: _products,
                          productTitle: _productTitle,
                          onGrant: (code) => _grant(u, code),
                          onRevoke: (code) => _revoke(u, code),
                          onResetPassword: () => _resetPassword(u),
                          onToggleActive: () => _toggleActive(u),
                          onDelete: () => _deleteUser(u),
                        );
                      },
                    ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.allProducts,
    required this.productTitle,
    required this.onGrant,
    required this.onRevoke,
    required this.onResetPassword,
    required this.onToggleActive,
    required this.onDelete,
  });

  final AdminUser user;
  final List<ProductInfo> allProducts;
  final String Function(String) productTitle;
  final Future<void> Function(String code) onGrant;
  final Future<void> Function(String code) onRevoke;
  final VoidCallback onResetPassword;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final granted =
        user.entitlements.map((e) => e.productCode).toSet();
    final notGranted = allProducts
        .where((p) => !granted.contains(p.code))
        .toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(user.email.isNotEmpty
                      ? user.email[0].toUpperCase()
                      : '?'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.email,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (user.isAdmin) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.shield,
                                size: 16, color: Colors.amber),
                          ],
                          if (!user.isActive) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.block,
                                size: 16, color: Colors.red),
                          ],
                          if (user.mustChangePassword) ...[
                            const SizedBox(width: 8),
                            const Tooltip(
                              message: 'Ещё не сменил временный пароль',
                              child: Icon(Icons.warning_amber,
                                  size: 16, color: Colors.orange),
                            ),
                          ],
                        ],
                      ),
                      if (user.fullName != null &&
                          user.fullName!.isNotEmpty)
                        Text(user.fullName!,
                            style: theme.textTheme.bodySmall),
                      Text(
                        'создан ${_fmtDate(user.createdAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'reset',
                        child: ListTile(
                            leading: Icon(Icons.lock_reset),
                            title: Text('Сбросить пароль'))),
                    PopupMenuItem(
                        value: 'toggle',
                        child: ListTile(
                            leading: Icon(user.isActive
                                ? Icons.block
                                : Icons.check_circle_outline),
                            title: Text(user.isActive
                                ? 'Заблокировать'
                                : 'Разблокировать'))),
                    if (!user.isAdmin)
                      const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                              leading: Icon(Icons.delete_outline,
                                  color: Colors.red),
                              title: Text('Удалить',
                                  style: TextStyle(color: Colors.red)))),
                  ],
                  onSelected: (v) {
                    switch (v) {
                      case 'reset':
                        onResetPassword();
                        break;
                      case 'toggle':
                        onToggleActive();
                        break;
                      case 'delete':
                        onDelete();
                        break;
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Доступные продукты',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline,
                )),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (granted.isEmpty)
                  Text('— нет —',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline)),
                ...granted.map((code) => InputChip(
                      label: Text(productTitle(code)),
                      avatar: const Icon(Icons.check, size: 16),
                      onDeleted: () => onRevoke(code),
                      deleteIcon: const Icon(Icons.close, size: 16),
                    )),
              ],
            ),
            if (notGranted.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Выдать ещё',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  )),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: notGranted
                    .map((p) => ActionChip(
                          label: Text(p.title),
                          avatar: const Icon(Icons.add, size: 16),
                          onPressed: () => onGrant(p.code),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog({
    required this.api,
    required this.token,
    required this.products,
  });

  final AuthApi api;
  final String token;
  final List<ProductInfo> products;

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _selected = <String>{};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // По умолчанию выдаём «Частный дом» — это самый ходовой продукт.
    if (widget.products.any((p) => p.code == 'privateHouse')) {
      _selected.add('privateHouse');
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.createUser(
        token: widget.token,
        email: _email.text.trim().toLowerCase(),
        fullName:
            _name.text.trim().isEmpty ? null : _name.text.trim(),
        products: _selected.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on AuthApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Создать клиента'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Заполните';
                    if (!v.contains('@')) return 'Это не email';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'ФИО (необязательно)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Выдать продукты',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                ...widget.products.map((p) => CheckboxListTile(
                      value: _selected.contains(p.code),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(p.code);
                        } else {
                          _selected.remove(p.code);
                        }
                      }),
                      title: Text(p.title),
                      subtitle: Text(p.code,
                          style: Theme.of(context).textTheme.bodySmall),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    )),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: Text(_busy ? 'Создаю…' : 'Создать'),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.mono = false});
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
            width: 70,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall)),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              fontFamily: mono ? 'monospace' : null,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Скопировать',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Скопировано: $label')),
            );
          },
          icon: const Icon(Icons.copy, size: 18),
        ),
      ],
    );
  }
}

String _fmtDate(DateTime d) {
  final dl = d.toLocal();
  return '${dl.day.toString().padLeft(2, '0')}.${dl.month.toString().padLeft(2, '0')}.${dl.year}';
}
