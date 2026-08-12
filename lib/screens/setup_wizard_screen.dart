import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/connection_settings.dart';
import '../core/termux_bridge.dart';
import 'settings_screen.dart';

const _allowExternalAppsCommand =
    "echo 'allow-external-apps=true' >> ~/.termux/termux.properties && termux-reload-settings";

const _setupCommand = 'set -e; '
    'pkg install -y git; '
    'rm -rf ~/on_server_repo; '
    'git clone https://github.com/xtromate/on_server.git ~/on_server_repo; '
    'bash ~/on_server_repo/server/scripts/install.sh; '
    'bash ~/on_server_repo/server/scripts/setup-services.sh';

const _tailscaleCommand = 'set -e; '
    'pkg install -y tailscale; '
    '(nohup tailscaled --tun=userspace-networking >/dev/null 2>&1 &) ; '
    'sleep 2; '
    'tailscale up';

const _setupStatusUrl = 'http://localhost:8420/api/setup/status';
const _setupClaimUrl = 'http://localhost:8420/api/setup/claim';

enum _Step { welcome, termuxCheck, allowExternal, automatedSetup }

enum _SetupPhase {
  idle,
  requestingPermission,
  launching,
  polling,
  claiming,
  rejected,
  timedOut,
  claimConflict,
  error,
}

/// Multi-step wizard that automates almost all of the Termux-side setup via
/// Android intents into Termux's RUN_COMMAND API (see [TermuxBridge] /
/// MainActivity.kt), so the user mostly taps buttons instead of typing shell
/// commands. Shown by [_ConnectionGate] in main.dart in place of
/// [SettingsScreen] until the app is configured; offers a manual path into
/// [SettingsScreen] for users who already have a server running.
class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  final _termux = TermuxBridge();

  _Step _step = _Step.welcome;

  bool _checkingTermux = false;
  bool? _termuxInstalled;

  _SetupPhase _setupPhase = _SetupPhase.idle;
  String? _setupError;

  Future<void> _checkTermux() async {
    setState(() {
      _step = _Step.termuxCheck;
      _checkingTermux = true;
    });
    final installed = await _termux.isInstalled();
    if (!mounted) return;
    setState(() {
      _checkingTermux = false;
      _termuxInstalled = installed;
    });
    if (installed) {
      setState(() => _step = _Step.allowExternal);
    }
  }

  Future<void> _startAutomatedSetup() async {
    setState(() {
      _setupPhase = _SetupPhase.requestingPermission;
      _setupError = null;
    });
    final granted = await _termux.requestRunCommandPermission();
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _setupPhase = _SetupPhase.error;
        _setupError = 'Termux command permission was not granted. Open Android Settings > '
            'Apps > on_server > Permissions and allow "Run commands in Termux", then try again.';
      });
      return;
    }

    setState(() => _setupPhase = _SetupPhase.launching);
    final ok = await _termux.runCommand(
      path: '/data/data/com.termux/files/usr/bin/bash',
      arguments: ['-c', _setupCommand],
      background: true,
      label: 'on_server setup',
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _setupPhase = _SetupPhase.rejected;
        _setupError = 'Termux rejected the command. Make sure you completed the previous step '
            '(allow-external-apps) inside Termux, then try again.';
      });
      return;
    }

    setState(() => _setupPhase = _SetupPhase.polling);
    await _pollForReady();
  }

  Future<void> _pollForReady() async {
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    while (mounted && DateTime.now().isBefore(deadline)) {
      try {
        final resp = await http.get(Uri.parse(_setupStatusUrl)).timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final body = jsonDecode(resp.body);
          if (body is Map && body['ready'] == true) {
            if (body['claimed'] == true) {
              if (!mounted) return;
              setState(() {
                _setupPhase = _SetupPhase.claimConflict;
                _setupError = 'This server has already been set up and its token already '
                    'claimed. Go to Settings and enter the connection details manually.';
              });
              return;
            }
            await _claim();
            return;
          }
        }
      } catch (_) {
        // control-api probably isn't up yet — keep polling.
      }
      await Future.delayed(const Duration(seconds: 4));
    }
    if (!mounted) return;
    setState(() {
      _setupPhase = _SetupPhase.timedOut;
      _setupError = "Still not done — check the Termux notification for errors, or open "
          "Termux to see what's happening.";
    });
  }

  Future<void> _claim() async {
    setState(() => _setupPhase = _SetupPhase.claiming);
    try {
      final resp = await http.post(Uri.parse(_setupClaimUrl)).timeout(const Duration(seconds: 8));
      dynamic body;
      try {
        body = jsonDecode(resp.body);
      } catch (_) {
        body = null;
      }
      if (resp.statusCode == 200 && body is Map && body['ok'] == true && body['token'] is String) {
        if (!mounted) return;
        final token = body['token'] as String;
        // Show the Done/Tailscale steps on a pushed route (rather than
        // wiring them into this screen's own _step machine) so they stay
        // on screen regardless of what ConnectionGate does once
        // ConnectionSettings becomes configured — see _PostSetupScreen.
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _PostSetupScreen(token: token)),
        );
        return;
      }
      if (resp.statusCode == 409) {
        if (!mounted) return;
        setState(() {
          _setupPhase = _SetupPhase.claimConflict;
          _setupError = (body is Map && body['error'] != null)
              ? body['error'].toString()
              : 'This token has already been claimed. Go to Settings and enter the connection '
                  'details manually.';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _setupPhase = _SetupPhase.error;
        _setupError = 'Unexpected response while claiming the token (${resp.statusCode}).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _setupPhase = _SetupPhase.error;
        _setupError = 'Could not reach the server to claim the token: $e';
      });
    }
  }

  void _openSettingsManually() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setup Wizard')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _buildStep(context),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    switch (_step) {
      case _Step.welcome:
        return _WelcomeStep(
          key: const ValueKey('welcome'),
          onGetStarted: _checkTermux,
          onManualSetup: _openSettingsManually,
        );
      case _Step.termuxCheck:
        return _TermuxCheckStep(
          key: const ValueKey('termuxCheck'),
          checking: _checkingTermux,
          installed: _termuxInstalled,
          onOpenInstallPage: _termux.openInstallPage,
          onRecheck: _checkTermux,
        );
      case _Step.allowExternal:
        return _AllowExternalStep(
          key: const ValueKey('allowExternal'),
          onOpenTermux: _termux.openTermux,
          onContinue: () => setState(() => _step = _Step.automatedSetup),
        );
      case _Step.automatedSetup:
        return _AutomatedSetupStep(
          key: const ValueKey('automatedSetup'),
          phase: _setupPhase,
          error: _setupError,
          onStart: _startAutomatedSetup,
          onBack: () => setState(() {
            _step = _Step.allowExternal;
            _setupPhase = _SetupPhase.idle;
            _setupError = null;
          }),
          onOpenSettings: _openSettingsManually,
          onOpenTermux: _termux.openTermux,
        );
    }
  }
}

