import 'package:flutter/material.dart';
import 'operation_screens/search_product_screen.dart';
import 'operation_screens/critical_threshold_screen.dart';
import 'operation_screens/history_screen.dart';
import 'operation_screens/statistics_screen.dart';
import 'operation_screens/profit_screen.dart';
import 'operation_screens/sale_screen.dart';
import 'operation_screens/purchase_screen.dart';

/// Écran Opération
/// Menu principal avec 7 fonctionnalités:
/// 1. Rechercher un produit
/// 2. Consulter le seuil critique
/// 3. Consulter l'historique
/// 4. Consulter les statistiques
/// 5. Consulter les bénéfices
/// 6. Effectuer une vente
/// 7. Effectuer un réapprovisionnement
class OperationScreen extends StatelessWidget {
  const OperationScreen({super.key});

  /// Navigue vers l'écran sélectionné au clic sur un bouton
  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Titre principal
              Text(
                '🔄 Opérations',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),

              // Sous-titre
              const SizedBox(height: 8),
              Text(
                'Que souhaitez-vous faire?',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey,
                ),
              ),

              const SizedBox(height: 30),

              // Bouton 1: Rechercher un produit
              _OperationButton(
                icon: Icons.search,
                title: '🔍 Rechercher un produit',
                subtitle: 'Afficher les détails d\'un produit',
                onPressed: () => _navigateTo(
                  context,
                  const SearchProductScreen(),
                ),
              ),

              const SizedBox(height: 15),

              // Bouton 2: Consulter le seuil critique
              _OperationButton(
                icon: Icons.warning,
                title: '⚠️ Consulter le seuil critique',
                subtitle: 'Voir les produits à réapprovisionner',
                onPressed: () => _navigateTo(
                  context,
                  const CriticalThresholdScreen(),
                ),
              ),

              const SizedBox(height: 15),

              // Bouton 3: Consulter l'historique
              _OperationButton(
                icon: Icons.history,
                title: '📜 Consulter l\'historique',
                subtitle: 'Voir l\'historique des ventes',
                onPressed: () => _navigateTo(
                  context,
                  const HistoryScreen(),
                ),
              ),

              const SizedBox(height: 15),

              // Bouton 4: Consulter les statistiques
              _OperationButton(
                icon: Icons.bar_chart,
                title: '📈 Statistiques',
                subtitle: 'Analyser les produits les plus vendus',
                onPressed: () => _navigateTo(
                  context,
                  const StatisticsScreen(),
                ),
              ),

              const SizedBox(height: 15),

              // Bouton 5: Consulter les bénéfices
              _OperationButton(
                icon: Icons.monetization_on,
                title: '💰 Bénéfices',
                subtitle: 'Connaître vos bénéfices par période',
                onPressed: () => _navigateTo(
                  context,
                  const ProfitScreen(),
                ),
              ),

              const SizedBox(height: 15),

              // Bouton 6: Effectuer une vente
              _OperationButton(
                icon: Icons.shopping_cart,
                title: '🛒 Effectuer une vente',
                subtitle: 'Enregistrer une nouvelle vente',
                onPressed: () => _navigateTo(
                  context,
                  const SaleScreen(),
                ),
              ),

              const SizedBox(height: 15),

              // Bouton 7: Effectuer un réapprovisionnement
              _OperationButton(
                icon: Icons.inventory,
                title: '📦 Effectuer un réapprovisionnement',
                subtitle: 'Enregistrer un nouvel achat de stock',
                onPressed: () => _navigateTo(
                  context,
                  const PurchaseScreen(),
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget personnalisé pour les boutons d'opération
class _OperationButton extends StatelessWidget {
  // Icône du bouton
  final IconData icon;
  
  // Titre du bouton
  final String title;
  
  // Sous-titre descriptif
  final String subtitle;
  
  // Fonction appelée au clic
  final VoidCallback onPressed;

  const _OperationButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      // Crée un effet d'encre au clic
      child: InkWell(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            // Arrière-plan blanc avec bordure
            color: Colors.white,
            border: Border.all(color: Colors.blue.shade200),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icône du bouton
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: Colors.blue,
                ),
              ),

              const SizedBox(width: 16),

              // Titre et sous-titre
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Titre principal
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),

                    // Sous-titre
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              // Flèche indiquant la navigation
              Icon(
                Icons.arrow_forward,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
