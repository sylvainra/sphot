/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

// Orchestrateur INTERNE des commandes SPHOT. Pas de route HTTP exportée.
// Le navigateur ne peut jamais transmettre un objet `prepared`.
// La fonction prepareFromServer doit relire les choix commerciaux, les
// prix, le payeur, la fiscalité et l'acceptation des CGV dans les sources
// SERVEUR authentifiées. Elle ne peut pas simplement copier le body HTTP.
// Le moteur n'émet AUCUNE facture, ne déclenche AUCUN paiement, et
// n'accorde AUCUN droit commercial. Pas de retry aveugle si Odoo échoue.

const {resolveOdooCheckoutIdentity} = require("./odoo_checkout_identity");
const {assertPrepared, createOrGetOdooDraft} = require("./odoo_order_draft");

const COLLECTION = "odooCheckoutIntents";
const REFERENCE = /^SPHOT-(?:ADM|PUB)-[A-Z0-9_-]{8,100}$/;
const CYCLE = /^[A-Z0-9_-]{3,64}$/;

function refused(message, httpStatus = 409) {
  const e = new Error(message);
  e.code = "SPHOT_CHECKOUT_ORCHESTRATOR_REFUSED";
  e.httpStatus = httpStatus;
  return e;
}

function text(value) {
  return typeof value === "string" ? value.trim() : "";
}

function assertServerPreparation(identity, prepared) {
  const market = identity.market;
  const canonical = market === "ADMIN" ? "ADMIN" : "ADVERTISER";
  if (!prepared || typeof prepared !== "object" ||
      prepared.requestId !== identity.requestId ||
      !CYCLE.test(prepared.cycleKey || "") ||
      prepared.ownerUid !== identity.uid ||
      prepared.market !== canonical ||
      !REFERENCE.test(prepared.reference || "") ||
      prepared.testOnly !== false ||
      prepared.verified !== true ||
      !prepared.verification ||
      prepared.verification.source !== "sphot_server_firestore_verified" ||
      !text(prepared.verification.cgvVersion) ||
      !text(prepared.verification.cgvAcceptedAt) ||
      !text(prepared.verification.buyerEvidenceId) ||
      !text(prepared.verification.taxEvidenceId) ||
      !text(prepared.verification.pricingReference) ||
      prepared.orderValues?.origin !==
        `SPHOT ${prepared.verification.pricingReference}`) {
    throw refused("Justificatifs serveur de la commande incomplets.");
  }
  // Contrôle structurel Odoo déjà installé. Le statut `verified` est
  // insuffisant à lui seul et ne garantit pas le contrôle de Firestore.
  assertPrepared(canonical, prepared);
  return canonical;
}

