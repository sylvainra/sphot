import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminRequestsPage extends StatelessWidget {
  const AdminRequestsPage({super.key});

  static const Color adminColor = Color(0xFF1E3A8A);
  static const Color redColor = Color(0xFFDC2626);

  Future<void> _approveRequest(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();

    final proConnect =
        Map<String, dynamic>.from(data['proConnect'] ?? {});
    final profile = Map<String, dynamic>.from(data['profile'] ?? {});
    final structure = Map<String, dynamic>.from(data['structure'] ?? {});
    final territoire = Map<String, dynamic>.from(data['territoire'] ?? {});
    final facturation =
        Map<String, dynamic>.from(data['facturation'] ?? {});
    final subscriptionPreview =
        Map<String, dynamic>.from(data['subscriptionPreview'] ?? {});

    final uid = (data['uid'] ?? doc.id).toString();

    final batch = FirebaseFirestore.instance.batch();

    final adminRef =
        FirebaseFirestore.instance.collection('admins').doc(uid);

    final requestRef =
        FirebaseFirestore.instance.collection('adminRequests').doc(doc.id);

    final subscriptionRef =
        FirebaseFirestore.instance.collection('subscriptions').doc(uid);

    batch.set(
      adminRef,
      {
        'uid': uid,
        'email': profile['email'] ?? proConnect['email'] ?? '',
        'organisation': structure['nom'] ?? proConnect['organisation'] ?? '',
        'siret': proConnect['siret'] ?? facturation['billingSiret'] ?? '',
        'siren': proConnect['siren'] ?? '',
        'territoireId': territoire['territoireId'] ?? '',
        'role': 'admin',
        'accessStatus': 'approved',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    batch.set(
      subscriptionRef,
      {
        'organisationId': uid,
        'adminUid': uid,
        'billingOrganisation': facturation['billingOrganisation'] ?? '',
        'billingSiret': facturation['billingSiret'] ??
            proConnect['siret'] ??
            '',
        'billingAddress': facturation['billingAddress'] ?? '',
        'billingPostalCode': facturation['billingPostalCode'] ?? '',
        'billingCity': facturation['billingCity'] ?? '',
        'billingContactName': facturation['billingContactName'] ?? '',
        'billingContactEmail': facturation['billingContactEmail'] ?? '',
        'purchaseOrderNumber': facturation['purchaseOrderNumber'] ?? '',
        'engagementNumber': facturation['engagementNumber'] ?? '',
        'chorusServiceCode': facturation['chorusServiceCode'] ?? '',
        'numberOfRescueStations':
            facturation['numberOfRescueStations'] ?? 0,
        'trialDurationDays':
            subscriptionPreview['trialDurationDays'] ?? 8,
        'pricePerStationExclTax':
            subscriptionPreview['pricePerStationExclTax'] ?? 500,
        'billingCycle': subscriptionPreview['billingCycle'] ?? 'annual',
        'vatRate': subscriptionPreview['vatRate'] ?? 20,
        'status': 'trial',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    batch.update(
      requestRef,
      {
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );

    try {
  await batch.commit();

  debugPrint('===== APPROVAL SUCCESS =====');

  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Demande approuvée.'),
      backgroundColor: Colors.green,
    ),
  );
} catch (e, stackTrace) {
  debugPrint('===== APPROVAL ERROR =====');
  debugPrint(e.toString());
  debugPrint(stackTrace.toString());

  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Colors.red,
      content: Text('Erreur : $e'),
      duration: const Duration(seconds: 8),
    ),
  );
}
  }

  Future<void> _rejectRequest(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    await FirebaseFirestore.instance
        .collection('adminRequests')
        .doc(doc.id)
        .update({
      'status': 'rejected',
      'rejectedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Demande refusée.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('adminRequests')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Erreur de chargement des demandes.',
              style: TextStyle(
                color: redColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final requests = snapshot.data!.docs;

        if (requests.isEmpty) {
          return const Center(
            child: Text(
              'Aucune demande admin en attente.',
              style: TextStyle(
                color: adminColor,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc = requests[index];
            final data = doc.data();

            final proConnect =
                Map<String, dynamic>.from(data['proConnect'] ?? {});
            final profile =
                Map<String, dynamic>.from(data['profile'] ?? {});
            final structure =
                Map<String, dynamic>.from(data['structure'] ?? {});
            final territoire =
                Map<String, dynamic>.from(data['territoire'] ?? {});
            final facturation =
                Map<String, dynamic>.from(data['facturation'] ?? {});

            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: adminColor,
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    structure['nom']?.toString().isNotEmpty == true
                        ? structure['nom'].toString()
                        : 'Structure non renseignée',
                    style: const TextStyle(
                      color: redColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${profile['prenomAffiche'] ?? ''} ${profile['nomAffiche'] ?? ''}',
                    style: const TextStyle(
                      color: adminColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Email : ${profile['email'] ?? proConnect['email'] ?? ''}',
                    style: const TextStyle(
                      color: adminColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Fonction : ${profile['fonction'] ?? ''}',
                    style: const TextStyle(
                      color: adminColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Territoire : ${territoire['ville'] ?? ''} - ${territoire['departement'] ?? ''}',
                    style: const TextStyle(
                      color: adminColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'SIRET : ${proConnect['siret'] ?? facturation['billingSiret'] ?? ''}',
                    style: const TextStyle(
                      color: adminColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Postes de secours : ${facturation['numberOfRescueStations'] ?? 0}',
                    style: const TextStyle(
                      color: adminColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _approveRequest(context, doc),
                        icon: const Icon(
                          Icons.check_circle_outline,
                          color: adminColor,
                        ),
                        label: const Text(
                          'APPROUVER',
                          style: TextStyle(
                            color: adminColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: adminColor,
                            width: 1.6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => _rejectRequest(context, doc),
                        icon: const Icon(
                          Icons.cancel_outlined,
                          color: redColor,
                        ),
                        label: const Text(
                          'REFUSER',
                          style: TextStyle(
                            color: redColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: redColor,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}