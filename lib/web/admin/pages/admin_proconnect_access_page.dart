import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../shared/web_colors.dart';

class AdminProConnectAccessPage extends StatelessWidget {
  const AdminProConnectAccessPage({super.key});

  void _continueToAdminRequest(BuildContext context) {
    Navigator.of(context).pushReplacementNamed('/admin-request-form');
  }

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
                      'SPHOT ADMIN',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: WebColors.blue,
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'L’accès est réservé aux professionnels identifiés par '
                      'ProConnect.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: WebColors.blue,
                        fontSize: 16,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: () => _continueToAdminRequest(context),
                        icon: const Icon(Icons.verified_user_outlined),
                        label: const Text(
                          'S’IDENTIFIER AVEC PROCONNECT',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: WebColors.blue,
                          side: const BorderSide(
                            color: WebColors.blue,
                            width: 2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 22,
            child: Center(
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: WebColors.blue, width: 2),
                ),
                child: IconButton(
                  onPressed: () {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/',
                      (route) => false,
                    );
                  },
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: WebColors.blue,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
