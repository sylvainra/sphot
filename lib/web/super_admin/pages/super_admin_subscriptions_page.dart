import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SuperAdminSubscriptionsPage extends StatefulWidget {
  const SuperAdminSubscriptionsPage({super.key});

  @override
  State<SuperAdminSubscriptionsPage> createState() =>
      _SuperAdminSubscriptionsPageState();
}

class _SuperAdminSubscriptionsPageState extends State<SuperAdminSubscriptionsPage> {
  static const Color adminColor = Color(0xFF1E3A8A);
  static const Color redColor = Color(0xFFDC2626);

  String _statusFilter = 'all';
  String _countryFilter = 'all';
  String _regionFilter = 'all';
  String _departmentFilter = 'all';
  String _cityFilter = 'all';
  String _search = '';

  String _text(dynamic value) => (value ?? '').toString();

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(_text(value)) ?? 0;
  }

  String _formatDate(dynamic value) {
    if (value == null) return '—';

    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    } else if (value is String && value.trim().isNotEmpty) {
      date = DateTime.tryParse(value);
    }

    if (date == null) return '—';

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();

    return '$day/$month/$year';
  }

  List<String> _uniqueValues(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String key,
  ) {
    final values = docs
        .map((doc) => _text(doc.data()[key]).trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    values.sort();
    return ['all', ...values];
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredSubscriptions(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final filtered = docs.where((doc) {
      final data = doc.data();

      final status = _text(data['status']);
      final country = _text(data['country']);
      final region = _text(data['region']);
      final department = _text(data['department']);
      final city = _text(data['city']);

      if (_statusFilter != 'all' && status != _statusFilter) return false;
      if (_countryFilter != 'all' && country != _countryFilter) return false;
      if (_regionFilter != 'all' && region != _regionFilter) return false;
      if (_departmentFilter != 'all' && department != _departmentFilter) {
        return false;
      }
      if (_cityFilter != 'all' && city != _cityFilter) return false;

      final searchable = [
        data['billingOrganisation'],
        data['billingSiret'],
        data['billingContactName'],
        data['billingContactEmail'],
        data['adminUid'],
        data['organisationId'],
        country,
        region,
        department,
        city,
      ].map(_text).join(' ').toLowerCase();

      return searchable.contains(_search.toLowerCase().trim());
    }).toList();

    filtered.sort((a, b) {
      final left = [
        _text(a.data()['country']),
        _text(a.data()['region']),
        _text(a.data()['department']),
        _text(a.data()['city']),
        _text(a.data()['billingOrganisation']),
      ].join('|');

      final right = [
        _text(b.data()['country']),
        _text(b.data()['region']),
        _text(b.data()['department']),
        _text(b.data()['city']),
        _text(b.data()['billingOrganisation']),
      ].join('|');

      return left.compareTo(right);
    });

    return filtered;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'trial':
        return Colors.green;
      case 'active':
        return adminColor;
      case 'overdue':
        return Colors.orange;
      case 'cancelled':
        return redColor;
      default:
        return adminColor;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'trial':
        return 'ESSAI';
      case 'active':
        return 'ACTIF';
      case 'overdue':
        return 'EN RETARD';
      case 'cancelled':
        return 'RÉSILIÉ';
      default:
        return status.isEmpty ? 'INCONNU' : status.toUpperCase();
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
    return DropdownButtonFormField<String>(
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
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: adminColor, width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: adminColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: redColor,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

    Future<void> _updateSubscriptionStatus(
    String subscriptionId,
    String newStatus,
  ) async {
    final now = DateTime.now();

    final data = <String, dynamic>{
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (newStatus == 'active') {
      data.addAll({
        'subscriptionStartDate': Timestamp.fromDate(now),
        'subscriptionEndDate': Timestamp.fromDate(
          DateTime(now.year + 1, now.month, now.day),
        ),
        'lastPaymentDate': Timestamp.fromDate(now),
        'nextInvoiceDate': Timestamp.fromDate(now),
      });
    }

    await FirebaseFirestore.instance
        .collection('subscriptions')
        .doc(subscriptionId)
        .set(
          data,
          SetOptions(merge: true),
        );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('subscriptions').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Erreur de chargement des abonnements.',
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

        final allSubscriptions = snapshot.data!.docs;
        final subscriptions = _filteredSubscriptions(allSubscriptions);

        final totalCount = allSubscriptions.length;
        final trialCount = allSubscriptions
            .where((doc) => doc.data()['status'] == 'trial')
            .length;
        final activeCount = allSubscriptions
            .where((doc) => doc.data()['status'] == 'active')
            .length;
        final overdueCount = allSubscriptions
            .where((doc) => doc.data()['status'] == 'overdue')
            .length;
        final cancelledCount = allSubscriptions
            .where((doc) => doc.data()['status'] == 'cancelled')
            .length;

        final totalRescueStations =
            allSubscriptions.fold<int>(0, (total, doc) {
          return total + _intValue(doc.data()['numberOfRescueStations']);
        });

        final estimatedAnnualRevenue =
            allSubscriptions.fold<int>(0, (total, doc) {
          final data = doc.data();
          final stations = _intValue(data['numberOfRescueStations']);
          final price = _intValue(data['pricePerStationExclTax']);
          return total + (stations * price);
        });

        final countryValues = _uniqueValues(allSubscriptions, 'country');
        final regionValues = _uniqueValues(allSubscriptions, 'region');
        final departmentValues = _uniqueValues(allSubscriptions, 'department');
        final cityValues = _uniqueValues(allSubscriptions, 'city');

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _statusButton('TOUS ($totalCount)', 'all'),
                      _statusButton('ESSAI ($trialCount)', 'trial'),
                      _statusButton('ACTIFS ($activeCount)', 'active'),
                      _statusButton('EN RETARD ($overdueCount)', 'overdue'),
                      _statusButton('RÉSILIÉS ($cancelledCount)', 'cancelled'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: 220,
                        child: _filterDropdown(
                          label: 'Pays',
                          value: _countryFilter,
                          values: countryValues,
                          onChanged: (value) {
                            setState(() {
                              _countryFilter = value;
                            });
                          },
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: _filterDropdown(
                          label: 'Région',
                          value: _regionFilter,
                          values: regionValues,
                          onChanged: (value) {
                            setState(() {
                              _regionFilter = value;
                            });
                          },
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: _filterDropdown(
                          label: 'Département',
                          value: _departmentFilter,
                          values: departmentValues,
                          onChanged: (value) {
                            setState(() {
                              _departmentFilter = value;
                            });
                          },
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: _filterDropdown(
                          label: 'Commune',
                          value: _cityFilter,
                          values: cityValues,
                          onChanged: (value) {
                            setState(() {
                              _cityFilter = value;
                            });
                          },
                        ),
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
                      labelText:
                          'Recherche organisation, SIRET, email, commune...',
                      labelStyle: const TextStyle(
                        color: adminColor,
                        fontWeight: FontWeight.w700,
                      ),
                      prefixIcon: const Icon(Icons.search, color: adminColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _summaryCard(
                        title: 'Abonnements',
                        value: totalCount.toString(),
                      ),
                      const SizedBox(width: 8),
                      _summaryCard(
                        title: 'Postes surveillés',
                        value: totalRescueStations.toString(),
                      ),
                      const SizedBox(width: 8),
                      _summaryCard(
                        title: 'CA estimé',
                        value: '$estimatedAnnualRevenue € HT / an',
                      ),
                      const SizedBox(width: 8),
                      _summaryCard(
                        title: 'Essais en cours',
                        value: trialCount.toString(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: subscriptions.isEmpty
                  ? const Center(
                      child: Text(
                        'Aucun abonnement ne correspond aux filtres.',
                        style: TextStyle(
                          color: adminColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      itemCount: subscriptions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final doc = subscriptions[index];
                        final data = doc.data();

                        final status = _text(data['status']);
                        final numberOfRescueStations =
                            _intValue(data['numberOfRescueStations']);
                        final pricePerStation =
                            _intValue(data['pricePerStationExclTax']);
                        final annualAmount =
                            numberOfRescueStations * pricePerStation;

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
                                      _text(data['billingOrganisation']).isEmpty
                                          ? 'Organisation non renseignée'
                                          : _text(data['billingOrganisation']),
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
                                'Territoire : ${data['country'] ?? ''} / ${data['region'] ?? ''} / ${data['department'] ?? ''} / ${data['city'] ?? ''}',
                                style: const TextStyle(
                                  color: adminColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'SIRET : ${data['billingSiret'] ?? ''}',
                                style: const TextStyle(
                                  color: adminColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Contact facturation : ${data['billingContactName'] ?? ''}',
                                style: const TextStyle(
                                  color: adminColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Email facturation : ${data['billingContactEmail'] ?? ''}',
                                style: const TextStyle(
                                  color: adminColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Postes de secours : $numberOfRescueStations',
                                style: const TextStyle(
                                  color: adminColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Essai gratuit : ${data['trialDurationDays'] ?? 8} jours',
                                style: const TextStyle(
                                  color: adminColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Début essai : ${_formatDate(data['trialStartDate'])}',
                                style: const TextStyle(
                                  color: adminColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Fin essai : ${_formatDate(data['trialEndDate'])}',
                                style: const TextStyle(
                                  color: adminColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Début abonnement : ${_formatDate(data['subscriptionStartDate'])}',
                                style: const TextStyle(
                                  color: adminColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Fin abonnement : ${_formatDate(data['subscriptionEndDate'])}',
                                style: const TextStyle(
                                  color: adminColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Prochaine facture : ${_formatDate(data['nextInvoiceDate'])}',
                                style: const TextStyle(
                                  color: adminColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

Text(
  'Email activation : '
  '${_formatDate(data['activationEmailSentAt'])}',
  style: const TextStyle(
    color: adminColor,
    fontWeight: FontWeight.w600,
  ),
),
Text(
  'Rappel fin essai : '
  '${_formatDate(data['trialReminderEmailSentAt'])}',
  style: const TextStyle(
    color: adminColor,
    fontWeight: FontWeight.w600,
  ),
),
Text(
  'Relance retard : '
  '${_formatDate(data['overdueReminderEmailSentAt'])}',
  style: const TextStyle(
    color: adminColor,
    fontWeight: FontWeight.w600,
  ),
),

                              const SizedBox(height: 8),
                              Text(
                                'Tarif : $pricePerStation € HT / poste / an',
                                style: const TextStyle(
                                  color: adminColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Montant annuel estimé : $annualAmount € HT / an',
                                style: const TextStyle(
                                  color: redColor,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _updateSubscriptionStatus(
                                      doc.id,
                                      'active',
                                    ),
                                    icon: const Icon(
                                      Icons.check_circle_outline,
                                      color: adminColor,
                                    ),
                                    label: const Text(
                                      'PASSER ACTIF',
                                      style: TextStyle(
                                        color: adminColor,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _updateSubscriptionStatus(
                                      doc.id,
                                      'overdue',
                                    ),
                                    icon: const Icon(
                                      Icons.warning_amber_outlined,
                                      color: Colors.orange,
                                    ),
                                    label: const Text(
                                      'EN RETARD',
                                      style: TextStyle(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _updateSubscriptionStatus(
                                      doc.id,
                                      'cancelled',
                                    ),
                                    icon: const Icon(
                                      Icons.cancel_outlined,
                                      color: redColor,
                                    ),
                                    label: const Text(
                                      'RÉSILIER',
                                      style: TextStyle(
                                        color: redColor,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _updateSubscriptionStatus(
                                      doc.id,
                                      'trial',
                                    ),
                                    icon: const Icon(
                                      Icons.replay_outlined,
                                      color: adminColor,
                                    ),
                                    label: const Text(
                                      'REMETTRE ESSAI',
                                      style: TextStyle(
                                        color: adminColor,
                                        fontWeight: FontWeight.w900,
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