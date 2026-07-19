import 'package:flutter/material.dart';

class ProfessionalLoginPage extends StatefulWidget {
  const ProfessionalLoginPage({super.key});

  @override
  State<ProfessionalLoginPage> createState() =>
      _ProfessionalLoginPageState();
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

  Future<void> _loginProfessional() async {
    if (_isLoggingIn) return;

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    setState(() {
      _errorMessage = null;
    });

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage =
            'Veuillez renseigner votre adresse email et votre mot de passe.';
      });

      return;
    }

    setState(() {
      _isLoggingIn = true;
    });

    try {
      /*
       * CONNEXION PROFESSIONNELLE À RACCORDER
       *
       * Cette méthode accueillera ensuite :
       *
       * 1. Firebase Authentication
       * 2. La lecture du profil Firestore
       * 3. La détection automatique du rôle
       * 4. La redirection vers le portail correspondant :
       *
       *    - SUPER_ADMIN
       *    - ADMIN
       *    - ADVERTISER
       *
       * Le rôle SAUVETEUR restera volontairement associé
       * à l'espace Sauveteur de la page précédente.
       */

      await Future<void>.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'La connexion professionnelle sera raccordée à Firebase à l’étape suivante.',
              textAlign: TextAlign.center,
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
    } catch (error, stackTrace) {
      debugPrint('Erreur de connexion professionnelle : $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Connexion impossible. Vérifiez vos identifiants et réessayez.';
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
        _errorMessage =
            'Renseignez votre adresse email avant de demander un nouveau mot de passe.';
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
      hintStyle: const TextStyle(
        color: _proColor,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(
        prefixIcon,
        color: _proColor,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.10),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: _proColor,
          width: 2,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: _proColor,
          width: 2,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: _proColor,
          width: 2.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Colors.redAccent,
          width: 2,
        ),
      ),
    );
  }

  Widget _buildProfessionalForm() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _proColor,
          width: 2.5,
        ),
      ),
      child: Column(
        children: [
          const Text(
            'ESPACE PRO',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: _proColor,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _emailController,
            focusNode: _emailFocusNode,
            autofocus: MediaQuery.of(context).size.width >= 900,
            enabled: !_isLoggingIn,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [
              AutofillHints.username,
              AutofillHints.email,
            ],
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
              hintText: 'Adresse email',
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
            autofillHints: const [
              AutofillHints.password,
            ],
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
                tooltip: _showPassword
                    ? 'Masquer le mot de passe'
                    : 'Afficher le mot de passe',
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
              padding: const EdgeInsets.only(
                bottom: 12,
              ),
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
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoggingIn ? null : _loginProfessional,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: _proColor,
                disabledBackgroundColor: Colors.transparent,
                disabledForegroundColor:
                    _proColor.withValues(alpha: 0.55),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: _isLoggingIn
                        ? _proColor.withValues(alpha: 0.55)
                        : _proColor,
                    width: 2,
                  ),
                ),
              ),
              child: _isLoggingIn
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: _proColor,
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onTap: _closeKeyboard,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'data/images/map_background.jpg',
              fit: BoxFit.cover,
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 520,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'data/icons/title.png',
                                height: 64,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                              const SizedBox(height: 12),
                              Visibility(
                                visible: !_isEditing,
                                maintainSize: true,
                                maintainAnimation: true,
                                maintainState: true,
                                child: const Text(
  'CONNEXION',
  style: TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w900,
    color: Color(0xFFEF4444),
    letterSpacing: 0.5,
  ),
),
                              ),
                              const SizedBox(height: 18),
                              _buildProfessionalForm(),
                              const SizedBox(height: 20),
                                  Container(
                                  width: 62,
                                  height: 62,
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _proColor,
                                      width: 2,
                                    ),
                                  ),
                                  child: IconButton(
                                    tooltip: 'Retour',
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                    },
                                    icon: const Icon(
                                      Icons.arrow_back,
                                      color: _proColor,
                                      size: 30,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}