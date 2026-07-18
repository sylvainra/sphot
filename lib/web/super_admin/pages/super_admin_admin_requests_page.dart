import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SuperAdminAdminRequestsPage extends StatefulWidget {
  const SuperAdminAdminRequestsPage({super.key});

  @override
  State<SuperAdminAdminRequestsPage> createState() =>
      _SuperAdminAdminRequestsPageState();
}

class _SuperAdminAdminRequestsPageState
    extends State<SuperAdminAdminRequestsPage> {
  static const Color adminColor = Color(0xFF1E3A8A);
  static const Color redColor = Color(0xFFDC2626);

  String _statusFilter = 'all';
  String _countryFilter = 'all';
  String _regionFilter = 'all';
  String _departmentFilter = 'all';
  String _cityFilter = 'all';
  String _search = '';

  Future<void> _approveRequest(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
) async {
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

  final subscriptionPreview =
      Map<String, dynamic>.from(data['subscriptionPreview'] ?? {});

  final uid = (data['uid'] ?? doc.id).toString();

  final email = (
    profile['email'] ??
    proConnect['email'] ??
    ''
  ).toString().trim();

  final batch = FirebaseFirestore.instance.batch();

  final adminRef =
      FirebaseFirestore.instance.collection('admins').doc(uid);

  final requestRef = FirebaseFirestore.instance
      .collection('adminRequests')
      .doc(doc.id);

  final subscriptionRef = FirebaseFirestore.instance
      .collection('subscriptions')
      .doc(uid);

  batch.set(
    adminRef,
    {
      'uid': uid,
      'email': email,
      'organisation':
          structure['nom'] ?? proConnect['organisation'] ?? '',
      'siret':
          structure['siret'] ??
          proConnect['siret'] ??
          facturation['billingSiret'] ??
          '',
      'siren':
          structure['siren'] ??
          proConnect['siren'] ??
          '',
      'territoireId': territoire['territoireId'] ?? '',
      'pays': territoire['pays'] ?? '',
      'region': territoire['region'] ?? '',
      'departement': territoire['departement'] ?? '',
      'ville': territoire['ville'] ?? '',
      'role': 'admin',
      'accessStatus': 'approved',
      'configurationAccessGranted': true,
      'configurationAccessOpenedAt':
          FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );

  batch.set(
    subscriptionRef,
    {
      'organisationId': uid,
      'adminUid': uid,

      'billingOrganisation':
          facturation['billingOrganisation'] ??
          structure['nom'] ??
          '',

      'billingSiret':
          facturation['billingSiret'] ??
          structure['siret'] ??
          proConnect['siret'] ??
          '',

      'billingAddress':
          facturation['billingAddress'] ?? '',

      'billingPostalCode':
          facturation['billingPostalCode'] ?? '',

      'billingCity':
          facturation['billingCity'] ??
          territoire['ville'] ??
          '',

      'billingContactName':
          facturation['billingContactName'] ?? '',

      'billingContactEmail':
          facturation['billingContactEmail'] ?? email,

      'purchaseOrderNumber':
          facturation['purchaseOrderNumber'] ?? '',

      'engagementNumber':
          facturation['engagementNumber'] ?? '',

      'chorusServiceCode':
          facturation['chorusServiceCode'] ?? '',

      'numberOfRescueStations': 0,

      'trialDurationDays':
          subscriptionPreview['trialDurationDays'] ?? 8,

      'pricePerStationExclTax':
          subscriptionPreview['pricePerStationExclTax'] ?? 500,

      'billingCycle':
          subscriptionPreview['billingCycle'] ?? 'annual',

      'vatRate':
          subscriptionPreview['vatRate'] ?? 20,

      // L’essai ne commence pas à l’approbation.
      'status': 'awaiting_configuration',
      'trialStartDate': null,
      'trialEndDate': null,
      'trialReadyAt': null,

      'subscriptionStartDate': null,
      'subscriptionEndDate': null,
      'lastPaymentDate': null,
      'nextInvoiceDate': null,

      'country': territoire['pays'] ?? '',
      'region': territoire['region'] ?? '',
      'department': territoire['departement'] ?? '',
      'city': territoire['ville'] ?? '',

      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );

  batch.set(
    requestRef,
    {
      'status': 'approved',
      'accessPhase': 'configuration_access',
      'approvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),

      'administrativeTracking.status': 'approved',
      'administrativeTracking.approvedAt':
          FieldValue.serverTimestamp(),

      'commercialTracking.status':
          'configuration_access_opened',

      'commercialTracking.configurationAccessOpenedAt':
          FieldValue.serverTimestamp(),

      'setupProgress.accessGranted': true,
      'setupProgress.updatedAt':
          FieldValue.serverTimestamp(),

      // La Cloud Function enverra le mail.
      'approvalEmail': {
        'status': 'pending',
        'recipient': email,
        'sentAt': null,
        'messageId': null,
        'error': null,
        'updatedAt': FieldValue.serverTimestamp(),
      },

      'lastEvent': {
        'type': 'admin_request_approved',
        'category': 'administrative',
        'label': 'Demande administrateur approuvée',
        'createdAt': FieldValue.serverTimestamp(),
        'createdByRole': 'super_admin',
      },
    },
    SetOptions(merge: true),
  );

  await batch.commit();

  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Demande approuvée. Le mail d’accès va être envoyé.',
      ),
      backgroundColor: Colors.green,
    ),
  );
}

  Future<void> _rejectRequest(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final uid = (doc.data()['uid'] ?? doc.id).toString();

    final batch = FirebaseFirestore.instance.batch();

    final requestRef =
        FirebaseFirestore.instance.collection('adminRequests').doc(doc.id);
    final adminRef = FirebaseFirestore.instance.collection('admins').doc(uid);
    final subscriptionRef =
        FirebaseFirestore.instance.collection('subscriptions').doc(uid);

    batch.update(
      requestRef,
      {
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );

    batch.set(
      adminRef,
      {
        'uid': uid,
        'accessStatus': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    batch.set(
      subscriptionRef,
      {
        'adminUid': uid,
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Demande refusée.'),
        backgroundColor: redColor,
      ),
    );
  }

  Future<void> _setPending(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final uid = (doc.data()['uid'] ?? doc.id).toString();

    final batch = FirebaseFirestore.instance.batch();

    final requestRef =
        FirebaseFirestore.instance.collection('adminRequests').doc(doc.id);
    final adminRef = FirebaseFirestore.instance.collection('admins').doc(uid);
    final subscriptionRef =
        FirebaseFirestore.instance.collection('subscriptions').doc(uid);

    batch.set(
      requestRef,
      {
        'status': 'pending',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    batch.set(
      adminRef,
      {
        'uid': uid,
        'accessStatus': 'pending',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    batch.set(
      subscriptionRef,
      {
        'adminUid': uid,
        'status': 'pending',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Demande remise en attente.'),
      ),
    );
  }

  String _text(dynamic value) => (value ?? '').toString();

  String _formatTimestamp(Timestamp? timestamp) {
  if (timestamp == null) return '';

  final date = timestamp.toDate();

  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}

  List<String> _uniqueValues(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String key,
  ) {
    final values = docs
        .map((doc) {
          final territoire =
              Map<String, dynamic>.from(doc.data()['territoire'] ?? {});
          return _text(territoire[key]).trim();
        })
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    values.sort();
    return ['all', ...values];
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final filtered = docs.where((doc) {
      final data = doc.data();

      final status = _text(data['status']);
      final proConnect = Map<String, dynamic>.from(data['proConnect'] ?? {});
      final profile = Map<String, dynamic>.from(data['profile'] ?? {});
      final structure = Map<String, dynamic>.from(data['structure'] ?? {});
      final territoire = Map<String, dynamic>.from(data['territoire'] ?? {});
      final facturation = Map<String, dynamic>.from(data['facturation'] ?? {});

      final pays = _text(territoire['pays']);
      final region = _text(territoire['region']);
      final departement = _text(territoire['departement']);
      final ville = _text(territoire['ville']);

      if (_statusFilter != 'all' && status != _statusFilter) return false;
      if (_countryFilter != 'all' && pays != _countryFilter) return false;
      if (_regionFilter != 'all' && region != _regionFilter) return false;
      if (_departmentFilter != 'all' &&
          departement != _departmentFilter) return false;
      if (_cityFilter != 'all' && ville != _cityFilter) return false;

      final searchable = [
        structure['nom'],
        proConnect['organisation'],
        proConnect['siret'],
        proConnect['siren'],
        profile['email'],
        profile['nomAffiche'],
        profile['prenomAffiche'],
        facturation['billingSiret'],
        ville,
        departement,
        region,
        pays,
      ].map(_text).join(' ').toLowerCase();

      return searchable.contains(_search.toLowerCase().trim());
    }).toList();

    filtered.sort((a, b) {
      final ta = Map<String, dynamic>.from(a.data()['territoire'] ?? {});
      final tb = Map<String, dynamic>.from(b.data()['territoire'] ?? {});

      final left = [
        _text(ta['pays']),
        _text(ta['region']),
        _text(ta['departement']),
        _text(ta['ville']),
        _text(a.data()['status']),
      ].join('|');

      final right = [
        _text(tb['pays']),
        _text(tb['region']),
        _text(tb['departement']),
        _text(tb['ville']),
        _text(b.data()['status']),
      ].join('|');

      return left.compareTo(right);
    });

    return filtered;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return redColor;
      default:
        return adminColor;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'APPROUVÉE';
      case 'rejected':
        return 'REFUSÉE';
      default:
        return 'EN ATTENTE';
    }
  }

  Widget _statusButton(String label, String value) {
    final selected = _statusFilter == value;

    return OutlinedButton(
      onPressed: () {
        setState(() {
          _statusFilter = value;
        });
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? adminColor : Colors.transparent,
        foregroundColor: selected ? Colors.white : adminColor,
        side: const BorderSide(color: adminColor, width: 1.4),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _filterDropdown({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String> onChanged,
  }) {
    return Expanded(
      child: DropdownButtonFormField<String>(
        value: values.contains(value) ? value : 'all',
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: adminColor,
            fontWeight: FontWeight.w700,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        items: values.map((item) {
          return DropdownMenuItem(
            value: item,
            child: Text(
              item == 'all' ? 'Tous' : item,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (newValue) {
          if (newValue == null) return;
          onChanged(newValue);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('adminRequests')
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
          return const Center(child: CircularProgressIndicator());
        }

        final allRequests = snapshot.data!.docs;
        final requests = _filteredDocs(allRequests);

        final totalCount = allRequests.length;

final pendingCount = allRequests.where((doc) {
  return doc.data()['status'] == 'pending';
}).length;

final approvedCount = allRequests.where((doc) {
  return doc.data()['status'] == 'approved';
}).length;

final rejectedCount = allRequests.where((doc) {
  return doc.data()['status'] == 'rejected';
}).length;

        final paysValues = _uniqueValues(allRequests, 'pays');
        final regionValues = _uniqueValues(allRequests, 'region');
        final departmentValues = _uniqueValues(allRequests, 'departement');
        final cityValues = _uniqueValues(allRequests, 'ville');

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    children: [
                      _statusButton('TOUTES ($totalCount)', 'all'),
                      const SizedBox(width: 8),
                      _statusButton('EN ATTENTE ($pendingCount)', 'pending'),
                      const SizedBox(width: 8),
                      _statusButton('APPROUVÉES ($approvedCount)', 'approved'),
                      const SizedBox(width: 8),
                      _statusButton('REFUSÉES ($rejectedCount)', 'rejected'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _filterDropdown(
                        label: 'Pays',
                        value: _countryFilter,
                        values: paysValues,
                        onChanged: (value) {
                          setState(() {
                            _countryFilter = value;
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      _filterDropdown(
                        label: 'Région',
                        value: _regionFilter,
                        values: regionValues,
                        onChanged: (value) {
                          setState(() {
                            _regionFilter = value;
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      _filterDropdown(
                        label: 'Département',
                        value: _departmentFilter,
                        values: departmentValues,
                        onChanged: (value) {
                          setState(() {
                            _departmentFilter = value;
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      _filterDropdown(
                        label: 'Commune',
                        value: _cityFilter,
                        values: cityValues,
                        onChanged: (value) {
                          setState(() {
                            _cityFilter = value;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (value) {
                      setState(() {
                        _search = value;
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Recherche organisation, SIRET, email, commune...',
                      labelStyle: const TextStyle(
                        color: adminColor,
                        fontWeight: FontWeight.w700,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: adminColor,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: requests.isEmpty
                  ? const Center(
                      child: Text(
                        'Aucune demande ne correspond aux filtres.',
                        style: TextStyle(
                          color: adminColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      itemCount: requests.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final doc = requests[index];
                        final data = doc.data();

                        final status = _text(data['status']);
                        final proConnect = Map<String, dynamic>.from(
                            data['proConnect'] ?? {});
                        final profile =
                            Map<String, dynamic>.from(data['profile'] ?? {});
                        final structure =
                            Map<String, dynamic>.from(data['structure'] ?? {});
                        final territoire =
                            Map<String, dynamic>.from(data['territoire'] ?? {});
                        final facturation =
                            Map<String, dynamic>.from(data['facturation'] ?? {});

                            final subscriptionPreview =
    Map<String, dynamic>.from(
  data['subscriptionPreview'] ?? {},
);

                            final requestedAt = data['requestedAt'] as Timestamp?;
final approvedAt = data['approvedAt'] as Timestamp?;
final rejectedAt = data['rejectedAt'] as Timestamp?;

                        return Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _statusColor(status),
                              width: 1.8,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      structure['nom']
                                                  ?.toString()
                                                  .isNotEmpty ==
                                              true
                                          ? structure['nom'].toString()
                                          : 'Structure non renseignée',
                                      style: const TextStyle(
                                        color: redColor,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _statusColor(status),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: Text(
                                      _statusLabel(status),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
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
                                'Territoire : ${territoire['pays'] ?? ''} / ${territoire['region'] ?? ''} / ${territoire['departement'] ?? ''} / ${territoire['ville'] ?? ''}',
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

const SizedBox(height: 8),

Text(
  'Demandée le : ${_formatTimestamp(requestedAt)}',
  style: const TextStyle(
    color: adminColor,
    fontWeight: FontWeight.w600,
  ),
),

if (approvedAt != null)
  Text(
    'Approuvée le : ${_formatTimestamp(approvedAt)}',
    style: const TextStyle(
      color: Colors.green,
      fontWeight: FontWeight.w700,
    ),
  ),

if (rejectedAt != null)
  Text(
    'Refusée le : ${_formatTimestamp(rejectedAt)}',
    style: const TextStyle(
      color: redColor,
      fontWeight: FontWeight.w700,
    ),
  ),

const SizedBox(height: 8),

Text(
  'Essai gratuit : ${subscriptionPreview['trialDurationDays'] ?? 8} jours',
  style: const TextStyle(
    color: adminColor,
    fontWeight: FontWeight.w600,
  ),
),

Text(
  'Tarif estimé : ${subscriptionPreview['pricePerStationExclTax'] ?? 500} € HT / poste / an',
  style: const TextStyle(
    color: adminColor,
    fontWeight: FontWeight.w700,
  ),
),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _approveRequest(context, doc),
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
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _rejectRequest(context, doc),
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
                                  OutlinedButton.icon(
                                    onPressed: () => _setPending(context, doc),
                                    icon: const Icon(
                                      Icons.pending_actions_outlined,
                                      color: adminColor,
                                    ),
                                    label: const Text(
                                      'REMETTRE EN ATTENTE',
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
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}