class _WelcomeStep extends StatelessWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onManualSetup;

  const _WelcomeStep({super.key, required this.onGetStarted, required this.onManualSetup});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.dns, size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text('Turn this phone into a server', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          'On Server runs a small backend inside Termux — Node, nginx, redis, postgres and '
          'friends — that this app talks to over HTTP. This wizard automates almost all of '
          'that setup: it sends commands to Termux for you, so you mostly just tap buttons '
          'instead of typing shell commands.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onGetStarted,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Get started'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: onManualSetup,
          child: const Text("I already have a server running — enter connection details manually"),
        ),
      ],
    );
  }
}

class _TermuxCheckStep extends StatelessWidget {
  final bool checking;
  final bool? installed;
  final Future<void> Function() onOpenInstallPage;
  final Future<void> Function() onRecheck;

  const _TermuxCheckStep({
    super.key,
    required this.checking,
    required this.installed,
    required this.onOpenInstallPage,
    required this.onRecheck,
  });

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (installed == true) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Termux is required', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          "On Server runs entirely inside Termux, a terminal app. It isn't installed on this "
          "phone yet — and it needs to be the F-Droid build specifically (the Play Store build "
          'is outdated and no longer supported by Termux itself).',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onOpenInstallPage,
          icon: const Icon(Icons.open_in_browser),
          label: const Text('Open F-Droid page'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRecheck,
          icon: const Icon(Icons.refresh),
          label: const Text("I've installed it"),
        ),
      ],
    );
  }
}

