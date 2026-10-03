import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'operation_screen.dart';
import 'settings_screen.dart';
import 'login_screen.dart';

/// Écran principal de l'application ShopBook
/// Gère la navigation entre les trois onglets: Home, Opération, Réglage
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  // Index de l'onglet actuellement affiché
  int _currentTabIndex = 0;

  // Liste des écrans pour chaque onglet
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    // Initialise les écrans une seule fois
    _screens = [
      const HomeScreen(), // Onglet 0: Home
      const OperationScreen(), // Onglet 1: Opération
      const SettingsScreen(), // Onglet 2: Réglage
    ];
  }

  /// Traite la déconnexion de l'utilisateur
  void _handleLogout() {
    // Affiche une boîte de dialogue de confirmation
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Êtes-vous sûr de vouloir vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              // Déconnecte l'utilisateur
              AuthService.logout();
              
              // Navigue vers l'écran de connexion
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
            child: const Text('Déconnecter', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Barre d'en-tête avec le titre et bouton de déconnexion
      appBar: AppBar(
        title: const Text('ShopBook - Carnet du Boutiquier'),
        backgroundColor: Colors.blue,
        elevation: 2,
        actions: [
          // Bouton de déconnexion dans la barre d'en-tête
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
            tooltip: 'Déconnecter',
          ),
        ],
      ),

      // Corps de l'application affichant l'écran sélectionné
      body: _screens[_currentTabIndex],

      // Barre de navigation inférieure avec trois onglets
      bottomNavigationBar: BottomNavigationBar(
        // Index de l'onglet actuellement sélectionné
        currentIndex: _currentTabIndex,
        
        // Nombre d'éléments dans la barre de navigation
        items: const [
          // Onglet 1: Home (Accueil)
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Accueil',
          ),
          
          // Onglet 2: Opération
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart),
            label: 'Opération',
          ),
          
          // Onglet 3: Réglage
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Réglage',
          ),
        ],
        
        // Couleur de l'onglet sélectionné
        selectedItemColor: Colors.blue,
        
        // Couleur de l'onglet non sélectionné
        unselectedItemColor: Colors.grey,
        
        // Gère le changement d'onglet
        onTap: (index) {
          setState(() {
            _currentTabIndex = index;
          });
        },
      ),
    );
  }
}
