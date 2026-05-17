import 'package:flutter/material.dart';

import 'admin_info_page.dart';

import '../pages/lifeguard/lifeguard_menu_page.dart';

enum LoginProfile { lifeguard, admin }

class LifeguardLoginPage extends StatefulWidget {
  const LifeguardLoginPage({super.key});

  @override
  State<LifeguardLoginPage> createState() => _LifeguardLoginPageState();
}

class _LifeguardLoginPageState extends State<LifeguardLoginPage>
    with WidgetsBindingObserver {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _idFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  LoginProfile _selectedProfile = LoginProfile.lifeguard;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();

    final bottomInset =
        WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom;

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

  void _login() {
    final id = _idController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (_selectedProfile == LoginProfile.lifeguard) {
      if (id == 'sauveteur' && password == '1234') {
        Navigator.of(context).pushReplacement(
  MaterialPageRoute(
    builder: (_) => LifeguardMenuPage(
  profileColor: const Color(0xFFFF0000),
),
  ),
);
      } else {
        _showLoginError();
      }
    } else {
      if (id == 'admin' && password == 'admin2026') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminInfoPage()),
        );
      } else {
        _showLoginError();
      }
    }
  }

  void _showLoginError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Identifiant ou mot de passe incorrect'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _activateEditingMode() {
    if (!_isEditing) {
      setState(() => _isEditing = true);
    }
  }

  void _closeKeyboard() {
    FocusScope.of(context).unfocus();
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isLifeguard = _selectedProfile == LoginProfile.lifeguard;

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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Column(
                  children: [
                    Image.asset(
                      'data/icons/title.png',
                      height: 64,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                    const SizedBox(height: 12),

                    AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      transform: Matrix4.translationValues(
                        0,
                        _isEditing ? -110 : 0,
                        0,
                      ),
                      child: Column(
                        children: [
                          Visibility(
                            visible: !_isEditing,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: Column(
                              children: [
                                const Text(
                                  'CONNEXION',
                                  style: TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  isLifeguard
                                      ? 'Accès sauveteurs'
                                      : 'Accès administration',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),

                          Row(
                            children: [
                              Expanded(
                                child: _profileButton(
                                  label: 'SAUVETEUR',
                                  selected: isLifeguard,
                                  color: const Color(0xFFFF0000),
                                  onTap: () {
                                    setState(() {
                                      _selectedProfile =
                                          LoginProfile.lifeguard;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _profileButton(
                                  label: 'ADMIN',
                                  selected: !isLifeguard,
                                  color: const Color(0xFF1E3A8A),
                                  onTap: () {
                                    setState(() {
                                      _selectedProfile = LoginProfile.admin;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 18),

                          TextField(
                            controller: _idController,
                            focusNode: _idFocusNode,
                            textInputAction: TextInputAction.next,
                            onTap: _activateEditingMode,
                            onSubmitted: (_) {
                              FocusScope.of(context)
                                  .requestFocus(_passwordFocusNode);
                            },
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Identifiant',
                              hintStyle:
                                  const TextStyle(color: Colors.black54),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.08),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                              border: OutlineInputBorder(
  borderRadius: BorderRadius.circular(16),
  borderSide: const BorderSide(
    color: Colors.black,
    width: 2,
  ),
),

enabledBorder: OutlineInputBorder(
  borderRadius: BorderRadius.circular(16),
  borderSide: const BorderSide(
    color: Colors.black,
    width: 2,
  ),
),

focusedBorder: OutlineInputBorder(
  borderRadius: BorderRadius.circular(16),
  borderSide: const BorderSide(
    color: Colors.black,
    width: 2.4,
  ),
),
                            ),
                          ),

                          const SizedBox(height: 14),

                          TextField(
                            controller: _passwordController,
                            focusNode: _passwordFocusNode,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            onTap: _activateEditingMode,
                            onSubmitted: (_) => _login(),
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Mot de passe',
                              hintStyle:
                                  const TextStyle(color: Colors.black54),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.08),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                              border: OutlineInputBorder(
  borderRadius: BorderRadius.circular(16),
  borderSide: const BorderSide(
    color: Colors.black,
    width: 2,
  ),
),

enabledBorder: OutlineInputBorder(
  borderRadius: BorderRadius.circular(16),
  borderSide: const BorderSide(
    color: Colors.black,
    width: 2,
  ),
),

focusedBorder: OutlineInputBorder(
  borderRadius: BorderRadius.circular(16),
  borderSide: const BorderSide(
    color: Colors.black,
    width: 2.4,
  ),
),
                            ),
                          ),

                          const SizedBox(height: 22),

                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isLifeguard
                                    ? const Color(0xFFFF0000)
                                    : const Color(0xFF1E3A8A),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(18),
  side: const BorderSide(
    color: Colors.black,
    width: 2,
  ),
),
                              ),
                              child: const Text(
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
                    ),

                    const Spacer(),

                    if (!_isEditing)
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
  color: Colors.transparent,
  shape: BoxShape.circle,
  border: Border.all(
    color: Colors.black,
    width: 2,
  ),
),
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.black,
                            size: 30,
                          ),
                        ),
                      ),

                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileButton({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 54,
        decoration: BoxDecoration(
          color: selected
    ? color.withOpacity(0.18)
    : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 2),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}