import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';

/// Écran de statistiques
/// Affiche les 15 produits les plus vendus du mois
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  // Liste des 15 produits les plus vendus
  List<Product> _topProducts = [];
  
  // Indicateur de chargement
  bool _isLoading = true;
  
  // Message d'erreur
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  /// Charge les statistiques des produits les plus vendus
  Future<void> _loadStatistics() async {
    if (AuthService.currentUser == null) return;

    try {
      // Récupère tous les produits
      final products = await DatabaseService.getProductsByUserId(
        AuthService.currentUser!.id!,
      );

      // Trie par quantité vendue décroissante
      products.sort((a, b) => b.totalSoldQuantity.compareTo(a.totalSoldQuantity));

      setState(() {
        // Prend les 15 premiers ou moins s'il y a moins de 15 produits
        _topProducts = products.take(15).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiques'),
        backgroundColor: Colors.blue,
      ),
      body: RefreshIndicator(
        onRefresh: _loadStatistics,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage.isNotEmpty
                ? Container(
                    padding: const EdgeInsets.all(12),
                    child: Text(_errorMessage),
                  )
                : _topProducts.isEmpty
                    ? const Center(
                        child: Text('Aucune donnée disponible'),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          // Titre
                          Text(
                            '📈 Top 15 des produits les plus vendus',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Liste numérotée des produits
                          ..._topProducts.asMap().entries.map((entry) {
                            final index = entry.key + 1;
                            final product = entry.value;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue,
                                  child: Text(
                                    '$index',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Text(
                                  product.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  'Bénéfice total: ${(product.potentialProfit * product.totalSoldQuantity).toStringAsFixed(2)} FCFA',
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade100,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${product.totalSoldQuantity} vendus',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      ),
      ),
    );
  }
}