function intentPayload(identity, prepared, serverTimestamp) {
  return {
    uid: identity.uid,
    requestId: identity.requestId,
    market: identity.market,
    cycleKey: prepared.cycleKey,
    reference: prepared.reference,
    fingerprint: prepared.fingerprint,
    expectedUntaxedCents: prepared.expectedUntaxedCents,
    expectedTotalCents: prepared.expectedTotalCents,
    pricingReference: prepared.verification.pricingReference,
    cgvVersion: prepared.verification.cgvVersion,
    cgvAcceptedAt: prepared.verification.cgvAcceptedAt,
    buyerEvidenceId: prepared.verification.buyerEvidenceId,
    taxEvidenceId: prepared.verification.taxEvidenceId,
    status: "draft_pending",
    testOnly: false,
    paymentStatus: "not_started",
    activatesCommercialRights: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

function sameIntent(current, identity, prepared) {
  return current && current.uid === identity.uid &&
    current.market === identity.market &&
    current.requestId === identity.requestId &&
    current.cycleKey === prepared.cycleKey &&
    current.reference === prepared.reference &&
    current.fingerprint === prepared.fingerprint &&
    current.expectedUntaxedCents === prepared.expectedUntaxedCents &&
    current.expectedTotalCents === prepared.expectedTotalCents &&
    current.cgvVersion === prepared.verification.cgvVersion &&
    current.pricingReference === prepared.verification.pricingReference &&
    current.testOnly === false;
}

function receiptFromSaved(current) {
  if (!current || current.status !== "draft_created" ||
      !text(current.orderNumber) ||
      !["draft", "sent"].includes(current.orderState)) {
    throw refused("État local de commande non vérifié.");
  }
  return {
    outcome: "existing", reference: current.reference,
    orderNumber: current.orderNumber, orderState: current.orderState,
    amountUntaxedCents: current.expectedUntaxedCents,
    amountTotalCents: current.expectedTotalCents,
    paymentStatus: "unverified", activatesCommercialRights: false,
  };
}

async function createOrResumeVerifiedCheckout({
  admin, authorization, market, requestId, prepareFromServer, odooClient,
} = {}) {
  if (typeof prepareFromServer !== "function") {
    throw refused("Vérification commerciale serveur manquante.", 503);
  }
  if (!odooClient || typeof odooClient.call !== "function") {
    throw refused("Liaison Odoo indisponible.", 503);
  }
  const identity = await resolveOdooCheckoutIdentity({
    admin, authorization, market, requestId,
  });
  const db = admin.firestore();
  // Aucune donnée de prix / identité du payeur n'est lue du navigateur.
  const prepared = await prepareFromServer({identity, db, admin});
  const canonical = assertServerPreparation(identity, prepared);
  // Une seule réservation par dossier ET cycle contractuel. Une référence
  // Odoo différente pour le même cycle est refusée avant toute requête.
  const intentId = `${identity.market}_${identity.requestId}_${prepared.cycleKey}`;
  const intentRef = db.collection(COLLECTION).doc(intentId);
  const timestamp = () => admin.firestore.FieldValue.serverTimestamp();

  const state = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(intentRef);
    if (snapshot.exists) {
      const current = snapshot.data() || {};
      if (!sameIntent(current, identity, prepared)) {
        throw refused("Une commande différente existe pour cette référence.");
      }
      if (current.status === "draft_created") {
        return {alreadyCreated: true, current};
      }
      if (current.status !== "draft_pending") {
        throw refused("Cette commande n'est pas dans un état reprenable.");
      }
      // Une réponse Odoo incertaine est toujours reprise par son opération
      // atomique de type create_or_get_draft_order, pas par un create simple.
      return {alreadyCreated: false};
    }
    tx.create(intentRef, intentPayload(identity, prepared, timestamp));
    return {alreadyCreated: false};
  });

  if (state.alreadyCreated) {
    return {receipt: receiptFromSaved(state.current), alreadyExists: true};
  }

  // Odoo garantit l'unicité de la référence par l'addon métier.
  const receipt = await createOrGetOdooDraft({
    market: canonical, prepared, odooClient,
  });
  if (!receipt || !["draft", "sent"].includes(receipt.orderState) ||
      receipt.reference !== prepared.reference ||
      receipt.activatesCommercialRights !== false) {
    throw refused("Résultat Odoo non conforme au brouillon attendu.", 502);
  }

  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(intentRef);
    const current = snapshot.data() || {};
    if (!snapshot.exists || !sameIntent(current, identity, prepared) ||
        !["draft_pending", "draft_created"].includes(current.status)) {
      throw refused("La commande a changé pendant le rapprochement.");
    }
    if (current.status === "draft_created") {
      if (current.orderNumber !== receipt.orderNumber ||
          current.orderState !== receipt.orderState) {
        throw refused("Réponse Odoo concurrente incohérente.");
      }
      return;
    }
    tx.update(intentRef, {
      status: "draft_created",
      orderNumber: receipt.orderNumber,
      orderState: receipt.orderState,
      // Le statut n'est en aucun cas une preuve de paiement.
      paymentStatus: "unverified",
      activatesCommercialRights: false,
      updatedAt: timestamp(),
    });
  });
  return {receipt, alreadyExists: receipt.outcome === "existing"};
}

module.exports = {createOrResumeVerifiedCheckout,
  assertServerPreparation, sameIntent, receiptFromSaved};
