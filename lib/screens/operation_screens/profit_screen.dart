import 'package:flutter/material.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';

/// Écran d'affichage des bénéfices
/// Calcule et affiche les bénéfices pour une période donnée
class ProfitScreen extends StatefulWidget {
  const ProfitScreen({super.key});

  @override
  State<ProfitScreen> createState() => _ProfitScreenState();
}

class _ProfitScreenState extends State<ProfitScreen> {
  // Période sélectionnée: 'day', 'week', ou 'month'
  String _selectedPeriod = 'day';
  
  // Bénéfice calculé
  double _profit = 0.0;
  
  // Indicateur de chargement
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Charge les données au démarrage
    _calculateProfit();
  }

  /// Calcule le bénéfice pour la période sélectionnée
  Future<void> _calculateProfit() async {
    if (AuthService.currentUser == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final now = DateTime.now();
      String startDate;
      String endDate = now.toIso8601String();

      // Détermine la date de début selon la période
      switch (_selectedPeriod) {
        case 'day':
          // Aujourd'hui
          final startOfDay = DateTime(now.year, now.month, now.day);
          startDate = startOfDay.toIso8601String();
          break;

        case 'week':
          // Cette semaine
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          startDate = DateTime(weekStart.year, weekStart.month, weekStart.day).toIso8601String();
          break;

        case 'month':
          // Ce mois
          startDate = DateTime(now.year, now.month, 1).toIso8601String();
          break;

        default:
          startDate = now.toIso8601String();
      }

      // Récupère le bénéfice total pour la période
      final profit = await DatabaseService.getTotalProfitForPeriod(
        AuthService.currentUser!.id!,
        startDate,
        endDate,
      );

      setState(() {
        _profit = profit;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bénéfices'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Titre
              Text(
                '💰 Bénéfices engendré',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),

              const SizedBox(height: 10),

              // Sous-titre
              Text(
                'Voulez-vous connaître vos bénéfices:',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey,
                ),
              ),

              const SizedBox(height: 30),

              // Boutons de sélection de période
              Column(
                children: [
                  // Bouton jour
                  _PeriodButton(
                    icon: Icons.today,
                    title: 'Du jour',
                    subtitle: 'Bénéfices d\'aujourd\'hui',
                    isSelected: _selectedPeriod == 'day',
                    onPressed: () {
                      setState(() => _selectedPeriod = 'day');
                      _calculateProfit();
                    },
                  ),

                  const SizedBox(height: 12),

                  // Bouton semaine
                  _PeriodButton(
                    icon: Icons.calendar_view_week,
                    title: 'De la semaine',
                    subtitle: 'Bénéfices de cette semaine',
                    isSelected: _selectedPeriod == 'week',
                    onPressed: () {
                      setState(() => _selectedPeriod = 'week');
                      _calculateProfit();
                    },
                  ),

                  const SizedBox(height: 12),

                  // Bouton mois
                  _PeriodButton(
                    icon: Icons.calendar_today,
                    title: 'Du mois',
                    subtitle: 'Bénéfices de ce mois',
                    isSelected: _selectedPeriod == 'month',
                    onPressed: () {
                      setState(() => _selectedPeriod = 'month');
                      _calculateProfit();
                    },
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // Affichage du résultat
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade400, Colors.green.shade700],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Texte "Votre bénéfice"
                    Text(
                      'Votre bénéfice',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Affiche le bénéfice calculé ou un indicateur de chargement
                    _isLoading
                        ? const SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            '${_profit.toStringAsFixed(2)} FCFA',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Informations supplémentaires
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Période sélectionnée',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        _getPeriodLabel(),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Retourne le libellé de la période sélectionnée
  String _getPeriodLabel() {
    final now = DateTime.now();
    
    switch (_selectedPeriod) {
      case 'day':
        return 'Aujourd\'hui (${now.day}/${now.month}/${now.year})';
      case 'week':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        return 'Semaine du ${weekStart.day}/${weekStart.month}/${weekStart.year}';
      case 'month':
        return 'Mois de ${_getMonthName(now.month)} ${now.year}';
      default:
        return '';
    }
  }

  /// Retourne le nom du mois en français
  String _getMonthName(int month) {
    const months = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
    ];
    return months[month - 1];
  }
}

/// Bouton pour sélectionner une période
class _PeriodButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onPressed;

  const _PeriodButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      child: InkWell(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.shade100 : Colors.white,
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Icône
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? Colors.white : Colors.grey,
                  size: 28,
                ),
              ),

              const SizedBox(width: 16),

              // Titre et sous-titre
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.blue : Colors.black,
                      ),
                    ),
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

              // Checkmark si sélectionné
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: Colors.blue,
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
