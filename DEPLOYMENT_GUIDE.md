# 🚀 GUIDE DE DÉPLOIEMENT - ShopBook

## ✅ Avant de démarrer

Vérifiez que vous avez:
- [x] Flutter SDK installé (version 3.9.2+)
- [x] Android Studio ou Xcode (selon la plateforme)
- [x] Un appareil ou émulateur connecté

---

## 📋 ÉTAPE 1: Vérifier l'installation

### Windows PowerShell ou Terminal

```powershell
# Vérifier Flutter
flutter --version

# Vérifier doctor
flutter doctor
```

Vous devriez voir:
- ✅ Flutter SDK OK
- ✅ Android toolchain OK (si Android)
- ✅ Xcode OK (si iOS)

---

## 🔧 ÉTAPE 2: Préparer le projet

```powershell
# Naviguer au répertoire du projet
cd "c:\Users\Boris NGOUADJEU\Desktop\Tous les dossiers du burreau\projet\app\shopnotbook"

# Nettoyer les builds précédentes
flutter clean

# Récupérer les dépendances
flutter pub get

# Analyser le code pour erreurs
dart analyze
```

---

## 📱 ÉTAPE 3: Tester sur émulateur/appareil

### Lancer l'application

```powershell
# Lister appareils disponibles
flutter devices

# Lancer sur l'appareil par défaut
flutter run

# Lancer sur un appareil spécifique
flutter run -d <device-id>
```

### Mode développement
```powershell
# Avec Hot Reload
flutter run

# Puis dans le terminal:
# Appuyez sur 'r' pour hot reload
# Appuyez sur 'R' pour hot restart
# Appuyez sur 'q' pour quitter
```

---

## 🏗️ ÉTAPE 4: Build pour Android

### Options de build

#### Option 1: APK (Plus simple, teste uniquement)
```powershell
# Build APK en mode release
flutter build apk --release

# Le fichier APK sera dans:
# build/app/outputs/flutter-apk/app-release.apk
```

#### Option 2: App Bundle (Pour Google Play Store)
```powershell
# Build App Bundle
flutter build appbundle --release

# Le fichier Bundle sera dans:
# build/app/outputs/bundle/release/app-release.aab
```

### Installer APK sur appareil

```powershell
# Après le build APK
adb install build/app/outputs/flutter-apk/app-release.apk

# Ou via l'interface graphique:
# 1. Connecter l'appareil en USB
# 2. Activer le mode développeur
# 3. Autoriser les installations d'APK tiers
# 4. Double-cliquer sur l'APK
```

---

## 🍎 ÉTAPE 5: Build pour iOS

### Compilation

```powershell
# Build pour iOS (sur Mac uniquement)
flutter build ios --release

# Ou build pour le simulateur iOS
flutter build ios --simulator

# Pour générer un IPA
flutter build ipa --release
```

### Déployer sur App Store

```powershell
# Ouvrir le projet Xcode
open ios/Runner.xcworkspace

# Dans Xcode:
# 1. Aller à Product > Archive
# 2. Sélectionner Distribute App
# 3. Choisir App Store Connect
# 4. Valider et envoyer
```

---

## 🌐 ÉTAPE 6: Build pour Web (Optionnel)

```powershell
# Activer Web support
flutter config --enable-web

# Build Web
flutter build web

# Serveur local
flutter run -d chrome

# Les fichiers sont dans:
# build/web/
```

---

## 📊 ÉTAPE 7: Test & Validation

### Tests de fonctionnalité

```powershell
# Lancer les tests
flutter test

# Tests spécifiques
flutter test test/widget_test.dart
```

### Checklist de validation

- [ ] Inscription fonctionne
- [ ] Connexion fonctionne  
- [ ] Home affiche produits
- [ ] Recherche produit fonctionne
- [ ] Vente s'enregistre
- [ ] Stock se met à jour
- [ ] Alertes s'affichent (Orange/Rouge)
- [ ] Seuils se sauvegardent
- [ ] Bénéfices se calculent
- [ ] Déconnexion fonctionne

