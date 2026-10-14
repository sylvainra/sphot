import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../widgets/adaptive_asset_image.dart';
import '../../../services/published_commercial_quote_service.dart';

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
  final Map<int, Future<PublishedCommercialQuote>> _offerQuotes = {};

  final Map<String, String> _draft = <String, String>{};
  final Set<String> _expandedSections = <String>{};

  String? _savingSection;
  bool? _draftNoOrderRequired;
  String? _draftPaymentMethod;
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

  int? _administrativeReferenceYear(Map<String, dynamic> data) {
    for (final field in const [
      'currentPeriodStartDate',
      'renewalStartDate',
      'subscriptionStartDate',
      'trialStartDate',
    ]) {
      final value = data[field];
      if (value is Timestamp) return value.toDate().year;
      if (value is DateTime) return value.year;
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed.year;
      }
    }

    final explicitYear = data['billingYear'] ?? data['subscriptionYear'];
    return explicitYear is num ? explicitYear.toInt() : null;
  }

  String _periodAdministrativeReference(Map<String, dynamic> data) {
    final reference = _text(
      data['administrativeReference'] ?? data['requestNumber'],
    );
    final year = _administrativeReferenceYear(data);
    if (reference.isEmpty || year == null) return reference;

    final pattern = RegExp(
      r'^(SPHOT-ADM-[A-Z]{3}-)\d{4}(-\d+)$',
      caseSensitive: false,
    );
    if (!pattern.hasMatch(reference)) return reference;

    return reference.replaceFirstMapped(
      pattern,
      (match) => '${match.group(1)}$year${match.group(2)}',
    );
  }

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
    if (idSphot.isEmpty) return name;
    if (name.toUpperCase().startsWith(idSphot.toUpperCase())) return name;
    return '$idSphot - $name';
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
      'administrativeReference': value('administrativeReference', [
        request['requestNumber'],
      ]),
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
      'billingCycle': value('billingCycle', [
        preview['billingCycle'],
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
      final requestSnapshot = await _adminRequestReference.get();
      final administrativeReference = _text(
        requestSnapshot.data()?['requestNumber'],
      );

      await _subscriptionReference.set(
        <String, dynamic>{
          'adminUid': _uid,
          if (administrativeReference.isNotEmpty)
            'administrativeReference': administrativeReference,
          ...fields,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

    } catch (error) {
      if (!mounted) return;

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
            SizedBox(
              width: 85,
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
                _publishedOfferSummary(
                  selectedCount: selectedCount,
                  selectedIds: activeSelectedIds.toList()..sort(),
                  selectedStations: selectedStations,
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// L'offre reprend EXCLUSIVEMENT le devis simulé de la grille publiée.
  /// Les champs enregistrés restent un BROUILLON : la commande contractuelle
  /// devra toujours être recalculée et validée côté serveur.
  Widget _publishedOfferSummary({
    required int selectedCount,
    required List<String> selectedIds,
    required List<Map<String, dynamic>> selectedStations,
  }) {
    if (selectedCount == 0) {
      return const Text(
        'Sélectionnez au moins un poste pour consulter la grille publiée.',
        style: TextStyle(color: _grey, fontSize: 12),
      );
    }

    final future = _offerQuotes.putIfAbsent(
      selectedCount,
      () => const PublishedCommercialQuoteService().admin(
        numberOfRescueStations: selectedCount,
      ),
    );

    return FutureBuilder<PublishedCommercialQuote>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
            'Grille publiée indisponible. Aucun tarif de remplacement '
            'n’est appliqué et l’offre ne peut pas être enregistrée.',
            style: TextStyle(color: _red, fontSize: 12),
          );
        }
        final quote = snapshot.data;
        if (quote == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(color: _blue),
            ),
          );
        }

        final raw = quote.details['lines'];
        final lines = raw is List ? raw : const [];
        if (lines.isEmpty) {
          return const Text(
            'Détail de grille indisponible : impossible d’enregistrer l’offre.',
            style: TextStyle(color: _red, fontSize: 12),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                    '$selectedCount poste(s) sélectionné(s)',
                    style: const TextStyle(
                      color: _blue, fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'TARIFICATION SUIVANT GRILLE ${quote.pricingReference}',
                    style: const TextStyle(
                      color: _blue, fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  for (final line in lines)
                    if (line is Map &&
                        line['count'] is num &&
                        (line['count'] as num) > 0 &&
                        line['unitExclTax'] is num &&
                        line['amountExclTax'] is num)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                switch (line['tier']) {
                                  1 => '1er Poste de Secours',
                                  2 => 'Du 2e au 4e : ${(line['count'] as num).toInt()} × ${(line['unitExclTax'] as num).toStringAsFixed(2).replaceAll('.', ',')} €',
                                  3 => 'Du 5e au 9e : ${(line['count'] as num).toInt()} × ${(line['unitExclTax'] as num).toStringAsFixed(2).replaceAll('.', ',')} €',
                                  4 => 'À partir du 10e : ${(line['count'] as num).toInt()} × ${(line['unitExclTax'] as num).toStringAsFixed(2).replaceAll('.', ',')} €',
                                  _ => 'Tranche tarifaire',
                                },
                                style: const TextStyle(
                                  color: _blue, fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              '${(line['amountExclTax'] as num).toStringAsFixed(2).replaceAll('.', ',')} €',
                              style: const TextStyle(
                                color: _blue, fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                  const Divider(),
                  Text(
                    'TOTAL ANNUEL HT : ${quote.amountExclTax.toStringAsFixed(2).replaceAll('.', ',')} €',
                    style: const TextStyle(
                      color: _red, fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('PÉRIODE D’ABONNEMENT',
                    style: TextStyle(color: _blue, fontSize: 12,
                      fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  const Text('Début : date réelle d’activation',
                    style: TextStyle(color: _blue, fontSize: 12)),
                  const Text('Fin : 31 décembre de l’année d’activation',
                    style: TextStyle(color: _blue, fontSize: 12)),
                  const Text('Renouvellement : 1er janvier — sans prorata',
                    style: TextStyle(color: _blue, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Cette simulation prépare l’offre. Elle ne confirme aucune '
              'commande et n’active pas l’abonnement.',
              style: TextStyle(color: _grey, fontSize: 11),
            ),
            const SizedBox(height: 12),
            _saveButton(
              section: 'offer',
              onPressed: () {
                _saveSection(
                  'offer',
                  <String, dynamic>{
                    'selectedRescueStationIds': selectedIds,
                    'selectedRescueStations': selectedStations,
                    'numberOfRescueStations': selectedCount,
                    'annualAmountExclTax': quote.amountExclTax,
                    'publishedPricingReference': quote.pricingReference,
                    'publishedPricingVersion': quote.version,
                    'pricePerStationExclTax': FieldValue.delete(),
                    'vatRate': FieldValue.delete(),
                    'billingCycle': 'annual',
                    'subscriptionPeriodRule': 'calendar_year',
                    'firstPeriodProrated': false,
                    'subscriptionDurationMonths': FieldValue.delete(),
                  },
                  'Sélection et simulation publiées enregistrées.',
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _paymentMethodForm(Map<String, dynamic> data) {
    final chosen = _draftPaymentMethod ?? _text(data['preferredPaymentMethod']);
    final selected = chosen == 'card' || chosen == 'public_invoice' ? chosen : '';
    final noOrderRequired = _noOrderRequired(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Choisissez le mode de règlement de votre organisme.',
          style: TextStyle(color: _blue, fontSize: 12)),
        RadioListTile<String>(
          value: 'card',
          groupValue: selected,
          activeColor: _red,
          contentPadding: EdgeInsets.zero,
          title: const Text('Carte bancaire',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          subtitle: const Text(
            'Paiement sécurisé par un prestataire à raccorder.',
            style: TextStyle(fontSize: 11)),
          onChanged: (value) => setState(() => _draftPaymentMethod = value),
        ),
        RadioListTile<String>(
          value: 'public_invoice',
          groupValue: selected,
          activeColor: _red,
          contentPadding: EdgeInsets.zero,
          title: const Text('Commande publique / facturation administrative',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          subtitle: const Text(
            'Sous réserve de vérification d’un engagement valide.',
            style: TextStyle(fontSize: 11)),
          onChanged: (value) => setState(() => _draftPaymentMethod = value),
        ),
        if (selected == 'public_invoice') ...[
          const Divider(height: 18),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: noOrderRequired,
            activeColor: _blue,
            title: const Text('Aucun bon de commande exigé par l’organisme',
              style: TextStyle(fontSize: 12, color: _blue)),
            onChanged: (value) =>
                setState(() => _draftNoOrderRequired = value == true),
          ),
          _field(data: data, field: 'purchaseOrderNumber',
            label: 'Numéro de bon de commande'),
          _field(data: data, field: 'engagementNumber',
            label: 'Numéro d’engagement juridique'),
          _field(data: data, field: 'chorusServiceCode',
            label: 'Code service Chorus Pro'),
          const Text(
            'Une référence saisie ne vaut pas preuve contractuelle. '
            'Le contrôle sera effectué avant activation.',
            style: TextStyle(color: _grey, fontSize: 11),
          ),
        ],
        if (selected == 'card')
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Le paiement et son renouvellement devront être autorisés '
              'et confirmés par le prestataire. Aucun débit pendant le test.',
              style: TextStyle(color: _grey, fontSize: 11),
            ),
          ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 12),
          _saveButton(
            section: 'payment',
            onPressed: () => _saveSection(
              'payment',
              <String, dynamic>{
                'preferredPaymentMethod': selected,
                if (selected == 'public_invoice') ...{
                  'purchaseOrderNotRequired': noOrderRequired,
                  'purchaseOrderNumber': _fieldValue(data, 'purchaseOrderNumber'),
                  'engagementNumber': _fieldValue(data, 'engagementNumber'),
                  'chorusServiceCode': _fieldValue(data, 'chorusServiceCode'),
                },
              },
              'Préférence de règlement enregistrée.',
            ),
          ),
        ],
      ],
    );
  }

  Widget _conditionsSummary({
    required Map<String, dynamic> data,
    required bool payerComplete,
    required bool offerComplete,
    required bool paymentReady,
  }) {
    final annualAmount = _number(data['annualAmountExclTax']);
    final reference = _text(data['publishedPricingReference']);
    final status = _text(data['status']).toLowerCase();

    Widget progress(String label, bool valid) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(valid ? Icons.check_circle_rounded : Icons.pending_outlined,
          color: valid ? _green : _grey, size: 19),
        const SizedBox(width: 8),
        Expanded(child: Text(label,
          style: TextStyle(color: valid ? _green : _grey,
            fontSize: 12, fontWeight: FontWeight.w700))),
      ]),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        progress('Postes et offre enregistrés', offerComplete),
        progress('Organisme payeur renseigné', payerComplete),
        progress('Mode de règlement choisi', paymentReady),
        if (offerComplete) ...[
          const Divider(height: 18),
          Text('Grille tarifaire : $reference',
            style: const TextStyle(color: _blue, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            'TOTAL ANNUEL HT : ${annualAmount.toStringAsFixed(2).replaceAll('.', ',')} €',
            style: const TextStyle(color: _red, fontWeight: FontWeight.w900,
              fontSize: 14),
          ),
          const Text(
            'Année civile, renouvellement au 1er janvier, sans prorata. '
            'Fiscalité et montant définitif à confirmer avant engagement.',
            style: TextStyle(color: _grey, fontSize: 11, height: 1.35),
          ),
        ],
        if (status == 'active') ...[
          const SizedBox(height: 8),
          const Text('ABONNEMENT ACTIF — les droits existants restent inchangés.',
            style: TextStyle(color: _green, fontWeight: FontWeight.w800,
              fontSize: 12)),
        ],
        const Divider(height: 24),
        const Text('CONDITIONS GÉNÉRALES DE VENTE — SPHOT ADMIN',
          style: TextStyle(color: _blue, fontSize: 12,
            fontWeight: FontWeight.w900)),
        const SizedBox(height: 7),
        const Text(
          'Le document de CGV publié, sa version et l’acceptation '
          'traçable restent à raccorder. Aucun accord n’est présumé.',
          style: TextStyle(color: _grey, fontSize: 11, height: 1.35),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity, height: 44,
          child: ElevatedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.lock_outline_rounded, size: 19),
            label: const Text('CONFIRMER MA COMMANDE',
              style: TextStyle(fontWeight: FontWeight.w900)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _grey.withOpacity(0.18),
              disabledForegroundColor: _grey,
            ),
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Action désactivée pendant les tests : contrôle serveur, fiscalité '
          'et CGV non finalisés. Aucune commande ni aucun paiement réel.',
          style: TextStyle(color: _grey, fontSize: 11),
        ),
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
          const SizedBox(width: 6),
          Transform.translate(
            offset: const Offset(-12, 0),
            child: Transform.scale(
              scale: 1.5,
              alignment: Alignment.center,
              child: AdaptiveAssetImage(
                'data/icons/fire_red_icon.svg',
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
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
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
                          final savedIds = savedStationIds is Iterable
                              ? savedStationIds.map(_text).toSet()
                              : <String>{};
                          final sameSelection =
                              savedIds.length == _selectedRescueStationIds.length &&
                              savedIds.containsAll(_selectedRescueStationIds);
                          final offerComplete =
                              hasSavedStations &&
                              sameSelection &&
                              _text(data['publishedPricingReference']).isNotEmpty &&
                              _number(data['annualAmountExclTax']) > 0 &&
                              _text(data['billingCycle']) == 'annual';

                          final savedPayment = _text(data['preferredPaymentMethod']);
                          final chosenPayment = _draftPaymentMethod ?? savedPayment;
                          final paymentStarted = chosenPayment.isNotEmpty;
                          final paymentReady =
                              (savedPayment == 'card' ||
                               savedPayment == 'public_invoice') &&
                              chosenPayment == savedPayment;

                          return Container(
                            color: const Color(0xFFF8FAFC),
                            child: ListView(
                              padding: const EdgeInsets.all(20),
                              children: [
_accordionSection(
                                  id: 'offer',
                                  icon: Icons.place_outlined,
                                  title: '01 — POSTES ET OFFRE',
                                  description:
                                      'Postes de secours et tarif annuel suivant la grille publiée.',
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
                                  id: 'payer',
                                  icon: Icons.apartment_rounded,
                                  title: '02 — ORGANISME PAYEUR',
                                  description:
                                      'Coordonnées et informations pour la facturation électronique.',
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
                                  id: 'payment',
                                  icon: Icons.credit_card_rounded,
                                  title: '03 — MODALITÉS DE RÈGLEMENT',
                                  description:
                                      'Carte bancaire ou commande publique suivant votre organisme.',
                                  status: _status(
                                    complete: paymentReady,
                                    started: paymentStarted,
                                  ),
                                  statusColor: _statusColor(
                                    complete: paymentReady,
                                    started: paymentStarted,
                                  ),
                                  child: _paymentMethodForm(data),
                                ),
                                const SizedBox(height: 12),
                                _accordionSection(
                                  id: 'conditions',
                                  icon: Icons.verified_user_outlined,
                                  title: '04 — CONDITIONS ET CONFIRMATION',
                                  description:
                                      'Récapitulatif, fiscalité, CGV et validation sécurisée.',
                                  status: 'EN PRÉPARATION',
                                  statusColor: _orange,
                                  child: _conditionsSummary(
                                    data: data,
                                    payerComplete: payerComplete,
                                    offerComplete: offerComplete,
                                    paymentReady: paymentReady,
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
