import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/connection_settings.dart';
import 'screens/home_shell.dart';
import 'screens/setup_wizard_screen.dart';

void main() {
  runApp(const OnServerApp());
}

class OnServerApp extends StatelessWidget {
  const OnServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ConnectionSettings()..load(),
      child: MaterialApp(
        title: 'On Server',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2A78D6)),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3987E5),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const _ConnectionGate(),
      ),
    );
  }
}

/// Routes to [SetupWizardScreen] until connection settings (host + token)
/// are configured, then to [HomeShell]. Reactive: saving valid settings
/// (from the wizard, or from Settings reached via the wizard's manual-setup
/// link) flips this over automatically. [SettingsScreen] remains reachable
/// afterward from within [HomeShell] for reconfiguring.
class _ConnectionGate extends StatelessWidget {
  const _ConnectionGate();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<ConnectionSettings>();
    if (!settings.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!settings.isConfigured) {
      return const SetupWizardScreen();
    }
    return const HomeShell();
  }
}
