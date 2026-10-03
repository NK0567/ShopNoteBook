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
    runApp(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: repo),
        ChangeNotifierProvider(create: (_) => Session(repo)),
      ],
      child: const ShopBookApp(),
    ));
  } catch (e) {
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Impossible d\'ouvrir la base de données.\n\n$e', textAlign: TextAlign.center),
          ),
        ),
      ),
    ));
  }
}
