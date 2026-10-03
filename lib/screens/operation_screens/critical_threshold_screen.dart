import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';

/// Écran d'affichage des seuils critiques
/// Affiche les produits à réapprovisionner (orange) et 
/// les produits avec réapprov urgente (rouge)
class CriticalThresholdScreen extends StatefulWidget {
  const CriticalThresholdScreen({super.key});

  @override
  State<CriticalThresholdScreen> createState() => _CriticalThresholdScreenState();
}

class _CriticalThresholdScreenState extends State<CriticalThresholdScreen> {
  // Liste des produits avec alerte orange
  List<Product> _warningProducts = [];
  
  // Liste des produits avec alerte rouge
  List<Product> _criticalProducts = [];
  
  // Indicateur de chargement
  bool _isLoading = true;
  
  // Message d'erreur
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    // Charge les données au démarrage
    _loadData();
  }

  /// Charge les produits avec seuils critiques
  Future<void> _loadData() async {
    if (AuthService.currentUser == null) {
      setState(() {
        _errorMessage = 'Veuillez vous connecter';
        _isLoading = false;
      });
      return;
    }

    try {
      // Récupère les produits avec alerte orange (stock faible)
      final warning = await DatabaseService.getWarningStockProducts(
        AuthService.currentUser!.id!,
      );

      // Récupère les produits avec alerte rouge (stock critique)
      final critical = await DatabaseService.getCriticalStockProducts(
        AuthService.currentUser!.id!,
      );

      // Met à jour l'état
      setState(() {
        _warningProducts = warning;
        _criticalProducts = critical;
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
        title: const Text('Seuils critiques'),
        backgroundColor: Colors.blue,
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Container(
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
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Alerte rouge (URGENT)
                          Text(
                            '🔴 Alerte critique (Rouge) - URGENT',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),

                          const SizedBox(height: 12),

                          if (_criticalProducts.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Aucun produit en alerte critique',
                                style: TextStyle(color: Colors.green.shade700),
                              ),
                            )
                          else
                            ..._criticalProducts.map((product) {
                              return Card(
                                color: Colors.red.shade50,
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  leading: const Icon(Icons.error, color: Colors.red),
                                  title: Text(
                                    product.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    'Stock critique: ${product.quantity} ${product.unit}',
                                  ),
                                  trailing: ElevatedButton(
                                    onPressed: () {
                                      // Générer PDF (à implémenter)
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('PDF généré'),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    child: const Text('PDF'),
                                  ),
                                ),
                              );
                            }).toList(),

                          const SizedBox(height: 30),

                          // Alerte orange (À RÉAPPROVISIONNER)
                          Text(
                            '🟠 Alerte faible (Orange) - À réapprovisionner',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),

                          const SizedBox(height: 12),

                          if (_warningProducts.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Aucun produit à réapprovisionner',
                                style: TextStyle(color: Colors.green.shade700),
                              ),
                            )
                          else
                            ..._warningProducts.map((product) {
                              return Card(
                                color: Colors.orange.shade50,
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  leading: const Icon(Icons.warning, color: Colors.orange),
                                  title: Text(
                                    product.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    'Stock faible: ${product.quantity} ${product.unit}',
                                  ),
                                  trailing: ElevatedButton(
                                    onPressed: () {
                                      // Générer PDF
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('PDF généré'),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                    ),
                                    child: const Text('PDF'),
                                  ),
                                ),
                              );
                            }).toList(),
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}
