import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../data/database.dart';
import '../common.dart';

/// Connexion et création de compte sur le même écran : email + mot de passe, rien d'autre.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _signUp = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final auth = ref.read(supabaseProvider).auth;
    try {
      if (_signUp) {
        final res = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'display_name': _name.text.trim()},
        );
        // Sans session, le projet exige la confirmation de l'email.
        if (res.session == null && mounted) {
          setState(() {
            _signUp = false;
            _info = 'Compte créé. Confirme ton email, puis connecte-toi.';
          });
        }
      } else {
        await auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Saisis ton email pour recevoir le lien de réinitialisation.');
      return;
    }
    await guarded(context, () => ref.read(supabaseProvider).auth.resetPasswordForEmail(email));
    if (mounted) setState(() => _info = 'Si un compte existe, un email vient de partir.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FormPage(
      children: [
        const SizedBox(height: 32),
        Text('Coach', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          _signUp ? 'Crée ton compte' : 'Connecte-toi pour retrouver tes séances',
          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 32),
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              children: [
                if (_signUp) ...[
                  TextFormField(
                    key: const Key('auth-name'),
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(labelText: 'Prénom et nom'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Indique ton nom' : null,
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  key: const Key('auth-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) =>
                      (v == null || !v.contains('@')) ? 'Email invalide' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('auth-password'),
                  controller: _password,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    helperText: _signUp ? '8 caractères minimum' : null,
                  ),
                  validator: (v) => (v == null || v.length < (_signUp ? 8 : 1))
                      ? '8 caractères minimum'
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        if (_info != null) ...[
          const SizedBox(height: 12),
          Text(_info!, style: TextStyle(color: theme.colorScheme.primary)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('auth-submit'),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(_signUp ? 'Créer mon compte' : 'Me connecter'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _signUp = !_signUp;
                    _error = null;
                    _info = null;
                  }),
          child: Text(_signUp ? 'J’ai déjà un compte' : 'Créer un compte'),
        ),
        if (!_signUp)
          TextButton(
            onPressed: _busy ? null : _resetPassword,
            child: const Text('Mot de passe oublié ?'),
          ),
      ],
    );
  }
}
