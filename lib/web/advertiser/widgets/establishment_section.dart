import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/web_colors.dart';

class EstablishmentSection extends StatefulWidget {
  const EstablishmentSection({super.key, required this.user});

  final User? user;

  @override
  State<EstablishmentSection> createState() => _EstablishmentSectionState();
}

class _EstablishmentSectionState extends State<EstablishmentSection> {
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

  static const _allowedLogoExtensions = <String>{
    'png',
    'jpg',
    'jpeg',
    'webp',
  };

  static const _maximumLogoSize = 2 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _legalNameController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _siretController = TextEditingController();
  final _sirenController = TextEditingController();
  final _addressController = TextEditingController();
  final _addressComplementController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _cityController = TextEditingController();
  final _countryController = TextEditingController(text: 'France');
  final _publicPhoneController = TextEditingController();
  final _publicEmailController = TextEditingController();
  final _websiteController = TextEditingController();

  String? _activityType;
  Uint8List? _logoBytes;
  String? _logoFileName;
  String? _logoExtension;
  String? _logoMimeType;
  String? _existingLogoUrl;
  bool _loading = true;
  bool _saving = false;
  bool _completed = false;
  bool _requestExists = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _siretController.addListener(_updateSiren);
    _initialiseEstablishment();
  }

  @override
  void dispose() {
    _siretController.removeListener(_updateSiren);
    _legalNameController.dispose();
    _businessNameController.dispose();
    _siretController.dispose();
    _sirenController.dispose();
    _addressController.dispose();
    _addressComplementController.dispose();
    _postalCodeController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    _publicPhoneController.dispose();
    _publicEmailController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _initialiseEstablishment() async {
    final user = widget.user;
    if (user != null) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('advertiserRequests')
            .doc(user.uid)
            .get();
        final data = snapshot.data();
        _requestExists = snapshot.exists;

        if (data != null) {
          final rawEstablishment = data['establishment'];
          final establishment = rawEstablishment is Map
              ? Map<String, dynamic>.from(rawEstablishment)
              : <String, dynamic>{};

          _legalNameController.text = _read(
            establishment['legalName'],
            data['organisation'],
          );
          _businessNameController.text = _read(
            establishment['businessName'],
            data['advertiserName'],
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
          _cityController.text = _read(establishment['city']);
          _countryController.text = _read(
            establishment['country'],
            'France',
          );
          _publicPhoneController.text = _read(
            establishment['publicPhone'],
            data['phone'],
          );
          _publicEmailController.text = _read(
            establishment['publicEmail'],
            data['publicEmail'],
          );
          _websiteController.text = _read(
            establishment['websiteUrl'],
            data['websiteUrl'],
          );
          _existingLogoUrl = _nullableRead(
            establishment['logoUrl'],
            data['logoUrl'],
          );

          final savedActivity = _read(establishment['activityType']);
          if (_activityTypes.contains(savedActivity)) {
            _activityType = savedActivity;
          }

          _completed = data['establishmentCompleted'] == true;
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

  String? _nullableRead(Object? primary, [Object? fallback]) {
    final value = _read(primary, fallback);
    return value.isEmpty ? null : value;
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

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final fileName = picked.name;
    final parts = fileName.split('.');
    final extension = parts.length > 1 ? parts.last.toLowerCase() : '';

    if (!_allowedLogoExtensions.contains(extension)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Format refusé. Utilisez PNG, JPG, JPEG ou WEBP.'),
        ),
      );
      return;
    }

    if (bytes.length > _maximumLogoSize) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le logo ne doit pas dépasser 2 Mo.')),
      );
      return;
    }

    final mimeType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };

    if (!mounted) return;
    setState(() {
      _logoBytes = bytes;
      _logoFileName = fileName;
      _logoExtension = extension;
      _logoMimeType = mimeType;
      _completed = false;
      _error = null;
    });
  }

  Future<String?> _uploadLogo(String uid) async {
    final bytes = _logoBytes;
    if (bytes == null) return _existingLogoUrl;

    final extension = _logoExtension ?? 'jpg';
    final reference = FirebaseStorage.instance
        .ref()
        .child('advertiser_logos')
        .child(uid)
        .child('logo_${DateTime.now().millisecondsSinceEpoch}.$extension');

    await reference.putData(
      bytes,
      SettableMetadata(contentType: _logoMimeType ?? 'image/jpeg'),
    );
    return reference.getDownloadURL();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final user = widget.user;
      var logoUrl = _existingLogoUrl;
      if (user != null) {
        logoUrl = await _uploadLogo(user.uid);
      }

      final siret = _digits(_siretController.text);
      final siren = _digits(_sirenController.text);
      final legalName = _legalNameController.text.trim();
      final businessName = _businessNameController.text.trim();
      final publicPhone = _publicPhoneController.text.trim();
      final publicEmail = _publicEmailController.text.trim();
      final websiteUrl = _websiteController.text.trim();

      if (user != null) {
        final creationData = _requestExists
            ? <String, Object?>{}
            : <String, Object?>{
                'status': 'pending',
                'createdAt': FieldValue.serverTimestamp(),
              };

        await FirebaseFirestore.instance
            .collection('advertiserRequests')
            .doc(user.uid)
            .set({
          ...creationData,
          'uid': user.uid,
          'organisation': legalName,
          'advertiserName': businessName,
          'siret': siret,
          'siren': siren,
          'phone': publicPhone,
          'publicEmail': publicEmail,
          'websiteUrl': websiteUrl,
          'logoUrl': logoUrl,
          'establishmentCompleted': true,
          'establishment': <String, Object?>{
            'legalName': legalName,
            'businessName': businessName,
            'activityType': _activityType,
            'siret': siret,
            'siren': siren,
            'address': _addressController.text.trim(),
            'addressComplement': _addressComplementController.text.trim(),
            'postalCode': _postalCodeController.text.trim(),
            'city': _cityController.text.trim(),
            'country': _countryController.text.trim(),
            'publicPhone': publicPhone,
            'publicEmail': publicEmail,
            'websiteUrl': websiteUrl,
            'logoUrl': logoUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        _requestExists = true;
      }

      if (!mounted) return;
      setState(() {
        _existingLogoUrl = logoUrl;
        _logoBytes = null;
        _logoFileName = null;
        _completed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Établissement enregistré.')),
      );
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
    final requiredError = _requiredValidator(value);
    if (requiredError != null) return requiredError;
    return _digits(value!).length == 14
        ? null
        : 'Le SIRET doit comporter 14 chiffres';
  }

  String? _emailValidator(String? value) {
    final requiredError = _requiredValidator(value);
    if (requiredError != null) return requiredError;
    final valid = RegExp(
      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
    ).hasMatch(value!.trim());
    return valid ? null : 'Adresse email invalide';
  }

  String? _websiteValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final candidate = text.contains('://') ? text : 'https://$text';
    final uri = Uri.tryParse(candidate);
    return uri != null && uri.host.contains('.')
        ? null
        : 'Adresse de site invalide';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(color: WebColors.red),
        ),
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EstablishmentCard(
            icon: Icons.storefront_outlined,
            title: 'INFORMATIONS DE L’ÉTABLISSEMENT',
            status: _completed ? 'COMPLET' : 'À COMPLÉTER',
            statusColor: _completed
                ? const Color(0xFF15803D)
                : const Color(0xFF6B7280),
            child: Column(
              children: [
                _EstablishmentField(
                  controller: _legalNameController,
                  label: 'Raison sociale *',
                  validator: _requiredValidator,
                  onChanged: _markAsModified,
                ),
                _EstablishmentField(
                  controller: _businessNameController,
                  label: 'Nom commercial / marque *',
                  validator: _requiredValidator,
                  onChanged: _markAsModified,
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    value: _activityType,
                    isExpanded: true,
                    decoration: _fieldDecoration('Type d’activité *'),
                    items: _activityTypes
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(type, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _activityType = value;
                        _completed = false;
                      });
                    },
                    validator: (value) => value == null
                        ? 'Sélectionnez un type d’activité'
                        : null,
                  ),
                ),
                _EstablishmentField(
                  controller: _siretController,
                  label: 'SIRET *',
                  validator: _siretValidator,
                  onChanged: _markAsModified,
                  keyboardType: TextInputType.number,
                  digitsOnly: true,
                  maxLength: 14,
                ),
                _EstablishmentField(
                  controller: _sirenController,
                  label: 'SIREN calculé depuis le SIRET',
                  validator: _requiredValidator,
                  onChanged: _markAsModified,
                  readOnly: true,
                ),
              ],
            ),
          ),
          _EstablishmentCard(
            icon: Icons.location_on_outlined,
            title: 'ADRESSE PUBLIQUE',
            status: 'INFORMATIONS PUBLIQUES',
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
                ),
                _EstablishmentField(
                  controller: _countryController,
                  label: 'Pays *',
                  validator: _requiredValidator,
                  onChanged: _markAsModified,
                ),
              ],
            ),
          ),
          _EstablishmentCard(
            icon: Icons.public_outlined,
            title: 'COORDONNÉES PUBLIQUES',
            status: 'VISIBLES PAR LES UTILISATEURS',
            child: Column(
              children: [
                _EstablishmentField(
                  controller: _publicPhoneController,
                  label: 'Téléphone public *',
                  validator: _requiredValidator,
                  onChanged: _markAsModified,
                  keyboardType: TextInputType.phone,
                ),
                _EstablishmentField(
                  controller: _publicEmailController,
                  label: 'Email public *',
                  validator: _emailValidator,
                  onChanged: _markAsModified,
                  keyboardType: TextInputType.emailAddress,
                ),
                _EstablishmentField(
                  controller: _websiteController,
                  label: 'Site Internet',
                  validator: _websiteValidator,
                  onChanged: _markAsModified,
                  keyboardType: TextInputType.url,
                ),
                _LogoPicker(
                  bytes: _logoBytes,
                  existingLogoUrl: _existingLogoUrl,
                  fileName: _logoFileName,
                  onPick: _saving ? null : _pickLogo,
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
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: WebColors.blue,
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
                  : const Icon(Icons.save_outlined),
              label: Text(
                _saving ? 'ENREGISTREMENT…' : 'ENREGISTRER L’ÉTABLISSEMENT',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
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

class _EstablishmentCard extends StatelessWidget {
  const _EstablishmentCard({
    required this.icon,
    required this.title,
    required this.status,
    required this.child,
    this.statusColor = const Color(0xFF6B7280),
  });

  final IconData icon;
  final String title;
  final String status;
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
              Icon(icon, color: WebColors.blue, size: 30),
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
                    const SizedBox(height: 5),
                    Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
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
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool digitsOnly;
  final int? maxLength;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final formatters = digitsOnly
        ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: formatters,
        maxLength: maxLength,
        readOnly: readOnly,
        validator: validator,
        onChanged: onChanged,
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

class _LogoPicker extends StatelessWidget {
  const _LogoPicker({
    required this.bytes,
    required this.existingLogoUrl,
    required this.fileName,
    required this.onPick,
  });

  final Uint8List? bytes;
  final String? existingLogoUrl;
  final String? fileName;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final hasLogo = bytes != null || existingLogoUrl != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'LOGO DE L’ÉTABLISSEMENT',
            style: TextStyle(
              color: WebColors.blue,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'PNG, JPG ou WEBP · 2 Mo maximum',
            style: TextStyle(
              color: Color(0xFF4B5F97),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasLogo) ...[
            const SizedBox(height: 12),
            Container(
              height: 110,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: bytes != null
                  ? Image.memory(bytes!, fit: BoxFit.contain)
                  : Image.network(
                      existingLogoUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Color(0xFF6B7280),
                        size: 42,
                      ),
                    ),
            ),
          ],
          if (fileName != null) ...[
            const SizedBox(height: 8),
            Text(
              fileName!,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF4B5F97),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onPick,
            style: OutlinedButton.styleFrom(
              foregroundColor: WebColors.blue,
              side: const BorderSide(color: WebColors.blue),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(
              hasLogo ? 'REMPLACER LE LOGO' : 'AJOUTER UN LOGO',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}
