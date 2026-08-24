import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/advertiser_auth_service.dart';
import '../shared/web_colors.dart';
import 'pages/advertiser_dashboard_page.dart';

class WebAdvertiserApp extends StatelessWidget {
  const WebAdvertiserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPHOT Annonceur',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: WebColors.blue,
        scaffoldBackgroundColor: const Color(0xFFF3F6FA),
      ),
      home: const _AdvertiserAccessGate(),
    );
  }
}

class _AdvertiserAccessGate extends StatefulWidget {
  const _AdvertiserAccessGate();

  @override
  State<_AdvertiserAccessGate> createState() =>
      _AdvertiserAccessGateState();
}

class _AdvertiserAccessGateState extends State<_AdvertiserAccessGate> {
  bool _checkingRedirect = true;
  bool _startingSignIn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolveRedirect();
  }

  Future<void> _resolveRedirect() async {
    try {
      await AdvertiserAuthService.handleRedirectResult();
    } on FirebaseAuthException catch (error) {
      _error = error.message ?? error.code;
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() => _checkingRedirect = false);
      }
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _startingSignIn = true;
      _error = null;
    });

    try {
      await AdvertiserAuthService.signInWithProConnectRedirect();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _startingSignIn = false;
        _error = error.message ?? error.code;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _startingSignIn = false;
        _error = error.toString();
      });
    }
  }

  bool _isProConnectUser(User user) {
    return user.providerData.any(
      (provider) => provider.providerId == AdvertiserAuthService.providerId,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingRedirect) {
      return const _AdvertiserLoadingPage();
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;

        if (snapshot.connectionState == ConnectionState.waiting && user == null) {
          return const _AdvertiserLoadingPage();
        }

        if (user != null && _isProConnectUser(user)) {
          return AdvertiserDashboardPage(
            user: user,
            onSignOut: AdvertiserAuthService.signOut,
          );
        }

        return _AdvertiserLoginPage(
          isLoading: _startingSignIn,
          error: user == null
              ? _error
              : 'Cette session ne provient pas de ProConnect. Déconnectez-vous puis identifiez-vous avec votre identité professionnelle.',
          onSignIn: _signIn,
          onClearSession: user == null ? null : AdvertiserAuthService.signOut,
        );
      },
    );
  }
}

class _AdvertiserLoadingPage extends StatelessWidget {
  const _AdvertiserLoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: WebColors.red),
      ),
    );
  }
}

class _AdvertiserLoginPage extends StatelessWidget {
  const _AdvertiserLoginPage({
    required this.isLoading,
    required this.error,
    required this.onSignIn,
    required this.onClearSession,
  });

  final bool isLoading;
  final String? error;
  final Future<void> Function() onSignIn;
  final Future<void> Function()? onClearSession;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('data/images/map_background.jpg', fit: BoxFit.cover),
          ColoredBox(color: Colors.white.withOpacity(0.72)),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                width: 500,
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.97),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: WebColors.blue, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      'data/icons/fire_red_icon.svg',
                      width: 42,
                      height: 58,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'ESPACE ANNONCEUR SPHOT',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: WebColors.blue,
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'L’accès est réservé aux professionnels identifiés par ProConnect.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: WebColors.blue,
                        fontSize: 16,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEEEE),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: WebColors.red),
                        ),
                        child: Text(
                          error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: WebColors.red,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: isLoading ? null : onSignIn,
                        icon: isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.verified_user_outlined),
                        label: Text(
                          isLoading
                              ? 'CONNEXION EN COURS…'
                              : 'S’IDENTIFIER AVEC PROCONNECT',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: WebColors.blue,
                          side: const BorderSide(color: WebColors.blue, width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    if (onClearSession != null) ...[
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: onClearSession,
                        child: const Text('DÉCONNECTER LA SESSION ACTUELLE'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
