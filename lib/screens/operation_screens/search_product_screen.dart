import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';

/// Écran de recherche de produit par nom
/// Affiche les détails: nom, prix d'achat, prix de vente,
/// gain potentiel et quantité en stock avec code couleur
class SearchProductScreen extends StatefulWidget {
  const SearchProductScreen({super.key});

  @override
  State<SearchProductScreen> createState() => _SearchProductScreenState();
}

class _SearchProductScreenState extends State<SearchProductScreen> {
  // Contrôleur pour la barre de recherche
  final _searchController = TextEditingController();
  
  // Produit trouvé après la recherche
  Product? _foundProduct;
  
  // Indicateur de chargement
  bool _isSearching = false;
  
  // Message d'erreur/information
  String _message = '';

  @override
  void dispose() {
    // Libère les ressources du contrôleur
    _searchController.dispose();
    super.dispose();
  }

  /// Effectue la recherche du produit par son nom
  Future<void> _searchProduct() async {
    // Valide la saisie
    if (_searchController.text.trim().isEmpty) {
      setState(() {
        _message = 'Veuillez entrer le nom du produit';
        _foundProduct = null;
      });
      return;
    }

    // Active l'indicateur de chargement
    setState(() {
      _isSearching = true;
      _message = '';
      _foundProduct = null;
    });

    try {
      // Recherche le produit en base de données
      final product = await DatabaseService.getProductByName(
        AuthService.currentUser!.id!,
        _searchController.text.trim(),
      );

      // Affiche le résultat
      setState(() {
        _foundProduct = product;
        _message = product == null ? 'Produit non trouvé' : '';
      });
    } catch (e) {
      // Affiche l'erreur
      setState(() {
        _message = 'Erreur lors de la recherche: $e';
      });
    } finally {
      // Désactive l'indicateur de chargement
      setState(() {
        _isSearching = false;
      });
    }
  }

  /// Obtient la couleur du statut de stock
  Color _getStockStatusColor(Product product) {
    final status = product.getStockStatus();
    
    if (status == 'critical') {
      return Colors.red;
    } else if (status == 'warning') {
      return Colors.orange;
    }
    return Colors.green;
  }

  /// Obtient le libellé du statut de stock
  String _getStockStatusLabel(Product product) {
    final status = product.getStockStatus();
    
    if (status == 'critical') {
      return 'CRITIQUE (ROUGE)';
    } else if (status == 'warning') {
      return 'FAIBLE (ORANGE)';
    }
    return 'SUFFISANT (VERT)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rechercher un produit'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Instructions
              Text(
                '🔍 Rechercher par nom de produit',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 15),

              // Champ de recherche
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Nom du produit',
                  hintText: 'Ex: Riz blanc 25kg',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _foundProduct = null;
                            _message = '';
                          });
                        },
                      )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.grey),
                  ),
                ),
                onChanged: (_) {
                  setState(() {});
                },
              ),

              const SizedBox(height: 15),

              // Bouton de recherche
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isSearching ? null : _searchProduct,
                  icon: _isSearching
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 2,
                        ),
                      )
                      : const Icon(Icons.search),
                  label: const Text('Rechercher'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    disabledBackgroundColor: Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // Affiche le message d'information/erreur
              if (_message.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _message,
                    style: TextStyle(color: Colors.orange.shade700),
                  ),
                ),

              // Affiche les détails du produit trouvé
              if (_foundProduct != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Titre du résultat
                    Text(
                      'Détails du produit',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),

                    const SizedBox(height: 15),

                    // Card avec les détails
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Nom du produit
                            _DetailRow(
                              label: 'Nom du produit',
                              value: _foundProduct!.name,
                              icon: Icons.inventory_2,
                              color: Colors.blue,
                            ),

                            const Divider(height: 20),

                            // Description
                            _DetailRow(
                              label: 'Description',
                              value: _foundProduct!.description.isEmpty
                                  ? '-'
                                  : _foundProduct!.description,
                              icon: Icons.description,
                              color: Colors.green,
                            ),

                            const Divider(height: 20),

                            // Prix d'achat
                            _DetailRow(
                              label: 'Prix d\'achat (fixe)',
                              value: '${_foundProduct!.costPrice.toStringAsFixed(2)} FCFA',
                              icon: Icons.shopping_bag,
                              color: Colors.orange,
                            ),

                            const Divider(height: 20),

                            // Prix de vente
                            _DetailRow(
                              label: 'Prix de vente',
                              value: '${_foundProduct!.sellingPrice.toStringAsFixed(2)} FCFA',
                              icon: Icons.local_offer,
                              color: Colors.purple,
                            ),

                            const Divider(height: 20),

                            // Gain potentiel
                            _DetailRow(
                              label: 'Gain potentiel (bénéfice)',
                              value: '${_foundProduct!.potentialProfit.toStringAsFixed(2)} FCFA',
                              icon: Icons.trending_up,
                              color: Colors.green,
                            ),

                            const Divider(height: 20),

                            // Marge bénéficiaire
                            _DetailRow(
                              label: 'Marge bénéficiaire',
                              value: '${_foundProduct!.profitMargin.toStringAsFixed(2)}%',
                              icon: Icons.percent,
                              color: Colors.teal,
                            ),

                            const Divider(height: 20),

                            // Quantité en stock avec code couleur
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _getStockStatusColor(_foundProduct!).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _getStockStatusColor(_foundProduct!),
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.storage,
                                    color: _getStockStatusColor(_foundProduct!),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Quantité en stock',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          '${_foundProduct!.quantity} ${_foundProduct!.unit}',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: _getStockStatusColor(_foundProduct!),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getStockStatusColor(_foundProduct!),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _getStockStatusLabel(_foundProduct!),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 15),

                            // Catégorie et unité
                            Row(
                              children: [
                                Expanded(
                                  child: _DetailRow(
                                    label: 'Catégorie',
                                    value: _foundProduct!.category,
                                    icon: Icons.category,
                                    color: Colors.cyan,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _DetailRow(
                                    label: 'Unité',
                                    value: _foundProduct!.unit,
                                    icon: Icons.straighten,
                                    color: Colors.indigo,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget pour afficher une ligne de détail avec icône
class _DetailRow extends StatelessWidget {
  // Libellé du détail
  final String label;
  
  // Valeur du détail
  final String value;
  
  // Icône du détail
  final IconData icon;
  
  // Couleur de l'icône
  final Color color;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Icône
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        
        // Libellé et valeur
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Libellé
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              // Valeur
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
