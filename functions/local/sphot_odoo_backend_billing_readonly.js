"use strict";

// SPHOT / Odoo : AUDIT RETOUR ODOO -> BACKEND SPHOT EN LECTURE SEULE.
// Les deux factures TEST existent deja dans la copie neutralisee.
// Ne cree aucun devis, commande, facture, paiement ou droit SPHOT.
// Le lien Firestore est SIMULE seulement pour valider le lecteur backend.
// Aucune modification de functions/index.js ; aucune fonction publique.

const {readOdooBillingStatus} = require("../odoo_billing_status");
const CLONE = "sphot_checkout_clone_neutral_20261118";
const CAS = Object.freeze([
  Object.freeze({
    market: "ADMIN",
    reference: "SPHOT-ADM-0F3EDE8D43580D75C2D66D3C",
    orderId: 11, invoiceId: 18, totalCents: 60000,
  }),
  Object.freeze({
    market: "ADVERTISER",
    reference: "SPHOT-PUB-AD7D6478DECA71715DCD2321",
    orderId: 12, invoiceId: 19, totalCents: 17880,
  }),
]);

function verifier(condition, message) {
  if (!condition) throw new Error(message);
}
function clientLectureOdoo({apiKey, fetchImpl = globalThis.fetch} = {}) {
  verifier(typeof apiKey === "string" && apiKey.length > 12,
      "Cle Odoo TEST absente");
  verifier(typeof fetchImpl === "function",
      "Transport de lecture Odoo indisponible");

  const autorisations = Object.freeze({
    "sale.order": "search_read",
    "account.move": "read",
  });
  return Object.freeze({
    async call(model, method, body) {
      verifier(Object.hasOwn(autorisations, model) &&
          autorisations[model] === method &&
          body && typeof body === "object" && !Array.isArray(body),
      "Seules les deux operations de lecture Odoo sont autorisees");
      const url = "http://127.0.0.1:8069/json/2/" +
          encodeURIComponent(model) + "/" + method;
      const response = await fetchImpl(url, {
        method: "POST",
        headers: {
          Authorization: "bearer " + apiKey,
          "X-Odoo-Database": CLONE,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(20000),
        redirect: "error",
      });
      verifier(response?.ok === true, "Lecture Odoo TEST indisponible");
      const result = await response.json();
      verifier(result !== null && typeof result === "object" &&
          !Object.hasOwn(result, "error"),
      "Reponse de lecture Odoo invalide");
      return result;
    },
  });
}

function lectureSimuleeFirestore(cas, empreinte) {
  const uid = "SPHOT_LECTURE_TEST_" + cas.market;
  const linked = {
    ownerUid: uid,
    adminUid: uid,
    market: cas.market,
    orderReference: cas.reference,
    orderFingerprint: empreinte,
    testOnly: false,
  };
  const identity = {
    uid, requestId: uid, market: cas.market,
    dossier: cas.market === "ADVERTISER" ?
      {odooBilling: linked} : {},
  };
  const db = {
    collection(name) {
      verifier(["subscriptions", "adminOdooCycles"].includes(name),
          "Collection fictive inattendue");
      return {
        doc(id) {
          return {
            async get() {
              if (cas.market === "ADMIN" &&
                  name === "subscriptions" && id === uid) {
                return {exists: true,
                  data: () => ({odooAdminCycleRef: cas.reference})};
              }
              if (cas.market === "ADMIN" &&
                  name === "adminOdooCycles" && id === cas.reference) {
                return {exists: true, data: () => linked};
              }
              return {exists: false, data: () => undefined};
            },
          };
        },
      };
    },
  };
  return {identity, admin: {firestore: () => db}};
}

async function verifierRetourBackend({odooClient, cas = CAS} = {}) {
  verifier(odooClient && typeof odooClient.call === "function",
      "Client Odoo en lecture seule requis");
  const resultats = [];
  for (const scenario of cas) {
    const orders = await odooClient.call("sale.order", "search_read", {
      domain: [["x_sphot_reference", "=", scenario.reference]],
      fields: ["id", "name", "state", "client_order_ref",
        "x_sphot_reference", "x_sphot_fingerprint", "invoice_ids"],
      limit: 2,
    });
    verifier(Array.isArray(orders) && orders.length === 1 &&
        orders[0].id === scenario.orderId &&
        orders[0].client_order_ref === scenario.reference &&
        orders[0].x_sphot_reference === scenario.reference &&
        orders[0].state === "sale" &&
        /^[a-f0-9]{64}$/.test(orders[0].x_sphot_fingerprint || "") &&
        Array.isArray(orders[0].invoice_ids) &&
        orders[0].invoice_ids.length === 1 &&
        orders[0].invoice_ids[0] === scenario.invoiceId,
    scenario.market + " : commande/facture existantes non conformes");

    // Seule la liaison Firestore est fictive. Le lecteur ci-dessous est
    // exactement celui du backend SPHOT deja present sur GitHub.
    const simulation = lectureSimuleeFirestore(
        scenario, orders[0].x_sphot_fingerprint);
    const status = await readOdooBillingStatus({
      ...simulation, odooClient,
    });
    verifier(status.status === "invoice_found" &&
        status.orderState === "sale" &&
        status.invoiceState === "posted" &&
        status.paymentState === "not_paid" &&
        status.amountTotalCents === scenario.totalCents &&
        status.amountResidualCents === scenario.totalCents &&
        status.activatesCommercialRights === false,
    scenario.market + " : statut de facture SPHOT incoherent");
    resultats.push({
      marche: scenario.market,
      commande: scenario.orderId,
      facture: scenario.invoiceId,
      totalTtc: (status.amountTotalCents / 100).toFixed(2),
      statut: status.paymentState,
    });
  }
  return resultats;
}

async function main() {
  verifier(process.argv.length === 2 || process.argv[2] === "--lecture",
      "Mode inconnu : seule la lecture est autorisee");
  console.log("=== SPHOT : RETOUR ODOO -> BACKEND (LECTURE SEULE) ===");
  console.log("Odoo : copie neutralisee uniquement ; Firestore : lien simule");
  const results = await verifierRetourBackend({
    odooClient: clientLectureOdoo({
      apiKey: process.env.SPHOT_ODOO_LOCAL_API_KEY,
    }),
  });
  for (const r of results) {
    console.log(r.marche + " : commande " + r.commande +
        ", facture " + r.facture + ", " + r.totalTtc +
        " EUR TTC, " + r.statut);
  }
  console.log("=== RETOUR BACKEND OK : 2/2 ===");
  console.log("AUCUNE ECRITURE ODOO/FIRESTORE, AUCUN DROIT SPHOT");
}

if (require.main === module) {
  main().catch(error => {
    console.error("STOP : " + String(error?.message ||
        "Erreur de controle").slice(0, 200));
    process.exitCode = 1;
  });
}

module.exports = {clientLectureOdoo, verifierRetourBackend, CAS, CLONE};
