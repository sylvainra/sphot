/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Prépare les écritures Firestore SERVER-SIDE après vérification Odoo.
// Aucun appel à Firestore : l'orchestrateur devra effectuer les deux écritures
// dans une transaction avec contrôle d'idempotence et de session.
const {assessActivation} = require("./odoo_admin_checkout_contract");

const SOURCE = "odoo_admin_v1";

function refused(message) {
  const error = new Error(message);
  error.code = "ADMIN_ENTITLEMENT_REFUSED";
  return error;
}

function isValidDate(date) {
  return date instanceof Date && Number.isFinite(date.getTime());
}

function yearEndUtc(year) {
  // Minuit du 1er janvier (heure de Paris) exclus : le 31 décembre est inclus.
  return new Date(Date.UTC(year, 11, 31, 23, 0, 0, 0));
}

function buildAdminActivationProjection({prepared, verifiedOdooStatus,
  payment, commitment, activatedAt} = {}) {
  if (!prepared || prepared.testOnly !== true ||
      !Number.isSafeInteger(prepared.year) ||
      !prepared.locked || !verifiedOdooStatus ||
      !verifiedOdooStatus.order ||
      !Number.isSafeInteger(verifiedOdooStatus.order.id) ||
      verifiedOdooStatus.order.id < 1 ||
      !isValidDate(activatedAt)) {
    throw refused("Activation ADMIN : éléments serveur insuffisants.");
  }
  const order = verifiedOdooStatus.order;
  const assessment = assessActivation({prepared, order: {
    reference: order.x_sphot_reference,
    fingerprint: order.x_sphot_fingerprint,
    state: order.state,
  }, payment, commitment});
  if (!assessment.allowed) {
    throw refused(`Activation ADMIN refusée : ${assessment.reason}.`);
  }
  if (order.client_order_ref !== prepared.reference ||
      activatedAt >= yearEndUtc(prepared.year) ||
      activatedAt.getUTCFullYear() !== prepared.year ||
      (assessment.basis === "stripe_verified" &&
        (!verifiedOdooStatus.invoice ||
          !Number.isSafeInteger(verifiedOdooStatus.invoice.id) ||
          verifiedOdooStatus.invoice.id < 1))) {
    throw refused("Activation ADMIN : commande, facture ou période incohérente.");
  }

  const stationIds = prepared.locked.stationIds;
  if (!Array.isArray(stationIds) || !stationIds.length ||
      new Set(stationIds).size !== stationIds.length) {
    throw refused("Activation ADMIN : sélection de postes absente.");
  }
  const endAt = yearEndUtc(prepared.year);
  const cycle = {
    source: SOURCE, market: "ADMIN", testOnly: true,
    adminUid: prepared.locked.adminUid,
    territoryId: prepared.locked.territoireId,
    cycleId: prepared.cycleId,
    orderReference: prepared.reference,
    orderFingerprint: prepared.fingerprint,
    odooOrderId: order.id,
    odooOrderNumber: order.name,
    odooInvoiceId: verifiedOdooStatus.invoice?.id || null,
    pricingReference: prepared.locked.pricingReference,
    cgvVersion: prepared.locked.cgvVersion,
    selectedRescueStationIds: [...stationIds],
    paymentMethod: prepared.paymentMethod,
    paymentStatus: assessment.paymentStatus,
    activationBasis: assessment.basis,
    commitmentDocumentHash: assessment.basis ===
      "verified_public_commitment" ? commitment.documentHash : null,
    activatedAt: new Date(activatedAt),
    validUntilExclusive: endAt,
  };
  const subscriptionPatch = {
    adminUid: prepared.locked.adminUid,
    status: "active",
    billingCycle: "annual",
    selectedRescueStationIds: [...stationIds],
    subscriptionStartDate: new Date(activatedAt),
    subscriptionEndDate: new Date(endAt.getTime() - 1),
    odooAdminManaged: true,
    odooAdminCycleRef: prepared.reference,
    odooPaymentStatus: assessment.paymentStatus,
    currentOrderNumber: order.name,
  };
  return Object.freeze({
    cycleCollection: "adminOdooCycles",
    cycleDocumentId: prepared.reference,
    cycle,
    subscriptionCollection: "subscriptions",
    subscriptionDocumentId: prepared.locked.adminUid,
    subscriptionPatch,
  });
}

function dueActions({dueDate, asOfDate, amountResidualCents,
  invoicePaymentState} = {}) {
  if (typeof dueDate !== "string" ||
      !/^\d{4}-\d{2}-\d{2}$/.test(dueDate) ||
      !isValidDate(asOfDate) ||
      !Number.isSafeInteger(amountResidualCents) || amountResidualCents < 0 ||
      !["not_paid", "partial", "in_payment", "paid"].includes(
          invoicePaymentState)) {
    throw refused("Échéance ADMIN : données Odoo invalides.");
  }
  const dueMs = Date.parse(`${dueDate}T00:00:00.000Z`);
  if (!Number.isFinite(dueMs) ||
      new Date(dueMs).toISOString().slice(0, 10) !== dueDate) {
    throw refused("Échéance ADMIN : date impossible.");
  }
  if (amountResidualCents === 0 && invoicePaymentState === "paid") {
    return {daysLate: 0, actionsDue: [], paymentStatus: "paid",
      suspendAccess: false};
  }
  if (amountResidualCents === 0 || invoicePaymentState === "paid") {
    throw refused("Échéance ADMIN : réconciliation Odoo incohérente.");
  }
  const todayUtc = Date.UTC(asOfDate.getUTCFullYear(),
      asOfDate.getUTCMonth(), asOfDate.getUTCDate());
  const daysLate = Math.max(0, Math.floor((todayUtc - dueMs) / 86400000));
  const actionsDue = [];
  if (daysLate >= 7) actionsDue.push("reminder_j7");
  if (daysLate >= 15) actionsDue.push("reminder_j15");
  if (daysLate >= 30) actionsDue.push("manual_review_j30");
  return {daysLate, actionsDue, paymentStatus: "unpaid",
    suspendAccess: false};
}

module.exports = {SOURCE, buildAdminActivationProjection, dueActions};
