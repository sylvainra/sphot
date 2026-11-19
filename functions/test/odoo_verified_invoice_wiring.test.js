"use strict";

// Tests hors ligne. Aucune connexion Odoo/Firebase et aucune facture reelle.
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {initialPrices} = require("../advertiser_radius_tariffs");
const {prepareCheckoutFromFirestore} =
    require("../odoo_checkout_verified_preparation");
const {confirmVerifiedInvoiceFromServer} =
    require("../odoo_verified_invoice_wiring");

const UID = "admin_test_1234567890";
const ADVERT_ID = "advert_test_1234567890";
const CYCLE = "INITIAL_2026";
const SIRET = "99999999800019";
const PRICES = [499, 399, 299, 199];

const sha = value => crypto.createHash("sha256")
    .update(JSON.stringify(value)).digest("hex");
function fixture(market) {
  const isAdmin = market === "ADMIN";
  const requestId = isAdmin ? UID : ADVERT_ID;
  const prefix = market + "_" + requestId + "_" + CYCLE;
  const dbStore = new Map();
  const k = (c, id) => c + "/" + id;
  const put = (c, id, value) => dbStore.set(k(c, id), value);
  const db = {
    collection(c) {
      return {doc(id) {
        return {async get() {
          const value = dbStore.get(k(c, id));
          return {exists: value !== undefined, data: () => value};
        }};
      }};
    },
  };
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => "TEST"};
  const claims = isAdmin ?
    {uid: UID, role: "ADMIN", adminUid: UID,
      territoireId: "territoire_123456"} :
    {uid: UID, role: "ANNONCEUR", advertiserRequestId: ADVERT_ID};
  const admin = {
    auth: () => ({
      async verifyIdToken(token, revoked) {
        assert.equal(token, "token-test");
        assert.equal(revoked, true);
        return claims;
      },
    }),
    firestore,
  };
  const isPaid = {invoice: null};
  const publishedPrices = isAdmin ? PRICES.slice() :
    initialPrices();
  const type = isAdmin ? "ADMIN" : "ADVERTISER_RADIUS";
  const pricingReference = "FR_" + type + "-V2";
  const ht = isAdmin ? 49900 : 14900;
  const ttc = Math.round(ht * 1.2);
  const selected = ["LONGE_09"];
  const choices = isAdmin ? {stationIds: selected} : {
    territory: "radius_5km", offer: "map", duration: "1 mois",
  };
  put("commercialPricingMarkets", "FR_" + type, {
    type, country: "FR", currency: "EUR",
    publishedVersion: 2, publishedPrices,
  });
  const legalId = isAdmin ? "adminCgv" : "advertiserCgv";
  put("legalDocuments", legalId, {
    version: "1.0", revision: 2, published: true,
  });
  if (isAdmin) {
    put("admins", UID, {
      uid: UID, accessStatus: "approved",
      territoireId: "territoire_123456",
    });
    put("subscriptions", UID, {
      selectedRescueStationIds: selected,
      numberOfRescueStations: 1,
      billingCycle: "annual",
      billingPayerRelation: "manager",
      billingSiret: SIRET,
      commercialCycleKey: CYCLE,
      publishedPricingReference: pricingReference,
      publishedPricingVersion: 2,
    });
    put("odooAdminCgvAcceptanceEvidence", UID, {
      adminUid: UID, documentId: legalId,
      accepted: true, version: "1.0",
      revision: 2, acceptedAt: {seconds: 1793872800},
      source: "sphot_admin_cgv_server_acceptance_v1",
      testOnly: false,
    });
  } else {
    put("advertiserRequests", ADVERT_ID, {
      status: "approved", firebaseUid: UID,
      commercialCycleKey: CYCLE,
      campaignActivated: false,
      advertisingSpotCompleted: true,
      diffusionCompleted: true,
      planningCompleted: true,
      advertisingTerritory: {level: "radius_5km"},
      diffusion: {visibilityType: "map"},
      planning: {durationLabel: "1 mois"},
      acceptedDocuments: {
        advertiserCgv: true, advertiserCgvVersion: "1.0",
        documentRevisions: {advertiserCgv: 2},
        acceptedAt: {seconds: 1793872800},
      },
    });
  }
  put("odooCommercialVerifications", prefix, {
    market, requestId, ownerUid: UID, cycleKey: CYCLE,
    status: "verified", testOnly: false,
    source: "sphot_server_odoo_verified_v1",
    verifiedAt: "2026-11-19T17:00:00.000Z",
    verifiedBy: "trusted_server_test",
    buyerEvidenceId: "buyer_test_1234",
    taxEvidenceId: "tax_test_1234",
    partnerId: isAdmin ? 9 : 8,
    productId: 1,
    adminTierProductIds: [2, 3, 4, 5],
    pricingReference,
    cgvVersion: "1.0", cgvRevision: 2,
    expectedUntaxedCents: ht, expectedTotalCents: ttc,
    buyerCountry: "FR", buyerLegalId: SIRET, buyerSiret: SIRET,
    choicesHash: sha(choices), stationIdsHash: sha(selected),
    territoireId: "territoire_123456",
  });

  const identity = {
    uid: UID, market, requestId,
    dossier: dbStore.get(k(isAdmin ? "admins" :
      "advertiserRequests", requestId)),
  };
  const state = {order: null, invoice: null, invoiceCalls: 0};
  const orderId = isAdmin ? 11 : 12;
  const invoiceId = isAdmin ? 18 : 19;
  const partnerId = isAdmin ? 9 : 8;
  const orderNumber = isAdmin ? "S00011" : "S00012";
  const invoiceNumber = isAdmin ? "INV/2026/18" : "INV/2026/19";

  const odooClient = {
    async call(model, method, body) {
      if (model === "sale.order" && method === "search_read") {
        return state.order ? [structuredClone(state.order)] : [];
      }
      if (model === "account.move" && method === "read") {
        return state.invoice ? [structuredClone(state.invoice)] : [];
      }
      if (method === "confirm_and_post_one_invoice") {
        state.invoiceCalls++;
        assert.equal(model, isAdmin ?
          "sphot.admin.checkout" : "sphot.advertiser.checkout");
        assert.equal(body.sphot_reference, state.order.x_sphot_reference);
        assert.equal(body.sphot_fingerprint,
            state.order.x_sphot_fingerprint);
        assert.equal(body.expected_total_cents, ttc);
        assert.equal(body.sale_order_id, orderId);
        state.order.state = "sale";
        state.order.invoice_ids = [invoiceId];
        state.invoice = {
          id: invoiceId, name: invoiceNumber,
          invoice_origin: orderNumber,
          state: "posted", move_type: "out_invoice",
          payment_state: "not_paid",
          partner_id: [partnerId, "CLIENT TEST"],
          currency_id: [1, "EUR"],
          amount_untaxed: ht / 100,
          amount_tax: (ttc - ht) / 100,
          amount_total: ttc / 100, amount_residual: ttc / 100,
          x_sphot_reference: state.order.x_sphot_reference,
          x_sphot_fingerprint: state.order.x_sphot_fingerprint,
          x_sphot_sale_order_id: [orderId, orderNumber],
        };
        return {
          contract: isAdmin ? "sphot_admin_atomic_invoice_v1" :
            "sphot_advertiser_atomic_invoice_v1",
          outcome: "created",
          reference: body.sphot_reference,
          fingerprint: body.sphot_fingerprint,
          invoice: {id: invoiceId},
        };
      }
      throw Error("Appel Odoo imprevu dans la simulation " +
          model + "." + method);
    },
  };

  async function seedOrder() {
    const prepared = await prepareCheckoutFromFirestore({
      identity, admin, db,
    });
    put("odooCheckoutIntents", prefix, {
      uid: UID, requestId, market, cycleKey: CYCLE,
      reference: prepared.reference,
      fingerprint: prepared.fingerprint,
      expectedUntaxedCents: ht, expectedTotalCents: ttc,
      pricingReference, cgvVersion: "1.0",
      status: "draft_created",
      paymentStatus: "unverified",
      activatesCommercialRights: false,
      testOnly: false, orderNumber, orderState: "draft",
    });
    state.order = {
      id: orderId, name: orderNumber, state: "draft",
      partner_id: [partnerId, "CLIENT TEST"],
      currency_id: [1, "EUR"],
      client_order_ref: prepared.reference,
      x_sphot_reference: prepared.reference,
      x_sphot_fingerprint: prepared.fingerprint,
      invoice_ids: [],
      amount_untaxed: ht / 100,
      amount_tax: (ttc - ht) / 100,
      amount_total: ttc / 100,
    };
    return prepared;
  }
  const options = {
    admin, authorization: "Bearer token-test",
    market, requestId, odooClient,
  };
  return {options, state, put, dbStore, prefix, seedOrder,
    prices: publishedPrices, ht, ttc};
}

