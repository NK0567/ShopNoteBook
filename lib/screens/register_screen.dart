import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

/// Écran d'inscription (Register)
/// Permet à un nouveau commerçant de créer un compte
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Contrôleur pour le champ nom complet
  final _nameController = TextEditingController();
  
  // Contrôleur pour le champ email
  final _emailController = TextEditingController();
  
  // Contrôleur pour le champ mot de passe
  final _passwordController = TextEditingController();
  
  // Contrôleur pour la confirmation du mot de passe
  final _confirmPasswordController = TextEditingController();
  
  // Contrôleur pour le nom de la boutique
  final _businessNameController = TextEditingController();
  
  // Clé globale pour le formulaire (validation)
  final _formKey = GlobalKey<FormState>();
  
  // Indicateur de chargement pendant l'inscription
  bool _isLoading = false;
  
  // Message d'erreur à afficher à l'utilisateur
  String _errorMessage = '';

  @override
  void dispose() {
    // Libère les ressources des contrôleurs
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _businessNameController.dispose();
    super.dispose();
  }

  /// Traite l'inscription d'un nouvel utilisateur
  Future<void> _handleRegister() async {
    // Valide les données du formulaire
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Vérifie que les deux mots de passe correspondent
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Les mots de passe ne correspondent pas';
      });
      return;
    }

    // Active l'indicateur de chargement
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Tente d'enregistrer le nouvel utilisateur
      final success = await AuthService.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        businessName: _businessNameController.text.trim(),
      );

      if (success && mounted) {
        // Affiche un message de succès
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Inscription réussie! Vous pouvez maintenant vous connecter.'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Navigue vers l'écran de connexion
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      } else {
        // Affiche un message d'erreur si l'inscription a échoué
        setState(() {
          _errorMessage = 'Erreur lors de l\'inscription. Cet email est peut-être déjà utilisé.';
        });
      }
    } catch (e) {
      // Affiche l'erreur en cas d'exception
      setState(() {
        _errorMessage = 'Erreur lors de l\'inscription: $e';
      });
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
        title: const Text('ShopBook - Inscription'),
        backgroundColor: Colors.blue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      
      // Corps de l'écran
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Espacement supérieur
              const SizedBox(height: 20),
              
              // Titre principal
              Text(
                'Créer un compte',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              // Sous-titre
              const SizedBox(height: 10),
              Text(
                'Bienvenue sur ShopBook',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
              ),
              
              // Espacement
              const SizedBox(height: 30),
              
              // Formulaire d'inscription
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Champ nom complet avec validation
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Nom complet',
                        hintText: 'Entrez votre nom complet',
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Colors.grey),
                        ),
                      ),
                      // Validation du nom
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Veuillez entrer votre nom';
                        }
                        if (value.length < 3) {
                          return 'Le nom doit avoir au moins 3 caractères';
                        }
                        return null;
                      },
                    ),
                    
                    // Espacement
                    const SizedBox(height: 15),
                    
                    // Champ nom de la boutique avec validation
                    TextFormField(
                      controller: _businessNameController,
                      decoration: InputDecoration(
                        labelText: 'Nom de la boutique',
                        hintText: 'Entrez le nom de votre boutique',
                        prefixIcon: const Icon(Icons.store),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Colors.grey),
                        ),
                      ),
                      // Validation du nom de boutique
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Veuillez entrer le nom de votre boutique';
                        }
                        if (value.length < 3) {
                          return 'Le nom doit avoir au moins 3 caractères';
                        }
                        return null;
                      },
                    ),
                    
                    // Espacement
                    const SizedBox(height: 15),
                    
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
                      // Validation de l'email
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
                    
                    // Espacement
                    const SizedBox(height: 15),
                    
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
                    
                    // Espacement
                    const SizedBox(height: 15),
                    
                    // Champ confirmation mot de passe avec validation
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: true, // Masque le mot de passe
                      decoration: InputDecoration(
                        labelText: 'Confirmer le mot de passe',
                        hintText: 'Confirmez votre mot de passe',
                        prefixIcon: const Icon(Icons.lock),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Colors.grey),
                        ),
                      ),
                      // Validation de confirmation
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Veuillez confirmer votre mot de passe';
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
              
              // Bouton d'inscription
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
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
                        'S\'inscrire',
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
              
              // Lien pour se connecter si on a déjà un compte
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Vous avez déjà un compte ? '),
                  TextButton(
                    onPressed: () {
                      // Revient à l'écran de connexion
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Se connecter',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              
              // Espacement inférieur
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
