import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';


import 'admin_profile_button.dart';

import 'admin_creation_sauveteur_page.dart';

class AdminGestionSauveteurPage extends StatefulWidget {
  final String ville;
  final String territoireId;

  const AdminGestionSauveteurPage({
    super.key,
    this.ville = 'VILLE_NON_RENSEIGNEE',
    required this.territoireId,
  });

@override
State<AdminGestionSauveteurPage> createState() =>
    _AdminGestionSauveteurPageState();
}

class _AdminGestionSauveteurPageState
    extends State<AdminGestionSauveteurPage> {

  static const Color adminColor = Color(0xFF1E3A8A);
  static const Color actionColor = Color(0xFFDC2626);

  final Set<String> passwordResetDoneIds = {};

String _generateTemporaryPassword() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';

  final now = DateTime.now().millisecondsSinceEpoch;

  String password = '';

  for (int i = 0; i < 8; i++) {
    password += chars[(now + i * 17) % chars.length];
  }

  return password;
}
  

Future<List<Widget>> _buildSphotLines(List<String> posteIds) async {
  final widgets = <Widget>[];

  if (posteIds.isEmpty) {
    return [
      const Text(
        'Aucun SPHOT affecté',
        style: TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ];
  }

  for (final posteId in posteIds) {
    final doc = await FirebaseFirestore.instance
        .collection('territoires')
        .doc(widget.territoireId)
        .collection('spots')
        .doc(posteId)
        .get();

    if (!doc.exists) continue;

    final data = doc.data() ?? {};

    final idSphot = (data['idSphot'] ?? posteId).toString();
    final nomSecours = (data['nomSecours'] ?? '').toString();
    final nomSphot = (data['nomSphot'] ?? '').toString();

    final periodes =
        (data['periodesSurveillance'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];

    final sphotLabel = [
      'SPHOT $idSphot',
      nomSecours,
      nomSphot,
    ].where((value) => value.trim().isNotEmpty).join(' - ');

    widgets.add(
      Text(
        sphotLabel,
        style: const TextStyle(
          color: Color(0xFFDC2626),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    for (final periode in periodes) {
      widgets.add(
        Text(
          periode,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF1E3A8A),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    widgets.add(const SizedBox(height: 4));
  }

  return widgets;
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'data/images/map_background.jpg',
            fit: BoxFit.cover,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  SizedBox(
  height: 56,
  width: double.infinity,
  child: Stack(
    alignment: Alignment.center,
    children: [
      Image.asset(
        'data/icons/title.png',
        height: 56,
        fit: BoxFit.contain,
      ),
      const Positioned(
        right: 0,
        child: AdminProfileButton(),
      ),
    ],
  ),
),
                  const Text(
                    'GESTION DU/DES SAUVETEUR(S)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: actionColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: adminColor,
                          width: 2,
                        ),
                      ),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
    .collection('territoires')
    .doc(widget.territoireId)
    .collection('sauveteurs')
    .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          final docs = snapshot.data!.docs;

                          docs.sort((a, b) {
  final dataA = a.data() as Map<String, dynamic>;
  final dataB = b.data() as Map<String, dynamic>;

  final nomA = (dataA['nom'] ?? '').toString().toUpperCase();
  final nomB = (dataB['nom'] ?? '').toString().toUpperCase();

  final prenomA = (dataA['prenom'] ?? '').toString().toUpperCase();
  final prenomB = (dataB['prenom'] ?? '').toString().toUpperCase();

  final compareNom = nomA.compareTo(nomB);
  if (compareNom != 0) return compareNom;

  return prenomA.compareTo(prenomB);
});

                          if (docs.isEmpty) {
                            return const Center(
                              child: Text(
                                'Aucun sauveteur enregistré',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: adminColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            );
                          }

                          return ListView.separated(
                            itemCount: docs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final doc = docs[index];
final data = doc.data() as Map<String, dynamic>;

final nom = (data['nom'] ?? '').toString();
                              final prenom =
                                  (data['prenom'] ?? '').toString();
                              final telephone =
                                  (data['telephone'] ?? '').toString();
                              final postesAffectes =
    (data['postesAffectes'] as List?)
        ?.cast<String>() ??
    [];

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: adminColor,
                                    width: 2,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.person_rounded,
                                      color: actionColor,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Flexible(
      child: Text(
        '$nom $prenom'.trim().toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFDC2626),
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
    const SizedBox(width: 4),
    IconButton(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AdminCreationSauveteurPage(
              territoireId: widget.territoireId,
              docId: doc.id,
              data: data,
            ),
          ),
        );
      },
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: 24,
        minHeight: 24,
      ),
      icon: const Icon(
        Icons.edit_rounded,
        color: Color(0xFFDC2626),
        size: 18,
      ),
    ),
  ],
),
                                          const SizedBox(height: 3),
                                          Text(
                                            telephone.isEmpty
                                                ? 'Téléphone non renseigné'
                                                : telephone,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF1E3A8A),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          FutureBuilder<List<Widget>>(
  future: _buildSphotLines(postesAffectes),
  builder: (context, sphotSnapshot) {
    if (!sphotSnapshot.hasData) {
      return const Text(
        'Chargement des SPHOT(s)...',
        style: TextStyle(
          color: Color(0xFF1E3A8A),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sphotSnapshot.data!,
    );
  },
),
const SizedBox(height: 8),

Builder(
  builder: (context) {
    final passwordResetDone =
        passwordResetDoneIds.contains(doc.id);

    return SizedBox(
      width: double.infinity,
      height: 34,
      child: ElevatedButton(
        onPressed: passwordResetDone
    ? null
    : () async {
        final newPassword =
            _generateTemporaryPassword();

        await FirebaseFirestore.instance
            .collection('territoires')
            .doc(widget.territoireId)
            .collection('sauveteurs')
            .doc(doc.id)
            .set(
          {
            'temporaryPassword': newPassword,
            'mustChangePassword': true,
            'passwordResetAt':
                FieldValue.serverTimestamp(),
            'updatedAt':
                FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        if (!mounted) return;

        setState(() {
          passwordResetDoneIds.add(doc.id);
        });
      },
        style: ElevatedButton.styleFrom(
          backgroundColor: passwordResetDone
              ? const Color(0xFF1E3A8A)
              : Colors.transparent,
          foregroundColor: passwordResetDone
              ? Colors.white
              : const Color(0xFFDC2626),
          disabledBackgroundColor: const Color(0xFF1E3A8A),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          side: BorderSide(
            color: passwordResetDone
                ? const Color(0xFF1E3A8A)
                : const Color(0xFFDC2626),
            width: 1.6,
          ),
        ),
        child: Text(
          passwordResetDone
              ? 'MOT DE PASSE RÉINITIALISÉ'
              : 'RÉINITIALISER LE MOT DE PASSE',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  },
),

const SizedBox(height: 6),

Builder(
  builder: (context) {

    final isSuspended =
        (data['accountStatus'] ?? '') == 'SUSPENDED';

    return SizedBox(
      width: double.infinity,
      height: 34,
      child: ElevatedButton(
        onPressed: () async {
  final newStatus =
      isSuspended ? 'ACTIVE' : 'SUSPENDED';

  await FirebaseFirestore.instance
      .collection('territoires')
      .doc(widget.territoireId)
      .collection('sauveteurs')
      .doc(doc.id)
      .set(
    {
      'accountStatus': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );
},
        style: ElevatedButton.styleFrom(
          backgroundColor: isSuspended
              ? const Color(0xFFDC2626)
              : Colors.transparent,
          foregroundColor: isSuspended
              ? Colors.white
              : const Color(0xFFDC2626),
          elevation: 0,
          side: const BorderSide(
            color: Color(0xFFDC2626),
            width: 1.6,
          ),
        ),
        child: Text(
          isSuspended
              ? 'SAUVETEUR SUSPENDU'
              : 'SUSPENDRE LE SAUVETEUR',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  },
),
    

const SizedBox(height: 6),

Builder(
  builder: (context) {
    bool confirmDelete = false;

    return StatefulBuilder(
      builder: (context, setDeleteState) {
        return SizedBox(
          width: double.infinity,
          height: 34,
          child: ElevatedButton(
            onPressed: () async {
              if (!confirmDelete) {
                setDeleteState(() {
  confirmDelete = true;
});

Future.delayed(
  const Duration(seconds: 2),
  () {
    if (context.mounted) {
      setDeleteState(() {
        confirmDelete = false;
      });
    }
  },
);

return;
              }

              await FirebaseFirestore.instance
                  .collection('territoires')
                  .doc(widget.territoireId)
                  .collection('sauveteurs')
                  .doc(doc.id)
                  .delete();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: Text(
              confirmDelete
                  ? 'CONFIRMER LA SUPPRESSION'
                  : 'SUPPRIMER LE SAUVETEUR',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      },
    );
  },
),


                                        ],
                                      ),
                                    ),
                                    const SizedBox.shrink(),
                                  ],
                                ),
                                                            
                            );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: adminColor,
                        width: 2,
                      ),
                    ),
                    child: IconButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: adminColor,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}