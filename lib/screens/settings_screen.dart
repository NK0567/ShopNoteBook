import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/user.dart';

/// Écran des paramètres/réglages
/// Permet à l'utilisateur de configurer les seuils d'alerte
/// et les couleurs personnalisées de l'application
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Contrôleur pour le seuil critique
  late TextEditingController _criticalThresholdController;
  
  // Contrôleur pour le seuil d'alerte faible
  late TextEditingController _warningThresholdController;
  
  // Contrôleur pour le seuil de la boutique
  late TextEditingController _businessNameController;
  
  // Couleur sélectionnée pour l'alerte orange
  late Color _warningColor;
  
  // Couleur sélectionnée pour l'alerte rouge
  late Color _criticalColor;
  
  // Indicateur de chargement pendant la sauvegarde
  bool _isSaving = false;
  
  // Message de succès/erreur
  String _message = '';

  @override
  void initState() {
    super.initState();
    // Initialise les contrôleurs avec les valeurs actuelles de l'utilisateur
    final user = AuthService.currentUser;
    
    _criticalThresholdController = TextEditingController(
      text: user?.criticalStockThreshold.toString() ?? '5',
    );
    
    _warningThresholdController = TextEditingController(
      text: user?.warningStockThreshold.toString() ?? '10',
    );
    
    _businessNameController = TextEditingController(
      text: user?.businessName ?? '',
    );

    // Initialise les couleurs à partir des paramètres utilisateur
    _warningColor = _parseColor(user?.warningColor ?? '#FF9800');
    _criticalColor = _parseColor(user?.criticalColor ?? '#F44336');
  }

  @override
  void dispose() {
    // Libère les ressources des contrôleurs
    _criticalThresholdController.dispose();
    _warningThresholdController.dispose();
    _businessNameController.dispose();
    super.dispose();
  }

  /// Convertit une chaîne de couleur hexadécimale en objet Color
  Color _parseColor(String hexColor) {
    // Supprime le # s'il existe
    final hex = hexColor.replaceFirst('#', '');
    
    // Convertit la valeur hexadécimale en entier
    return Color(int.parse(hex, radix: 16) | 0xFF000000);
  }

  /// Convertit un objet Color en chaîne hexadécimale
  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  /// Affiche un sélecteur de couleur
  void _showColorPicker(bool isWarning) async {
    // Couleur actuelle sélectionnée
    Color selectedColor = isWarning ? _warningColor : _criticalColor;

    // Utilise un simple dialog avec les 6 couleurs recommandées
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isWarning ? 'Couleur alerte orange (faible stock)' : 'Couleur alerte rouge (stock critique)',
        ),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 10,
            children: [
              // Palette de couleurs prédéfinies
              _ColorOption(
                color: Colors.orange,
                label: 'Orange',
                onTap: () {
                  setState(() {
                    if (isWarning) {
                      _warningColor = Colors.orange;
                    } else {
                      _criticalColor = Colors.orange;
                    }
                  });
                  Navigator.pop(context);
                },
              ),
              _ColorOption(
                color: Colors.red,
                label: 'Rouge',
                onTap: () {
                  setState(() {
                    if (isWarning) {
                      _warningColor = Colors.red;
                    } else {
                      _criticalColor = Colors.red;
                    }
                  });
                  Navigator.pop(context);
                },
              ),
              _ColorOption(
                color: Colors.amber,
                label: 'Ambre',
                onTap: () {
                  setState(() {
                    if (isWarning) {
                      _warningColor = Colors.amber;
                    } else {
                      _criticalColor = Colors.amber;
                    }
                  });
                  Navigator.pop(context);
                },
              ),
              _ColorOption(
                color: Colors.yellow,
                label: 'Jaune',
                onTap: () {
                  setState(() {
                    if (isWarning) {
                      _warningColor = Colors.yellow;
                    } else {
                      _criticalColor = Colors.yellow;
                    }
                  });
                  Navigator.pop(context);
                },
              ),
              _ColorOption(
                color: Colors.deepOrange,
                label: 'Orange foncé',
                onTap: () {
                  setState(() {
                    if (isWarning) {
                      _warningColor = Colors.deepOrange;
                    } else {
                      _criticalColor = Colors.deepOrange;
                    }
                  });
                  Navigator.pop(context);
                },
              ),
              _ColorOption(
                color: Colors.redAccent,
                label: 'Rouge accent',
                onTap: () {
                  setState(() {
                    if (isWarning) {
                      _warningColor = Colors.redAccent;
                    } else {
                      _criticalColor = Colors.redAccent;
                    }
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }

  /// Sauvegarde les modifications des paramètres
  Future<void> _saveSettings() async {
    // Valide les saisies
    final criticalThreshold = int.tryParse(_criticalThresholdController.text);
    final warningThreshold = int.tryParse(_warningThresholdController.text);
    final businessName = _businessNameController.text.trim();

    if (criticalThreshold == null || warningThreshold == null) {
      setState(() {
        _message = 'Veuillez entrer des nombres valides pour les seuils';
      });
      return;
    }

    if (businessName.isEmpty) {
      setState(() {
        _message = 'Veuillez entrer le nom de la boutique';
      });
      return;
    }

    if (criticalThreshold >= warningThreshold) {
      setState(() {
        _message = 'Le seuil critique doit être inférieur au seuil d\'alerte';
      });
      return;
    }

    // Active l'indicateur de chargement
    setState(() {
      _isSaving = true;
      _message = '';
    });

    try {
      // Crée un nouvel utilisateur avec les modifications
      final updatedUser = User(
        id: AuthService.currentUser!.id,
        name: AuthService.currentUser!.name,
        email: AuthService.currentUser!.email,
        passwordHash: AuthService.currentUser!.passwordHash,
        businessName: businessName,
        criticalStockThreshold: criticalThreshold,
        warningStockThreshold: warningThreshold,
        warningColor: _colorToHex(_warningColor),
        criticalColor: _colorToHex(_criticalColor),
        createdAt: AuthService.currentUser!.createdAt,
      );

      // Sauvegarde en base de données
      await DatabaseService.updateUser(updatedUser);

      // Met à jour l'utilisateur local via la méthode publique
      AuthService.updateCurrentUser(updatedUser);

      // Affiche un message de succès
      setState(() {
        _message = 'Paramètres sauvegardés avec succès!';
      });

      // Affiche une notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paramètres mis à jour'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Affiche un message d'erreur
      setState(() {
        _message = 'Erreur lors de la sauvegarde: $e';
      });
    } finally {
      // Désactive l'indicateur de chargement
      setState(() {
        _isSaving = false;
      });
    }
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
                '⚙️ Paramètres',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),

              const SizedBox(height: 30),

              // Section: Informations de la boutique
              Text(
                'Informations de la boutique',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 15),

              // Champ nom de la boutique
              TextFormField(
                controller: _businessNameController,
                decoration: InputDecoration(
                  labelText: 'Nom de la boutique',
                  prefixIcon: const Icon(Icons.store),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.grey),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // Section: Seuils d'alerte
              Text(
                'Seuils d\'alerte de stock',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 15),

              // Champ seuil d'alerte faible (orange)
              TextFormField(
                controller: _warningThresholdController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Seuil alerte faible (Orange)',
                  helperText: 'Quantité minimale pour déclencher l\'alerte orange',
                  prefixIcon: const Icon(Icons.warning),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.orange),
                  ),
                ),
              ),

              const SizedBox(height: 15),

              // Champ seuil d'alerte critique (rouge)
              TextFormField(
                controller: _criticalThresholdController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Seuil alerte critique (Rouge)',
                  helperText: 'Quantité minimale pour déclencher l\'alerte rouge',
                  prefixIcon: const Icon(Icons.error),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // Section: Personnalisation des couleurs
              Text(
                'Personnalisation des couleurs',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 15),

              // Sélecteur couleur alerte faible
              _ColorSelector(
                label: 'Couleur alerte faible (Orange)',
                color: _warningColor,
                onTap: () => _showColorPicker(true),
              ),

              const SizedBox(height: 15),

              // Sélecteur couleur alerte critique
              _ColorSelector(
                label: 'Couleur alerte critique (Rouge)',
                color: _criticalColor,
                onTap: () => _showColorPicker(false),
              ),

              const SizedBox(height: 30),

              // Message de succès/erreur
              if (_message.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _message.contains('succès') || _message.contains('Paramètres')
                        ? Colors.green.shade100
                        : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _message,
                    style: TextStyle(
                      color: _message.contains('succès') || _message.contains('Paramètres')
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              // Bouton de sauvegarde
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    disabledBackgroundColor: Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                      : const Text(
                        'Sauvegarder les paramètres',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget pour afficher un sélecteur de couleur
class _ColorSelector extends StatelessWidget {
  // Libellé du sélecteur
  final String label;
  
  // Couleur actuellement sélectionnée
  final Color color;
  
  // Fonction appelée au clic
  final VoidCallback onTap;

  const _ColorSelector({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // Aperçu de la couleur
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey),
                ),
              ),

              const SizedBox(width: 16),

              // Libellé
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              // Icône de sélection
              const Icon(Icons.arrow_forward),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget pour une option de couleur dans le sélecteur
class _ColorOption extends StatelessWidget {
  // Couleur de l'option
  final Color color;
  
  // Libellé de la couleur
  final String label;
  
  // Fonction appelée au clic
  final VoidCallback onTap;

  const _ColorOption({
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade400),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
