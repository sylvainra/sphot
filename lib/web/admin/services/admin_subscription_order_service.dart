import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminSubscriptionOrderService {
  static const Color _blue = Color(0xFF1E3A8A);
  static const Color _red = Color(0xFFDC2626);
  static const Color _green = Color(0xFF16A34A);
  static const Color _orange = Color(0xFFF59E0B);
  static const double _defaultPricePerStationExclTax = 500.0;
  static const double _defaultVatRate = 20.0;

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(_text(value).replaceAll(',', '.')) ?? 0;
  }

  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(_text(value)) ?? 0;
  }

  static String _money(double value) =>
      '${value.toStringAsFixed(2).replaceAll('.', ',')} €';

  static Future<DocumentSnapshot<Map<String, dynamic>>?> _requestForUid(
    String uid,
  ) async {
    final direct = await FirebaseFirestore.instance
        .collection('adminRequests')
        .doc(uid)
        .get();
    if (direct.exists) return direct;

    final query = await FirebaseFirestore.instance
        .collection('adminRequests')
        .where('uid', isEqualTo: uid)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    return query.docs.first;
  }

  static Future<void> showAndSubmit({
    required BuildContext context,
    required String adminUid,
    required Map<String, dynamic> data,
  }) async {
    final uid = adminUid.trim();
    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Identifiant administrateur introuvable.'),
          backgroundColor: _red,
        ),
      );
      return;
    }

    final stations = _int(data['numberOfRescueStations']);
    final unitPrice = _number(data['pricePerStationExclTax']) > 0
        ? _number(data['pricePerStationExclTax'])
        : _defaultPricePerStationExclTax;
    final vatRate = _number(data['vatRate']) > 0
        ? _number(data['vatRate'])
        : _defaultVatRate;
    final totalExclTax = stations * unitPrice;
    final vatAmount = totalExclTax * vatRate / 100;
    final totalInclTax = totalExclTax + vatAmount;

    if (stations <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sélectionnez au moins un poste de secours avant de valider la commande.',
          ),
          backgroundColor: _orange,
        ),
      );
      return;
    }

    final billingOrganisation = _text(data['billingOrganisation']);
    final billingSiret = _text(data['billingSiret']);
    final billingAddress = _text(data['billingAddress']);
    final billingPostalCode = _text(data['billingPostalCode']);
    final billingCity = _text(data['billingCity']);
    final billingCountry = _text(data['billingCountry']).isEmpty
        ? 'France'
        : _text(data['billingCountry']);
    final billingContactName = _text(data['billingContactName']);
    final billingContactEmail = _text(data['billingContactEmail']);
    final billingContactPhone = _text(data['billingContactPhone']);
    final purchaseOrderNumber = _text(data['purchaseOrderNumber']);
    final engagementNumber = _text(data['engagementNumber']);
    final chorusServiceCode = _text(data['chorusServiceCode']);
    final purchaseOrderNotRequired = data['purchaseOrderNotRequired'] == true;

    if (billingOrganisation.isEmpty ||
        billingSiret.isEmpty ||
        billingAddress.isEmpty ||
        billingPostalCode.isEmpty ||
        billingCity.isEmpty ||
        billingContactEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complétez les informations administratives et de facturation avant de valider la commande.',
          ),
          backgroundColor: _orange,
        ),
      );
      return;
    }

    String paymentMethod = 'public_invoice';
    bool administrativeConfirmed = true;
    bool billingConfirmed = true;

    final validated = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                final publicRefsComplete = purchaseOrderNotRequired ||
                    purchaseOrderNumber.isNotEmpty ||
                    engagementNumber.isNotEmpty;
                final canConfirm = administrativeConfirmed &&
                    billingConfirmed &&
                    (paymentMethod == 'card' || publicRefsComplete);

                return AlertDialog(
                  title: const Text(
                    'VALIDER LA COMMANDE D’ABONNEMENT',
                    style: TextStyle(
                      color: _blue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  content: SizedBox(
                    width: 610,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ABONNEMENT ANNUEL SPHOT ADMIN',
                            style: TextStyle(
                              color: _red,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _summaryLine('Postes de secours', '$stations'),
                          _summaryLine(
                            'Tarif unitaire HT',
                            '${_money(unitPrice)} / an / poste',
                          ),
                          _summaryLine('Montant annuel HT', _money(totalExclTax)),
                          _summaryLine('TVA', '${vatRate.toStringAsFixed(2)} %'),
                          _summaryLine('Montant TTC', _money(totalInclTax)),
                          const Divider(height: 28),
                          const Text(
                            'MODE DE RÈGLEMENT',
                            style: TextStyle(
                              color: _blue,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          RadioListTile<String>(
                            value: 'public_invoice',
                            groupValue: paymentMethod,
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() => paymentMethod = value);
                            },
                            title: const Text(
                              'Facturation à une entité publique',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: const Text(
                              'Bon de commande / engagement + facturation électronique / Chorus Pro.',
                            ),
                            activeColor: _blue,
                          ),
                          RadioListTile<String>(
                            value: 'card',
                            groupValue: paymentMethod,
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() => paymentMethod = value);
                            },
                            title: const Text(
                              'Carte bancaire',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: const Text(
                              'À utiliser lorsque votre organisme autorise ce mode de règlement. Le prestataire de paiement sera raccordé séparément.',
                            ),
                            activeColor: _blue,
                          ),
                          if (paymentMethod == 'public_invoice' &&
                              !publicRefsComplete)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _orange.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: _orange),
                              ),
                              child: const Text(
                                'Renseignez un numéro de bon de commande ou un numéro d’engagement, sauf si votre structure a indiqué qu’aucun bon de commande n’est requis.',
                                style: TextStyle(
                                  color: _orange,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          const Divider(height: 28),
                          CheckboxListTile(
                            value: administrativeConfirmed,
                            onChanged: (value) => setDialogState(
                              () => administrativeConfirmed = value == true,
                            ),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Je confirme les références administratives de $billingOrganisation.',
                              style: const TextStyle(
                                color: _blue,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          CheckboxListTile(
                            value: billingConfirmed,
                            onChanged: (value) => setDialogState(
                              () => billingConfirmed = value == true,
                            ),
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Je confirme les informations de facturation pour cette commande annuelle.',
                              style: TextStyle(
                                color: _blue,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('ANNULER'),
                    ),
                    ElevatedButton(
                      onPressed: canConfirm
                          ? () => Navigator.of(dialogContext).pop(true)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text(
                        'VALIDER LA COMMANDE D’ABONNEMENT',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        false;

    if (!validated || !context.mounted) return;

    final requestSnapshot = await _requestForUid(uid);
    if (requestSnapshot == null || !requestSnapshot.exists) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dossier administratif introuvable.'),
          backgroundColor: _red,
        ),
      );
      return;
    }

    final requestData = requestSnapshot.data() ?? const <String, dynamic>{};
    final territoire = requestData['territoire'] is Map
        ? Map<String, dynamic>.from(requestData['territoire'] as Map)
        : const <String, dynamic>{};
    final requestNumber = _text(requestData['requestNumber']);
    final subscriptionStatus = _text(data['status']).toLowerCase();
    final orderType = subscriptionStatus == 'active' ||
            subscriptionStatus == 'awaiting_renewal'
        ? 'renewal'
        : 'initial';
    final year = DateTime.now().year;
    final orderReference = FirebaseFirestore.instance.collection('orders').doc();
    final serverNow = FieldValue.serverTimestamp();

    final orderData = <String, dynamic>{
      'orderId': orderReference.id,
      'orderNumber': null,
      'requestId': requestSnapshot.id,
      'dossierNumber': requestNumber,
      'adminUid': uid,
      'organisationId': _text(data['organisationId']).isEmpty
          ? uid
          : _text(data['organisationId']),
      'territoireId': _text(
        territoire['territoireId'] ?? data['territoireId'],
      ),
      'subscriptionYear': year,
      'orderType': orderType,
      'status': 'submitted',
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentMethod == 'card'
          ? 'awaiting_card_payment'
          : 'not_invoiced',
      'electronicInvoiceStatus': 'draft',
      'billingOrganisation': billingOrganisation,
      'billingSiret': billingSiret,
      'billingAddress': billingAddress,
      'billingPostalCode': billingPostalCode,
      'billingCity': billingCity,
      'billingCountry': billingCountry,
      'billingContactName': billingContactName,
      'billingContactEmail': billingContactEmail,
      'billingContactPhone': billingContactPhone,
      'purchaseOrderNotRequired': purchaseOrderNotRequired,
      'purchaseOrderNumber': purchaseOrderNumber,
      'engagementNumber': engagementNumber,
      'chorusServiceCode': chorusServiceCode,
      'numberOfRescueStations': stations,
      'unitPriceExclTax': unitPrice,
      'totalExclTax': totalExclTax,
      'vatRate': vatRate,
      'vatAmount': vatAmount,
      'totalInclTax': totalInclTax,
      'administrativeDataConfirmedAt': serverNow,
      'billingDataConfirmedAt': serverNow,
      'confirmedByUid': uid,
      'createdAt': serverNow,
      'updatedAt': serverNow,
    };

    final batch = FirebaseFirestore.instance.batch();
    batch.set(orderReference, orderData);
    batch.set(
      FirebaseFirestore.instance.collection('subscriptions').doc(uid),
      <String, dynamic>{
        'currentOrderId': orderReference.id,
        'commercialOrderStatus': 'submitted',
        'paymentMethod': paymentMethod,
        'administrativeDataConfirmedAt': serverNow,
        'billingDataConfirmedAt': serverNow,
        if (subscriptionStatus != 'active') 'status': 'order_pending',
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );
    batch.set(
      requestSnapshot.reference,
      <String, dynamic>{
        'commercialTracking.status': 'order_submitted',
        'commercialTracking.currentOrderId': orderReference.id,
        'commercialTracking.orderSubmittedAt': serverNow,
        'lastEvent': <String, dynamic>{
          'type': 'subscription_order_submitted',
          'category': 'commercial',
          'label': 'Commande d’abonnement annuel SPHOT ADMIN validée',
          'createdAt': serverNow,
          'createdByRole': 'admin',
          'createdByUid': uid,
        },
        'updatedAt': serverNow,
      },
      SetOptions(merge: true),
    );

    await batch.commit();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Commande d’abonnement enregistrée. Un email de confirmation va vous être envoyé.',
        ),
        backgroundColor: _green,
      ),
    );
  }

  static Widget _summaryLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 175,
            child: Text(
              '$label :',
              style: const TextStyle(
                color: _blue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
