import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'services/session.dart';
import 'ui/auth/lock_screen.dart';
import 'ui/auth/login_screen.dart';
import 'ui/home_shell.dart';

class ShopBookApp extends StatelessWidget {
  const ShopBookApp({super.key});

  static ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0), brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return MaterialApp(
      // Nouvelle clé à chaque connexion / déconnexion : toute la pile d'écrans
      // du compte précédent est détruite.
      key: ValueKey(session.user?.id),
      title: 'ShopBook',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: session.isLoggedIn ? const HomeShell() : const LoginScreen(),
      // L'écran de verrouillage recouvre tous les écrans ouverts, sans les fermer.
      builder: (context, child) => Stack(children: [
        // Toute interaction (sur n'importe quel écran) repousse le verrouillage auto.
        Listener(behavior: HitTestBehavior.translucent, onPointerDown: (_) => session.touch(), child: child!),
        if (session.isLoggedIn && session.isLocked)
          Overlay(initialEntries: [OverlayEntry(builder: (_) => const LockScreen())]),
      ]),
    );
  }
}
