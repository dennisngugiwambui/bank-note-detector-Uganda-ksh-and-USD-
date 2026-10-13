import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/auth.dart';
import 'theme.dart';

/// Sign in and create-account screen, in one animated form. "Continue as
/// guest" is always offered: a blind user must never be locked out of
/// identifying money because they can't get through a login.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final auth = AppScope.of(context).auth;
    final announcer = AppScope.of(context).scan.announcer;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_signUp) {
        await auth.signUp(name: _name.text, email: _email.text, password: _password.text);
      } else {
        await auth.signIn(email: _email.text, password: _password.text);
      }
      announcer.say('Welcome, ${auth.currentUser!.firstName}');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
      announcer.say(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.primary;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(20)),
                        child: Icon(Icons.payments_rounded, color: context.colors.onPrimary, size: 34),
                      ),
                    ),
                    const SizedBox(height: 28),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Semantics(
                        key: ValueKey(_signUp),
                        header: true,
                        child: Text(_signUp ? 'Create your\naccount.' : 'Welcome\nback.', style: context.text.displayMedium),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _signUp
                          ? 'Your settings, totals and history stay on this phone.'
                          : 'Sign in to pick up where you left off.',
                      style: context.text.titleMedium?.copyWith(color: context.tokens.muted, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 32),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      child: _signUp
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: TextFormField(
                                controller: _name,
                                textCapitalization: TextCapitalization.words,
                                autofillHints: const [AutofillHints.name],
                                decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_rounded)),
                                validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your name' : null,
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email_rounded)),
                      validator: (v) =>
                          (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_rounded),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Semantics(
                        liveRegion: true,
                        child: Text(_error!, style: TextStyle(color: context.colors.error, fontWeight: FontWeight.w600)),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                          : Text(_signUp ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => AppScope.of(context).auth.continueAsGuest(),
                      icon: const Icon(Icons.bolt_rounded),
                      label: const Text('Continue without an account'),
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () => setState(() {
                        _signUp = !_signUp;
                        _error = null;
                      }),
                      child: Text(_signUp ? 'Already have an account? Sign in' : 'New here? Create an account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
