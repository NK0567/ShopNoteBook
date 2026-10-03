import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/shop_repository.dart';
import 'services/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'fr_FR';
  await initializeDateFormatting('fr_FR');

  try {
    final db = await AppDatabase.open();
    final repo = ShopRepository(db);
    final session = Session(repo);
    // Enregistré avant l'application : reçoit le bouton Retour d'Android en premier.
    WidgetsBinding.instance.addObserver(_LockedBackGuard(session));
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: repo),
          ChangeNotifierProvider.value(value: session),
        ],
        child: const ShopBookApp(),
      ),
    );
  } catch (e) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Impossible d\'ouvrir la base de données.\n\n$e', textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quand l'application est verrouillée, le bouton Retour ne doit pas fermer
/// les écrans cachés sous l'écran de verrouillage.
class _LockedBackGuard with WidgetsBindingObserver {
  _LockedBackGuard(this.session);
  final Session session;

  @override
  Future<bool> didPopRoute() async => session.isLoggedIn && session.isLocked;
}