for (const market of ["ADMIN", "ADVERTISER"]) {
  test(market + " : une facture unique, reprise idempotente et sans droits",
      async () => {
        const f = fixture(market);
        await f.seedOrder();
        const first = await confirmVerifiedInvoiceFromServer(f.options);
        assert.equal(first.outcome, "created");
        assert.equal(first.amountTotalCents, f.ttc);
        assert.equal(first.paymentStatus, "unverified");
        assert.equal(first.activatesCommercialRights, false);
        assert.equal(first.requiresSeparatePaymentEvidence, true);
        assert.equal(f.state.invoiceCalls, 1);
        const second = await confirmVerifiedInvoiceFromServer(f.options);
        assert.equal(second.outcome, "existing");
        assert.equal(second.invoiceId, first.invoiceId);
        assert.equal(f.state.invoiceCalls, 1);
        assert.equal(f.dbStore.get(
            "odooCheckoutIntents/" + f.prefix).status, "draft_created");
      });
}

test("ADMIN : nouveau tarif publie bloque avant Odoo", async () => {
  const f = fixture("ADMIN");
  await f.seedOrder();
  f.prices[0] = 599;
  await assert.rejects(
      confirmVerifiedInvoiceFromServer(f.options),
      /Odoo|fiscalite|Preuves/i);
  assert.equal(f.state.invoiceCalls, 0);
});

