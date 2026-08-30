import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/web_colors.dart';

class IdentityProfessionalSection extends StatefulWidget {
  const IdentityProfessionalSection({
    super.key,
    required this.user,
    this.requestId,
    this.readOnly = false,
    this.developmentBypass = false,
    this.onSaved,
  });

  final User? user;
  final String? requestId;
  final bool readOnly;
  final bool developmentBypass;
  final VoidCallback? onSaved;

  @override
  State<IdentityProfessionalSection> createState() =>
      _IdentityProfessionalSectionState();
}

class _IdentityProfessionalSectionState
    extends State<IdentityProfessionalSection> {
  final _formKey = GlobalKey<FormState>();
  final _lastNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _functionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _professionalEmailController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _completed = false;
  bool _requestExists = false;
  String? _error;
  String? _certifiedDisplayName;
  String? _certifiedEmail;
  String? _certifiedId;

  String? get _requestId {
    final value = widget.requestId?.trim() ?? '';
    if (value.isNotEmpty) return value;
    return widget.user?.uid;
  }

  @override
  void initState() {
    super.initState();
    _initialiseProfile();
  }

  @override
  void dispose() {
    _lastNameController.dispose();
    _firstNameController.dispose();
    _functionController.dispose();
    _phoneController.dispose();
    _professionalEmailController.dispose();
    super.dispose();
  }

  Future<void> _initialiseProfile() async {
    final user = widget.user;
    final requestId = _requestId;
    _professionalEmailController.text = user?.email ?? '';
    _certifiedDisplayName = user?.displayName;
    _certifiedEmail = user?.email;
    _certifiedId = user?.uid ?? requestId;

    if (requestId != null) {
      _prefillDisplayName(user?.displayName);

      if (!widget.developmentBypass) {
        try {
          final snapshot = await FirebaseFirestore.instance
              .collection('advertiserRequests')
              .doc(requestId)
              .get();
          final data = snapshot.data();
          _requestExists = snapshot.exists;

          if (data != null) {
            _certifiedDisplayName = _textValue(
              data['displayName'],
              _certifiedDisplayName ?? '',
            );
            _certifiedEmail = _textValue(
              data['email'] ?? data['contactEmail'],
              _certifiedEmail ?? '',
            );
            _lastNameController.text = _textValue(
              data['contactLastName'],
              _lastNameController.text,
            );
            _firstNameController.text = _textValue(
              data['contactFirstName'],
              _firstNameController.text,
            );
            _functionController.text = _textValue(data['contactFunction']);
            _phoneController.text = _PhoneNumberInputFormatter.format(
              _textValue(data['contactPhone']),
            );
            _professionalEmailController.text = _textValue(
              data['contactEmail'],
              _professionalEmailController.text,
            );
            _completed = data['profileCompleted'] == true || _fieldsAreComplete;
          }
        } catch (error) {
          _error = 'Impossible de charger les informations enregistrées.';
          debugPrint('Chargement identité annonceur impossible : $error');
        }
      }
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  String _textValue(Object? value, [String fallback = '']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  void _prefillDisplayName(String? displayName) {
    final parts = (displayName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) return;
    _firstNameController.text = parts.first;
    if (parts.length > 1) {
      _lastNameController.text = parts.skip(1).join(' ');
    }
  }

  bool get _fieldsAreComplete {
    return _lastNameController.text.trim().isNotEmpty &&
        _firstNameController.text.trim().isNotEmpty &&
        _functionController.text.trim().isNotEmpty &&
        _phoneController.text.trim().isNotEmpty &&
        _professionalEmailController.text.trim().isNotEmpty;
  }

  Future<void> _save() async {
    if (widget.readOnly) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final user = widget.user;
      final requestId = _requestId;
      final lastName = _lastNameController.text.trim();
      final firstName = _firstNameController.text.trim();
      final contactEmail = _professionalEmailController.text.trim();

      if (requestId != null && !widget.developmentBypass) {
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
              'email': user?.email ?? contactEmail,
              'displayName': user?.displayName ?? '$firstName $lastName',
              'contactName': '$firstName $lastName'.trim(),
              'contactFirstName': firstName,
              'contactLastName': lastName,
              'contactFunction': _functionController.text.trim(),
              'contactPhone': _phoneController.text.trim(),
              'contactEmail': contactEmail,
              'profileCompleted': true,
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
      debugPrint('Enregistrement identité annonceur impossible : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Champ obligatoire';
    }
    return null;
  }

  String? _emailValidator(String? value) {
    final requiredError = _requiredValidator(value);
    if (requiredError != null) return requiredError;

    final email = value!.trim();
    final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
    return valid ? null : 'Adresse email invalide';
  }

  void _profileChanged(String _) {
    if (_completed) setState(() => _completed = false);
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
        if (widget.readOnly)
          const _SectionCard(
            icon: Icons.lock_outline_rounded,
            title: 'PROFIL VALIDÉ PAR SPHOT',
            status: 'LECTURE SEULE',
            statusColor: Color(0xFF15803D),
            child: Text(
              'Ces informations ont servi à valider votre accès annonceur.',
              style: TextStyle(
                color: WebColors.blue,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        _SectionCard(
          icon: Icons.verified_user_outlined,
          title: 'IDENTITÉ CERTIFIÉE',
          status: widget.readOnly
              ? 'VALIDÉE PAR SPHOT'
              : widget.user == null
              ? 'EN ATTENTE'
              : 'CERTIFIÉE PROCONNECT',
          statusColor: widget.user == null && !widget.readOnly
              ? const Color(0xFF6B7280)
              : const Color(0xFF15803D),
          child: Column(
            children: [
              _ReadOnlyLine(
                label: 'Nom et prénom',
                value: _certifiedDisplayName,
              ),
              _ReadOnlyLine(label: 'Email certifié', value: _certifiedEmail),
              _ReadOnlyLine(
                label: 'Identifiant',
                value: _certifiedId,
                isLast: true,
              ),
            ],
          ),
        ),
        _SectionCard(
          icon: Icons.badge_outlined,
          title: 'PROFIL PROFESSIONNEL SPHOT',
          status: _completed ? 'COMPLET' : 'À COMPLÉTER',
          statusColor: _completed
              ? const Color(0xFF15803D)
              : const Color(0xFF6B7280),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _ProfileField(
                  controller: _lastNameController,
                  label: 'Nom affiché *',
                  validator: _requiredValidator,
                  onChanged: _profileChanged,
                  readOnly: widget.readOnly,
                ),
                _ProfileField(
                  controller: _firstNameController,
                  label: 'Prénom affiché *',
                  validator: _requiredValidator,
                  onChanged: _profileChanged,
                  readOnly: widget.readOnly,
                ),
                _ProfileField(
                  controller: _functionController,
                  label: 'Fonction *',
                  validator: _requiredValidator,
                  onChanged: _profileChanged,
                  readOnly: widget.readOnly,
                ),
                _ProfileField(
                  controller: _phoneController,
                  label: 'Téléphone professionnel *',
                  keyboardType: TextInputType.phone,
                  inputFormatters: const [_PhoneNumberInputFormatter()],
                  validator: _requiredValidator,
                  onChanged: _profileChanged,
                  readOnly: widget.readOnly,
                ),
                _ProfileField(
                  controller: _professionalEmailController,
                  label: 'Email professionnel *',
                  keyboardType: TextInputType.emailAddress,
                  validator: _emailValidator,
                  onChanged: _profileChanged,
                  readOnly: widget.readOnly,
                ),
                if (!widget.readOnly) const SizedBox(height: 4),
                if (!widget.readOnly)
                  SizedBox(
                    width: double.infinity,
                    height: 46,
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
                            ? 'IDENTITÉ PROFESSIONNELLE ENREGISTRÉE'
                            : 'ENREGISTRER L’IDENTITÉ PROFESSIONNELLE',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _error!,
              style: const TextStyle(
                color: WebColors.red,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
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

class _ReadOnlyLine extends StatelessWidget {
  const _ReadOnlyLine({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String? value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final displayedValue = value?.trim();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF4B5F97),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              displayedValue == null || displayedValue.isEmpty
                  ? 'Non disponible'
                  : displayedValue,
              style: const TextStyle(
                color: WebColors.blue,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.controller,
    required this.label,
    required this.validator,
    required this.onChanged,
    this.keyboardType,
    this.inputFormatters,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?) validator;
  final ValueChanged<String> onChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        onChanged: onChanged,
        readOnly: readOnly,
        style: const TextStyle(
          color: WebColors.blue,
          fontWeight: FontWeight.w700,
        ),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF4B5F97)),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
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
        ),
      ),
    );
  }
}

class _PhoneNumberInputFormatter extends TextInputFormatter {
  const _PhoneNumberInputFormatter();

  static String format(String input) {
    final trimmed = input.trim();
    final hasInternationalPrefix = trimmed.startsWith('+');
    var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 15) digits = digits.substring(0, 15);

    final groups = <String>[];
    for (var index = 0; index < digits.length; index += 2) {
      final end = index + 2 < digits.length ? index + 2 : digits.length;
      groups.add(digits.substring(index, end));
    }
    final formatted = groups.join(' ');
    if (formatted.isEmpty) return hasInternationalPrefix ? '+' : '';
    return hasInternationalPrefix ? '+$formatted' : formatted;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = format(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