class _AllowExternalStep extends StatelessWidget {
  final Future<void> Function() onOpenTermux;
  final VoidCallback onContinue;

  const _AllowExternalStep({super.key, required this.onOpenTermux, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('One manual step', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          "Termux requires one one-time command to be typed inside Termux itself before it "
          "will accept commands from any other app, including this one. There's no way to do "
          "this from outside Termux — it's Termux's own security gate, not a permission this "
          'app can request on your behalf.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            _allowExternalAppsCommand,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: _allowExternalAppsCommand));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Command copied')));
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy command'),
            ),
            OutlinedButton.icon(
              onPressed: onOpenTermux,
              icon: const Icon(Icons.terminal),
              label: const Text('Open Termux'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          "We can't verify this automatically — just make sure it ran without error in Termux "
          'before continuing.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onContinue,
          icon: const Icon(Icons.arrow_forward),
          label: const Text("I've done this, continue"),
        ),
      ],
    );
  }
}

class _AutomatedSetupStep extends StatelessWidget {
  final _SetupPhase phase;
  final String? error;
  final Future<void> Function() onStart;
  final VoidCallback onBack;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onOpenTermux;

  const _AutomatedSetupStep({
    super.key,
    required this.phase,
    required this.error,
    required this.onStart,
    required this.onBack,
    required this.onOpenSettings,
    required this.onOpenTermux,
  });

  bool get _busy =>
      phase == _SetupPhase.requestingPermission ||
      phase == _SetupPhase.launching ||
      phase == _SetupPhase.polling ||
      phase == _SetupPhase.claiming;

  String get _busyLabel {
    switch (phase) {
      case _SetupPhase.requestingPermission:
        return 'Requesting Termux command permission…';
      case _SetupPhase.launching:
        return 'Starting setup in Termux…';
      case _SetupPhase.polling:
        return 'Setting up your server — this can take several minutes the first time.';
      case _SetupPhase.claiming:
        return 'Finishing setup…';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Automated setup', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          "This installs Node, nginx, redis, postgres and the other pieces On Server needs, "
          'then starts them. It can take several minutes the first time, and runs in the '
          'background — Termux will show a notification while it works.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        if (_busy) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Center(
            child: Text(_busyLabel, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ),
          if (phase == _SetupPhase.polling) ...[
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton.icon(
                onPressed: onOpenTermux,
                icon: const Icon(Icons.terminal),
                label: const Text('Open Termux'),
              ),
            ),
          ],
        ] else ...[
          if (error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.rocket_launch),
            label: Text(phase == _SetupPhase.idle ? 'Set Up Server' : 'Try again'),
          ),
          const SizedBox(height: 12),
          if (phase == _SetupPhase.rejected || phase == _SetupPhase.idle)
            TextButton(onPressed: onBack, child: const Text('Back')),
          if (phase == _SetupPhase.claimConflict || phase == _SetupPhase.error)
            TextButton(onPressed: onOpenSettings, child: const Text('Go to Settings instead')),
        ],
      ],
    );
  }
}

enum _TailscalePhase { idle, requestingPermission, launching, launched, error }

/// Shown by pushing a new route on top of [SetupWizardScreen] once the
/// setup token has been claimed. Deliberately kept off of the reactive
/// ConnectionGate swap: as soon as ConnectionSettings.update() below makes
/// the app "configured", ConnectionGate (in main.dart) will swap its own
/// content over to HomeShell — but that only affects the route underneath
/// this one, so the Done/Tailscale steps stay visible until the user
/// explicitly continues.
class _PostSetupScreen extends StatefulWidget {
  final String token;
  const _PostSetupScreen({required this.token});

  @override
  State<_PostSetupScreen> createState() => _PostSetupScreenState();
}

class _PostSetupScreenState extends State<_PostSetupScreen> {
  final _termux = TermuxBridge();

  _PostStep _step = _PostStep.done;

  bool _connecting = true;
  bool _healthOk = false;
  String? _healthError;

