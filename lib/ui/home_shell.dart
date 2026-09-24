import 'package:flutter/material.dart';

import '../data/notifications.dart';
import '../main.dart';
import 'absences_page.dart';
import 'cahier_page.dart';
import 'planning_page.dart';
import 'profile_page.dart';
import 'travail_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  final _planning = GlobalKey<PlanningPageState>();
  late final _pages = [PlanningPage(key: _planning), const TravailPage(), const CahierPage(), const AbsencesPage(), const ProfilePage()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PlanningNotifications.openRequests.addListener(_onOpenRequest);
    // Application lancée par une notification : la demande attend déjà.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onOpenRequest());
  }

  @override
  void dispose() {
    PlanningNotifications.openRequests.removeListener(_onOpenRequest);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onOpenRequest() {
    final request = PlanningNotifications.openRequests.value;
    if (request == null || !mounted) return;
    PlanningNotifications.openRequests.value = null;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _index = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _planning.currentState?.open(request));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) AppScope.read(context).sync();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today_rounded),
            label: 'Planning',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment_rounded),
            label: 'Travail',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Cahier',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_busy_outlined),
            selectedIcon: Icon(Icons.event_busy_rounded),
            label: 'Absences',
          ),
          NavigationDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps_rounded),
            label: 'Plus',
          ),
        ],
      ),
    );
  }
}
