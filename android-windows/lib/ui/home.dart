import 'package:flutter/material.dart';

import 'notes_screen.dart';
import 'settings_screen.dart';
import 'subjects_screen.dart';
import 'tasks_screen.dart';
import 'theme.dart';
import 'today_screen.dart';
import 'widgets.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon, this.screen);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

final _destinations = [
  const _Destination('Heute', Icons.wb_sunny_outlined, Icons.wb_sunny, TodayScreen()),
  const _Destination('Fächer', Icons.menu_book_outlined, Icons.menu_book, SubjectsScreen()),
  const _Destination('Aufgaben', Icons.check_circle_outline, Icons.check_circle, TasksScreen()),
  const _Destination('Notizen', Icons.description_outlined, Icons.description, NotesScreen()),
];

/// Bottom bar on phones, side rail on tablets and PCs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(index: _index, children: [for (final d in _destinations) d.screen]);
    if (!isWide(context)) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final d in _destinations)
              NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Margin', style: context.serifTitle.copyWith(fontSize: 18)),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(padding: const EdgeInsets.only(bottom: 16), child: SettingsButton()),
              ),
            ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
            ],
          ),
          VerticalDivider(width: 1, color: context.colors.ruling),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Opens the settings; the icon shows the sync state.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Services.sync,
        builder: (context, _) {
          final sync = Services.sync;
          final icon = !sync.enabled
              ? Icons.settings_outlined
              : sync.lastError != null
                  ? Icons.cloud_off_outlined
                  : sync.syncing
                      ? Icons.sync
                      : Icons.cloud_done_outlined;
          return IconButton(
            tooltip: 'Einstellungen',
            icon: Icon(icon),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          );
        },
      );
}

/// App bar actions of the main screens: settings live in the rail on wide screens.
List<Widget> shellActions(BuildContext context) => isWide(context) ? const [] : const [SettingsButton()];
