import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminSubscriptionPanel extends StatefulWidget {
  final String adminUid;
  final VoidCallback onClose;

  const AdminSubscriptionPanel({
    super.key,
    required this.adminUid,
    required this.onClose,
  });

  @override
  State<AdminSubscriptionPanel> createState() =>
      _AdminSubscriptionPanelState();
}

class _AdminSubscriptionPanelState extends State<AdminSubscriptionPanel> {
  static const Color _blue = Color(0xFF1E3A8A);
  static const Color _red = Color(0xFFDC2626);
  static const Color _grey = Color(0xFF6B7280);
  static const Color _green = Color(0xFF16A34A);
  static const Color _orange = Color(0xFFF59E0B);
  static const double _fallbackAnnualPricePerStationExclTax = 500.0;

  final Map<String, String> _draft = <String, String>{};
  final Set<String> _expandedSections = <String>{};

  String? _savingSection;
  bool? _draftNoOrderRequired;
  late final Stream<Map<String, dynamic>> _dataStream;
  late final Future<String> _territoireIdFuture;
  final Set<String> _selectedRescueStationIds = <String>{};
  bool _offerSelectionInitialized = false;

  @override
  void initState() {
    super.initState();
    _dataStream = _subscriptionDataStream();
    _territoireIdFuture = _resolveTerritoireId();
  }

  String get _uid => widget.adminUid.trim();

  DocumentReference<Map<String, dynamic>> get _subscriptionReference =>
      FirebaseFirestore.instance.collection('subscriptions').doc(_uid);

  DocumentReference<Map<String, dynamic>> get _adminRequestReference =>
      FirebaseFirestore.instance.collection('adminRequests').doc(_uid);

  DocumentReference<Map<String, dynamic>> get _adminReference =>
      FirebaseFirestore.instance.collection('admins').doc(_uid);

  String _text(dynamic value) => value?.toString().trim() ?? '';

  Future<String> _resolveTerritoireId() async {
    if (_uid.isEmpty) return '';

    final requestSnapshot = await _adminRequestReference.get();
    Map<String, dynamic>? adminData = requestSnapshot.data();

    if (adminData == null) {
      final adminSnapshot = await _adminReference.get();
      adminData = adminSnapshot.data();
    }

    if (adminData == null) return '';

    final territoire = _nestedMap(adminData, 'territoire');
    return _text(
      territoire['territoireId'] ??
          adminData['territoireId'] ??
          adminData['organisationId'],
    );
  }

  bool _isRescueStation(Map<String, dynamic> data) {
    if (data['isPosteSecours'] == true) return true;
    return _text(data['typeSphot'])
        .toUpperCase()
        .contains('POSTE DE SECOURS');
  }

  String _spotName(Map<String, dynamic> data) {
    return _text(
      data['nomSphot'] ??
          data['nomSecours'] ??
          data['name'] ??
          data['nom'] ??
          data['title'] ??
          'SPHOT sans nom',
    );
  }

  String _spotDisplayName(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final idSphot = _text(data['idSphot']);
    final name = _spotName(data);
    final displayedId = idSphot.isEmpty ? documentId : idSphot;
    return displayedId.isEmpty ? name : '$displayedId - $name';
  }

  void _initializeOfferSelection(Map<String, dynamic> data) {
    if (_offerSelectionInitialized) return;

    final storedIds = data['selectedRescueStationIds'];
    if (storedIds is Iterable) {
      _selectedRescueStationIds.addAll(
        storedIds
            .map((value) => _text(value))
            .where((value) => value.isNotEmpty),
      );
    }

    _offerSelectionInitialized = true;
  }

  Map<String, dynamic> _nestedMap(
    Map<String, dynamic> data,
    String field,
  ) {
    final value = data[field];
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }

  dynamic _firstFilled(List<dynamic> values) {
    for (final value in values) {
      if (_text(value).isNotEmpty) return value;
    }
    return '';
  }

