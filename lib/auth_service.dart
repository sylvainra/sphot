import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // =========================
  // INSCRIPTION
  // =========================

  Future<User?> signUpWithEmail(
    String email,
    String password,
  ) async {
    try {
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      return userCredential.user;

    } catch (e) {

      print('Erreur lors de l\'inscription : $e');

      return null;
    }
  }

  // =========================
  // CONNEXION
  // =========================

  Future<User?> signInWithEmail(
    String email,
    String password,
  ) async {
    try {
      UserCredential userCredential =
          await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      return userCredential.user;

    } catch (e) {

      print('Erreur lors de la connexion : $e');

      return null;
    }
  }

  // =========================
  // DÉCONNEXION
  // =========================

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // =========================
  // UTILISATEUR ACTUEL
  // =========================

  User? get currentUser => _auth.currentUser;
}



