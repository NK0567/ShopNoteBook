# ShopBook - Carnet du Boutiquier

## 🎯 Description

**ShopBook** est une application mobile professionnelle conçue pour les commerçants grossistes. Elle offre une solution complète pour gérer leur boutique au quotidien avec simplicité et sécurité.

## ✨ Fonctionnalités principales

### 🏠 Onglet 1: Home (Accueil)
- **Statistiques principales**
  - Affichage des 3 produits les plus demandés
  - Nombre total de ventes et bénéfices du mois
  
- **Alertes de stock**
  - Produits à stock faible (ORANGE) - Réapprovisionnement recommandé
  - Produits à stock critique (ROUGE) - Réapprovisionnement urgent
  - Utilisation de couleurs pour identification rapide

### 🔄 Onglet 2: Opération
Menu avec 7 fonctionnalités essentielles:

1. **🔍 Rechercher un produit**
   - Recherche par nom du produit
   - Affichage du prix d'achat, prix de vente, bénéfice potentiel
   - Code couleur du stock (Vert/Orange/Rouge)

2. **⚠️ Consulter le seuil critique**
   - Deux volets: Orange (faible) et Rouge (critique)
   - Liste des produits concernés
   - Bouton pour générer PDF

3. **📜 Consulter l'historique**
   - Liste de tous les produits vendus
   - Filtrage par jour, semaine, mois

4. **📈 Statistiques**
   - Top 15 des produits les plus vendus
   - Analyse des bénéfices par produit

5. **💰 Bénéfices engendré**
   - Calcul automatique des bénéfices
   - Choix de période: jour, semaine, mois

6. **🛒 Effectuer une vente**
   - Formulaire de vente avec validation obligatoire
   - Enregistrement immédiat de chaque transaction
   - Calcul automatique des bénéfices

7. **📦 Effectuer un réapprovisionnement**
   - Formulaire d'achat avec validation
   - Enregistrement du fournisseur et facture
   - Mise à jour automatique du stock

### ⚙️ Onglet 3: Réglage
- **Fixer le seuil limite**
  - Seuil d'alerte faible (orange)
  - Seuil d'alerte critique (rouge)
  
- **Personnalisation graphique**
  - Choix des couleurs d'alerte
  - Palettes prédéfinies disponibles

## 🔐 Sécurité & Authentification

- ✅ Authentification obligatoire à la connexion
- ✅ Inscription sécurisée pour nouvelles boutiques
- ✅ Mots de passe hashés avec SHA256
- ✅ Données privées et sécurisées par utilisateur
- ✅ Confidentialité totale des informations financières

## 📊 Architecture technique

### Modèles de données
- **User**: Profil utilisateur et paramètres
- **Product**: Catalogue de produits
- **Sale**: Historique des ventes
- **Purchase**: Historique des réapprovisionnements

### Services
- **AuthService**: Gestion de l'authentification
- **DatabaseService**: Opérations CRUD SQLite

### Structure des fichiers
```
lib/
├── main.dart                          # Point d'entrée
├── models/
│   ├── user.dart                     # Modèle utilisateur
│   ├── product.dart                  # Modèle produit
│   ├── sale.dart                     # Modèle vente
│   └── purchase.dart                 # Modèle réapprovisionnement
├── services/
│   ├── auth_service.dart             # Service authentification
│   └── database_service.dart         # Service base de données
└── screens/
    ├── login_screen.dart             # Écran connexion
    ├── register_screen.dart          # Écran inscription
    ├── main_app.dart                 # Application principale
    ├── home_screen.dart              # Onglet accueil
    ├── operation_screen.dart         # Onglet opération
    ├── settings_screen.dart          # Onglet réglage
    └── operation_screens/            # Sous-écrans opérations
        ├── search_product_screen.dart
        ├── critical_threshold_screen.dart
        ├── history_screen.dart
        ├── statistics_screen.dart
        ├── profit_screen.dart
        ├── sale_screen.dart
        └── purchase_screen.dart
```

## 🎨 Design & UX

- **Thème couleur**: Bleu principal avec accents orange et rouge
- **Responsivité**: Adaptation à tous les appareils mobiles
- **Navigation**: Bottom navigation bar avec 3 onglets
- **Code couleur visuel**: 
  - 🟢 Vert = Stock suffisant
  - 🟠 Orange = Stock faible (alerte)
  - 🔴 Rouge = Stock critique (alerte urgente)

## 📱 Dépendances

```yaml
- flutter
- sqflite: Base de données locale
- intl: Formatage dates/heures
- pdf: Génération de PDF
- printing: Impression de documents
- crypto: Hachage sécurisé
```

## 🚀 Installation & Utilisation

### Prérequis
- Flutter SDK installé
- Connexion Internet (pour télécharger les dépendances)

### Étapes d'installation
```bash
# 1. Cloner le projet
git clone <repository>

# 2. Accéder au répertoire
cd shopnotbook

# 3. Installer les dépendances
flutter pub get

# 4. Lancer l'application
flutter run
```

## 📝 Workflow utilisateur

### Premier lancement
1. L'utilisateur arrive sur l'écran d'inscription
2. Crée un compte avec email et mot de passe
3. Accède à l'application principale
4. Configure les seuils d'alerte dans Réglages
5. Ajoute ses produits
6. Commence à enregistrer ventes et achats

### Utilisation quotidienne
1. Se connecte à l'application
2. Consulte le Home pour aperçu rapide
3. Enregistre les ventes/achats dans Opération
4. Surveille les alertes de stock
5. Consulte les statistiques et bénéfices

## 💡 Points clés pour les commerçants

✅ **Simplicité**: Interface intuitive sans courbe d'apprentissage
✅ **Rapidité**: Enregistrement instant des transactions
✅ **Fiabilité**: Données stockées localement en sécurité
✅ **Transparence**: Vue claire des gains et pertes
✅ **Alerte**: Prévention des ruptures de stock
✅ **Analyse**: Statistiques pour optimiser le commerce

## 🔄 Flux de données

```
Utilisateur → App ↔ SQLite Local → Opérations ↔ Base de données
```

- Toutes les données sont stockées localement sur l'appareil
- Aucun envoi externe (respecte la confidentialité)
- Synchronisation instantanée

## 📞 Support & Maintenance

Cette application est conçue pour fonctionner de manière autonome sur l'appareil de l'utilisateur. Pour toute maintenance:

1. Mettre à jour Flutter et les dépendances
2. Tester sur différents appareils
3. Sauvegarder régulièrement la base de données

## 📄 Commentaires du code

Tous les fichiers contiennent des commentaires explicatifs en français pour:
- Comprendre la logique
- Faciliter la maintenance
- Permettre l'évolution future

---

**Créé pour les commerçants grossistes - Simplicité, Sécurité, Succès**

ShopBook v1.0.0
