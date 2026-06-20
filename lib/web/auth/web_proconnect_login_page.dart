import 'package:flutter/material.dart';

import '../services/web_proconnect_auth_service.dart';
import '../shared/web_colors.dart';
import '../admin/web_admin_registration_page.dart';

class WebProConnectLoginPage extends StatefulWidget {
  final String mode;

  const WebProConnectLoginPage({
    super.key,
    required this.mode,
  });

  @override
  State<WebProConnectLoginPage> createState() =>
      _WebProConnectLoginPageState();
}

class _WebProConnectLoginPageState
    extends State<WebProConnectLoginPage> {
  bool _isLoading = false;

  bool get isAdmin => widget.mode == 'admin';

  @override
  void initState() {
    super.initState();
    // _handleRedirectResult();
  }

  Future<void> _handleRedirectResult() async {
    try {
      final result =
          await WebProConnectAuthService().handleRedirectResult();

      if (!mounted) return;

      await _handleAccessResult(
        result,
        showSignedOutMessage: false,
      );
    } catch (e) {
      debugPrint('Erreur redirect ProConnect : $e');
    }
  }

  Future<void> _signInWithProConnect() async {
    if (!isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connexion sauveteur non encore reliée à ProConnect.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await WebProConnectAuthService().signIn();

      if (!mounted) return;

      await _handleAccessResult(result);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur ProConnect : $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleAccessResult(
    WebAdminAccessResult result, {
    bool showSignedOutMessage = true,
  }) async {
    switch (result.status) {
      case WebAdminAccessStatus.approved:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Connexion Admin ProConnect réussie.',
            ),
          ),
        );
        break;

      case WebAdminAccessStatus.pending:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const _WebAdminPendingPage(),
          ),
        );
        break;

      case WebAdminAccessStatus.rejected:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const _WebAdminRejectedPage(),
          ),
        );
        break;

      case WebAdminAccessStatus.registrationRequired:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => WebAdminRegistrationPage(
              proConnectUid: 'test_uid_admin_001',
              proConnectEmail: 'admin@testville.fr',
              proConnectNom: 'DUPONT',
              proConnectPrenom: 'Marie',
              proConnectOrganisation: 'MAIRIE DE TESTVILLE',
              proConnectSiret: '12345678901234',
              proConnectSiren: '123456789',
            ),
          ),
        );
        break;

      case WebAdminAccessStatus.signedOut:
        if (showSignedOutMessage) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connexion annulée.'),
            ),
          );
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color mainColor =
        isAdmin ? WebColors.blue : WebColors.red;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'data/images/map_background.jpg',
            fit: BoxFit.cover,
          ),
          Container(
            color: Colors.white.withOpacity(0.65),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                Image.asset(
                  'data/icons/title.png',
                  height: 64,
                  fit: BoxFit.contain,
                ),
                const Spacer(),
                Container(
                  width: 420,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.96),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: mainColor,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isAdmin
                            ? Icons.admin_panel_settings
                            : Icons.groups,
                        size: 56,
                        color: mainColor,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        isAdmin
                            ? 'CONNEXION ADMIN'
                            : 'CONNEXION SAUVETEUR',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: mainColor,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _isLoading
                              ? null
                              : _signInWithProConnect,
                          style: ButtonStyle(
                            side:
                                MaterialStateProperty.resolveWith(
                              (states) => BorderSide(
                                color: states.contains(
                                  MaterialState.hovered,
                                )
                                    ? WebColors.red
                                    : mainColor,
                                width: 2,
                              ),
                            ),
                            foregroundColor:
                                MaterialStateProperty.resolveWith(
                              (states) =>
                                  states.contains(
                                MaterialState.hovered,
                              )
                                      ? WebColors.red
                                      : mainColor,
                            ),
                            overlayColor:
                                MaterialStateProperty.all(
                              Colors.transparent,
                            ),
                            shape: MaterialStateProperty.all(
                              RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(30),
                              ),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'S’IDENTIFIER AVEC PROCONNECT',
                                  style: TextStyle(
                                    fontWeight:
                                        FontWeight.w900,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),

SizedBox(
  width: double.infinity,
  height: 52,
  child: OutlinedButton(
    onPressed: _isLoading
        ? null
        : () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => WebAdminRegistrationPage(
                  proConnectUid: 'test_uid_admin_001',
                  proConnectEmail: 'admin@testville.fr',
                  proConnectNom: 'DUPONT',
                  proConnectPrenom: 'Marie',
                  proConnectOrganisation: 'MAIRIE DE TESTVILLE',
                  proConnectSiret: '12345678901234',
                  proConnectSiren: '123456789',
                ),
              ),
            );
          },
    style: OutlinedButton.styleFrom(
      side: const BorderSide(
        color: WebColors.red,
        width: 2,
      ),
      foregroundColor: WebColors.red,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(30),
      ),
    ),
    child: const Text(
      'TEST INSCRIPTION ADMIN',
      style: TextStyle(
        fontWeight: FontWeight.w900,
      ),
    ),
  ),
),

const SizedBox(height: 12),

TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: ButtonStyle(
                          foregroundColor:
                              MaterialStateProperty.resolveWith(
                            (states) =>
                                states.contains(
                              MaterialState.hovered,
                            )
                                    ? WebColors.red
                                    : WebColors.blue,
                          ),
                          overlayColor:
                              MaterialStateProperty.all(
                            Colors.transparent,
                          ),
                        ),
                        child: const Text(
                          'RETOUR',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WebAdminPendingPage extends StatelessWidget {
  const _WebAdminPendingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Demande en cours de validation',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _WebAdminRejectedPage extends StatelessWidget {
  const _WebAdminRejectedPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Accès refusé',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}