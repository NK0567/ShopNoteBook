import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/sale.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';

/// Écran d'historique des ventes
/// Affiche la liste des produits vendus avec options de filtrage
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // Liste des ventes à afficher
  List<Sale> _sales = [];
  
  // Indicateur de chargement
  bool _isLoading = true;
  
  // Filtre actif (par jour, semaine, mois)
  String _filterType = 'all'; // all, day, week, month

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  /// Charge l'historique des ventes
  Future<void> _loadSales() async {
    if (AuthService.currentUser == null) return;

    try {
      // Récupère toutes les ventes
      final sales = await DatabaseService.getSalesByUserId(
        AuthService.currentUser!.id!,
      );

      setState(() {
        _sales = sales;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Filtre les ventes selon le type de filtre sélectionné
  List<Sale> _getFilteredSales() {
    final now = DateTime.now();
    
    return _sales.where((sale) {
      final saleDate = DateTime.parse(sale.saleDate);
      
      switch (_filterType) {
        case 'day':
          return saleDate.year == now.year &&
              saleDate.month == now.month &&
              saleDate.day == now.day;
        case 'week':
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          return saleDate.isAfter(weekStart) && saleDate.isBefore(now.add(const Duration(days: 1)));
        case 'month':
          return saleDate.year == now.year && saleDate.month == now.month;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredSales = _getFilteredSales();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique des ventes'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // Boutons de filtre
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterButton(
                    label: 'Tous',
                    isActive: _filterType == 'all',
                    onPressed: () => setState(() => _filterType = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _FilterButton(
                    label: 'Aujourd\'hui',
                    isActive: _filterType == 'day',
                    onPressed: () => setState(() => _filterType = 'day'),
                  ),
                  const SizedBox(width: 8),
                  _FilterButton(
                    label: 'Cette semaine',
                    isActive: _filterType == 'week',
                    onPressed: () => setState(() => _filterType = 'week'),
                  ),
                  const SizedBox(width: 8),
                  _FilterButton(
                    label: 'Ce mois',
                    isActive: _filterType == 'month',
                    onPressed: () => setState(() => _filterType = 'month'),
                  ),
                ],
              ),
            ),
          ),

          // Liste des ventes
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredSales.isEmpty
                    ? const Center(
                        child: Text('Aucune vente enregistrée'),
                      )
                    : ListView.builder(
                        itemCount: filteredSales.length,
                        itemBuilder: (context, index) {
                          final sale = filteredSales[index];
                          final date = DateTime.parse(sale.saleDate);

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.shopping_bag, color: Colors.blue),
                              title: Text(sale.productName),
                              subtitle: Text(
                                '${sale.quantity} ${sale.quantity > 1 ? "pcs" : "pc"} à ${sale.unitPrice.toStringAsFixed(2)} FCFA',
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${sale.totalAmount.toStringAsFixed(2)} FCFA',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  Text(
                                    DateFormat('dd/MM/yyyy').format(date),
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Bouton de filtre
class _FilterButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onPressed;

  const _FilterButton({
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? Colors.blue : Colors.grey.shade200,
        foregroundColor: isActive ? Colors.white : Colors.grey.shade700,
      ),
      child: Text(label),
    );
  }
}