---

## 🔒 ÉTAPE 8: Configuration de sécurité

### Android
```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<!-- Vérifier les permissions -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

### iOS
```
<!-- ios/Runner/Info.plist -->
<!-- Vérifier les paramètres de confidentialité -->
```

---

## 📦 ÉTAPE 9: Distribution

### Google Play Store

```powershell
# 1. Créer un compte Google Play Developer

# 2. Créer l'app
# 3. Remplir les informations

# 4. Uploader l'APK/AAB
flutter build appbundle --release

# 5. Attendre l'approbation (24-48h)
```

### Apple App Store

```powershell
# 1. Créer compte Apple Developer

# 2. Créer l'app dans App Store Connect

# 3. Build et upload via Xcode
flutter build ipa --release

# 4. Valider et soumettre
# 5. Attendre l'approbation (24-48h)
```

---

## 🐛 Dépannage

### L'application ne démarre pas
```powershell
# Solution 1: Nettoyer
flutter clean
flutter pub get
flutter run

# Solution 2: Vérifier la version Flutter
flutter --version
# Doit être >= 3.9.2

# Solution 3: Vérifier les dépendances
flutter doctor -v
```

### Erreurs de build Android
```powershell
# Solution 1: Mettre à jour Gradle
# Edit: android/build.gradle

# Solution 2: Invalider le cache
flutter clean
flutter pub get

# Solution 3: Accorder les permissions
adb shell pm grant com.example.shopnotbook android.permission.WRITE_EXTERNAL_STORAGE
```

### Problèmes iOS
```powershell
# Nettoyer le build iOS
rm -rf ios/Pods
rm ios/Podfile.lock
flutter clean
flutter pub get
flutter run
```

### Erreurs SQLite
```powershell
# Si problèmes de base de données:
# 1. Supprimer l'app
# 2. Réinstaller
# 3. Vérifier les migrations dans database_service.dart
```

---

## 📈 Monitoring post-déploiement

### Vérifier les performances

```powershell
# Profiler l'app
flutter run --profile

# DevTools
flutter pub global activate devtools
devtools
```

### Analyser les crashs

```powershell
# Voir les logs
adb logcat flutter:I *:S

# iOS logs
idevicesyslog
```

---

## 🔄 Mise à jour de l'app

### Augmenter la version

```yaml
# pubspec.yaml
version: 1.0.1+2
# Format: version+buildNumber
# Incrémenter pour chaque nouvelle release
```

### Mettre à jour les dépendances

```powershell
# Vérifier les updates
flutter pub outdated

# Mettre à jour tout
flutter pub upgrade

# Mettre à jour une dépendance
flutter pub upgrade sqflite
```

---

## 📚 Ressources utiles

- [Flutter Official Docs](https://flutter.dev/docs)
- [Google Play Developer Docs](https://developer.android.com)
- [Apple App Store Connect](https://appstoreconnect.apple.com)
- [Flutter Troubleshooting](https://flutter.dev/docs/testing/troubleshooting)

---

## ✨ Commandes rapides

```powershell
# Tout d'un coup
flutter clean; flutter pub get; flutter run

# Tester
flutter test

# Analyser
dart analyze

# Build APK
flutter build apk --release

# Build AAB
flutter build appbundle --release

# Build iOS
flutter build ios --release

# Build Web
flutter build web
```

---

## 🎯 Étapes finales avant publication

- [ ] Mise à jour version dans pubspec.yaml
- [ ] Tests complets sur appareil réel
- [ ] Vérification sécurité (pas de données sensibles)
- [ ] Fichiers de logs nettoyés
- [ ] Documentation mise à jour
- [ ] Screenshots préparés
- [ ] Description app rédigée
- [ ] Politique de confidentialité prête
- [ ] Numéro d'assistance défini
- [ ] Tests des permissions

---

## 🚀 Prêt?

```powershell
# Lancez simplement!
flutter run --release

# Ou
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

**Bonne chance avec le déploiement de ShopBook!** 🎉

*Pour toute question, consulter la documentation Flutter officielle*
