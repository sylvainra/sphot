import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SuperAdminAdminWorkflowPanel extends StatelessWidget {
  static const Color _blue = Color(0xFF1E3A8A);
  static const Color _red = Color(0xFFDC2626);
  static const Color _green = Color(0xFF16A34A);
  static const Color _orange = Color(0xFFF59E0B);
  static const double _pricePerStationExclTax = 500.0;

  final Map<String, dynamic> adminData;

  const SuperAdminAdminWorkflowPanel({
    super.key,
    required this.adminData,
  });

  String _text(dynamic value) => value?.toString().trim() ?? '';

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  String get _requestId => _text(
        adminData['requestId'] ??
            adminData['uid'] ??
            adminData['_docId'],
      );

  String _formatDateTime(dynamic value) {
    DateTime? date;
    if (value is Timestamp) date = value.toDate();
    if (value is DateTime) date = value;
    if (value is String && value.isNotEmpty) {
      date ??= DateTime.tryParse(value);
    }
    if (date == null) return '—';
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$d/$m/${date.year} à ${h}h$min';
  }

  String _formatMoney(dynamic value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(_text(value).replaceAll(',', '.')) ?? 0;
    return '${number.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'trial':
      case 'active':
      case 'sent':
        return _green;
      case 'pending':
      case 'submitted':
      case 'order_pending':
        return _orange;
      case 'expired':
      case 'rejected':
      case 'awaiting_subscription':
      case 'awaiting_renewal':
        return _red;
      default:
        return _blue;
    }
  }

  String _trialStatusLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'pending':
        return 'En attente de validation';
      case 'approved':
      case 'trial':
        return 'Validée / en cours';
      case 'expired':
        return 'Terminée';
      case 'rejected':
        return 'Refusée';
      default:
        return raw.isEmpty ? 'Non demandée' : raw;
    }
  }

  Widget _section({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _blue.withOpacity(0.045),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _blue.withOpacity(0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _red,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              '$label :',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusLine(String label, String status, String display) {
    final color = _statusColor(status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              '$label :',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: color.withOpacity(0.55)),
            ),
            child: Text(
              display,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmTrial(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text(
              'VALIDER LA PÉRIODE D’ESSAI',
              style: TextStyle(
                color: _blue,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: const Text(
              'Cette action démarre immédiatement la période d’essai gratuite '
              'SPHOT ADMIN de 8 jours et ouvre les droits de diffusion.',
              style: TextStyle(
                color: _blue,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('ANNULER'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('VALIDER L’ESSAI'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _approveTrial(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> requestSnapshot,
    Map<String, dynamic> subscription,
  ) async {
    if (!await _confirmTrial(context)) return;

    final data = requestSnapshot.data() ?? const <String, dynamic>{};
    final trialRequest = _map(data['trialRequest']);
    final profile = _map(data['profile']);
    final proConnect = _map(data['proConnect']);
    final uid = _text(data['uid'] ?? requestSnapshot.id);
    final territoire = _map(data['territoire']);
    final territoireId = _text(
      data['territoireId'] ?? territoire['territoireId'],
    );
    final email = _text(profile['email'] ?? proConnect['email'] ?? data['email']);
    final duration = (trialRequest['trialDurationDays'] is num)
        ? (trialRequest['trialDurationDays'] as num).toInt()
        : 8;
    final numberOfStations = (trialRequest['numberOfRescueStations'] is num)
        ? (trialRequest['numberOfRescueStations'] as num).toInt()
        : (subscription['numberOfRescueStations'] is num)
            ? (subscription['numberOfRescueStations'] as num).toInt()
            : 0;

    final start = DateTime.now();
    final end = start.add(Duration(days: duration));
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    final serverNow = FieldValue.serverTimestamp();

    batch.set(
      requestSnapshot.reference,
      <String, dynamic>{
        'trialRequestStatus': 'approved',
        'accessPhase': 'trial_active',
        'trialRequest.status': 'approved',
        'trialRequest.approvedAt': serverNow,
        'trialTracking.status': 'approved',
        'trialTracking.approvedAt': serverNow,
        'trialTracking.approvedByRole': 'super_admin',
        'commercialTracking.status': 'trial_active',
        'commercialTracking.trialActivatedAt': serverNow,
        'trialApprovalEmail': <String, dynamic>{
          'status': 'pending',
          'recipient': email,
          'sentAt': null,
          'messageId': null,
          'error': null,
          'updatedAt': serverNow,
        },
        'lastEvent': <String, dynamic>{
          'type': 'trial_approved',
          'category': 'commercial',
          'label': 'Période d’essai SPHOT ADMIN validée',
          'createdAt': serverNow,
          'createdByRole': 'super_admin',
        },
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    batch.set(
      db.collection('subscriptions').doc(uid),
      <String, dynamic>{
        'adminUid': uid,
        'status': 'trial',
        'trialDurationDays': duration,
        'trialStartDate': Timestamp.fromDate(start),
        'trialEndDate': Timestamp.fromDate(end),
        'numberOfRescueStations': numberOfStations,
        'pricePerStationExclTax': subscription['pricePerStationExclTax'] ??
            _pricePerStationExclTax,
        'billingCycle': 'annual',
        'vatRate': subscription['vatRate'] ?? 20,
        'trialActivatedAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    batch.set(
      db.collection('admins').doc(uid),
      <String, dynamic>{
        'uid': uid,
        if (territoireId.isNotEmpty) 'territoireId': territoireId,
        'accessStatus': 'approved',
        'diffusionAccessGranted': true,
        'diffusionAccessOpenedAt': serverNow,
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    await batch.commit();

    if (!context.mounted) return;
  }

  Future<void> _approveOrder(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> order,
  ) async {
    final data = order.data();
    final paymentMethod = _text(data['paymentMethod']);
    if (paymentMethod == 'card' && _text(data['paymentStatus']) != 'paid') {
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text(
              'APPROUVER LA COMMANDE',
              style: TextStyle(color: _blue, fontWeight: FontWeight.w900),
            ),
            content: Text(
              'Confirmer la commande ${_text(data['orderNumber'])}. '
              'L’abonnement annuel sera activé et les droits de diffusion seront ouverts.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('ANNULER'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('APPROUVER'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    await order.reference.set(
      <String, dynamic>{
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedByRole': 'super_admin',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  String _documentRubricKey(Map<String, dynamic> data) {
    final subcategory = _text(data['subcategory']).toLowerCase();
    final type = _text(data['documentType']).toLowerCase();

    if (subcategory == 'inscription' ||
        type.contains('registration') ||
        type.contains('access')) {
      return 'access';
    }

    if (subcategory == 'essai' || type.contains('trial')) {
      return 'trial';
    }

    if (subcategory == 'commandes' ||
        subcategory == 'abonnement' ||
        type.contains('subscription') ||
        type.contains('order')) {
      return 'subscription';
    }

    if (subcategory == 'factures' ||
        subcategory == 'facturation' ||
        type.contains('invoice') ||
        type.contains('billing')) {
      return 'billing';
    }

    if (subcategory == 'renouvellement' ||
        type.contains('renewal') ||
        type.contains('renew')) {
      return 'renewal';
    }

    if (subcategory == 'administrateurs' ||
        subcategory == 'administrateur' ||
        type.contains('admin_change') ||
        type.contains('administrator_change') ||
        type.contains('replacement') ||
        type.contains('revocation')) {
      return 'admins';
    }

    return 'access';
  }

  int _compareDocumentsByReference(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final aData = a.data();
    final bData = b.data();
    final aNumber = _text(aData['documentNumber']);
    final bNumber = _text(bData['documentNumber']);

    if (aNumber.isNotEmpty && bNumber.isNotEmpty) {
      final referenceCompare = aNumber.compareTo(bNumber);
      if (referenceCompare != 0) return referenceCompare;
    }

    final aRawDate = aData['issuedAt'] ?? aData['createdAt'];
    final bRawDate = bData['issuedAt'] ?? bData['createdAt'];
    final aDate = aRawDate is Timestamp ? aRawDate.toDate() : DateTime(1970);
    final bDate = bRawDate is Timestamp ? bRawDate.toDate() : DateTime(1970);
    return aDate.compareTo(bDate);
  }

  Widget _documentRubric({
    required String title,
    required IconData icon,
    required List<Widget> children,
    required int documentCount,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _blue.withOpacity(0.18)),
      ),
      child: Theme(
        data: ThemeData(
          dividerColor: Colors.transparent,
          colorScheme: ColorScheme.fromSeed(seedColor: _blue),
        ),
        child: ExpansionTile(
          initiallyExpanded: documentCount > 0,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          leading: Icon(icon, color: _red, size: 21),
          title: Text(
            title,
            style: const TextStyle(
              color: _blue,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: documentCount > 0
                      ? _blue.withOpacity(0.08)
                      : Colors.grey.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$documentCount',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: documentCount > 0 ? _blue : Colors.black45,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.expand_more_rounded,
                color: _blue,
                size: 19,
              ),
            ],
          ),
          children: children.isEmpty
              ? const [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: Text(
                        'Aucun document émis à ce stade.',
                        style: TextStyle(
                          color: Colors.black45,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ]
              : children,
        ),
      ),
    );
  }

  Widget _documents(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> requestSnapshot,
  ) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('documents')
          .where('requestId', isEqualTo: requestSnapshot.id)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs.toList() ??
            <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        final requestData = requestSnapshot.data() ?? const <String, dynamic>{};
        final legacy = _map(requestData['acknowledgementDocument']);
        final hasLegacyInRegistry = docs.any(
          (doc) =>
              _text(doc.data()['documentType']) ==
              'registration_acknowledgement',
        );

        if (snapshot.connectionState == ConnectionState.waiting &&
            docs.isEmpty &&
            _text(legacy['downloadUrl']).isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final grouped =
            <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{
          'access': [],
          'trial': [],
          'subscription': [],
          'billing': [],
          'renewal': [],
          'admins': [],
        };

        for (final doc in docs) {
          final key = _documentRubricKey(doc.data());
          grouped.putIfAbsent(key, () => []).add(doc);
        }

        for (final values in grouped.values) {
          values.sort(_compareDocumentsByReference);
        }

        final accessChildren = <Widget>[
          for (final doc in grouped['access']!)
            _documentTile(
              context,
              title: _text(doc.data()['title']).isEmpty
                  ? _text(doc.data()['documentType'])
                  : _text(doc.data()['title']),
              number: _text(doc.data()['documentNumber']),
              date: _formatDateTime(
                doc.data()['issuedAt'] ?? doc.data()['createdAt'],
              ),
              status: _text(doc.data()['status']),
              url: _text(doc.data()['downloadUrl']),
            ),
        ];

        if (!hasLegacyInRegistry &&
            _text(legacy['downloadUrl']).isNotEmpty) {
          accessChildren.insert(
            0,
            _documentTile(
              context,
              title:
                  'Accusé de réception de la demande d’accès administrateur',
              number:
                  '${_text(requestData['requestNumber'])}-INS-AR-01',
              date: _formatDateTime(
                legacy['generatedAt'] ?? requestData['requestedAt'],
              ),
              status: 'issued',
              url: _text(legacy['downloadUrl']),
            ),
          );
        }

        List<Widget> tilesFor(String key) {
          return grouped[key]!
              .map(
                (doc) => _documentTile(
                  context,
                  title: _text(doc.data()['title']).isEmpty
                      ? _text(doc.data()['documentType'])
                      : _text(doc.data()['title']),
                  number: _text(doc.data()['documentNumber']),
                  date: _formatDateTime(
                    doc.data()['issuedAt'] ?? doc.data()['createdAt'],
                  ),
                  status: _text(doc.data()['status']),
                  url: _text(doc.data()['downloadUrl']),
                ),
              )
              .toList();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Historique documentaire du dossier',
              style: TextStyle(
                color: _blue,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Documents conservés par rubrique et classés '
              'historiquement par référence.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            _documentRubric(
              title: '1 — DEMANDE D’ACCÈS',
              icon: Icons.assignment_ind_outlined,
              children: accessChildren,
              documentCount: accessChildren.length,
            ),
            _documentRubric(
              title: '2 — PÉRIODE D’ESSAI',
              icon: Icons.hourglass_bottom_rounded,
              children: tilesFor('trial'),
              documentCount: grouped['trial']!.length,
            ),
            _documentRubric(
              title: '3 — ABONNEMENT',
              icon: Icons.fact_check_outlined,
              children: tilesFor('subscription'),
              documentCount: grouped['subscription']!.length,
            ),
            _documentRubric(
              title: '4 — FACTURATION',
              icon: Icons.receipt_long_outlined,
              children: tilesFor('billing'),
              documentCount: grouped['billing']!.length,
            ),
            _documentRubric(
              title: '5 — RENOUVELLEMENT',
              icon: Icons.autorenew_rounded,
              children: tilesFor('renewal'),
              documentCount: grouped['renewal']!.length,
            ),
            _documentRubric(
              title: '6 — CHANGEMENTS D’ADMINISTRATEUR',
              icon: Icons.manage_accounts_outlined,
              children: tilesFor('admins'),
              documentCount: grouped['admins']!.length,
            ),
          ],
        );
      },
    );
  }

  Widget _documentTile(
    BuildContext context, {
    required String title,
    required String number,
    required String date,
    required String status,
    required String url,
  }) {
    final normalizedStatus = status.toLowerCase();

    final statusLabel = switch (normalizedStatus) {
      'issued' => 'ÉMIS',
      'generated' => 'ÉMIS',
      'approved' => 'VALIDÉ',
      'validated' => 'VALIDÉ',
      'pending' => 'EN ATTENTE',
      'replaced' => 'REMPLACÉ',
      'cancelled' => 'ANNULÉ',
      _ => status.isEmpty ? '' : status.toUpperCase(),
    };

    final statusColor = switch (normalizedStatus) {
      'approved' || 'validated' => _green,
      'pending' => _orange,
      'replaced' || 'cancelled' => Colors.black54,
      _ => _blue,
    };

    return Container(
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _blue.withOpacity(0.025),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _blue.withOpacity(0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.description_outlined,
              color: _blue,
              size: 21,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                if (number.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    number,
                    style: const TextStyle(
                      color: _red,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
                if (date != '—') ...[
                  const SizedBox(height: 3),
                  Text(
                    date,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (statusLabel.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: statusColor.withOpacity(0.55),
                      ),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (url.isNotEmpty)
            TextButton(
              onPressed: () async {
                final uri = Uri.tryParse(url);
                if (uri == null) return;
                await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
              },
              child: const Text(
                'VOIR',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_requestId.isEmpty) {
      return _section(
        title: 'SUIVI ADMINISTRATIF',
        children: const [
          Text(
            'Identifiant de dossier introuvable.',
            style: TextStyle(color: _red, fontWeight: FontWeight.w700),
          ),
        ],
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('adminRequests')
          .doc(_requestId)
          .snapshots(),
      builder: (context, requestSnapshotAsync) {
        if (!requestSnapshotAsync.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final requestSnapshot = requestSnapshotAsync.data!;
        final request = requestSnapshot.data() ?? adminData;
        final uid = _text(request['uid'] ?? requestSnapshot.id);
        final administrativeTracking = _map(request['administrativeTracking']);
        final trialTracking = _map(request['trialTracking']);
        final trialRequest = _map(request['trialRequest']);
        final registrationStatus = _text(
          request['status'] ?? administrativeTracking['status'],
        );
        final trialStatus = _text(
          request['trialRequestStatus'] ??
              trialTracking['status'] ??
              trialRequest['status'],
        );

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('subscriptions')
              .doc(uid)
              .snapshots(),
          builder: (context, subscriptionAsync) {
            final subscription = subscriptionAsync.data?.data() ??
                const <String, dynamic>{};

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('orders')
                  .where('requestId', isEqualTo: requestSnapshot.id)
                  .snapshots(),
              builder: (context, orderAsync) {
                final orders = orderAsync.data?.docs.toList() ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                orders.sort((a, b) {
                  final ad = a.data()['createdAt'];
                  final bd = b.data()['createdAt'];
                  final aDate = ad is Timestamp ? ad.toDate() : DateTime(1970);
                  final bDate = bd is Timestamp ? bd.toDate() : DateTime(1970);
                  return bDate.compareTo(aDate);
                });
                final latestOrder = orders.isEmpty ? null : orders.first;
                final latestOrderData = latestOrder?.data() ??
                    const <String, dynamic>{};

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _section(
                      title: 'INSCRIPTION ADMINISTRATEUR',
                      children: [
                        _line(
                          'Référence',
                          _text(request['requestNumber']).isEmpty
                              ? 'Non renseignée'
                              : _text(request['requestNumber']),
                        ),
                        _statusLine(
                          'Statut',
                          registrationStatus,
                          registrationStatus.toLowerCase() == 'approved'
                              ? 'Approuvée'
                              : registrationStatus.toLowerCase() == 'pending'
                                  ? 'En attente'
                                  : registrationStatus.isEmpty
                                      ? 'Non renseigné'
                                      : registrationStatus,
                        ),
                        _line(
                          'Demande reçue',
                          _formatDateTime(request['requestedAt']),
                        ),
                        _line(
                          'Validée le',
                          _formatDateTime(
                            administrativeTracking['approvedAt'] ??
                                request['approvedAt'],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _section(
                      title: 'PÉRIODE D’ESSAI',
                      children: [
                        _line(
                          'Durée',
                          '${trialRequest['trialDurationDays'] ?? 8} jours',
                        ),
                        _statusLine(
                          'Statut',
                          trialStatus,
                          _trialStatusLabel(trialStatus),
                        ),
                        _line(
                          'Demande reçue',
                          _formatDateTime(
                            trialTracking['requestedAt'] ??
                                request['trialRequestedAt'] ??
                                trialRequest['requestedAt'],
                          ),
                        ),
                        _line(
                          'Validée le',
                          _formatDateTime(trialTracking['approvedAt']),
                        ),
                        _line(
                          'Début',
                          _formatDateTime(subscription['trialStartDate']),
                        ),
                        _line(
                          'Fin',
                          _formatDateTime(subscription['trialEndDate']),
                        ),
                        _line(
                          'Diffusion',
                          trialStatus.toLowerCase() == 'approved' ||
                                  _text(subscription['status']) == 'trial'
                              ? 'Autorisée'
                              : 'Non autorisée',
                        ),
                        if (registrationStatus.toLowerCase() == 'approved' &&
                            trialStatus.toLowerCase() == 'pending') ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _approveTrial(
                                context,
                                requestSnapshot,
                                subscription,
                              ),
                              icon: const Icon(Icons.play_circle_fill_rounded),
                              label: const Text(
                                'VALIDER LA PÉRIODE D’ESSAI',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (latestOrder != null) ...[
                      const SizedBox(height: 10),
                      _section(
                        title: 'COMMANDE / ABONNEMENT',
                        children: [
                          _line(
                            'Commande',
                            _text(latestOrderData['orderNumber']).isEmpty
                                ? 'Numérotation en cours'
                                : _text(latestOrderData['orderNumber']),
                          ),
                          _statusLine(
                            'Statut',
                            _text(latestOrderData['status']),
                            _text(latestOrderData['status']).isEmpty
                                ? 'Non renseigné'
                                : _text(latestOrderData['status']),
                          ),
                          _line(
                            'Montant HT',
                            _formatMoney(latestOrderData['totalExclTax']),
                          ),
                          _line(
                            'Mode',
                            _text(latestOrderData['paymentMethod']) == 'card'
                                ? 'Carte bancaire'
                                : 'Facturation publique / Chorus Pro',
                          ),
                          if (_text(latestOrderData['status']) == 'submitted') ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _approveOrder(context, latestOrder),
                                icon: const Icon(Icons.verified_rounded),
                                label: const Text(
                                  'APPROUVER LA COMMANDE',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    _section(
                      title: 'DOCUMENTS DU DOSSIER',
                      children: [
                        _documents(context, requestSnapshot),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
