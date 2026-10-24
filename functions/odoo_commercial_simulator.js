/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

const {buildOdooDraft} = require("./odoo_commercial_bridge");

/**
 * Simulation locale du parcours SPHOT PUBLICITAIRE -> Odoo.
 *
 * Aucun appel reseau, identifiant API, ecriture Firestore, facture fiscale,
 * encaissement ou activation de campagne. Ce module n'est pas une Cloud
 * Function et n'est jamais une preuve de paiement utilisable en production.
 * Les references SIM-* ne doivent pas etre confondues avec celles d'Odoo.
 * L'etat est volontairement perdu lorsque l'instance est detruite.
 */

function simulatorError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function validReference(reference, label) {
  if (typeof reference !== "string" ||
      !/^[A-Za-z0-9_-]{6,96}$/.test(reference)) {
    throw simulatorError(400, label + " invalide.");
  }
  return reference;
}

function copy(value) {
  return JSON.parse(JSON.stringify(value));
}

function simulatedReference(prefix, sequence) {
  return "SIM-" + prefix + "-" + String(sequence).padStart(6, "0");
}

/**
 * Construit une simulation isolée. La fiscalite est seulement un scenario
 * de test fourni par le harnais serveur, jamais par un client Flutter.
 * Dans la vraie integration, Odoo determinera lui-meme les taxes et le TTC.
 */
