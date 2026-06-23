import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/advertiser_auth_service.dart';
import 'advertise_page.dart';

class AdvertiserAccessPage extends StatefulWidget {
  const AdvertiserAccessPage({super.key});

  @override
  State<AdvertiserAccessPage> createState() => _AdvertiserAccessPageState();
}

class _AdvertiserAccessPageState extends State<AdvertiserAccessPage> {
  static const Color refColor = Color(0xFF1E3A8A);
  static const Color redRefColor = Color(0xFFDC2626);

  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _handleProConnectReturn();
  }

  Future<void> _handleProConnectReturn() async {
  debugPrint('DEBUT _handleProConnectReturn');

  User? user;

  try {
    final credential =
        await FirebaseAuth.instance.getRedirectResult();

    debugPrint('credential.user: ${credential.user?.uid}');
    debugPrint('credential.providerId: ${credential.credential?.providerId}');

    user = credential.user;
  } catch (e) {
    debugPrint('ERREUR getRedirectResult direct: $e');
  }

  user ??= FirebaseAuth.instance.currentUser;

  if (user == null) {
    try {
      user = await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(const Duration(seconds: 5));

      debugPrint('authStateChanges user: ${user?.uid}');
    } catch (e) {
      debugPrint('AUCUN USER via authStateChanges: $e');
    }
  }

  debugPrint('currentUser final: ${user?.uid}');

  if (!mounted) return;

  if (user == null) {
  Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) => const AdvertisePage(),
    ),
  );
  return;
}

    final requestRef = FirebaseFirestore.instance
        .collection('advertiserRequests')
        .doc(user.uid);

    final requestDoc = await requestRef.get();

    if (!requestDoc.exists) {
      await requestRef.set({
  'uid': user.uid,
  'email': user.email ?? '',
  'displayName': user.displayName ?? '',
  'organisation': '',
  'siret': '',
  'contactName': user.displayName ?? '',
  'contactEmail': user.email ?? '',
  'billingAddress': '',
  'billingPostalCode': '',
  'billingCity': '',
  'billingCountry': 'France',
  'status': 'pending',
  'createdAt': FieldValue.serverTimestamp(),
  'updatedAt': FieldValue.serverTimestamp(),
});

      if (!mounted) return;

      setState(() {
        _checking = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Votre demande annonceur est en cours de validation.'),
        ),
      );

      return;
    }

    final status = requestDoc.data()?['status'];

    if (status == 'approved') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const AdvertisePage(),
        ),
      );
      return;
    }

    setState(() {
      _checking = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          status == 'rejected'
              ? 'Votre accès annonceur a été refusé.'
              : 'Votre demande annonceur est en cours de validation.',
        ),
      ),
    );
  }

  Future<void> _connectWithProConnect() async {
    await AdvertiserAuthService.signInWithProConnectRedirect();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0x00000000),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'data/images/map_background.jpg',
            fit: BoxFit.cover,
          ),
          SafeArea(
  child: SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
                children: [
                  SizedBox(
                    height: 58,
                    child: Center(
                      child: Image.asset(
                        'data/icons/title.png',
                        height: 58,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0x00000000),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: refColor,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'ESPACE ANNONCEUR PROFESSIONNEL',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: redRefColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Pour déposer une demande publicitaire sur SPHOT, '
                          'vous devez vous connecter avec ProConnect afin de vérifier votre organisation professionnelle.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: refColor,
                            fontSize: 15,
                            height: 1.4,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton(
  onPressed: _checking
      ? null
      : () {
          debugPrint('BOUTON PROCONNECT CLIQUE');
          _connectWithProConnect();
        },
  style: OutlinedButton.styleFrom(
    side: const BorderSide(
      color: refColor,
      width: 2,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    ),
  ),
  child: Center(
    child: Text(
      _checking
          ? 'VÉRIFICATION...'
          : 'SE CONNECTER AVEC PROCONNECT',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: refColor,
        fontWeight: FontWeight.w900,
      ),
    ),
  ),
),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: const Color(0x00000000),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: refColor,
                        width: 2,
                      ),
                    ),
                    child: Material(
                      color: const Color(0x00000000),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          Navigator.of(context).maybePop();
                        },
                        child: const Center(
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: refColor,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
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