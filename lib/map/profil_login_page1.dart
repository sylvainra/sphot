import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pages/sauveteur/change_password_page.dart';
import '../pages/sauveteur/sauveteur_menu_page.dart';

class ProfilLoginPage extends StatefulWidget {
  const ProfilLoginPage({super.key});

  @override
  State<ProfilLoginPage> createState() => _ProfilLoginPageState();
}

class _ProfilLoginPageState extends State<ProfilLoginPage>
    with WidgetsBindingObserver {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _idFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _isEditing = false;
  bool _showPassword = false;
  bool _isLoggingIn = false;

  String? _loginErrorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();

    final bottomInset = WidgetsBinding
        .instance.platformDispatcher.views.first.viewInsets.bottom;

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

    _idController.dispose();
    _passwordController.dispose();

    _idFocusNode.dispose();
    _passwordFocusNode.dispose();

    super.dispose();
  }

  Future<void> _loginSauveteur() async {
    if (_isLoggingIn) return;

    final id = _idController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    setState(() {
      _loginErrorMessage = null;
    });

    if (id.isEmpty || password.isEmpty) {
      setState(() {
        _loginErrorMessage =
            'Veuillez renseigner votre identifiant et votre mot de passe.';
      });

      return;
    }

    setState(() {
      _isLoggingIn = true;
    });

    try {
      final uri = Uri.parse(
        'https://us-central1-sphot-ab80b.cloudfunctions.net/loginSauveteur',
      );

      debugPrint('Appel Cloud Function : $uri');

      final response = await http.post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'login': id,
          'password': password,
        }),
      );

      debugPrint('Status = ${response.statusCode}');
      debugPrint('Body = ${response.body}');

      if (response.statusCode != 200) {
        if (!mounted) return;

        setState(() {
          _loginErrorMessage =
    'Identifiant ou mot de passe incorrect.\n'
    'Contactez votre administrateur si oubli.';
        });

        return;
      }

      final decodedResult = jsonDecode(response.body);

      if (decodedResult is! Map<String, dynamic>) {
        if (!mounted) return;

        setState(() {
          _loginErrorMessage =
              'Réponse de connexion invalide. Contactez votre administrateur SPHOT.';
        });

        return;
      }

      final result = decodedResult;

      if (result['success'] != true) {
        if (!mounted) return;

        setState(() {
          _loginErrorMessage =
    'Identifiant ou mot de passe incorrect.\n'
    'Contactez votre administrateur si oubli.';
        });

        return;
      }

      final userRole = (result['userRole'] ?? 'Sauveteur').toString();
      final territoireId = (result['territoireId'] ?? '').toString();
      final mustChangePassword = result['mustChangePassword'] == true;
      final webSessionToken =
          (result['webSessionToken'] ?? '').toString();

      if (!mounted) return;

      if (mustChangePassword) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ChangePasswordPage(
              login: id,
              territoireId: territoireId,
              userRole: userRole,
            ),
          ),
        );

        return;
      }

      if (userRole.toUpperCase() == 'SUPER_ADMIN') {
        await _openSuperAdminDashboard(webSessionToken);
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SauveteurMenuPage(
            profileColor: const Color(0xFFFF0000),
            userRole: userRole,
            territoireId: territoireId,
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Erreur de connexion sauveteur : $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _loginErrorMessage =
            'Connexion impossible. Vérifiez vos identifiants ou contactez votre administrateur SPHOT.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingIn = false;
        });
      }
    }
  }

  Future<void> _createProSpace() async {
    FocusScope.of(context).unfocus();

    final uri = kIsWeb
        ? Uri.base.replace(fragment: '/admin-request')
        : Uri.parse('https://sphot.app/#/admin-request');

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_blank' : null,
    );

    if (!opened && mounted) {
      setState(() {
        _loginErrorMessage =
            'Impossible d’ouvrir la demande d’accès Admin SPHOT.';
      });
    }
  }

  Future<void> _openSuperAdminDashboard(String token) async {
    FocusScope.of(context).unfocus();

    if (token.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _loginErrorMessage =
              'La session Web Super Admin n’a pas pu être créée.';
        });
      }
      return;
    }

    final route = Uri(
      path: '/super-admin',
      queryParameters: {'token': token},
    ).toString();
    final uri = kIsWeb
        ? Uri.base.replace(fragment: route)
        : Uri.parse('https://sphot.app/#$route');

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_blank' : null,
    );

    if (!opened && mounted) {
      setState(() {
        _loginErrorMessage =
            'Impossible d’ouvrir le dashboard Super Admin SPHOT.';
      });
    }
  }

  Future<void> _openProLogin() async {
    FocusScope.of(context).unfocus();

    final uri = kIsWeb
        ? Uri.base.replace(fragment: '/professional-login')
        : Uri.parse('https://sphot.app/#/professional-login');

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_blank' : null,
    );

    if (!opened && mounted) {
      setState(() {
        _loginErrorMessage =
            'Impossible d’ouvrir le portail professionnel SPHOT.';
      });
    }
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

  InputDecoration _buildSauveteurInputDecoration({
    required String hintText,
    required Color color,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: color,
        fontWeight: FontWeight.w700,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withOpacity(0.08),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: color,
          width: 2,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: color,
          width: 2,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: color,
          width: 2.4,
        ),
      ),
    );
  }

  ButtonStyle _buildOutlinedButtonStyle(Color color) {
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      backgroundColor: Colors.transparent,
      disabledForegroundColor: color.withOpacity(0.45),
      side: BorderSide(
        color: color,
        width: 2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }

  Widget _buildSauveteurSpace({
    required Color sauveteurColor,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: sauveteurColor,
          width: 2.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            'ESPACE SAUVETEUR',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: sauveteurColor,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _idController,
            focusNode: _idFocusNode,
            enabled: !_isLoggingIn,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            onTap: _activateEditingMode,
            onSubmitted: (_) {
              FocusScope.of(context).requestFocus(_passwordFocusNode);
            },
            style: TextStyle(
              color: sauveteurColor,
              fontWeight: FontWeight.w600,
            ),
            decoration: _buildSauveteurInputDecoration(
              hintText: 'Identifiant',
              color: sauveteurColor,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            enabled: !_isLoggingIn,
            obscureText: !_showPassword,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            onTap: _activateEditingMode,
            onSubmitted: (_) {
              if (!_isLoggingIn) {
                _loginSauveteur();
              }
            },
            style: TextStyle(
              color: sauveteurColor,
              fontWeight: FontWeight.w600,
            ),
            decoration: _buildSauveteurInputDecoration(
              hintText: 'Mot de passe',
              color: sauveteurColor,
              suffixIcon: IconButton(
                tooltip: _showPassword
                    ? 'Masquer le mot de passe'
                    : 'Afficher le mot de passe',
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: sauveteurColor,
                ),
                onPressed: _isLoggingIn
                    ? null
                    : () {
                        setState(() {
                          _showPassword = !_showPassword;
                        });
                      },
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoggingIn ? null : _loginSauveteur,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: sauveteurColor,
                disabledBackgroundColor: Colors.transparent,
                disabledForegroundColor: sauveteurColor.withOpacity(0.55),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: _isLoggingIn
                        ? sauveteurColor.withOpacity(0.55)
                        : sauveteurColor,
                    width: 2,
                  ),
                ),
              ),
              child: _isLoggingIn
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: sauveteurColor,
                      ),
                    )
                  : const Text(
                      'SE CONNECTER',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _loginErrorMessage == null
                  ? const SizedBox.shrink()
                  : Center(
                      key: ValueKey(_loginErrorMessage),
                      child: Text(
                        _loginErrorMessage!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProSpace({
    required Color proColor,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: proColor,
          width: 2.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            'ESPACE ADMIN',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: proColor,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _createProSpace,
              style: _buildOutlinedButtonStyle(proColor),
              icon: Icon(
                Icons.add_business_rounded,
                color: proColor,
                size: 23,
              ),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'CRÉER MON SPHOT',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _openProLogin,
              style: _buildOutlinedButtonStyle(proColor),
              icon: Icon(
                Icons.login_rounded,
                color: proColor,
                size: 23,
              ),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'ME CONNECTER À MON SPHOT',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color sauveteurColor = Color(0xFFEF4444);
    const Color proColor = Color(0xFF1E3A8A);

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onTap: _closeKeyboard,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Low-resolution offline fallback. The live map below covers it
            // whenever map tiles are available.
            Image.asset(
              'data/images/map_background.jpg',
              fit: BoxFit.cover,
            ),
            IgnorePointer(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final aspectRatio =
                      constraints.maxWidth / constraints.maxHeight;
                  final initialZoom = aspectRatio >= 1.2 ? 17.35 : 16.2;

                  return FlutterMap(
                    options: MapOptions(
                      initialCenter: const LatLng(
                        46.3893825,
                        -1.4942598,
                      ),
                      initialZoom: initialZoom,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                      backgroundColor: Colors.transparent,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        maxZoom: 19,
                        maxNativeZoom: 19,
                        userAgentPackageName: 'com.sylvainra.sphot',
                        keepBuffer: 5,
                        errorTileCallback: (tile, error, stackTrace) {
                          debugPrint(
                            'ERREUR FOND CARTE CONNEXION : $error',
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final contentWidth =
                      constraints.maxWidth.clamp(0.0, 520.0).toDouble();

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(26, 6, 26, 72),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: contentWidth,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'data/icons/title.png',
                                height: 56,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                              const SizedBox(height: 4),
                              Visibility(
                                visible: !_isEditing,
                                maintainSize: true,
                                maintainAnimation: true,
                                maintainState: true,
                                child: const Text(
                                  'CONNEXION',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFEF4444),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildSauveteurSpace(
                                sauveteurColor: sauveteurColor,
                              ),
                              const SizedBox(height: 12),
                              _buildProSpace(
                                proColor: proColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2,
                      ),
                    ),
                    child: IconButton(
                      tooltip: 'Retour',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