function createOdooCommercialSimulator({taxRateBasisPoints = 0} = {}) {
  if (!Number.isSafeInteger(taxRateBasisPoints) ||
      taxRateBasisPoints < 0 || taxRateBasisPoints > 10000) {
    throw simulatorError(400, "Taux de taxe de simulation invalide.");
  }

  const purchases = new Map();
  let orderSequence = 0;
  let invoiceSequence = 0;
  let transactionSequence = 0;

  function purchaseFor(sphotReference) {
    const reference = validReference(sphotReference, "Reference SPHOT");
    const purchase = purchases.get(reference);
    if (!purchase) {
      throw simulatorError(404, "Commande de simulation introuvable.");
    }
    return purchase;
  }

  function snapshot(purchase) {
    return copy({
      mode: "SIMULATION_ONLY",
      persisted: false,
      odooApiCalled: false,
      paymentProofVerified: false,
      campaignActivationAllowed: false,
      automaticRenewal: false,
      sphotReference: purchase.sphotReference,
      pricingReference: purchase.pricingReference,
      partnerId: purchase.partnerId,
      currency: "EUR",
      discountPercent: purchase.discountPercent,
      untaxedCents: purchase.untaxedCents,
      simulatedTaxCents: purchase.simulatedTaxCents,
      simulatedTotalCents: purchase.simulatedTotalCents,
      simulatedPaidCents: purchase.simulatedPaidCents,
      simulatedAmountDueCents:
          purchase.simulatedTotalCents - purchase.simulatedPaidCents,
      order: purchase.order,
      invoice: purchase.invoice,
      simulatedPaymentStatus: purchase.simulatedPaymentStatus,
      attempts: purchase.attempts,
    });
  }

  function createDraftOrder({quote, partnerId, productIds, sphotReference}) {
    if (quote?.market !== "ADVERTISER_RADIUS") {
      throw simulatorError(400, "Simulation reservee au SPHOT PUBLICITAIRE.");
    }
    // Reutilise le contrat structurel existant. Le devis DOIT deja provenir
    // du calcul de confiance cote serveur : ce module de simulation ne
    // verifie pas son origine et ne doit jamais etre expose au navigateur.
    const prepared = buildOdooDraft({
      quote, partnerId, productIds, sphotReference,
    });
    const fingerprint = JSON.stringify({
      partner: prepared.values.partner_id,
      pricingReference: prepared.pricingReference,
      expectedUntaxedCents: prepared.expectedUntaxedCents,
      discountPercent: prepared.discountPercent,
      orderLine: prepared.values.order_line,
    });
    const existing = purchases.get(prepared.sphotReference);
    if (existing) {
      if (existing.fingerprint !== fingerprint) {
        throw simulatorError(409,
            "Reference SPHOT deja utilisee pour une autre commande.");
      }
      return snapshot(existing);
    }

    const untaxedCents = prepared.expectedUntaxedCents;
    const simulatedTaxCents = Math.round(
        untaxedCents * taxRateBasisPoints / 10000);
    const simulatedTotalCents = untaxedCents + simulatedTaxCents;
    if (!Number.isSafeInteger(simulatedTotalCents) ||
        simulatedTotalCents <= 0) {
      throw simulatorError(400, "Montant de simulation invalide.");
    }

    const purchase = {
      fingerprint,
      sphotReference: prepared.sphotReference,
      pricingReference: prepared.pricingReference,
      partnerId: prepared.values.partner_id,
      discountPercent: prepared.discountPercent,
      untaxedCents,
      simulatedTaxCents,
      simulatedTotalCents,
      simulatedPaidCents: 0,
      order: {
        reference: simulatedReference("SO", ++orderSequence),
        status: "simulated_draft",
      },
      invoice: null,
      simulatedPaymentStatus: "not_started",
      attempts: [],
    };
    purchases.set(prepared.sphotReference, purchase);
    return snapshot(purchase);
  }

  function confirmOrder(sphotReference) {
    const purchase = purchaseFor(sphotReference);
    purchase.order.status = "simulated_confirmed";
    return snapshot(purchase);
  }

  function createInvoiceDraft(sphotReference) {
    const purchase = purchaseFor(sphotReference);
    if (purchase.order.status !== "simulated_confirmed") {
      throw simulatorError(409, "Commande non confirmee en simulation.");
    }
    if (!purchase.invoice) {
      purchase.invoice = {
        reference: simulatedReference("INV", ++invoiceSequence),
        status: "simulated_draft",
      };
    }
    return snapshot(purchase);
  }

  function confirmInvoice(sphotReference) {
    const purchase = purchaseFor(sphotReference);
    if (!purchase.invoice) {
      throw simulatorError(409, "Aucune facture brouillon de simulation.");
    }
    purchase.invoice.status = "simulated_posted";
    return snapshot(purchase);
  }

  function simulatePayment({sphotReference, attemptKey, outcome}) {
    const purchase = purchaseFor(sphotReference);
    validReference(attemptKey, "Cle de tentative");
    if (!["success", "failure", "pending"].includes(outcome)) {
      throw simulatorError(400, "Resultat de paiement simule invalide.");
    }
    if (purchase.invoice?.status !== "simulated_posted") {
      throw simulatorError(409, "Facture non confirmee en simulation.");
    }

    const existing = purchase.attempts.find(
        (attempt) => attempt.attemptKey === attemptKey);
    if (existing) {
      if (existing.outcome !== outcome) {
        throw simulatorError(409,
            "Cle de tentative deja associee a un autre resultat.");
      }
      return snapshot(purchase);
    }
    if (["simulated_success", "simulated_pending"].includes(
        purchase.simulatedPaymentStatus)) {
      throw simulatorError(409,
          "Paiement deja confirme ou en attente dans la simulation.");
    }

    purchase.attempts.push({
      reference: simulatedReference("TX", ++transactionSequence),
      attemptKey,
      outcome,
      amountCents: purchase.simulatedTotalCents,
      mode: "DEMO_SIMULATION_ONLY",
    });
    purchase.simulatedPaymentStatus = "simulated_" + outcome;
    purchase.simulatedPaidCents = outcome === "success" ?
      purchase.simulatedTotalCents : 0;
    return snapshot(purchase);
  }

  return Object.freeze({
    createDraftOrder,
    confirmOrder,
    createInvoiceDraft,
    confirmInvoice,
    simulatePayment,
    getPurchase: (sphotReference) => snapshot(purchaseFor(sphotReference)),
  });
}

module.exports = {createOdooCommercialSimulator};
