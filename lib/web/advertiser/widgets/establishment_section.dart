import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../shared/text_input_formatters.dart';
import '../../shared/web_colors.dart';
import '../../../services/company_registry_service.dart';

class EstablishmentSection extends StatefulWidget {
  const EstablishmentSection({
    super.key,
    required this.user,
    this.requestId,
    this.readOnly = false,
    this.onSaved,
  });

  final User? user;
  final String? requestId;
  final bool readOnly;
  final VoidCallback? onSaved;

  @override
  State<EstablishmentSection> createState() => _EstablishmentSectionState();
}

class _EstablishmentSectionState extends State<EstablishmentSection> {
  static const _foreignCountries = <String, String>{
    'AU': 'AUSTRALIE',
    'ZA': 'AFRIQUE DU SUD',
    'CA': 'CANADA',
    'US': 'ÉTATS-UNIS',
    'NZ': 'NOUVELLE-ZÉLANDE',
    'GB': 'ROYAUME-UNI',
    'OTHER': 'AUTRE PAYS',
  };
  static const _activityTypes = <String>[
    'Cosmétique',
    'Optique / lunettes',
    'Surfwear / prêt-à-porter',
    'Sports nautiques',
    'Tourisme',
    'Restauration',
    'Produits alimentaires',
    'Boissons',
    'Hôtellerie',
    'Hôtellerie de plein air',
    'Commerce local',
    'Institutionnel',
    'Autre',
  ];

  final _formKey = GlobalKey<FormState>();
  final _legalNameController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _otherActivityController = TextEditingController();
  final _siretController = TextEditingController();
  final _sirenController = TextEditingController();
  final _addressController = TextEditingController();
  final _addressComplementController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _cityController = TextEditingController();
  final _countryController = TextEditingController(text: 'FRANCE');
  final _publicPhoneController = TextEditingController();
  final _publicEmailController = TextEditingController();
  final _foreignRegistrationController = TextEditingController();
  final _foreignAuthorityController = TextEditingController();

  bool _isFrenchRegistration = true;
  String _foreignCountryCode = 'US';
  String _registryStatus = 'unverified';
  String _registryMessage = '';
  String _activityCode = '';
  bool _checkingRegistry = false;
  PlatformFile? _selectedProof;
  Map<String, dynamic> _savedForeignProof = {};

  String? _activityType;
  final _activityFieldKey = GlobalKey();
  OverlayEntry? _activityOverlay;
  String? _activityError;
  bool _loading = true;
  bool _saving = false;
  bool _completed = false;
  bool _requestExists = false;
  String? _error;

  String? get _requestId {
    final value = widget.requestId?.trim() ?? '';
    if (value.isNotEmpty) return value;
    return widget.user?.uid;
  }

  @override
  void initState() {
    super.initState();
    _siretController.addListener(_updateSiren);
    _initialiseEstablishment();
  }

  @override
  void dispose() {
    _closeActivityMenu();
    _siretController.removeListener(_updateSiren);
    _legalNameController.dispose();
    _businessNameController.dispose();
    _otherActivityController.dispose();
    _siretController.dispose();
    _sirenController.dispose();
    _addressController.dispose();
    _addressComplementController.dispose();
    _postalCodeController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    _publicPhoneController.dispose();
    _publicEmailController.dispose();
    _foreignRegistrationController.dispose();
    _foreignAuthorityController.dispose();
    super.dispose();
  }

