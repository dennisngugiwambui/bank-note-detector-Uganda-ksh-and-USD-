import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/auth.dart';
import 'theme.dart';
import 'widgets.dart';

/// Sign in and create-account screen, in one animated form: aurora brand
/// header over a Bolt-style sheet with pill fields and buttons. "Continue
/// without an account" is always offered: a blind user must never be locked
/// out of identifying money because they can't get through a login.
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
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

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

  /// 0..3, shown only while creating an account.
  int get _strength {
    final p = _password.text;
    var s = 0;
    if (p.length >= 8) s++;
    if (p.length >= 12) s++;
    if (RegExp(r'[0-9]').hasMatch(p) && RegExp(r'[A-Za-z]').hasMatch(p)) s++;
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.primary;
    final t = context.tokens;
    return Scaffold(
      backgroundColor: Color.lerp(accent, Colors.black, 0.15),
      body: AuroraBackground(
        colors: [accent, Color.lerp(accent, Colors.white, 0.3)!, Color.lerp(accent, Colors.black, 0.3)!],
        intensity: 0.35,
        child: SizedBox.expand(
          child: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                        child: Row(
                          children: [
                            Image.asset('assets/branding/logo.png', width: 56, height: 56, excludeFromSemantics: true),
                            const SizedBox(width: 14),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: Semantics(
                                  key: ValueKey(_signUp),
                                  header: true,
                                  child: Text(
                                    _signUp ? 'Create your account' : 'Welcome back',
                                    style: context.text.headlineMedium?.copyWith(color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        constraints: BoxConstraints(minHeight: box.maxHeight - 112),
                        decoration: BoxDecoration(
                          color: t.canvas,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                        ),
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 480),
                            child: Form(
                              key: _form,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    _signUp
                                        ? 'Your settings, totals and history stay on this phone.'
                                        : 'Sign in to pick up where you left off.',
                                    style: context.text.titleMedium?.copyWith(
                                      color: t.muted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 260),
                                    curve: Curves.easeOutCubic,
                                    child: _signUp
                                        ? Padding(
                                            padding: const EdgeInsets.only(bottom: 14),
                                            child: TextFormField(
                                              controller: _name,
                                              textCapitalization: TextCapitalization.words,
                                              autofillHints: const [AutofillHints.name],
                                              decoration: const InputDecoration(
                                                labelText: 'Full name',
                                                prefixIcon: Icon(Icons.person_outline_rounded),
                                              ),
                                              validator: (v) =>
                                                  (v == null || v.trim().length < 2) ? 'Enter your name' : null,
                                            ),
                                          )
                                        : const SizedBox(width: double.infinity),
                                  ),
                                  TextFormField(
                                    controller: _email,
                                    keyboardType: TextInputType.emailAddress,
                                    autofillHints: const [AutofillHints.email],
                                    decoration: const InputDecoration(
                                      labelText: 'Email',
                                      prefixIcon: Icon(Icons.alternate_email_rounded),
                                    ),
                                    validator: (v) =>
                                        (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()))
                                        ? 'Enter a valid email'
                                        : null,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _password,
                                    obscureText: _obscure,
                                    autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                                      suffixIcon: IconButton(
                                        tooltip: _obscure ? 'Show password' : 'Hide password',
                                        icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                                        onPressed: () => setState(() => _obscure = !_obscure),
                                      ),
                                    ),
                                    validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
                                    onFieldSubmitted: (_) => _submit(),
                                  ),
                                  if (_signUp && _password.text.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        for (var i = 0; i < 3; i++)
                                          Expanded(
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 250),
                                              height: 5,
                                              margin: const EdgeInsets.only(right: 6),
                                              decoration: BoxDecoration(
                                                color: i < _strength
                                                    ? [t.danger, t.warning, t.success][_strength - 1]
                                                    : t.cardHigh,
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                            ),
                                          ),
                                        Text(
                                          ['Too short', 'Weak', 'Good', 'Strong'][_strength],
                                          style: context.text.labelMedium?.copyWith(color: t.muted),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (_error != null) ...[
                                    const SizedBox(height: 14),
                                    Semantics(
                                      liveRegion: true,
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: t.danger.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.error_outline_rounded, color: t.danger),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                _error!,
                                                style: TextStyle(color: t.danger, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 24),
                                  FilledButton(
                                    onPressed: _busy ? null : _submit,
                                    child: _busy
                                        ? SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 3,
                                              color: context.colors.onPrimary,
                                            ),
                                          )
                                        : Text(_signUp ? 'Create account' : 'Sign in'),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(child: Divider(color: t.line)),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: Text('or', style: context.text.bodyMedium?.copyWith(color: t.muted)),
                                      ),
                                      Expanded(child: Divider(color: t.line)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: _busy ? null : () => AppScope.of(context).auth.continueAsGuest(),
                                    icon: const Icon(Icons.bolt_rounded),
                                    label: const Text('Continue without an account'),
                                  ),
                                  const SizedBox(height: 16),
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _signUp = !_signUp;
                                      _error = null;
                                    }),
                                    child: Text(
                                      _signUp ? 'Already have an account? Sign in' : 'New here? Create an account',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