  Map<String, dynamic> _mergeRegistrationData(
    Map<String, dynamic> subscription,
    Map<String, dynamic> request,
  ) {
    final facturation = _nestedMap(request, 'facturation');
    final profile = _nestedMap(request, 'profile');
    final structure = _nestedMap(request, 'structure');
    final territoire = _nestedMap(request, 'territoire');
    final proConnect = _nestedMap(request, 'proConnect');
    final preview = _nestedMap(request, 'subscriptionPreview');

    final contactName = [
      _text(profile['prenomAffiche']),
      _text(profile['nomAffiche']),
    ].where((value) => value.isNotEmpty).join(' ');

    dynamic value(String field, List<dynamic> fallbacks) {
      return _firstFilled(<dynamic>[
        subscription[field],
        ...fallbacks,
      ]);
    }

    return <String, dynamic>{
      ...subscription,
      'billingOrganisation': value('billingOrganisation', [
        facturation['billingOrganisation'],
        structure['nom'],
        proConnect['organisation'],
      ]),
      'billingSiret': value('billingSiret', [
        facturation['billingSiret'],
        structure['siret'],
        request['siret'],
        proConnect['siret'],
      ]),
      'billingAddress': value('billingAddress', [
        facturation['billingAddress'],
        territoire['adresse'],
      ]),
      'billingPostalCode': value('billingPostalCode', [
        facturation['billingPostalCode'],
        territoire['codePostal'],
      ]),
      'billingCity': value('billingCity', [
        facturation['billingCity'],
        territoire['ville'],
      ]),
      'billingCountry': value('billingCountry', [
        territoire['pays'],
        'France',
      ]),
      'billingContactName': value('billingContactName', [
        facturation['billingContactName'],
        contactName,
      ]),
      'billingContactEmail': value('billingContactEmail', [
        facturation['billingContactEmail'],
        profile['email'],
        proConnect['email'],
      ]),
      'billingContactPhone': value('billingContactPhone', [
        facturation['billingContactPhone'],
        profile['telephone'],
      ]),
      'purchaseOrderNumber': value('purchaseOrderNumber', [
        facturation['purchaseOrderNumber'],
      ]),
      'engagementNumber': value('engagementNumber', [
        facturation['engagementNumber'],
      ]),
      'chorusServiceCode': value('chorusServiceCode', [
        facturation['chorusServiceCode'],
      ]),
      'numberOfRescueStations': value('numberOfRescueStations', [
        facturation['numberOfRescueStations'],
      ]),
      'trialDurationDays': value('trialDurationDays', [
        preview['trialDurationDays'],
      ]),
      'pricePerStationExclTax': value('pricePerStationExclTax', [
        preview['pricePerStationExclTax'],
      ]),
      'billingCycle': value('billingCycle', [
        preview['billingCycle'],
      ]),
      'vatRate': value('vatRate', [
        preview['vatRate'],
      ]),
    };
  }

  Stream<Map<String, dynamic>> _subscriptionDataStream() {
    return _subscriptionReference.snapshots().asyncMap((snapshot) async {
      final subscription = snapshot.data() ?? const <String, dynamic>{};

      try {
        final requestSnapshot = await _adminRequestReference.get();
        final request =
            requestSnapshot.data() ?? const <String, dynamic>{};
        return _mergeRegistrationData(subscription, request);
      } catch (_) {
        return subscription;
      }
    });
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(_text(value).replaceAll(',', '.')) ?? 0;
  }

  String _fieldValue(
    Map<String, dynamic> data,
    String field, {
    String fallback = '',
  }) {
    if (_draft.containsKey(field)) return _draft[field]!;

    final storedValue = _text(data[field]);
    return storedValue.isEmpty ? fallback : storedValue;
  }

  bool _noOrderRequired(Map<String, dynamic> data) {
    return _draftNoOrderRequired ??
        (data['purchaseOrderNotRequired'] == true);
  }