  _TailscalePhase _tailscalePhase = _TailscalePhase.idle;
  String? _tailscaleError;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    final settings = context.read<ConnectionSettings>();
    await settings.update(host: 'localhost', port: 8420, token: widget.token);
    if (!mounted) return;
    final client = ApiClient(settings);
    try {
      final ok = await client.health();
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _healthOk = ok;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _healthOk = false;
        _healthError = e.toString();
      });
    } finally {
      client.dispose();
    }
  }

  Future<void> _startTailscale() async {
    setState(() {
      _tailscalePhase = _TailscalePhase.requestingPermission;
      _tailscaleError = null;
    });
    final granted = await _termux.requestRunCommandPermission();
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _tailscalePhase = _TailscalePhase.error;
        _tailscaleError = 'Termux command permission was not granted.';
      });
      return;
    }
    setState(() => _tailscalePhase = _TailscalePhase.launching);
    final ok = await _termux.runCommand(
      path: '/data/data/com.termux/files/usr/bin/bash',
      arguments: ['-c', _tailscaleCommand],
      background: false,
      label: 'on_server tailscale setup',
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _tailscalePhase = _TailscalePhase.error;
        _tailscaleError = 'Termux rejected the command.';
      });
      return;
    }
    // RUN_COMMAND_SESSION_ACTION only affects which session Termux focuses
    // once it's frontmost — starting the RunCommandService doesn't bring
    // Termux's own UI forward on its own, so bring it forward explicitly.
    await _termux.openTermux();
    if (!mounted) return;
    setState(() => _tailscalePhase = _TailscalePhase.launched);
  }

  void _finish() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setup Wizard'), automaticallyImplyLeading: false),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _step == _PostStep.done ? _buildDone(context) : _buildTailscale(context),
        ),
      ),
    );
  }

  Widget _buildDone(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _connecting
              ? Icons.hourglass_top
              : (_healthOk ? Icons.check_circle : Icons.error),
          size: 48,
          color: _connecting
              ? Theme.of(context).colorScheme.primary
              : (_healthOk ? Colors.green : Theme.of(context).colorScheme.error),
        ),
        const SizedBox(height: 16),
        Text(
          _connecting ? 'Connecting…' : (_healthOk ? "You're connected" : 'Connected, but health check failed'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        if (_connecting)
          const Text('Confirming the app can reach control-api…')
        else if (_healthOk)
          const Text('The app is now connected to the server running on this phone.')
        else
          Text(
            'The token was saved, but the health check failed'
            '${_healthError != null ? ' ($_healthError)' : ''}. You can retry from Settings, '
            'or continue — services may still be starting up.',
          ),
        const SizedBox(height: 16),
        Text(
          'Remote access over Tailscale is optional and not required to use the app on your '
          'home network. You can set it up now or skip it and do it later from Termux.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _connecting ? null : _finish,
          icon: const Icon(Icons.dashboard),
          label: const Text('Go to dashboard'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _connecting ? null : () => setState(() => _step = _PostStep.tailscale),
          icon: const Icon(Icons.wifi_tethering),
          label: const Text('Set up remote access (optional)'),
        ),
      ],
    );
  }

  Widget _buildTailscale(BuildContext context) {
    final busy = _tailscalePhase == _TailscalePhase.requestingPermission ||
        _tailscalePhase == _TailscalePhase.launching;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Remote access (optional)', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          'Tailscale lets you reach this server from outside your home network. The first run '
          "needs an interactive browser login, so this can't be fully automated — we'll install "
          'Tailscale and start it in Termux, then you tap the login link it prints.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        if (busy) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Center(child: Text(_tailscalePhase == _TailscalePhase.requestingPermission
              ? 'Requesting Termux command permission…'
              : 'Starting Tailscale in Termux…')),
        ] else if (_tailscalePhase == _TailscalePhase.launched) ...[
          const Icon(Icons.check_circle, color: Colors.green, size: 40),
          const SizedBox(height: 12),
          const Text(
            'Tailscale is starting in Termux — switch to Termux, tap the printed login URL, '
            'and sign in. Once connected, you can reach this server at its Tailscale address '
            'from Settings.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _finish,
            icon: const Icon(Icons.dashboard),
            label: const Text('Go to dashboard'),
          ),
        ] else ...[
          if (_tailscaleError != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _tailscaleError!,
                style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            onPressed: _startTailscale,
            icon: const Icon(Icons.terminal),
            label: const Text('Set up remote access'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _finish,
            child: const Text("Skip for now — I'll do this later from Termux"),
          ),
        ],
      ],
    );
  }
}

enum _PostStep { done, tailscale }
