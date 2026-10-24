import 'package:flutter/material.dart';

import 'api/asset_session.dart';
import 'api/asset_store.dart';

/// Account entry form. Passwords are never persisted and are cleared after attempts.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.session});
  final AssetSession session;
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _identifier = TextEditingController(),
      _password = TextEditingController(),
      _email = TextEditingController(),
      _name = TextEditingController();
  bool _register = false, _busy = false, _uncertain = false;
  String? _error;
  @override
  void dispose() {
    for (final c in [_identifier, _password, _email, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _uncertain) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await widget.session.register(
          email: _email.text,
          username: _identifier.text,
          name: _name.text,
          password: _password.text,
        );
      } else {
        await widget.session.login(_identifier.text, _password.text);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uncertain =
            _register &&
            !(error is AssetFailure &&
                (error.definitelyNotSent ||
                    [400, 401, 403, 409, 422, 429].contains(error.statusCode)));
        _error = _uncertain
            ? 'Registration may have completed. Try signing in before registering again. No automatic retry was made.'
            : error is AssetFailure
            ? error.message
            : 'Unable to sign in.';
      });
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
    }
  }

  Widget _field(
    String label,
    TextEditingController controller,
    int limit, {
    bool password = false,
    TextInputType? keyboard,
    String? helper,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: controller,
      enabled: !_busy,
      maxLength: limit,
      obscureText: password,
      autocorrect: false,
      enableSuggestions: !password,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Asset Desk')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _register
                  ? 'Create your personal account'
                  : 'Sign in to your inventory',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              'Credentials stay in memory for this session. No equipment records are available before sign-in.',
            ),
            const SizedBox(height: 16),
            if (_register) ...[
              _field(
                'Email',
                _email,
                254,
                keyboard: TextInputType.emailAddress,
              ),
              _field('Display name', _name, 100),
            ],
            _field(
              _register ? 'Username' : 'Email or username',
              _identifier,
              _register ? 30 : 100,
              helper: _register
                  ? '3-30 letters, numbers, dot or underscore'
                  : null,
            ),
            _field(
              'Password',
              _password,
              72,
              password: true,
              helper: '8-72 characters',
            ),
            if (_error != null) Text(_error!),
            if (_busy)
              const LinearProgressIndicator(semanticsLabel: 'Signing in'),
            FilledButton(
              onPressed: _busy || _uncertain ? null : _submit,
              child: Text(_register ? 'Create account' : 'Sign in'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _register = !_register;
                      _password.clear();
                      _error = null;
                      _uncertain = false;
                    }),
              child: Text(
                _register ? 'Use existing account' : 'Create a new account',
              ),
            ),
            const Text(
              'No password reset delivery is configured by this client.',
            ),
          ],
        ),
      ),
    ),
  );
}
