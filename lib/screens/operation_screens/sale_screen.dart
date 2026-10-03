import 'package:flutter/material.dart';
import '../../models/sale.dart';
import '../../models/product.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';

/// Écran d'enregistrement de vente
/// Permet d'enregistrer une nouvelle vente avec validation obligatoire
class SaleScreen extends StatefulWidget {
  const SaleScreen({super.key});

  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  // Liste des produits disponibles
  List<Product> _products = [];
  
  // Contrôleur pour le nom du produit
  final _productController = TextEditingController();
  
  // Contrôleur pour la quantité vendue
  final _quantityController = TextEditingController();
  
  // Contrôleur pour le prix de vente unitaire
  final _priceController = TextEditingController();
  
  // Clé du formulaire
  final _formKey = GlobalKey<FormState>();
  
  // Produit sélectionné
  Product? _selectedProduct;
  
  // Indicateur de chargement
  bool _isLoading = false;
  
  // Message de succès/erreur
  String _message = '';

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _productController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  /// Charge la liste des produits disponibles
  Future<void> _loadProducts() async {
    if (AuthService.currentUser == null) return;

    try {
      final products = await DatabaseService.getProductsByUserId(
        AuthService.currentUser!.id!,
      );

      setState(() {
        _products = products;
      });
    } catch (e) {
      setState(() {
        _message = 'Erreur: $e';
      });
    }
  }

  /// Enregistre une nouvelle vente
  Future<void> _recordSale() async {
    // Valide le formulaire
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Si l'utilisateur a tapé un nom mais n'a pas choisi dans la liste,
    // essaie de trouver un produit correspondant par nom exact (insensible à la casse)
    if (_selectedProduct == null && _productController.text.trim().isNotEmpty) {
      try {
        _selectedProduct = _products.firstWhere((p) => p.name.toLowerCase() == _productController.text.trim().toLowerCase());
      } catch (e) {
        // Aucun produit correspondant trouvé
      }
    }

    // Valide que le produit est sélectionné
    if (_selectedProduct == null) {
      setState(() {
        _message = 'Veuillez sélectionner un produit';
      });
      return;
    }

    // Récupère les valeurs
    final quantity = int.tryParse(_quantityController.text) ?? 0;
    final price = double.tryParse(_priceController.text) ?? 0.0;

    if (quantity <= 0 || price <= 0) {
      setState(() {
        _message = 'Quantité et prix doivent être supérieurs à 0';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = '';
    });

    try {
      // Calcule le montant total et le bénéfice
      final totalAmount = quantity * price;
      final costTotal = quantity * _selectedProduct!.costPrice;
      final profit = totalAmount - costTotal;

      // Crée l'enregistrement de vente
      final sale = Sale(
        userId: AuthService.currentUser!.id!,
        productId: _selectedProduct!.id!,
        productName: _selectedProduct!.name,
        quantity: quantity,
        unitPrice: price,
        totalAmount: totalAmount,
        profit: profit,
        saleDate: DateTime.now().toIso8601String(),
      );

      // Enregistre la vente
      await DatabaseService.createSale(sale);

      // Met à jour le stock du produit
      final updatedProduct = _selectedProduct!.copyWith(
        quantity: _selectedProduct!.quantity - quantity,
        totalSoldQuantity: _selectedProduct!.totalSoldQuantity + quantity,
        updatedAt: DateTime.now().toIso8601String(),
      );

      await DatabaseService.updateProduct(updatedProduct);

      // Affiche le message de succès
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Vente enregistrée avec succès! Bénéfice: ${profit.toStringAsFixed(2)} FCFA'),
            backgroundColor: Colors.green,
          ),
        );

        // Réinitialise le formulaire
        _productController.clear();
        _quantityController.clear();
        _priceController.clear();
        setState(() {
          _selectedProduct = null;
          _message = '';
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Erreur lors de l\'enregistrement: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Effectuer une vente'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Titre
                Text(
                  '🛒 Nouvelle vente',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),

                const SizedBox(height: 20),

                // Saisie/Recherche du produit (autocomplete)
                Autocomplete<Product>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text == '') {
                      return const Iterable<Product>.empty();
                    }
                    return _products.where((Product option) {
                      return option.name.toLowerCase().contains(textEditingValue.text.toLowerCase());
                    });
                  },
                  displayStringForOption: (Product option) => option.name,
                  fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                    // Initialize the internal controller with current value
                    textEditingController.text = _productController.text;
                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: 'Nom du produit',
                        prefixIcon: const Icon(Icons.inventory_2),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      validator: (value) {
                        if (_selectedProduct == null) {
                          return 'Veuillez sélectionner un produit';
                        }
                        return null;
                      },
                    );
                  },
                  onSelected: (Product selection) {
                    setState(() {
                      _selectedProduct = selection;
                      _productController.text = selection.name;
                      _priceController.text = selection.sellingPrice.toString();
                    });
                  },
                ),

                const SizedBox(height: 15),

                // Quantité vendue
                TextFormField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Quantité vendue',
                    prefixIcon: const Icon(Icons.shopping_bag),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Veuillez entrer la quantité';
                    }
                    final qty = int.tryParse(value);
                    if (qty == null || qty <= 0) {
                      return 'Quantité doit être un nombre positif';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 15),

                // Prix de vente unitaire
                TextFormField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Prix de vente unitaire (FCFA)',
                    prefixIcon: const Icon(Icons.attach_money),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Veuillez entrer le prix';
                    }
                    final price = double.tryParse(value);
                    if (price == null || price <= 0) {
                      return 'Prix doit être un nombre positif';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // Affichage du message
                if (_message.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _message,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),

                const SizedBox(height: 20),

                // Bouton d'enregistrement
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _recordSale,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      disabledBackgroundColor: Colors.grey,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                        : const Text(
                          'Enregistrer la vente',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
