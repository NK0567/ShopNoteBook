import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/main_app.dart';
import 'services/auth_service.dart';

/// Point d'entrée principal de l'application ShopBook
void main() {
  runApp(const ShopBookApp());
}

/// Application principale ShopBook
/// Configure le thème et la navigation de l'app
class ShopBookApp extends StatelessWidget {
  const ShopBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Titre de l'application
      title: 'ShopBook',
      
      // Désactive le banner "Debug" en mode développement
      debugShowCheckedModeBanner: false,
      
      // Thème de l'application avec couleur principale bleue
      theme: ThemeData(
        // Couleur principale de l'application
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        
        // Style des boutons élevés
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        
        // Style des champs texte
        inputDecorationTheme: InputDecorationTheme(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      
      // Écran d'accueil basé sur l'état d'authentification
      home: AuthService.isAuthenticated ? const MainApp() : const LoginScreen(),
      
      // Routes nommées pour la navigation
      routes: {
        '/login': (context) => const LoginScreen(),
        '/main': (context) => const MainApp(),
      },
    );
  }
}
