import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_controle_sphot_page.dart';

class AdminGestionSphotPage extends StatelessWidget {
  const AdminGestionSphotPage({super.key});

  static const Color pageColor = Color(0xFF16A34A);

  String _sphotTitle(Map<String, dynamic> data, String docId) {
    final nomSecours = (data['nomSecours'] ?? '').toString();
    final nomSphot = (data['nomSphot'] ?? '').toString();

    final title = [nomSecours, nomSphot]
        .where((value) => value.trim().isNotEmpty)
        .join(' - ');

    return title.isEmpty ? docId : title;
  }

  bool _isValidated(Map<String, dynamic> data) {
    return data['sphotValide'] == true;
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
                  Image.asset(
                    'data/icons/title.png',
                    height: 56,
                    fit: BoxFit.contain,
                  ),
                  const Text(
                    'GESTION DU/DES SPHOT(S)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFDC2626),
                      letterSpacing: 0.6,
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
        color: const Color(0xFF1E3A8A),
        width: 2,
      ),
    ),
    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('spots')
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

                          final secoursA =
                              (dataA['nomSecours'] ?? '').toString();
                          final secoursB =
                              (dataB['nomSecours'] ?? '').toString();

                          final matchA =
                              RegExp(r'(\d+)').firstMatch(secoursA);
                          final matchB =
                              RegExp(r'(\d+)').firstMatch(secoursB);

                          final numA =
                              int.tryParse(matchA?.group(1) ?? '9999') ?? 9999;
                          final numB =
                              int.tryParse(matchB?.group(1) ?? '9999') ?? 9999;

                          return numA.compareTo(numB);
                        });

                        if (docs.isEmpty) {
                          return const Center(
  child: Text(
    'Aucun SPHOT créé',
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: Color(0xFF1E3A8A),
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
                            final validated = _isValidated(data);
                            final title = _sphotTitle(data, doc.id);
                            final ville = (data['ville'] ?? '').toString();
                            final typeSphot =
                                (data['typeSphot'] ?? '').toString();

                            return GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => AdminControleSphotPage(
                                      docId: doc.id,
                                      data: data,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
  color: Colors.transparent,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(
    color: const Color(0xFF1E3A8A),
    width: 2,
  ),
),
                                child: Row(
                                  children: [
                                    Icon(
  validated
      ? Icons.check_circle_rounded
      : Icons.circle_rounded,
  color: validated
      ? const Color(0xFFDC2626)
      : const Color(0xFF1E3A8A),
  size: 28,
),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title.toUpperCase(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Color(0xFF1E3A8A),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            ville.isEmpty
                                                ? 'Ville non renseignée'
                                                : ville,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            typeSphot.isEmpty
                                                ? 'Type non renseigné'
                                                : typeSphot,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    IconButton(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AdminControleSphotPage(
              docId: doc.id,
              data: data,
            ),
          ),
        );
      },
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: 32,
        minHeight: 28,
      ),
      icon: const Icon(
        Icons.edit_rounded,
        color: Color(0xFFDC2626),
        size: 22,
      ),
    ),
    IconButton(
      onPressed: () async {
        await FirebaseFirestore.instance
            .collection('spots')
            .doc(doc.id)
            .delete();
      },
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: 32,
        minHeight: 28,
      ),
      icon: const Icon(
        Icons.delete_rounded,
        color: Color(0xFFDC2626),
        size: 22,
      ),
    ),
  ],
),
                                  ],
                                ),
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
                        color: const Color(0xFF1E3A8A),
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
                        color: const Color(0xFF1E3A8A),
                        size: 22,
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