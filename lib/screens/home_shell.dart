import 'package:flutter/material.dart';

import 'apps_screen.dart';
import 'bots_screen.dart';
import 'dashboard_screen.dart';
import 'files_screen.dart';
import 'services_screen.dart';
import 'settings_screen.dart';

/// Bottom-nav shell: Dashboard / Apps / Services / Files / Bots. Apps is the
/// flagship feature, so it sits right next to Dashboard rather than being
/// buried. Only the visible tab's screen keeps its poll timer running —
/// each screen is told whether it's `active` so it can pause when hidden.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['Dashboard', 'Apps', 'Services', 'Files', 'Bots'];

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(active: _index == 0),
      AppsScreen(active: _index == 1),
      ServicesScreen(active: _index == 2),
      FilesScreen(active: _index == 3),
      BotsScreen(active: _index == 4),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Connection settings',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.rocket_launch_outlined), selectedIcon: Icon(Icons.rocket_launch), label: 'Apps'),
          NavigationDestination(icon: Icon(Icons.dns_outlined), selectedIcon: Icon(Icons.dns), label: 'Services'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Files'),
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), selectedIcon: Icon(Icons.smart_toy), label: 'Bots'),
        ],
      ),
    );
  }
}
