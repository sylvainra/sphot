"use strict";

// Integration locale des briques EXISTANTES, avec Firestore et Odoo simules.
// Pas d'appel reseau, aucune base Odoo modifiee, aucun paiement ni droit SPHOT.
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {initialPrices} = require("../advertiser_radius_tariffs");
const {createVerifiedOdooDraftFromServer} =
    require("../odoo_verified_checkout_wiring");

const UID = "admin_test_1234567890";
const ADVERT_ID = "advert_test_1234567890";
const CYCLE = "INITIAL_2026";
const SIRET = "99999999800019";
const VERSION = 2;
const ADMIN_PRICES = [499, 399, 299, 199];
const STATIONS = ["LONGE_09", "LONGE_13"];

function empreinte(x) {
  return crypto.createHash("sha256").update(JSON.stringify(x)).digest("hex");
}
function snapshot(data) {
  return {exists: data !== undefined, data: () => data};
}

function fixture(marche) {
  const adminMarket = marche === "ADMIN";
  const requestId = adminMarket ? UID : ADVERT_ID;
  const key = (collection, id) => collection + "/" + id;
  const saved = new Map();
  const put = (collection, id, data) =>
    saved.set(key(collection, id), structuredClone(data));
  const get = (collection, id) =>
    snapshot(saved.get(key(collection, id)));

  const firestore = {
    collection(collection) {
      return {
        doc(id) {
          return {
            collection, id,
            async get() {
              return get(collection, id);
            },
          };
        },
      };
    },
    async runTransaction(handler) {
      const pending = [];
      const result = await handler({
        async get(ref) {
          return get(ref.collection, ref.id);
        },
        create(ref, data) {
          pending.push(() => {
            assert.equal(saved.has(key(ref.collection, ref.id)), false);
            put(ref.collection, ref.id, data);
          });
        },
        update(ref, data) {
          pending.push(() => {
            const before = saved.get(key(ref.collection, ref.id));
            assert.ok(before);
            put(ref.collection, ref.id, {...before, ...data});
          });
        },
      });
      for (const operation of pending) operation();
      return result;
    },
  };
  const firestoreFn = () => firestore;
  firestoreFn.FieldValue = {serverTimestamp: () => "timestamp_server"};

  const claims = adminMarket ? {
    uid: UID, adminUid: UID, role: "ADMIN",
    territoireId: "territoire_123456",
  } : {
    uid: UID, role: "ANNONCEUR", advertiserRequestId: ADVERT_ID,
  };
  const firebaseAdmin = {
    auth: () => ({
      async verifyIdToken(token, checkRevoked) {
        assert.equal(token, "valid-token");
        assert.equal(checkRevoked, true);
        return claims;
      },
    }),
    firestore: firestoreFn,
  };

  const adminPricing = {
    type: "ADMIN", country: "FR", currency: "EUR",
    publishedVersion: VERSION, publishedPrices: ADMIN_PRICES,
  };
  const advertiserPricing = {
    type: "ADVERTISER_RADIUS", country: "FR", currency: "EUR",
    publishedVersion: VERSION, publishedPrices: initialPrices(),
  };
  put("commercialPricingMarkets", "FR_ADMIN", adminPricing);
  put("commercialPricingMarkets", "FR_ADVERTISER_RADIUS",
      advertiserPricing);

  const legalId = adminMarket ? "adminCgv" : "advertiserCgv";
  const legalAcceptance = {
    accepted: true, version: "1.0", revision: 2,
    acceptedAt: {seconds: 1793872800},
  };
  put("legalDocuments", legalId, {
    version: "1.0", revision: 2, published: true,
  });

  let ht;
  let choices;
  const pricingReference = adminMarket ?
    "FR_ADMIN-V" + VERSION :
    "FR_ADVERTISER_RADIUS-V" + VERSION;
  if (adminMarket) {
    ht = (ADMIN_PRICES[0] + ADMIN_PRICES[1]) * 100;
    choices = {stationIds: STATIONS.slice().sort()};
    put("admins", UID, {
      uid: UID, accessStatus: "approved",
      territoireId: "territoire_123456",
    });
    put("subscriptions", UID, {
      selectedRescueStationIds: STATIONS,
      numberOfRescueStations: STATIONS.length,
      billingCycle: "annual",
      billingPayerRelation: "manager",
      billingSiret: SIRET,
      commercialCycleKey: CYCLE,
      publishedPricingReference: pricingReference,
      publishedPricingVersion: VERSION,
    });
    put("odooAdminCgvAcceptanceEvidence", UID, {
      adminUid: UID, documentId: legalId, ...legalAcceptance,
      source: "sphot_admin_cgv_server_acceptance_v1",
      testOnly: false,
    });
  } else {
    ht = initialPrices()["0:0:2"] * 100;
    choices = {
      territory: "radius_5km", offer: "map", duration: "1 mois",
    };
    put("advertiserRequests", ADVERT_ID, {
      firebaseUid: UID,
      status: "approved",
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
  put("odooCommercialVerifications",
      marche + "_" + requestId + "_" + CYCLE, {
        market: marche, requestId, ownerUid: UID, cycleKey: CYCLE,
        status: "verified", testOnly: false,
        source: "sphot_server_odoo_verified_v1",
        verifiedAt: "2026-11-19T17:00:00.000Z",
        verifiedBy: "trusted_server_test",
        buyerEvidenceId: "buyer_test_1234",
        taxEvidenceId: "tax_test_1234",
        partnerId: adminMarket ? 9 : 8,
        productId: 1,
        adminTierProductIds: [2, 3, 4, 5],
        pricingReference,
        cgvVersion: "1.0", cgvRevision: 2,
        expectedUntaxedCents: ht,
        expectedTotalCents: Math.round(ht * 1.2),
        buyerCountry: "FR",
        buyerLegalId: SIRET, buyerSiret: SIRET,
        choicesHash: empreinte(choices),
        stationIdsHash: empreinte(STATIONS.slice().sort()),
        territoireId: "territoire_123456",
      });

  let odooCalls = 0;
  const odooClient = {
    async call(modele, methode, donnees) {
      odooCalls++;
      assert.equal(methode, "create_or_get_draft_order");
      assert.equal(modele, adminMarket ?
        "sphot.admin.checkout" : "sphot.advertiser.checkout");
      assert.equal(donnees.order_values.origin,
          "SPHOT " + pricingReference);
      assert.equal(donnees.expected_untaxed_cents, ht);
      assert.equal(donnees.expected_total_cents, Math.round(ht * 1.2));
      const ref = donnees.sphot_reference;
      const orderValues = donnees.order_values;
      return {
        contract: adminMarket ?
          "sphot_admin_atomic_order_v1" :
          "sphot_advertiser_atomic_order_v1",
        outcome: "created", reference: ref,
        fingerprint: donnees.sphot_fingerprint,
        order: {
          id: adminMarket ? 11 : 12,
          name: adminMarket ? "S00011" : "S00012",
          x_sphot_reference: ref,
          x_sphot_fingerprint: donnees.sphot_fingerprint,
          client_order_ref: ref,
          partner_id: [orderValues.partner_id, "Client TEST"],
          currency_id: [1, "EUR"],
          state: "draft",
          order_line: orderValues.order_line.map((_, i) => i + 100),
          invoice_ids: [],
          amount_untaxed: ht / 100,
          amount_tax: (Math.round(ht * 1.2) - ht) / 100,
          amount_total: Math.round(ht * 1.2) / 100,
        },
      };
    },
  };
  const options = {
    admin: firebaseAdmin,
    authorization: "Bearer valid-token",
    market: marche, requestId, odooClient,
  };
  return {
    options, saved, put, ht,
    getOdooCalls: () => odooCalls,
  };
}

for (const marche of ["ADMIN", "ADVERTISER"]) {
  test(marche + " : grille PUBLIEE Firestore -> commande Odoo unique",
      async () => {
        const f = fixture(marche);
        const premier = await createVerifiedOdooDraftFromServer(f.options);
        assert.equal(premier.receipt.amountUntaxedCents, f.ht);
        assert.equal(premier.receipt.amountTotalCents,
            Math.round(f.ht * 1.2));
        assert.equal(premier.receipt.activatesCommercialRights, false);
        assert.equal(premier.receipt.paymentStatus, "unverified");
        assert.equal(f.getOdooCalls(), 1);
        const intent = f.saved.get("odooCheckoutIntents/" +
            marche + "_" + f.options.requestId + "_" + CYCLE);
        assert.equal(intent.status, "draft_created");
        assert.equal(intent.paymentStatus, "unverified");

        const second = await createVerifiedOdooDraftFromServer(f.options);
        assert.equal(second.alreadyExists, true);
        assert.equal(second.receipt.orderNumber,
            premier.receipt.orderNumber);
        assert.equal(f.getOdooCalls(), 1);
        assert.equal(f.saved.size, marche === "ADMIN" ? 9 : 6);
      });
}

test("ADMIN : changement de tarif publie bloque avant Odoo", async () => {
  const f = fixture("ADMIN");
  const pricing = f.saved.get("commercialPricingMarkets/FR_ADMIN");
  pricing.publishedPrices[0] = 599;
  await assert.rejects(
      createVerifiedOdooDraftFromServer(f.options),
      /Preuves Odoo|fiscalite|Odoo/i);
  assert.equal(f.getOdooCalls(), 0);
});

test("PUBLICITAIRE : changement de grille publiee bloque avant Odoo",
    async () => {
      const f = fixture("ADVERTISER");
      const pricing = f.saved.get(
          "commercialPricingMarkets/FR_ADVERTISER_RADIUS");
      pricing.publishedPrices["0:0:2"] = 199;
      await assert.rejects(
          createVerifiedOdooDraftFromServer(f.options),
          /Preuves Odoo|fiscalite|Odoo/i);
      assert.equal(f.getOdooCalls(), 0);
    });

test("Aucune preuve Odoo serveur : refus avant commande", async () => {
  const f = fixture("ADMIN");
  f.saved.delete("odooCommercialVerifications/" +
      "ADMIN_" + UID + "_" + CYCLE);
  await assert.rejects(createVerifiedOdooDraftFromServer(f.options),
      /Odoo/);
  assert.equal(f.getOdooCalls(), 0);
});

test("Le navigateur ne peut pas imposer un devis ou un paiement", async () => {
  const f = fixture("ADVERTISER");
  const result = await createVerifiedOdooDraftFromServer({
    ...f.options,
    quote: {amountExclTax: 1},
    expectedTotalCents: 1,
    partnerId: 999,
    prepared: {market: "ADMIN"},
    paymentStatus: "paid",
    activatesCommercialRights: true,
  });
  assert.equal(result.receipt.amountUntaxedCents, 14900);
  assert.equal(result.receipt.activatesCommercialRights, false);
  assert.equal(result.receipt.paymentStatus, "unverified");
  assert.equal(f.getOdooCalls(), 1);
});

test("Absence de client serveur Odoo : refus avant Firestore", async () => {
  const f = fixture("ADMIN");
  delete f.options.odooClient;
  await assert.rejects(createVerifiedOdooDraftFromServer(f.options),
      /Dependances/);
  assert.equal(f.getOdooCalls(), 0);
});
