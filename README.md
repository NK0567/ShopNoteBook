# ShopBook — le carnet du boutiquier

Application mobile Flutter (Android, iOS, Web) qui remplace les classeurs Excel de gestion de boutique
(`business/ma boutique.xlsm`, `MODIF UN PLUS.xlsm`, `classeur 2excl…xlsm`…). Elle en reprend la logique
(catalogue, entrées, sorties, inventaire au CUMP, tableau de bord par catégorie) en corrigeant leurs défauts.

## Correspondance Excel → application

| Classeur Excel | Application |
|---|---|
| Feuille **Marchandise** (formulaire + `ListeMarchandise`) | Onglet **Stock** → bouton « Produit » |
| Feuille **Opération** (boutons Entrée / Sortie / Annuler) | Boutons **Vente** / **Entrée**, bouton « Effacer » |
| Feuilles **Entrée** / **Sortie** | Onglet **Opérations** (historique filtrable) |
| Feuille **Inventaire** + bouton ACTUALISER | Onglet **Stock** : calculé en temps réel, plus besoin d'actualiser |
| Feuilles **Traitement** / **Tableau de bord** (TCD, camemberts, segment Catégorie) | Onglets **Accueil** et **Rapports** (filtres période + catégorie) |
| Colonne **Bénéfice** (cassée dans `MODIF UN PLUS`) | Bénéfice par vente = (prix − CUMP) × quantité |

## Règles de calcul

- **Stock final** = stock initial + Σ entrées − Σ sorties.
- **CUMP** = (stock initial × coût initial + Σ montants des entrées) / (stock initial + Σ quantités entrées).
- **Valeur du stock** = stock final × CUMP.
- **Statut** : ≤ 0 → *Non disponible* ; < 50 % du seuil → *Approvisionnement urgent* ;
  < seuil → *Approvisionnement nécessaire* ; sinon *Niveau satisfaisant*.
- **Bénéfice d'une vente** : (prix de vente − CUMP au moment de la vente) × quantité. Le CUMP est figé
  sur la vente : une entrée ultérieure à un autre prix ne réécrit pas les bénéfices passés.

## Défauts des classeurs corrigés

- Stock négatif impossible : une vente supérieure au stock est refusée.
- Référence produit unique, normalisée (`tc` = `TC`), plus de doublon « GO » pour deux produits.
- Catégories en liste fermée (fini « Smart phone » / « SmartPhone » / « SMARTPHONE »).
- Plus de formules `#REF!` ni de totaux saisis en dur : tout est recalculé depuis le journal.
- Date contrôlée (pas de date future), quantité > 0, prix ≥ 0.
- Numérotation `E-0001` / `S-0001` garantie unique.

## Sécurité

- Compte protégé par mot de passe (8 caractères min., lettres + chiffres), haché en
  **PBKDF2-HMAC-SHA256** avec sel aléatoire (60 000 itérations). Les anciens comptes (SHA256 sans sel)
  sont convertis automatiquement à la connexion.
- **Blocage** après 5 échecs (30 s, puis délai doublé, max 15 min) ; message identique que l'email
  existe ou non.
- **Verrouillage automatique** après inactivité (1 à 30 min, réglable) et bouton « Verrouiller ».
- **Historique non effaçable** : une opération ne se supprime pas, elle s'annule avec un motif et reste
  visible (barrée). Une entrée déjà vendue ne peut pas être annulée.
- Stock d'ouverture figé dès le premier mouvement ; un produit avec historique s'archive, il ne se supprime pas.
- **Journal d'activité** (Réglages) : connexions, échecs, créations, modifications de prix, annulations.
- Données isolées par compte, opérations de stock en transaction SQLite, contraintes `CHECK`/`UNIQUE`/clés étrangères.
- Android : sauvegarde ADB/cloud désactivée (`allowBackup=false`).

Limite connue : la base SQLite locale n'est pas chiffrée sur le disque. Étape suivante possible :
`sqflite_sqlcipher` avec une clé dérivée du mot de passe.

## Développement

```bash
flutter pub get
flutter test             # règles de calcul, sécurité, dépôt SQLite, migration v1 → v2
flutter run -d chrome    # aperçu Web (SQLite WebAssembly : web/sqlite3.wasm + web/sqflite_sw.js)
flutter build apk --release
```

`sqlite3` est volontairement contraint en 2.x : la 3.x télécharge une DLL native depuis GitHub
au build, et ce téléchargement échoue sur ce poste. Les fichiers Web ont été générés par
`dart run sqflite_common_ffi_web:setup`.

### Structure

```
lib/
  core/       règles de calcul (stock_math), périodes, formatage FCFA, hachage des mots de passe
  data/       schéma SQLite + migrations, modèles, ShopRepository (toutes les requêtes)
  services/   Session (connexion, blocage, verrouillage), rapports PDF
  ui/         écrans : auth, accueil, stock/produits, opérations, rapports, réglages
test/         tests unitaires et d'intégration (SQLite en mémoire)
```

Avant publication sur le Play Store : configurer une clé de signature (`android/key.properties`)
et un `applicationId` définitif (actuellement `com.example.shopnotbook`).
