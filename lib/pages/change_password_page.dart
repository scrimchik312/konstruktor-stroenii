/// Принудительная смена пароля при первом входе или после reset.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_api.dart';
import '../state/auth_state.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key, this.forced = false});

  /// Если `true`, страница показывается принудительно (после первого
  /// логина или после reset со стороны админа). Кнопка «выйти» доступна,
  /// но «Назад» — нет.
  final bool forced;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().changePassword(
            oldPassword: _old.text,
            newPassword: _new.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пароль изменён')),
      );
      if (!widget.forced) {
        Navigator.of(context).maybePop();
      }
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.forced
            ? 'Установите новый пароль'
            : 'Сменить пароль'),
        automaticallyImplyLeading: !widget.forced,
        actions: [
          if (widget.forced)
            IconButton(
              tooltip: 'Выйти',
              icon: const Icon(Icons.logout),
              onPressed: () => context.read<AuthState>().logout(),
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.forced)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Это первый вход или ваш пароль был сброшен '
                        'администратором. Установите свой пароль, чтобы '
                        'продолжить.',
                      ),
                    ),
                  TextFormField(
                    controller: _old,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Текущий пароль',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Заполните' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _new,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Новый пароль (минимум 8 символов)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Заполните';
                      if (v.length < 8) {
                        return 'Минимум 8 символов';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirm,
                    obscureText: true,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Повторите новый пароль',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v != _new.text) return 'Пароли не совпадают';
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style:
                            const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: Text(_busy ? 'Сохраняю…' : 'Сохранить'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
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
