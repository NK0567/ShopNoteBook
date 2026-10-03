import 'package:flutter/material.dart';
import '../../models/purchase.dart';
import '../../models/product.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';

/// Écran d'enregistrement de réapprovisionnement
/// Permet d'enregistrer un nouvel achat de stock
class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  // Liste des produits disponibles
  List<Product> _products = [];
  
  // Contrôleur pour la sélection du produit
  final _productController = TextEditingController();
  
  // Contrôleur pour le prix d'achat
  final _costPriceController = TextEditingController();
  
  // Contrôleur pour la quantité achetée
  final _quantityController = TextEditingController();
  
  // Contrôleur pour le nom du fournisseur
  final _supplierController = TextEditingController();
  
  // Contrôleur pour le numéro de facture
  final _invoiceController = TextEditingController();
  
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
    _costPriceController.dispose();
    _quantityController.dispose();
    _supplierController.dispose();
    _invoiceController.dispose();
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

  /// Enregistre un nouvel achat/réapprovisionnement
  Future<void> _recordPurchase() async {
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
    final costPrice = double.tryParse(_costPriceController.text) ?? 0.0;
    final quantity = int.tryParse(_quantityController.text) ?? 0;
    final supplier = _supplierController.text.trim();

    if (costPrice <= 0 || quantity <= 0 || supplier.isEmpty) {
      setState(() {
        _message = 'Tous les champs requis doivent être remplis avec des valeurs valides';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = '';
    });

    try {
      // Calcule le coût total
      final totalCost = costPrice * quantity;

      // Crée l'enregistrement d'achat
      final purchase = Purchase(
        userId: AuthService.currentUser!.id!,
        productId: _selectedProduct!.id!,
        productName: _selectedProduct!.name,
        quantity: quantity,
        unitCostPrice: costPrice,
        totalCost: totalCost,
        supplier: supplier,
        invoiceNumber: _invoiceController.text.trim().isEmpty
            ? null
            : _invoiceController.text.trim(),
        purchaseDate: DateTime.now().toIso8601String(),
      );

      // Enregistre l'achat en base de données
      await DatabaseService.createPurchase(purchase);

      // Met à jour le stock du produit
      final updatedProduct = _selectedProduct!.copyWith(
        quantity: _selectedProduct!.quantity + quantity,
        updatedAt: DateTime.now().toIso8601String(),
      );

      await DatabaseService.updateProduct(updatedProduct);

      // Affiche le message de succès
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Réapprovisionnement enregistré! Coût: ${totalCost.toStringAsFixed(2)} FCFA'),
            backgroundColor: Colors.green,
          ),
        );

        // Réinitialise le formulaire
        _productController.clear();
        _costPriceController.clear();
        _quantityController.clear();
        _supplierController.clear();
        _invoiceController.clear();
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
        title: const Text('Effectuer un réapprovisionnement'),
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
                  '📦 Nouvel achat de stock',
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
                      _costPriceController.text = selection.costPrice.toString();
                    });
                  },
                ),

                const SizedBox(height: 15),

                // Prix d'achat unitaire
                TextFormField(
                  controller: _costPriceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Prix d\'achat unitaire (FCFA)',
                    prefixIcon: const Icon(Icons.attach_money),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Veuillez entrer le prix d\'achat';
                    }
                    final price = double.tryParse(value);
                    if (price == null || price <= 0) {
                      return 'Prix doit être un nombre positif';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 15),

                // Quantité achetée
                TextFormField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Quantité achetée',
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

                // Fournisseur (obligatoire)
                TextFormField(
                  controller: _supplierController,
                  decoration: InputDecoration(
                    labelText: 'Fournisseur',
                    prefixIcon: const Icon(Icons.business),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Veuillez entrer le nom du fournisseur';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 15),

                // Numéro de facture (optionnel)
                TextFormField(
                  controller: _invoiceController,
                  decoration: InputDecoration(
                    labelText: 'Numéro de facture (optionnel)',
                    prefixIcon: const Icon(Icons.receipt),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
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
                    onPressed: _isLoading ? null : _recordPurchase,
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
                          'Enregistrer l\'achat',
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