test("Aucun brouillon SPHOT reserve : facturation refusee", async () => {
  const f = fixture("ADVERTISER");
  await f.seedOrder();
  f.dbStore.delete("odooCheckoutIntents/" + f.prefix);
  await assert.rejects(
      confirmVerifiedInvoiceFromServer(f.options),
      /absente/);
  assert.equal(f.state.invoiceCalls, 0);
});

test("Empreinte de commande Odoo divergente : blocage", async () => {
  const f = fixture("ADMIN");
  await f.seedOrder();
  f.state.order.x_sphot_fingerprint = "0".repeat(64);
  await assert.rejects(
      confirmVerifiedInvoiceFromServer(f.options),
      /incoherente/);
  assert.equal(f.state.invoiceCalls, 0);
});

test("Montant TTC Odoo different : blocage avant facture", async () => {
  const f = fixture("ADVERTISER");
  await f.seedOrder();
  f.state.order.amount_total = 999;
  await assert.rejects(
      confirmVerifiedInvoiceFromServer(f.options),
      /incoherente/);
  assert.equal(f.state.invoiceCalls, 0);
});

test("Facture deja payee : aucun second post, aucun droit accorde", async () => {
  const f = fixture("ADMIN");
  await f.seedOrder();
  await confirmVerifiedInvoiceFromServer(f.options);
  f.state.invoice.payment_state = "paid";
  f.state.invoice.amount_residual = 0;
  const r = await confirmVerifiedInvoiceFromServer(f.options);
  assert.equal(r.outcome, "existing");
  assert.equal(r.paymentStatus, "unverified");
  assert.equal(r.activatesCommercialRights, false);
  assert.equal(f.state.invoiceCalls, 1);
});

test("Client Odoo absent : aucune operation comptable", async () => {
  const f = fixture("ADMIN");
  await f.seedOrder();
  await assert.rejects(
      confirmVerifiedInvoiceFromServer({
        ...f.options, odooClient: null,
      }), /Dependances/);
  assert.equal(f.state.invoiceCalls, 0);
});
