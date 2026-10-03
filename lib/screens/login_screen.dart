import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'register_screen.dart';

/// Écran de connexion (Login)
/// Permet à l'utilisateur existant de se connecter à l'application
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Contrôleur pour le champ email
  final _emailController = TextEditingController();
  
  // Contrôleur pour le champ mot de passe
  final _passwordController = TextEditingController();
  
  // Clé globale pour le formulaire (validation)
  final _formKey = GlobalKey<FormState>();
  
  // Indicateur de chargement pendant la connexion
  bool _isLoading = false;
  
  // Message d'erreur à afficher à l'utilisateur
  String _errorMessage = '';

  @override
  void dispose() {
    // Libère les ressources des contrôleurs
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Traite la tentative de connexion
  Future<void> _handleLogin() async {
    // Valide les données du formulaire
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Active l'indicateur de chargement
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Tente de connecter l'utilisateur avec les identifiants fournis
      final success = await AuthService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // Vérifie si la connexion est réussie
      if (success && mounted) {
        // Navigue vers l'écran principal de l'application
        Navigator.of(context).pushReplacementNamed('/main');
      } else if (mounted) {
        // Affiche un message d'erreur si la connexion a échoué
        setState(() {
          _errorMessage = 'Email ou mot de passe incorrect';
        });
      }
    } catch (e) {
      // Affiche l'erreur en cas d'exception
      if (mounted) {
        setState(() {
          _errorMessage = 'Erreur lors de la connexion: $e';
        });
      }
    } finally {
      // Désactive l'indicateur de chargement
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Barre d'en-tête de l'écran
      appBar: AppBar(
        title: const Text('ShopBook - Connexion'),
        backgroundColor: Colors.blue,
        elevation: 0,
      ),
      
      // Corps de l'écran
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Espacement supérieur
              const SizedBox(height: 30),
              
              // Logo/Titre principal
              Text(
                'ShopBook',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              // Sous-titre
              const SizedBox(height: 10),
              Text(
                'Carnet du Boutiquier',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey,
                ),
              ),
              
              // Espacement
              const SizedBox(height: 40),
              
              // Formulaire de connexion
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Champ email avec validation
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        hintText: 'Entrez votre email',
                        prefixIcon: const Icon(Icons.email),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Colors.grey),
                        ),
                      ),
                      // Validation du format email
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Veuillez entrer votre email';
                        }
                        if (!value.contains('@')) {
                          return 'Entrez un email valide';
                        }
                        return null;
                      },
                    ),
                    
                    // Espacement entre les champs
                    const SizedBox(height: 20),
                    
                    // Champ mot de passe avec validation
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true, // Masque le mot de passe
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        hintText: 'Entrez votre mot de passe',
                        prefixIcon: const Icon(Icons.lock),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Colors.grey),
                        ),
                      ),
                      // Validation du mot de passe
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Veuillez entrer votre mot de passe';
                        }
                        if (value.length < 6) {
                          return 'Le mot de passe doit avoir au moins 6 caractères';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              
              // Affichage du message d'erreur si présent
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                ),
              
              // Espacement
              const SizedBox(height: 30),
              
              // Bouton de connexion
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
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
                        'Se connecter',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                ),
              ),
              
              // Espacement
              const SizedBox(height: 20),
              
              // Lien pour créer un compte
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Pas encore de compte ? '),
                  TextButton(
                    onPressed: () {
                      // Navigue vers l'écran d'inscription
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RegisterScreen()),
                      );
                    },
                    child: const Text(
                      'S\'inscrire',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
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
