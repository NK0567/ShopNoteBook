import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

/// Écran d'accueil (Home)
/// Affiche les statistiques principales, les produits les plus demandés
/// et les alertes de stock faible/critique
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Liste des 3 produits les plus vendus
  List<Product> _topProducts = [];
  
  // Liste des produits avec stock faible ou critique
  List<Product> _lowStockProducts = [];
  
  // Indicateur de chargement des données
  bool _isLoading = true;
  
  // Message d'erreur si le chargement échoue
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    // Charge les données au démarrage de l'écran
    _loadData();
  }

  /// Charge toutes les données nécessaires pour l'affichage
  Future<void> _loadData() async {
    // Vérifie qu'un utilisateur est connecté
    if (AuthService.currentUser == null) {
      setState(() {
        _errorMessage = 'Veuillez vous connecter';
        _isLoading = false;
      });
      return;
    }

    try {
      // Récupère les 3 produits les plus vendus
      final topProducts = await DatabaseService.getTopProducts(
        AuthService.currentUser!.id!,
      );

      // Récupère les produits avec stock faible ou critique
      final lowStock = await DatabaseService.getLowStockProducts(
        AuthService.currentUser!.id!,
      );

      // Met à jour l'état avec les données chargées
      setState(() {
        _topProducts = topProducts;
        _lowStockProducts = lowStock;
        _isLoading = false;
      });
    } catch (e) {
      // Affiche un message d'erreur si le chargement échoue
      setState(() {
        _errorMessage = 'Erreur lors du chargement des données: $e';
        _isLoading = false;
      });
    }
  }

  /// Obtient la couleur du statut de stock basée sur le produit
  Color _getStockStatusColor(Product product) {
    final status = product.getStockStatus();
    
    if (status == 'critical') {
      // Rouge pour stock critique
      return Colors.red;
    } else if (status == 'warning') {
      // Orange pour stock faible
      return Colors.orange;
    }
    // Vert pour stock suffisant
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      // Permet de rafraîchir les données en tirant vers le bas
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Affiche le message de bienvenue
              Text(
                'Bienvenue, ${AuthService.currentUser?.name ?? "Utilisateur"}!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              // Affiche le nom de la boutique
              Text(
                'Boutique: ${AuthService.currentUser?.businessName ?? "N/A"}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
              ),

              const SizedBox(height: 20),

              // Affiche un indicateur de chargement si les données se chargent
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(),
                )
              // Affiche le message d'erreur s'il existe
              else if (_errorMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                )
              // Affiche le contenu principal
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section: 3 produits les plus demandés
                    Text(
                      '📊 Produits les plus demandés',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Affiche la liste des 3 produits les plus vendus
                    if (_topProducts.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Aucun produit vendu pour le moment'),
                      )
                    else
                      ..._topProducts.map((product) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            // Icône du produit
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue,
                              child: Text(
                                '${product.totalSoldQuantity}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            // Nom du produit
                            title: Text(
                              product.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            // Prix et bénéfice
                            subtitle: Text(
                              'Vendu: ${product.totalSoldQuantity} | Bénéfice: ${product.potentialProfit.toStringAsFixed(2)} FCFA',
                            ),
                            // Affiche la quantité en stock avec couleur
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: _getStockStatusColor(product),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Stock: ${product.quantity}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),

                    const SizedBox(height: 30),

                    // Section: Produits à faible stock
                    Text(
                      '📦 Alertes Stock (À Réapprovisionner)',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Affiche les produits avec stock faible ou critique
                    if (_lowStockProducts.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Aucun produit en alerte - Stock suffisant!',
                          style: TextStyle(color: Colors.green),
                        ),
                      )
                    else
                      ..._lowStockProducts.map((product) {
                        // Détermine la couleur selon le statut du stock
                        final status = product.getStockStatus();
                        final color = status == 'critical' ? Colors.red : Colors.orange;
                        final alertText = status == 'critical'
                            ? 'ALERTE CRITIQUE (ROUGE)'
                            : 'À RÉAPPROVISIONNER (ORANGE)';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          color: color.withOpacity(0.1),
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: color, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListTile(
                            // Icône d'alerte
                            leading: Icon(
                              Icons.warning,
                              color: color,
                              size: 30,
                            ),
                            // Nom du produit
                            title: Text(
                              product.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                            // Description de l'alerte
                            subtitle: Text(alertText),
                            // Stock actuel
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Stock: ${product.quantity}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