  Future<void> _initialiseEstablishment() async {
    final requestId = _requestId;
    if (requestId != null) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('advertiserRequests')
            .doc(requestId)
            .get();
        final data = snapshot.data();
        _requestExists = snapshot.exists;

        if (data != null) {
          final rawEstablishment = data['establishment'];
          final establishment = rawEstablishment is Map
              ? Map<String, dynamic>.from(rawEstablishment)
              : <String, dynamic>{};

          _legalNameController.text = forceUpperCase(
            _read(establishment['legalName'], data['organisation']),
          );
          _businessNameController.text = forceUpperCase(
            _read(establishment['businessName'], data['advertiserName']),
          );
          _siretController.text = _digits(
            _read(establishment['siret'], data['siret']),
          );
          _sirenController.text = _digits(
            _read(establishment['siren'], data['siren']),
          );
          _addressController.text = _read(establishment['address']);
          _addressComplementController.text = _read(
            establishment['addressComplement'],
          );
          _postalCodeController.text = _read(establishment['postalCode']);
          _cityController.text = forceUpperCase(_read(establishment['city']));
          _countryController.text = forceUpperCase(
            _read(establishment['country'], 'FRANCE'),
          );
          _publicPhoneController.text = _read(
            establishment['publicPhone'],
            data['phone'],
          );
          _publicEmailController.text = _read(
            establishment['publicEmail'],
            data['publicEmail'],
          );
          final savedActivity = _read(establishment['activityType']);
          if (_activityTypes.contains(savedActivity)) {
            _activityType = savedActivity;
          }
          _otherActivityController.text = _read(
            establishment['activityTypeOther'],
          );

          _completed = data['establishmentCompleted'] == true;
          _isFrenchRegistration =
              _read(data['registrationMode'], 'france') != 'international';
          _foreignCountryCode = _read(data['registrationCountryCode'], 'US');
          if (!_foreignCountries.containsKey(_foreignCountryCode)) {
            _foreignCountryCode = 'OTHER';
          }
          _foreignRegistrationController.text = _read(
            data['foreignRegistrationNumber'],
          );
          _foreignAuthorityController.text = _read(
            data['foreignRegistrationAuthority'],
          );
          final precheck = data['registryPrecheck'];
          if (precheck is Map) {
            _registryStatus = _read(precheck['status'], 'unverified');
            _registryMessage = _read(precheck['message']);
            _activityCode = _read(precheck['activityCode']);
          }
          final proof = data['foreignProof'];
          if (proof is Map) {
            _savedForeignProof = Map<String, dynamic>.from(proof);
          }
        }
      } catch (error) {
        _error = 'Impossible de charger l’établissement enregistré.';
        debugPrint('Chargement établissement annonceur impossible : $error');
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  String _read(Object? primary, [Object? fallback]) {
    final primaryText = primary?.toString().trim() ?? '';
    if (primaryText.isNotEmpty) return primaryText;
    return fallback?.toString().trim() ?? '';
  }

  String _digits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  void _updateSiren() {
    final siret = _digits(_siretController.text);
    final siren = siret.length >= 9 ? siret.substring(0, 9) : '';
    if (_sirenController.text != siren) {
      _sirenController.text = siren;
    }
  }

  void _markAsModified([Object? _]) {
    if (_completed) setState(() => _completed = false);
  }

  Future<void> _verifySiret() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _checkingRegistry = true;
      _registryMessage = '';
    });
    try {
      final company = await const CompanyRegistryService().findBySiret(
        _siretController.text,
      );
      if (!mounted) return;
      setState(() {
        _siretController.text = company.siret;
        _sirenController.text = company.siren;
        _legalNameController.text = forceUpperCase(company.legalName);
        if (company.businessName.isNotEmpty) {
          _businessNameController.text = forceUpperCase(company.businessName);
        }
        _addressController.text = company.address;
        _postalCodeController.text = company.postalCode;
        _cityController.text = forceUpperCase(company.city);
        _countryController.text = 'FRANCE';
        _activityCode = company.activityCode;
        _registryStatus = company.isActive ? 'verified' : 'manual_review';
        _registryMessage = company.isActive
            ? 'SIRET vérifié dans le registre officiel.'
            : 'Établissement déclaré fermé : contrôle manuel obligatoire.';
        _completed = false;
      });
    } on CompanyRegistryException catch (error) {
      if (!mounted) return;
      setState(() {
        _registryStatus = 'manual_review';
        _registryMessage = error.message;
      });
    } finally {
      if (mounted) setState(() => _checkingRegistry = false);
    }
  }

  Future<void> _pickForeignProof() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.single;
    if (file.size > 5 * 1024 * 1024) {
      setState(() => _error = 'Le justificatif ne doit pas dépasser 5 Mo.');
      return;
    }
    setState(() {
      _selectedProof = file;
      _error = null;
      _completed = false;
    });
  }

  Future<Map<String, Object?>> _uploadForeignProof(String requestId) async {
    final file = _selectedProof;
    if (file == null) return Map<String, Object?>.from(_savedForeignProof);
    final Uint8List? bytes = file.bytes;
    if (bytes == null) {
      throw const CompanyRegistryException(
        'Lecture du justificatif impossible.',
      );
    }
    final extension = (file.extension ?? 'pdf').toLowerCase();
    final reference = FirebaseStorage.instance.ref(
      'advertiser_requests/$requestId/foreign_registration_proof.$extension',
    );
    await reference.putData(
      bytes,
      SettableMetadata(
        contentType: extension == 'pdf'
            ? 'application/pdf'
            : 'image/$extension',
      ),
    );
    return <String, Object?>{
      'url': await reference.getDownloadURL(),
      'fileName': file.name,
      'extension': extension,
      'fileSizeBytes': file.size,
      'uploadedAt': FieldValue.serverTimestamp(),
    };
  }

  void _closeActivityMenu() {
    _activityOverlay?.remove();
    _activityOverlay = null;
  }

  void _openActivityMenu(FormFieldState<String> fieldState) {
    _closeActivityMenu();

    final renderObject = _activityFieldKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;

    final position = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    final scrollController = ScrollController();

    void scrollToOtherField() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    }

    _activityOverlay = OverlayEntry(
      builder: (overlayContext) {
        return StatefulBuilder(
          builder: (overlayContext, overlaySetState) {
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _closeActivityMenu,
                    child: const ColoredBox(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  left: position.dx,
                  top: position.dy + size.height - 12,
                  width: size.width,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 330),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.97),
                        border: const Border(
                          left: BorderSide(color: WebColors.blue, width: 1.4),
                          right: BorderSide(color: WebColors.blue, width: 1.4),
                          bottom: BorderSide(color: WebColors.blue, width: 1.4),
                        ),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(10),
                          bottomRight: Radius.circular(10),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ScrollbarTheme(
                        data: const ScrollbarThemeData(
                          thumbColor: MaterialStatePropertyAll(WebColors.blue),
                          thumbVisibility: MaterialStatePropertyAll(true),
                          thickness: MaterialStatePropertyAll(9),
                          radius: Radius.circular(10),
                        ),
                        child: Scrollbar(
                          controller: scrollController,
                          thumbVisibility: true,
                          thickness: 9,
                          radius: const Radius.circular(10),
                          child: ListView.builder(
                            controller: scrollController,
                            primary: false,
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: _activityTypes.length,
                            itemBuilder: (context, index) {
                              final choice = _activityTypes[index];
                              final selected = _activityType == choice;
                              final showOtherField =
                                  choice == 'Autre' && selected;

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _activityType = choice;
                                        _activityError = null;
                                        _completed = false;
                                        if (choice != 'Autre') {
                                          _otherActivityController.clear();
                                        }
                                      });
                                      fieldState.didChange(choice);
                                      overlaySetState(() {});

                                      if (choice == 'Autre') {
                                        scrollToOtherField();
                                      } else {
                                        _closeActivityMenu();
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              choice,
                                              style: const TextStyle(
                                                color: WebColors.blue,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          if (selected)
                                            const Icon(
                                              Icons.check_rounded,
                                              color: WebColors.red,
                                              size: 20,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (showOtherField)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        0,
                                        16,
                                        10,
                                      ),
                                      child: TextField(
                                        controller: _otherActivityController,
                                        autofocus: true,
                                        style: const TextStyle(
                                          color: WebColors.blue,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        textCapitalization:
                                            TextCapitalization.sentences,
                                        onChanged: (value) {
                                          setState(() {
                                            _activityError = null;
                                            _completed = false;
                                          });
                                          overlaySetState(() {});
                                        },
                                        onSubmitted: (_) =>
                                            _closeActivityMenu(),
                                        decoration: InputDecoration(
                                          labelText: 'Précisez :',
                                          errorText: _activityError,
                                          labelStyle: const TextStyle(
                                            color: WebColors.blue,
                                          ),
                                          isDense: true,
                                          filled: true,
                                          fillColor: WebColors.blue.withOpacity(
                                            0.035,
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 10,
                                              ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            borderSide: BorderSide(
                                              color: WebColors.blue.withOpacity(
                                                0.55,
                                              ),
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            borderSide: const BorderSide(
                                              color: WebColors.blue,
                                              width: 1.7,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_activityOverlay!);
    if (_activityType == 'Autre') scrollToOtherField();
  }

  Future<void> _save() async {
    if (widget.readOnly) return;
    FocusScope.of(context).unfocus();
    final formIsValid = _formKey.currentState?.validate() ?? false;
    final otherActivityIsValid =
        _activityType != 'Autre' ||
        _otherActivityController.text.trim().isNotEmpty;
    final foreignProofIsValid =
        _isFrenchRegistration ||
        _selectedProof != null ||
        (_savedForeignProof['url']?.toString().trim().isNotEmpty ?? false);
    if (!otherActivityIsValid) {
      setState(() => _activityError = 'Précisez le type d’activité');
    }
    if (!foreignProofIsValid) {
      setState(() => _error = 'Joignez un justificatif officiel.');
    }
    if (!formIsValid || !otherActivityIsValid || !foreignProofIsValid) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final requestId = _requestId;
      final siret = _digits(_siretController.text);
      final siren = _digits(_sirenController.text);
      final legalName = forceUpperCase(_legalNameController.text.trim());
      final businessName = forceUpperCase(_businessNameController.text.trim());
      final city = forceUpperCase(_cityController.text.trim());
      final country = forceUpperCase(_countryController.text.trim());
      final publicPhone = _publicPhoneController.text.trim();
      final publicEmail = _publicEmailController.text.trim();
      final registrationMode = _isFrenchRegistration
          ? 'france'
          : 'international';

      _legalNameController.text = legalName;
      _businessNameController.text = businessName;
      _cityController.text = city;
      _countryController.text = country;

      if (requestId != null) {
        final foreignProof = _isFrenchRegistration
            ? <String, Object?>{}
            : await _uploadForeignProof(requestId);
        final creationData = _requestExists
            ? <String, Object?>{}
            : <String, Object?>{
                'status': 'draft',
                'createdAt': FieldValue.serverTimestamp(),
              };

        await FirebaseFirestore.instance
            .collection('advertiserRequests')
            .doc(requestId)
            .set({
              ...creationData,
              'uid': requestId,
              'organisation': legalName,
              'advertiserName': businessName,
              'siret': siret,
              'siren': siren,
              'phone': publicPhone,
              'publicEmail': publicEmail,
              'registrationMode': registrationMode,
              'registrationCountryCode': _isFrenchRegistration
                  ? 'FR'
                  : _foreignCountryCode,
              'foreignRegistrationNumber': _isFrenchRegistration
                  ? ''
                  : _foreignRegistrationController.text.trim(),
              'foreignRegistrationAuthority': _isFrenchRegistration
                  ? ''
                  : _foreignAuthorityController.text.trim(),
              'foreignProof': foreignProof,
              'registryPrecheck': <String, Object?>{
                'status': _isFrenchRegistration
                    ? _registryStatus
                    : 'manual_review',
                'message': _isFrenchRegistration
                    ? _registryMessage
                    : 'Entreprise étrangère : contrôle manuel obligatoire.',
                'activityCode': _activityCode,
                'checkedAt': FieldValue.serverTimestamp(),
              },
              'submissionLocale': Localizations.localeOf(context)
                  .toLanguageTag(),
              'establishmentCompleted': true,
              'establishment': <String, Object?>{
                'legalName': legalName,
                'businessName': businessName,
                'activityType': _activityType,
                'activityTypeOther': _activityType == 'Autre'
                    ? _otherActivityController.text.trim()
                    : '',
                'siret': siret,
                'siren': siren,
                'address': _addressController.text.trim(),
                'addressComplement': _addressComplementController.text.trim(),
                'postalCode': _postalCodeController.text.trim(),
                'city': city,
                'country': country,
                'publicPhone': publicPhone,
                'publicEmail': publicEmail,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
        _requestExists = true;
      }

      if (!mounted) return;
      setState(() => _completed = true);
      widget.onSaved?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'L’enregistrement a échoué. Réessayez.');
      debugPrint('Enregistrement établissement annonceur impossible : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) return 'Champ obligatoire';
    return null;
  }

  String? _siretValidator(String? value) {
    if (!_isFrenchRegistration) return null;
    final requiredError = _requiredValidator(value);
    if (requiredError != null) return requiredError;
    return _digits(value!).length == 14
        ? null
        : 'Le SIRET doit comporter 14 chiffres';
  }

  String? _emailValidator(String? value) {
    final requiredError = _requiredValidator(value);
    if (requiredError != null) return requiredError;
    final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value!.trim());
    return valid ? null : 'Adresse email invalide';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(color: WebColors.red)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.readOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('ENTREPRISE FRANÇAISE'),
                  icon: Icon(Icons.flag_outlined),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('ENTREPRISE ÉTRANGÈRE'),
                  icon: Icon(Icons.public),
                ),
              ],
              selected: {_isFrenchRegistration},
              onSelectionChanged: (selection) {
                setState(() {
                  _isFrenchRegistration = selection.first;
                  _countryController.text = _isFrenchRegistration
                      ? 'FRANCE'
                      : (_foreignCountries[_foreignCountryCode] ??
                            'AUTRE PAYS');
                  _completed = false;
                  _error = null;
                });
              },
            ),
          ),
        if (widget.readOnly)
          _EstablishmentCard(
            icon: Icons.lock_outline_rounded,
            title: 'ENTREPRISE VALIDÉE PAR SPHOT',
            status: 'LECTURE SEULE',
            statusColor: const Color(0xFF15803D),
            child: const Text(
              'Une modification de ces informations nécessitera un nouveau contrôle.',
              style: TextStyle(
                color: WebColors.blue,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        IgnorePointer(
          ignoring: widget.readOnly,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _EstablishmentCard(
                  icon: Icons.storefront_outlined,
                  title: 'INFORMATIONS DE L’ENTREPRISE',
                  status: _completed ? 'COMPLET' : 'À COMPLÉTER',
                  statusColor: _completed
                      ? WebColors.red
                      : const Color(0xFF6B7280),
                  child: Column(
                    children: [
                      _EstablishmentField(
                        controller: _legalNameController,
                        label: 'Raison sociale *',
                        validator: _requiredValidator,
                        onChanged: _markAsModified,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: const [UpperCaseTextInputFormatter()],
                      ),
                      _EstablishmentField(
                        controller: _businessNameController,
                        label: 'Nom commercial / marque *',
                        validator: _requiredValidator,
                        onChanged: _markAsModified,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: const [UpperCaseTextInputFormatter()],
                      ),
                      FormField<String>(
                        initialValue: _activityType,
                        validator: (value) => value == null
                            ? 'Sélectionnez un type d’activité'
                            : null,
                        builder: (fieldState) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GestureDetector(
                            key: _activityFieldKey,
                            onTap: widget.readOnly
                                ? null
                                : () => _openActivityMenu(fieldState),
                            child: InputDecorator(
                              decoration: _activityFieldDecoration(
                                'Type d’activité *',
                              ).copyWith(errorText: fieldState.errorText),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _activityType == null
                                          ? 'Sélectionnez une activité'
                                          : _activityType == 'Autre' &&
                                                _otherActivityController.text
                                                    .trim()
                                                    .isNotEmpty
                                          ? 'Autre — ${_otherActivityController.text.trim()}'
                                          : _activityType!,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _activityType == null
                                            ? const Color(0xFF4B5F97)
                                            : WebColors.blue,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: WebColors.red,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_isFrenchRegistration) ...[
                        _EstablishmentField(
                          controller: _siretController,
                          label: 'SIRET *',
                          validator: _siretValidator,
                          onChanged: (value) {
                            _registryStatus = 'unverified';
                            _registryMessage = '';
                            _markAsModified(value);
                          },
                          keyboardType: TextInputType.number,
                          digitsOnly: true,
                          maxLength: 14,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _checkingRegistry ? null : _verifySiret,
                            icon: _checkingRegistry
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.verified_outlined),
                            label: const Text('VÉRIFIER ET PRÉREMPLIR'),
                          ),
                        ),
                        if (_registryMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              _registryMessage,
                              style: TextStyle(
                                color: _registryStatus == 'verified'
                                    ? const Color(0xFF15803D)
                                    : WebColors.red,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        _EstablishmentField(
                          controller: _sirenController,
                          label: 'SIREN calculé depuis le SIRET',
                          validator: _requiredValidator,
                          onChanged: _markAsModified,
                          readOnly: true,
                        ),
                      ] else ...[
                        DropdownButtonFormField<String>(
                          value: _foreignCountryCode,
                          decoration: _fieldDecoration(
                            'Pays d’immatriculation *',
                          ),
                          items: _foreignCountries.entries
                              .map(
                                (entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _foreignCountryCode = value;
                              _countryController.text =
                                  _foreignCountries[value]!;
                              _completed = false;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        _EstablishmentField(
                          controller: _foreignRegistrationController,
                          label: 'Numéro d’enregistrement national *',
                          validator: _requiredValidator,
                          onChanged: _markAsModified,
                        ),
                        _EstablishmentField(
                          controller: _foreignAuthorityController,
                          label: 'Registre ou autorité (EIN, ABN/ACN, CIPC…) *',
                          validator: _requiredValidator,
                          onChanged: _markAsModified,
                        ),
                        OutlinedButton.icon(
                          onPressed: _pickForeignProof,
                          icon: const Icon(Icons.upload_file_outlined),
                          label: Text(
                            _selectedProof?.name ??
                                _savedForeignProof['fileName']?.toString() ??
                                'JOINDRE LE JUSTIFICATIF OFFICIEL *',
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'PDF, PNG, JPG ou WEBP — 5 Mo maximum. Le dossier sera contrôlé manuellement.',
                          style: TextStyle(
                            color: WebColors.blue,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _EstablishmentCard(
                  iconWidget: SvgPicture.asset(
                    'data/icons/fire_blue_icon.svg',
                    width: 30,
                    height: 30,
                    fit: BoxFit.contain,
                  ),
                  title: 'ADRESSE DE L’ENTREPRISE',
                  child: Column(
                    children: [
                      _EstablishmentField(
                        controller: _addressController,
                        label: 'Adresse *',
                        validator: _requiredValidator,
                        onChanged: _markAsModified,
                      ),
                      _EstablishmentField(
                        controller: _addressComplementController,
                        label: 'Complément d’adresse',
                        onChanged: _markAsModified,
                      ),
                      _EstablishmentField(
                        controller: _postalCodeController,
                        label: 'Code postal *',
                        validator: _requiredValidator,
                        onChanged: _markAsModified,
                      ),
                      _EstablishmentField(
                        controller: _cityController,
                        label: 'Ville *',
                        validator: _requiredValidator,
                        onChanged: _markAsModified,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: const [UpperCaseTextInputFormatter()],
                      ),
                      if (_isFrenchRegistration)
                        _EstablishmentField(
                          controller: _countryController,
                          label: 'Pays *',
                          validator: _requiredValidator,
                          onChanged: _markAsModified,
                          readOnly: true,
                        ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: WebColors.red,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                if (!widget.readOnly)
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: _completed
                            ? WebColors.red
                            : WebColors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Icon(
                              _completed
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.save_outlined,
                            ),
                      label: Text(
                        _saving
                            ? 'ENREGISTREMENT…'
                            : _completed
                            ? 'ENTREPRISE ENREGISTRÉE'
                            : 'ENREGISTRER L’ENTREPRISE',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

InputDecoration _fieldDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0xFF4B5F97)),
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    counterText: '',
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: WebColors.blue, width: 2),
    ),
  );
}

InputDecoration _activityFieldDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(
      color: WebColors.blue,
      fontWeight: FontWeight.w700,
    ),
    filled: true,
    fillColor: WebColors.blue.withOpacity(0.025),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: WebColors.blue, width: 1.6),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: WebColors.blue, width: 1.6),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: WebColors.blue, width: 2),
    ),
  );
}

class _EstablishmentCard extends StatelessWidget {
  const _EstablishmentCard({
    this.icon,
    this.iconWidget,
    required this.title,
    this.status,
    required this.child,
    this.statusColor = const Color(0xFF6B7280),
  });

  final IconData? icon;
  final Widget? iconWidget;
  final String title;
  final String? status;
  final Widget child;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child:
                    iconWidget ?? Icon(icon, color: WebColors.blue, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: WebColors.blue,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (status != null && status!.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        status!,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _EstablishmentField extends StatelessWidget {
  const _EstablishmentField({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.validator,
    this.keyboardType,
    this.digitsOnly = false,
    this.maxLength,
    this.readOnly = false,
    this.inputFormatters = const [],
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool digitsOnly;
  final int? maxLength;
  final bool readOnly;
  final List<TextInputFormatter> inputFormatters;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final formatters = <TextInputFormatter>[
      if (digitsOnly) FilteringTextInputFormatter.digitsOnly,
      ...inputFormatters,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: formatters.isEmpty ? null : formatters,
        textCapitalization: textCapitalization,
        maxLength: maxLength,
        readOnly: readOnly,
        validator: validator,
        onChanged: onChanged,
        style: const TextStyle(
          color: WebColors.blue,
          fontWeight: FontWeight.w700,
        ),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: _fieldDecoration(label).copyWith(
          fillColor: readOnly
              ? const Color(0xFFEFF3F8)
              : const Color(0xFFF8FAFC),
          suffixIcon: readOnly
              ? const Icon(Icons.lock_outline, color: Color(0xFF6B7280))
              : null,
        ),
      ),
    );
  }
}
