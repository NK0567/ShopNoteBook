import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shopnotbook/app.dart';
import 'package:shopnotbook/data/app_database.dart';
import 'package:shopnotbook/data/models.dart';
import 'package:shopnotbook/data/shop_repository.dart';
import 'package:shopnotbook/services/session.dart';
import 'package:shopnotbook/ui/settings/settings_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_db.dart';

/// Parcourt tous les écrans à la taille d'un téléphone (360 x 800 points) et
/// échoue sur tout débordement d'affichage ou exception de rendu.
/// `flutter test --dart-define=SCREENSHOTS=true --update-goldens test/ui_screens_test.dart`
/// produit en plus des captures dans test/goldens/.
const _screenshots = bool.fromEnvironment('SCREENSHOTS');

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
  final dir = '$root/bin/cache/artifacts/material_fonts';
  if (!Directory(dir).existsSync()) return;
  Future<ByteData> f(String name) async => ByteData.sublistView(await File('$dir/$name').readAsBytes());
  final roboto = FontLoader('Roboto')
    ..addFont(f('roboto-regular.ttf'))
    ..addFont(f('roboto-medium.ttf'))
    ..addFont(f('roboto-bold.ttf'));
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(f('materialicons-regular.otf'))).load();
}

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'fr_FR';
    await initializeDateFormatting('fr_FR');
    await _loadFonts();
  });

  for (final scale in [1.0, 1.3]) {
    for (final dark in [false, true]) {
      final label = 'x$scale${dark ? '-sombre' : ''}';
      testWidgets('tous les écrans sans débordement ($label)', (tester) async {
        tester.view.physicalSize = const Size(720, 1600);
        tester.view.devicePixelRatio = 2;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        tester.platformDispatcher.platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);

        late Database db;
        late ShopRepository repo;
        late Session session;
        await tester.runAsync(() async {
          db = await AppDatabase.open(factory: testDatabaseFactory(), path: inMemoryDatabasePath);
          repo = ShopRepository(db);
          session = Session(repo, hashIterations: 1000);
        });
        addTearDown(() => tester.runAsync(() => db.close()));

        Future<void> settle([int rounds = 8]) async {
          for (var i = 0; i < rounds; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
            await tester.pump(const Duration(milliseconds: 100));
          }
        }

        Future<void> shot(String name) async {
          await settle();
          if (_screenshots) {
            await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('goldens/$label/$name.png'));
          }
        }

        Future<void> back() async {
          await tester.runAsync(() => tester.state<NavigatorState>(find.byType(Navigator).first).maybePop());
          await settle();
        }

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: repo),
              ChangeNotifierProvider.value(value: session),
            ],
            child: const ShopBookApp(),
          ),
        );
        await shot('01_connexion');

        await tester.tap(find.textContaining('Créer ma boutique'));
        await shot('02_inscription');
        await back();
        await settle();
        await tester.tap(find.text('Mot de passe oublié ?'));
        await shot('02b_mot_de_passe_oublie');
        await back();
        await settle();

        // Données réalistes : noms longs, gros montants, catégories multiples.
        await tester.runAsync(() async {
          await session.register(
            name: 'Boris Ngouadjeu Kalefack',
            email: 'boris@test.cm',
            password: 'Boutique2026',
            businessName: 'Établissements Kalefack & Fils — Quincaillerie générale',
          );
          await session.login('boris@test.cm', 'Boutique2026');
          final uid = session.userId;
          final phones = await repo.addCategory(uid, 'Smartphones et tablettes');
          final acc = await repo.addCategory(uid, 'Accessoires');
          Future<int> p(String ref, String name, int? cat, int stock, double cost, double price, int seuil) =>
              repo.saveProduct(
                uid,
                Product(
                  reference: ref,
                  name: name,
                  categoryId: cat,
                  unit: 'unité',
                  alertThreshold: seuil,
                  initialStock: stock,
                  initialUnitCost: cost,
                  sellingPrice: price,
                ),
              );
          final a = await p('S1', 'Google Pixel 8 Pro 256 Go noir obsidienne', phones, 30, 450000, 625000, 5);
          final b = await p('C1', 'Chargeur rapide USB-C 65 W', acc, 4, 3500, 6000, 10);
          final c = await p('TOMATE', 'Tomates (cageot)', null, 0, 8000, 12000, 3);
          await p('RADIO', 'Radio FM', acc, 7, 15000, 22000, 10);
          for (var i = 0; i < 6; i++) {
            await repo.recordMovement(
              userId: uid,
              type: MovementType.sale,
              productId: a,
              quantity: 2,
              unitPrice: 625000,
              date: DateTime.now().subtract(Duration(days: i)),
              partner: 'Client fidèle numéro $i',
            );
          }
          await repo.recordMovement(
            userId: uid,
            type: MovementType.entry,
            productId: c,
            quantity: 10,
            unitPrice: 8000,
            date: DateTime.now(),
            partner: 'Marché central',
            note: 'Facture 2026-0042',
          );
          final s = await repo.recordMovement(
            userId: uid,
            type: MovementType.sale,
            productId: b,
            quantity: 3,
            unitPrice: 6000,
            date: DateTime.now(),
          );
          await repo.cancelMovement(uid, s.id, 'Erreur de saisie');
          // Vente à crédit et perte, pour les écrans Crédits / Tickets / Rapports.
          final radio = (await repo.inventory(uid)).firstWhere((i) => i.product.reference == 'RADIO');
          await repo.recordSale(
            userId: uid,
            lines: [SaleLine(item: radio, quantity: 2, unitPrice: 22000)],
            date: DateTime.now().subtract(const Duration(days: 12)),
            client: 'Mme Ngo Bassa',
            paid: 10000,
            method: 'Orange Money',
          );
          await repo.recordMovement(
            userId: uid,
            type: MovementType.loss,
            productId: c,
            quantity: 2,
            unitPrice: 0,
            date: DateTime.now(),
            note: 'Périmé',
          );
        });
        await shot('03_accueil');

        await tester.tap(find.text('Stock').last);
        await shot('04_stock');

        await tester.tap(find.text('Google Pixel 8 Pro 256 Go noir obsidienne').first);
        await shot('05_fiche_produit');
        await tester.drag(find.byType(ListView).last, const Offset(0, -600));
        await shot('05b_fiche_produit_bas');

        await tester.tap(find.byTooltip('Modifier'));
        await shot('06_modifier_produit');
        await back();
        await settle();
        await back();
        await settle();

        await tester.tap(find.byType(FloatingActionButton));
        await shot('07_nouveau_produit');
        await back();
        await settle();

        await tester.tap(find.text('Opérations').last);
        await shot('08_operations');

        // Première opération de la liste (toujours visible, même en grand texte).
        await tester.tap(find.text('Tomates (cageot)').first);
        await shot('09_detail_operation');
        await tester.tapAt(const Offset(180, 40));
        await settle();
        await tester.drag(find.byType(Scrollable).last, const Offset(0, 2000));
        await settle();

        await tester.tap(find.widgetWithText(FilledButton, 'Vente'));
        await shot('10_panier_vide');
        await tester.tap(find.widgetWithText(FilledButton, 'Ajouter').first);
        await shot('11_choix_produit');
        await tester.tap(find.text('Radio FM'));
        await shot('11b_quantite_prix');
        await tester.tap(find.widgetWithText(FilledButton, 'Ajouter').last);
        await settle();
        await tester.enterText(find.widgetWithText(TextField, 'Montant reçu du client'), '20000');
        await shot('12_panier_credit');
        await back();
        await settle();

        await tester.tap(find.widgetWithText(FilledButton, 'Entrée'));
        await shot('13_formulaire_entree');
        await back();
        await settle();

        await tester.tap(find.widgetWithText(OutlinedButton, 'Perte'));
        await shot('13b_perte');
        await back();
        await settle();

        await tester.tap(find.widgetWithText(OutlinedButton, 'Crédits'));
        await shot('13c_credits');
        await tester.tap(find.text('Mme Ngo Bassa').first);
        await shot('13d_credit_client');
        await back();
        await settle();
        await back();
        await settle();

        await tester.tap(find.byTooltip('Tickets de caisse'));
        await shot('13e_tickets');
        await tester.tap(find.byType(ListTile).first);
        await shot('13f_ticket');
        await back();
        await settle();
        await back();
        await settle();

        await tester.tap(find.text('Rapports').last);
        await shot('14_rapports');
        await tester.drag(find.byType(ListView).first, const Offset(0, -700));
        await shot('14b_rapports_bas');

        await tester.tap(find.text('Réglages').last);
        await shot('15_reglages');
        await tester.tap(find.text('Catégories'));
        await shot('16_categories');
        await back();
        await settle();
        await tester.scrollUntilVisible(
          find.text('Journal d\'activité'),
          150,
          scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first,
        );
        await settle(2);
        await tester.tap(find.text('Journal d\'activité'));
        await shot('17_journal');
        await back();
        await settle();

        session.lock();
        await shot('18_verrouillage');
      });
    }
  }
}
