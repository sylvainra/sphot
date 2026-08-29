import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../shared/web_colors.dart';

class IdentityProfessionalSection extends StatefulWidget {
  const IdentityProfessionalSection({
    super.key,
    required this.user,
  });

  final User? user;

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
    _professionalEmailController.text = user?.email ?? '';

    if (user != null) {
      _prefillDisplayName(user.displayName);

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('advertiserRequests')
            .doc(user.uid)
            .get();
        final data = snapshot.data();
        _requestExists = snapshot.exists;

        if (data != null) {
          _lastNameController.text =
              _textValue(data['contactLastName'], _lastNameController.text);
          _firstNameController.text =
              _textValue(data['contactFirstName'], _firstNameController.text);
          _functionController.text = _textValue(data['contactFunction']);
          _phoneController.text = _textValue(data['contactPhone']);
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
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final user = widget.user;
      final lastName = _lastNameController.text.trim();
      final firstName = _firstNameController.text.trim();
      final contactEmail = _professionalEmailController.text.trim();

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
          'email': user.email ?? '',
          'displayName': user.displayName ?? '',
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identité professionnelle enregistrée.')),
      );
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
        child: Center(
          child: CircularProgressIndicator(color: WebColors.red),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          icon: Icons.verified_user_outlined,
          title: 'IDENTITÉ CERTIFIÉE',
          status: widget.user == null ? 'EN ATTENTE' : 'CERTIFIÉE PROCONNECT',
          statusColor: widget.user == null
              ? const Color(0xFF6B7280)
              : const Color(0xFF15803D),
          child: Column(
            children: [
              _ReadOnlyLine(
                label: 'Nom et prénom',
                value: widget.user?.displayName,
              ),
              _ReadOnlyLine(
                label: 'Email certifié',
                value: widget.user?.email,
              ),
              _ReadOnlyLine(
                label: 'Identifiant',
                value: widget.user?.uid,
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
                ),
                _ProfileField(
                  controller: _firstNameController,
                  label: 'Prénom affiché *',
                  validator: _requiredValidator,
                  onChanged: _profileChanged,
                ),
                _ProfileField(
                  controller: _functionController,
                  label: 'Fonction *',
                  validator: _requiredValidator,
                  onChanged: _profileChanged,
                ),
                _ProfileField(
                  controller: _phoneController,
                  label: 'Téléphone professionnel *',
                  keyboardType: TextInputType.phone,
                  validator: _requiredValidator,
                  onChanged: _profileChanged,
                ),
                _ProfileField(
                  controller: _professionalEmailController,
                  label: 'Email professionnel *',
                  keyboardType: TextInputType.emailAddress,
                  validator: _emailValidator,
                  onChanged: _profileChanged,
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  height: 46,
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
                      _saving ? 'ENREGISTREMENT…' : 'ENREGISTRER',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _SectionCard(
          icon: Icons.alternate_email,
          title: 'COMPTE CONNECTÉ',
          status: 'LECTURE SEULE',
          child: Column(
            children: [
              _ReadOnlyLine(
                label: 'Adresse de connexion',
                value: widget.user?.email,
              ),
              _ReadOnlyLine(
                label: 'Fournisseur',
                value: widget.user == null ? null : 'ProConnect',
                isLast: true,
              ),
            ],
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
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final String? Function(String?) validator;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        onChanged: onChanged,
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
