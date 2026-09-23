import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'data/app_state.dart';
import 'ui/expressive.dart';
import 'ui/home_shell.dart';
import 'ui/login_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'fr_FR';
  await initializeDateFormatting('fr_FR');
  final state = await AppState.create();
  runApp(NetypareoApp(state: state));
}

/// Donne accès à [AppState] dans l'arbre, et reconstruit à chaque changement.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Sans abonnement aux changements (pour les callbacks).
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class NetypareoApp extends StatelessWidget {
  const NetypareoApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: DynamicColorBuilder(
        builder: (light, dark) {
          // On garde la couleur du fond d'écran comme graine, mais avec la palette expressive.
          return MaterialApp(
            title: 'NetYParéo+',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(light?.primary ?? kSeedColor, Brightness.light),
            darkTheme: buildTheme(dark?.primary ?? kSeedColor, Brightness.dark),
            home: const _AuthGate(),
          );
        },
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final status = AppScope.of(context).status;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      child: switch (status) {
        AuthStatus.loading => const Scaffold(key: ValueKey('loading'), body: Center(child: ExpressiveLoader())),
        AuthStatus.loggedOut => const LoginPage(key: ValueKey('login')),
        AuthStatus.loggedIn => const HomeShell(key: ValueKey('home')),
      },
    );
  }
}
