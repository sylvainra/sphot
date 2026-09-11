import 'dart:convert';

import '../../web/shared/sphot_access_page.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../web/admin/pages/admin_change_password_page.dart';
import '../../web/admin/pages/admin_dashboard_page.dart';
import '../../pages/sauveteur/change_password_page.dart';
import '../../web/super_admin/web_super_admin_app.dart';
import '../../web/advertiser/pages/advertiser_change_password_page.dart';
import '../../web/advertiser/pages/advertiser_dashboard_page.dart';

class ProfessionalLoginPage extends StatefulWidget {
  const ProfessionalLoginPage({super.key, this.advertiserAccess = false});

  final bool advertiserAccess;

  @override
  State<ProfessionalLoginPage> createState() => _ProfessionalLoginPageState();
}

class _ProfessionalLoginPageState extends State<ProfessionalLoginPage>
    with WidgetsBindingObserver {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _showPassword = false;
  bool _isLoggingIn = false;
  bool _isEditing = false;

  String? _errorMessage;

  static const Color _proColor = Color(0xFF1E3A8A);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();

    final bottomInset = WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .first
        .viewInsets
        .bottom;

    if (bottomInset == 0 && _isEditing) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (!mounted) return;

        FocusScope.of(context).unfocus();

        setState(() {
          _isEditing = false;
        });
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _emailController.dispose();
    _passwordController.dispose();

    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();

    super.dispose();
  }

  void _activateEditingMode() {
    if (_isEditing) return;

    setState(() {
      _isEditing = true;
    });
  }

  void _closeKeyboard() {
    FocusScope.of(context).unfocus();

    if (_isEditing) {
      setState(() {
        _isEditing = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _tryLogin({
    required String endpoint,
    required String login,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('https://us-central1-sphot-ab80b.cloudfunctions.net/$endpoint'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'login': login, 'password': password}),
    );
    if (widget.advertiserAccess &&
        response.statusCode != 200 &&
        response.statusCode != 401) {
      throw StateError(
        'Service annonceur indisponible (HTTP ${response.statusCode}).',
      );
    }
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      return null;
    }
    return decoded;
  }

  Future<void> _loginProfessional() async {
    if (_isLoggingIn) return;

    final login = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    FocusScope.of(context).unfocus();

    setState(() {
      _errorMessage = null;
    });

    if (login.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage =
            'Veuillez renseigner votre identifiant et votre mot de passe.';
      });
      return;
    }

    setState(() {
      _isLoggingIn = true;
    });

    try {
      final adminSession = widget.advertiserAccess
          ? null
          : await _tryLogin(
              endpoint: 'loginAdmin',
              login: login,
              password: password,
            );
      final advertiserSession = adminSession == null
          ? await _tryLogin(
              endpoint: 'loginAdvertiser',
              login: login,
              password: password,
            )
          : null;
      final potentialSuperAdminSession =
          !widget.advertiserAccess &&
              adminSession == null &&
              advertiserSession == null
          ? await _tryLogin(
              endpoint: 'loginSauveteur',
              login: login,
              password: password,
            )
          : null;
      final isSauveteurSuperAdmin =
          potentialSuperAdminSession != null &&
          (potentialSuperAdminSession['userRole'] ?? '')
                  .toString()
                  .toUpperCase() ==
              'SUPER_ADMIN';
      final decoded =
          adminSession ??
          advertiserSession ??
          (isSauveteurSuperAdmin ? potentialSuperAdminSession : null);

      if (decoded == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Identifiant ou mot de passe incorrect.';
        });
        return;
      }

      final mustChangePassword = decoded['mustChangePassword'] == true;
      final userRole = (decoded['userRole'] ?? 'ADMIN').toString();
      final prenom = (decoded['prenom'] ?? '').toString();
      final nom = (decoded['nom'] ?? '').toString();

      if (!mounted) return;

      if (userRole.toUpperCase() == 'SUPER_ADMIN') {
        final territoireId = (decoded['territoireId'] ?? '').toString();

        if (mustChangePassword) {
          if (isSauveteurSuperAdmin) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => ChangePasswordPage(
                  login: login,
                  territoireId: territoireId,
                  userRole: userRole,
                ),
              ),
            );
          } else {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => AdminChangePasswordPage(
                  login: login,
                  adminUid: (decoded['adminUid'] ?? '').toString(),
                  territoireId: territoireId,
                  userRole: userRole,
                  civilite: (decoded['civilite'] ?? '').toString(),
                  prenom: prenom,
                  nom: nom,
                ),
              ),
            );
          }
          return;
        }

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WebSuperAdminApp()),
          (route) => false,
        );
        return;
      }

      if (userRole.toUpperCase() == 'ANNONCEUR') {
        final advertiserRequestId = (decoded['advertiserRequestId'] ?? '')
            .toString();
        final firebaseToken = (decoded['firebaseToken'] ?? '').toString();
        if (advertiserRequestId.isEmpty || firebaseToken.isEmpty) {
          throw StateError('Session Firebase annonceur absente.');
        }
        final credential = await FirebaseAuth.instance.signInWithCustomToken(
          firebaseToken,
        );
        if (!mounted) return;
        if (mustChangePassword) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => AdvertiserChangePasswordPage(
                login: login,
                advertiserRequestId: advertiserRequestId,
                firstName: prenom,
                lastName: nom,
              ),
            ),
          );
          return;
        }
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => AdvertiserDashboardPage(
              user: credential.user,
              advertiserRequestId: advertiserRequestId,
              approvedAccess: true,
              onSignOut: FirebaseAuth.instance.signOut,
            ),
          ),
          (route) => false,
        );
        return;
      }

      final adminUid = (decoded['adminUid'] ?? '').toString();
      final territoireId = (decoded['territoireId'] ?? '').toString();
      final civilite = (decoded['civilite'] ?? '').toString();

      if (mustChangePassword) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AdminChangePasswordPage(
              login: login,
              adminUid: adminUid,
              territoireId: territoireId,
              userRole: userRole,
              civilite: civilite,
              prenom: prenom,
              nom: nom,
            ),
          ),
        );
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => AdminDashboardPage(
            adminUid: adminUid,
            territoireId: territoireId,
          ),
        ),
        (route) => false,
      );
    } catch (error, stackTrace) {
      debugPrint('Erreur de connexion professionnelle : $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _errorMessage = widget.advertiserAccess
            ? 'Connexion au service annonceur impossible. Réessayez ou contactez l’équipe SPHOT.'
            : 'Connexion impossible. Vérifiez votre connexion internet et réessayez.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingIn = false;
        });
      }
    }
  }

  void _forgotPassword() {
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim().toLowerCase();

    if (email.isEmpty) {
      setState(() {
        _errorMessage = 'Renseignez votre identifiant avant de demander un nouveau mot de passe.';
      });

      _emailFocusNode.requestFocus();
      return;
    }

    setState(() {
      _errorMessage = null;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'La réinitialisation du mot de passe sera raccordée à Firebase.',
            textAlign: TextAlign.center,
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
  }

  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: _proColor, fontWeight: FontWeight.w700),
      prefixIcon: Icon(prefixIcon, color: _proColor),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _proColor, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _proColor, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _proColor, width: 2.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
    );
  }

  Widget _buildProfessionalForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _emailController,
          focusNode: _emailFocusNode,
          autofocus: MediaQuery.of(context).size.width >= 900,
          enabled: !_isLoggingIn,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          onTap: _activateEditingMode,
          onChanged: (_) {
            if (_errorMessage != null) {
              setState(() {
                _errorMessage = null;
              });
            }
          },
          onSubmitted: (_) {
            FocusScope.of(context).requestFocus(_passwordFocusNode);
          },
          style: const TextStyle(
            color: _proColor,
            fontWeight: FontWeight.w700,
          ),
          decoration: _buildInputDecoration(
            hintText: 'Identifiant',
            prefixIcon: Icons.alternate_email_rounded,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _passwordController,
          focusNode: _passwordFocusNode,
          enabled: !_isLoggingIn,
          obscureText: !_showPassword,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.password],
          onTap: _activateEditingMode,
          onChanged: (_) {
            if (_errorMessage != null) {
              setState(() {
                _errorMessage = null;
              });
            }
          },
          onSubmitted: (_) {
            if (!_isLoggingIn) {
              _loginProfessional();
            }
          },
          style: const TextStyle(
            color: _proColor,
            fontWeight: FontWeight.w700,
          ),
          decoration: _buildInputDecoration(
            hintText: 'Mot de passe',
            prefixIcon: Icons.lock_outline_rounded,
            suffixIcon: IconButton(
              onPressed: _isLoggingIn
                  ? null
                  : () {
                      setState(() {
                        _showPassword = !_showPassword;
                      });
                    },
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: _proColor,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _isLoggingIn ? null : _forgotPassword,
            child: const Text(
              'MOT DE PASSE OUBLIÉ ?',
              style: TextStyle(
                color: _proColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        SphotAccessButton(
          label: 'SE CONNECTER',
          loading: _isLoggingIn,
          onPressed: _loginProfessional,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => SphotAccessPage(
    title: widget.advertiserAccess ? 'SPHOT PUBLICITAIRE' : 'SPHOT ADMIN',
    onBackgroundTap: _closeKeyboard,
    onBack: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false),
    child: _buildProfessionalForm(),
  );
}