  DateTime? _dateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _formatDate(dynamic value) {
    final date = _dateTime(value);
    if (date == null) return '-';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Future<void> _activateSubscription() async {
    if (_uid.isEmpty || _savingSection != null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'ACTIVER MON ABONNEMENT',
            style: TextStyle(
              color: _blue,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: const Text(
            'L\'activation ouvre immédiatement les droits d\'exploitation. '
            'La date de ce clic devient la date de début de l\'abonnement. '
            'La première période se terminera le 31 décembre de cette année, '
            'sans prorata.',
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
              child: const Text('CONFIRMER L\'ACTIVATION'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _savingSection = 'activation';
    });

    final now = DateTime.now();
    final endDate = DateTime(now.year, 12, 31, 23, 59, 59, 999);
    final serverNow = FieldValue.serverTimestamp();

    try {
      final batch = FirebaseFirestore.instance.batch();

      batch.set(
        _subscriptionReference,
        <String, dynamic>{
          'adminUid': _uid,
          'status': 'active',
          'subscriptionStartDate': Timestamp.fromDate(now),
          'subscriptionEndDate': Timestamp.fromDate(endDate),
          'subscriptionPeriodRule': 'calendar_year',
          'firstPeriodProrated': false,
          'billingCycle': 'annual',
          'activatedAt': serverNow,
          'activatedBy': _uid,
          'activatedByRole': 'admin',
          'updatedAt': serverNow,
        },
        SetOptions(merge: true),
      );

      batch.set(
        _adminRequestReference,
        <String, dynamic>{
          'commercialTracking': <String, dynamic>{
            'status': 'subscription_active',
            'subscriptionActivatedAt': serverNow,
          },
          'lastEvent': <String, dynamic>{
            'type': 'subscription_activated_by_admin',
            'category': 'commercial',
            'label': 'Abonnement activé par l\'administrateur',
            'createdAt': serverNow,
            'createdByRole': 'admin',
          },
          'updatedAt': serverNow,
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Abonnement activé jusqu\'au 31/12/${now.year}.',
          ),
          backgroundColor: _green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Activation impossible : $error'),
          backgroundColor: _red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingSection = null;
        });
      }
    }
  }

  Future<void> _saveSection(
    String section,
    Map<String, dynamic> fields,
    String successMessage,
  ) async {
    if (_uid.isEmpty || _savingSection != null) return;

    setState(() {
      _savingSection = section;
    });

    try {
      await _subscriptionReference.set(
        <String, dynamic>{
          'adminUid': _uid,
          ...fields,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: _green,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enregistrement impossible : $error'),
          backgroundColor: _red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingSection = null;
        });
      }
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: _blue,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: _blue.withOpacity(0.24),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: _blue,
          width: 1.6,
        ),
      ),
    );
  }

  Widget _field({
    required Map<String, dynamic> data,
    required String field,
    required String label,
    String fallback = '',
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        key: ValueKey<String>(
          '$field-${_fieldValue(data, field, fallback: fallback)}',
        ),
        initialValue: _fieldValue(data, field, fallback: fallback),
        style: const TextStyle(
          color: _blue,
          fontWeight: FontWeight.w600,
        ),
        keyboardType: keyboardType,
        onChanged: (value) => _draft[field] = value,
        decoration: _inputDecoration(label),
      ),
    );
  }

  String _status({
    required bool complete,
    required bool started,
  }) {
    if (complete) return 'RENSEIGNÉ';
    if (started) return 'EN COURS';
    return 'À COMPLÉTER';
  }

  Color _statusColor({
    required bool complete,
    required bool started,
  }) {
    if (complete) return _green;
    if (started) return _orange;
    return _grey;
  }

  Widget _saveButton({
    required String section,
    required VoidCallback onPressed,
  }) {
    final isSaving = _savingSection == section;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _savingSection == null ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: isSaving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.save_rounded, size: 18),
        label: Text(
          isSaving ? 'ENREGISTREMENT...' : 'ENREGISTRER',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _payerForm(Map<String, dynamic> data) {
    return Column(
      children: [
        _field(
          data: data,
          field: 'billingOrganisation',
          label: 'Organisation de facturation',
        ),
        _field(
          data: data,
          field: 'billingSiret',
          label: 'SIRET',
          keyboardType: TextInputType.number,
        ),
        _field(
          data: data,
          field: 'billingAddress',
          label: 'Adresse de facturation',
        ),
        Row(
          children: [
            Expanded(
              child: _field(
                data: data,
                field: 'billingPostalCode',
                label: 'Code postal',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _field(
                data: data,
                field: 'billingCity',
                label: 'Ville',
              ),
            ),
          ],
        ),
        _field(
          data: data,
          field: 'billingCountry',
          label: 'Pays',
          fallback: 'France',
        ),
        _field(
          data: data,
          field: 'billingContactName',
          label: 'Contact facturation',
        ),
        _field(
          data: data,
          field: 'billingContactEmail',
          label: 'Email de facturation',
          keyboardType: TextInputType.emailAddress,
        ),
        _field(
          data: data,
          field: 'billingContactPhone',
          label: 'Téléphone de facturation',
          keyboardType: TextInputType.phone,
        ),
        _saveButton(
          section: 'payer',
          onPressed: () {
            _saveSection(
              'payer',
              {
                'billingOrganisation':
                    _fieldValue(data, 'billingOrganisation'),
                'billingSiret': _fieldValue(data, 'billingSiret'),
                'billingAddress': _fieldValue(data, 'billingAddress'),
                'billingPostalCode':
                    _fieldValue(data, 'billingPostalCode'),
                'billingCity': _fieldValue(data, 'billingCity'),
                'billingCountry': _fieldValue(
                  data,
                  'billingCountry',
                  fallback: 'France',
                ),
                'billingContactName':
                    _fieldValue(data, 'billingContactName'),
                'billingContactEmail':
                    _fieldValue(data, 'billingContactEmail'),
                'billingContactPhone':
                    _fieldValue(data, 'billingContactPhone'),
              },
              'Organisme payeur enregistré.',
            );
          },
        ),
      ],
    );
  }

  Widget _offerForm(Map<String, dynamic> data) {
  _initializeOfferSelection(data);

  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('settings')
        .doc('subscriptionPricing')
        .snapshots(),
    builder: (context, pricingSnapshot) {
      final pricingData = pricingSnapshot.data?.data();

      final configuredPrice = _number(
        pricingData?['annualPricePerRescueStationExclTax'],
      );

      final annualPricePerStationExclTax = configuredPrice > 0
          ? configuredPrice
          : _fallbackAnnualPricePerStationExclTax;

      return FutureBuilder<String>(
      future: _territoireIdFuture,
      builder: (context, territoireSnapshot) {
        if (territoireSnapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: CircularProgressIndicator(color: _blue),
            ),
          );
        }

        final territoireId = territoireSnapshot.data ?? '';
        if (territoireId.isEmpty) {
          return const Text(
            'Aucun territoire associé à cet administrateur.',
            style: TextStyle(
              color: _red,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('territoires')
              .doc(territoireId)
              .collection('spots')
              .snapshots(),
          builder: (context, spotsSnapshot) {
            if (spotsSnapshot.connectionState == ConnectionState.waiting &&
                !spotsSnapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: CircularProgressIndicator(color: _blue),
                ),
              );
            }

            final spotDocuments = spotsSnapshot.data?.docs ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final rescueStations = spotDocuments
                .where((document) => _isRescueStation(document.data()))
                .toList()
              ..sort((first, second) {
                return _spotDisplayName(first.id, first.data()).compareTo(
                  _spotDisplayName(second.id, second.data()),
                );
              });

            final availableIds = rescueStations
                .map((document) => document.id)
                .toSet();
            final activeSelectedIds = _selectedRescueStationIds
                .where(availableIds.contains)
                .toSet();
            final selectedCount = activeSelectedIds.length;
            final annualTotalExclTax =
                selectedCount * annualPricePerStationExclTax;

            final selectedStations = rescueStations
                .where((document) => activeSelectedIds.contains(document.id))
                .map(
                  (document) => <String, dynamic>{
                    'spotDocumentId': document.id,
                    'idSphot': _text(document.data()['idSphot']),
                    'name': _spotName(document.data()),
                  },
                )
                .toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'POSTES DE SECOURS RÉFÉRENCÉS',
                  style: TextStyle(
                    color: _blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 8),
                if (rescueStations.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _grey.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _blue.withOpacity(0.16)),
                    ),
                    child: const Text(
                      'Aucun SPHOT référencé comme poste de secours.',
                      style: TextStyle(
                        color: _grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  ...rescueStations.map((document) {
                    final checked =
                        _selectedRescueStationIds.contains(document.id);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: checked
                            ? _blue.withOpacity(0.055)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: checked
                              ? _blue.withOpacity(0.55)
                              : _blue.withOpacity(0.18),
                        ),
                      ),
                      child: CheckboxListTile(
                        value: checked,
                        activeColor: _red,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 1,
                        ),
                        title: Text(
                          _spotDisplayName(document.id, document.data()),
                          style: const TextStyle(
                            color: _blue,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedRescueStationIds.add(document.id);
                            } else {
                              _selectedRescueStationIds.remove(document.id);
                            }
                          });
                        },
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _blue.withOpacity(0.045),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _blue.withOpacity(0.22)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$selectedCount poste${selectedCount > 1 ? 's' : ''} sélectionné${selectedCount > 1 ? 's' : ''}",
                        style: const TextStyle(
                          color: _blue,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
  'Tarif unique : ${annualPricePerStationExclTax.toStringAsFixed(2).replaceAll('.', ',')} € HT par poste et par an',
  style: const TextStyle(
                          color: _blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'TOTAL ANNUEL HT : ${annualTotalExclTax.toStringAsFixed(2).replaceAll('.', ',')} €',
                        style: const TextStyle(
                          color: _red,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      const Text(
                        'PÉRIODE D\'ABONNEMENT',
                        style: TextStyle(
                          color: _blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Début : date réelle d\'activation',
                        style: TextStyle(
                          color: _blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Fin : 31 décembre de l\'année d\'activation',
                        style: TextStyle(
                          color: _blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Renouvellement : du 1er janvier au 31 décembre',
                        style: TextStyle(
                          color: _blue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),                      
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Abonnement annuel uniquement. La sélection prépare l’offre et le devis sans activer l’abonnement.',
                  style: TextStyle(
                    color: _grey,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                _saveButton(
                  section: 'offer',
                  onPressed: () {
                    _saveSection(
                      'offer',
                      {
                        'selectedRescueStationIds':
                            activeSelectedIds.toList(),
                        'selectedRescueStations': selectedStations,
                        'numberOfRescueStations': selectedCount,
                        'pricePerStationExclTax':
                            annualPricePerStationExclTax,
                        'annualAmountExclTax': annualTotalExclTax,
                        'billingCycle': 'annual',
                        'subscriptionPeriodRule': 'calendar_year',
                        'firstPeriodProrated': false,
                        'subscriptionDurationMonths': FieldValue.delete(),
                        'vatRate': 20.0,
                      },
                      'Offre annuelle et sélection des postes enregistrées.',
                    );
                  },
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

  Widget _orderForm(Map<String, dynamic> data) {
    final noOrderRequired = _noOrderRequired(data);

    return Column(
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: noOrderRequired,
          activeColor: _blue,
          title: const Text(
            'Aucun bon de commande nécessaire',
            style: TextStyle(
              color: _blue,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          onChanged: (value) {
            setState(() {
              _draftNoOrderRequired = value == true;
            });
          },
        ),
        const SizedBox(height: 4),
        _field(
          data: data,
          field: 'purchaseOrderNumber',
          label: 'Numéro de bon de commande',
        ),
        _field(
          data: data,
          field: 'engagementNumber',
          label: 'Numéro d’engagement',
        ),
        _field(
          data: data,
          field: 'chorusServiceCode',
          label: 'Code service Chorus Pro',
        ),
        _saveButton(
          section: 'order',
          onPressed: () {
            _saveSection(
              'order',
              {
                'purchaseOrderNotRequired': _noOrderRequired(data),
                'purchaseOrderNumber':
                    _fieldValue(data, 'purchaseOrderNumber'),
                'engagementNumber':
                    _fieldValue(data, 'engagementNumber'),
                'chorusServiceCode':
                    _fieldValue(data, 'chorusServiceCode'),
              },
              'Commande enregistrée.',
            );
          },
        ),
      ],
    );
  }

  Widget _activationSummary({
    required Map<String, dynamic> data,
    required bool payerComplete,
    required bool offerComplete,
    required bool orderComplete,
  }) {
    final isActive = _text(data['status']).toLowerCase() == 'active';
    final canActivate = payerComplete && offerComplete && orderComplete;

    Widget line(String label, bool complete) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(
              complete
                  ? Icons.check_circle_rounded
                  : Icons.pending_outlined,
              color: complete ? _green : _grey,
              size: 19,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: complete ? _green : _grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line('Organisme payeur', payerComplete),
        line('Offre et devis', offerComplete),
        line('Commande', orderComplete),
        const SizedBox(height: 6),
        if (isActive) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _green.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ABONNEMENT ACTIF',
                  style: TextStyle(
                    color: _green,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Début : ${_formatDate(data['subscriptionStartDate'])}',
                  style: const TextStyle(
                    color: _blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Fin : ${_formatDate(data['subscriptionEndDate'])}',
                  style: const TextStyle(
                    color: _blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Text(
            canActivate
                ? 'Le dossier est complet. L\'activation ouvre immédiatement les droits d\'exploitation.'
                : 'Complétez les trois rubriques ci-dessus pour pouvoir activer l\'abonnement.',
            style: const TextStyle(
              color: _grey,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: canActivate && _savingSection == null
                  ? _activateSubscription
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _grey.withOpacity(0.16),
                disabledForegroundColor: _grey,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: _savingSection == 'activation'
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.verified_rounded, size: 20),
              label: const Text(
                'ACTIVER MON ABONNEMENT',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _accordionSection({
    required String id,
    required IconData icon,
    required String title,
    required String description,
    required String status,
    required Color statusColor,
    required Widget child,
  }) {
    final isExpanded = _expandedSections.contains(id);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpanded ? _blue : _blue.withOpacity(0.22),
          width: isExpanded ? 1.6 : 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedSections.remove(id);
                } else {
                  _expandedSections.add(id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: _blue, size: 27),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: _blue,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          description,
                          style: TextStyle(
                            color: _blue.withOpacity(0.72),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: _blue,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Column(
              children: [
                Divider(
                  height: 1,
                  color: _blue.withOpacity(0.16),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: child,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Transform.translate(
            offset: const Offset(-12, 0),
            child: Transform.scale(
              scale: 1.5,
              child: Image.asset(
                'data/icons/fire_red_icon.png',
                width: 30,
                height: 30,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          const Expanded(
            child: Text(
              'ABONNEMENT',
              style: TextStyle(
                color: _blue,
                fontSize: 19,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.7,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Fermer',
            onPressed: widget.onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 430,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        border: Border(
          left: BorderSide(
            color: _blue.withOpacity(0.45),
            width: 1.5,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              Divider(
                height: 1,
                color: _blue.withOpacity(0.20),
              ),
              Expanded(
                child: _uid.isEmpty
                    ? const Center(
                        child: Text(
                          'Administrateur non identifié.',
                          style: TextStyle(
                            color: _red,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : StreamBuilder<Map<String, dynamic>>(
                        stream: _dataStream,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              !snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(color: _blue),
                            );
                          }

                          final data = snapshot.data ??
                              const <String, dynamic>{};

                          final payerValues = [
                            data['billingOrganisation'],
                            data['billingSiret'],
                            data['billingAddress'],
                            data['billingPostalCode'],
                            data['billingCity'],
                            data['billingContactName'],
                            data['billingContactEmail'],
                          ];
                          final payerStarted = payerValues.any(
                            (value) => _text(value).isNotEmpty,
                          );
                          final payerComplete = payerValues.every(
                            (value) => _text(value).isNotEmpty,
                          );

                          _initializeOfferSelection(data);
                          final savedStationIds = data['selectedRescueStationIds'];
                          final hasSavedStations = savedStationIds is Iterable &&
                              savedStationIds.any(
                                (value) => _text(value).isNotEmpty,
                              );
                          final offerStarted =
                              _selectedRescueStationIds.isNotEmpty ||
                                  hasSavedStations;
                          final offerComplete =
    hasSavedStations &&
        _number(data['pricePerStationExclTax']) > 0 &&
        _text(data['billingCycle']) == 'annual';

                          final orderValues = [
                            data['purchaseOrderNumber'],
                            data['engagementNumber'],
                            data['chorusServiceCode'],
                          ];
                          final orderStarted =
                              data['purchaseOrderNotRequired'] == true ||
                                  orderValues.any(
                                    (value) => _text(value).isNotEmpty,
                                  );
                          final orderComplete = orderStarted;
                          final subscriptionActive =
                              _text(data['status']).toLowerCase() == 'active';

                          return Container(
                            color: const Color(0xFFF8FAFC),
                            child: ListView(
                              padding: const EdgeInsets.all(20),
                              children: [
                                _accordionSection(
                                  id: 'payer',
                                  icon: Icons.apartment_rounded,
                                  title: 'ORGANISME PAYEUR',
                                  description:
                                      'Coordonnées administratives et informations de facturation de votre organisme.',
                                  status: _status(
                                    complete: payerComplete,
                                    started: payerStarted,
                                  ),
                                  statusColor: _statusColor(
                                    complete: payerComplete,
                                    started: payerStarted,
                                  ),
                                  child: _payerForm(data),
                                ),
                                const SizedBox(height: 12),
                                _accordionSection(
                                  id: 'offer',
                                  icon: Icons.description_outlined,
                                  title: 'OFFRE ET DEVIS',
                                  description:
                                      'Sélection des postes de secours et montant annuel de l’abonnement.',
                                  status: _status(
                                    complete: offerComplete,
                                    started: offerStarted,
                                  ),
                                  statusColor: _statusColor(
                                    complete: offerComplete,
                                    started: offerStarted,
                                  ),
                                  child: _offerForm(data),
                                ),
                                const SizedBox(height: 12),
                                _accordionSection(
                                  id: 'order',
                                  icon:
                                      Icons.assignment_turned_in_outlined,
                                  title: 'COMMANDE',
                                  description:
                                      'Bon de commande, numéro d’engagement et code service si nécessaire.',
                                  status: _status(
                                    complete: orderComplete,
                                    started: orderStarted,
                                  ),
                                  statusColor: _statusColor(
                                    complete: orderComplete,
                                    started: orderStarted,
                                  ),
                                  child: _orderForm(data),
                                ),
                                const SizedBox(height: 12),
                                _accordionSection(
                                  id: 'activation',
                                  icon: Icons.verified_outlined,
                                  title: 'ACTIVATION',
                                  description:
                                      'Contrôle des renseignements avant activation de l’abonnement.',
                                  status: subscriptionActive
                                      ? 'ABONNEMENT ACTIF'
                                      : payerComplete &&
                                              offerComplete &&
                                              orderComplete
                                          ? 'PRÊT À ACTIVER'
                                          : 'EN ATTENTE',
                                  statusColor: subscriptionActive ||
                                          (payerComplete &&
                                              offerComplete &&
                                              orderComplete)
                                      ? _green
                                      : _grey,
                                  child: _activationSummary(
                                    data: data,
                                    payerComplete: payerComplete,
                                    offerComplete: offerComplete,
                                    orderComplete: orderComplete,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
