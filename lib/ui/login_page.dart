import 'package:flutter/material.dart';

import '../core/netypareo_client.dart';
import '../data/app_state.dart';
import '../main.dart';
import 'expressive.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = AppScope.read(context);
    try {
      var challenge = await state.login(_user.text.trim(), _password.text);
      while (challenge != null && mounted) {
        final code = await _askOtp(challenge);
        if (code == null) break;
        challenge = await state.submitOtp(challenge, code);
      }
    } catch (e) {
      if (mounted) setState(() => _error = AppState.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askOtp(OtpChallenge challenge) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.sms_rounded),
        title: const Text('Code de vérification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(challenge.message.isEmpty ? 'NetYParéo t\'a envoyé un code.' : challenge.message),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 8),
              autofillHints: const [AutofillHints.oneTimeCode],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Valider')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Image.asset('assets/logo/logo.png', width: 104, height: 104, semanticLabel: 'Logo NetYParéo+'),
                      ),
                      const SizedBox(height: 32),
                      Text('NetYParéo+', style: text.displaySmall),
                      const SizedBox(height: 8),
                      Text(
                        'Ton emploi du temps, ton cahier de textes et tes absences, sans passer par le site.',
                        style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 40),
                      TextFormField(
                        controller: _user,
                        enabled: !_busy,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                          labelText: 'Identifiant',
                          prefixIcon: Icon(Icons.person_rounded),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Identifiant requis' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        enabled: !_busy,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          prefixIcon: const Icon(Icons.lock_rounded),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Afficher' : 'Masquer',
                            icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Mot de passe requis' : null,
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutBack,
                        child: _error == null
                            ? const SizedBox(height: 24)
                            : Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: scheme.errorContainer,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.error_rounded, color: scheme.onErrorContainer),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      SpringPress(
                        child: FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? ExpressiveLoader(size: 24, color: scheme.onPrimary)
                              : const Text('Se connecter'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Icon(Icons.shield_rounded, size: 18, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Tes identifiants restent chiffrés sur ce téléphone. L\'app parle directement à NetYParéo.',
                              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
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
