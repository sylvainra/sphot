"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {secureReferenceFor} = require("../local/odoo_secure_checkout_client");
const {DEMO_PROJECT_ID, EMULATOR_HOST, assertDemoEmulator,
  createC2EmulatorService} = require("../local/odoo_c2_firestore_emulator");

const start = "2026-10-25T00:00:00Z";
const end = "2026-11-01T00:00:00Z";
const today = Date.parse("2026-10-29T09:00:00Z");

// Ces tests utilisent une fausse base en mémoire : aucune connexion Firebase.
process.env.FIRESTORE_EMULATOR_HOST = EMULATOR_HOST;
process.env.GCLOUD_PROJECT = DEMO_PROJECT_ID;

/**
 * Simule les méthodes transactionnelles utilisées par le SDK Admin.
 * Les écritures restent privées jusqu'à la validation de la transaction.
 * @return {Object} Base fictive et outils de test.
 */
function fakeFirestore() {
  const store = new Map();
  let queue = Promise.resolve();

  /**
   * @param {string} path Chemin de document fictif.
   * @return {Object} Référence locale.
   */
  function doc(path) {
    const parts = path.split("/");
    return {
      path, id: parts[parts.length - 1],
      get: async () => ({id: parts[parts.length - 1],
        exists: store.has(path),
        data: () => structuredClone(store.get(path))}),
      collection: (name) => collection(`${path}/${name}`),
    };
  }

  /**
   * @param {string} path Chemin de collection fictif.
   * @return {Object} Collection locale.
   */
  function collection(path) {
    return {
      doc: (id) => doc(`${path}/${id}`),
      where: (field, operator, value) => {
        assert.equal(operator, "==");
        return {get: async () => {
          const matches = [...store.entries()]
              .filter(([key, data]) => key.startsWith(`${path}/`) &&
                  key.slice(path.length + 1).indexOf("/") === -1 &&
                  data[field] === value);
          return {docs: await Promise.all(matches.map(([key]) =>
            doc(key).get()))};
        }};
      },
    };
  }

  /**
   * @param {Function} callback Fonction transactionnelle.
   * @return {Promise<*>} Résultat avec séquencement fictif.
   */
  async function runTransaction(callback) {
    const before = queue;
    let release;
    queue = new Promise((resolve) => {
      release = resolve;
    });
    await before;
    const staged = [];
    let wrote = false;
    const tx = {
      get: async (ref) => {
        if (wrote) throw new Error("Lecture après écriture interdite.");
        return ref.get();
      },
      update: (ref, data) => {
        wrote = true;
        staged.push({path: ref.path, data, kind: "update"});
      },
      create: (ref, data) => {
        wrote = true;
        staged.push({path: ref.path, data, kind: "create"});
      },
    };
    try {
      const result = await callback(tx);
      const copy = new Map(store);
      for (const op of staged) {
        if ((op.kind === "create" && copy.has(op.path)) ||
            (op.kind === "update" && !copy.has(op.path))) {
          throw new Error("Conflit de transaction fictive.");
        }
        copy.set(op.path, op.kind === "update" ?
          {...copy.get(op.path), ...structuredClone(op.data)} :
          structuredClone(op.data));
      }
      for (const [key, value] of copy) store.set(key, value);
      return result;
    } finally {
      release();
    }
  }
  return {collection, runTransaction,
    seed: (path, data) => store.set(path, structuredClone(data)),
    raw: (path) => structuredClone(store.get(path)),
    count: (prefix) => [...store.keys()]
        .filter((key) => key.startsWith(prefix)).length};
}

/**
 * @param {string} suffix Variante des identifiants.
 * @return {Object} Jeu de données strictement inventé.
 */
function fixture(suffix = "") {
  const requestId = `case_c2_2026${suffix}`;
  const campaignId = `campaign_c2_2026${suffix}`;
  return {requestId, campaignId,
    request: {
      status: "approved", advertisingSpotCompleted: true,
      diffusionCompleted: true, planningCompleted: true,
      diffusion: {visibilityType: "pack"},
      advertisingTerritory: {level: "radius_5km", radiusKm: 5},
      planning: {campaignStartDate: start, campaignEndDate: end},
      approvedApplication: {visual: {
        url: "https://example.test/c2-approved.jpg",
      }},
    },
    campaign: {
      status: "draft", advertiserRequestId: requestId,
      visibilityType: "pack", broadcastType: "local",
      centerLat: 46.4, centerLng: -1.5, radiusKm: 5,
      campaignStartDate: start, campaignEndDate: end,
      bannerUrl: "https://example.test/c2-approved.jpg",
      destinationUrl: "https://example.test/",
      advertiserName: "Annonceur fictif",
      contactEmail: "private@example.test",
    },
    order: {testOnly: true, odooState: "sale", odooOrderId: 7,
      reference: secureReferenceFor(requestId), odooTotalCents: 15480},
    invoice: {testOnly: true, odooInvoiceId: 12,
      odooInvoiceName: "FAC/TEST/C2", state: "posted",
      paymentState: "paid", amountTotalCents: 15480,
      amountResidualCents: 0, odooPaymentRecorded: true},
    payment: {paymentConfirmed: true, transactions: [{
      id: 51, reference: "FAC/TEST/C2", state: "done",
      provider: "stripe", currency: "EUR", amountCents: 15480,
      testOnly: true,
    }]},
    nowMs: today,
  };
}

/**
 * @param {Object} data Données fictives.
 * @return {Object} Couple base-service en mémoire.
 */
function setup(data) {
  const db = fakeFirestore();
  db.seed(`advertiserRequests/${data.requestId}`, data.request);
  db.seed(`adRequests/${data.campaignId}`, data.campaign);
  return {db, service: createC2EmulatorService(db)};
}

test("bloc C2 : refus du projet Firebase de production", () => {
  const previous = process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT = "sphot-ab80b";
  assert.throws(() => assertDemoEmulator(), /refusé/);
  process.env.GCLOUD_PROJECT = previous;
  const previousHost = process.env.FIRESTORE_EMULATOR_HOST;
  delete process.env.FIRESTORE_EMULATOR_HOST;
  assert.throws(() => assertDemoEmulator(), /refusé/);
  process.env.FIRESTORE_EMULATOR_HOST = previousHost;
});

test("bloc C2 : verrou vérifié à chaque opération", async () => {
  const input = fixture();
  const {service} = setup(input);
  const previousHost = process.env.FIRESTORE_EMULATOR_HOST;
  delete process.env.FIRESTORE_EMULATOR_HOST;
  await assert.rejects(service.activate(input), /refusé/);
  await assert.rejects(service.publicAdvertisements(today), /refusé/);
  process.env.FIRESTORE_EMULATOR_HOST = previousHost;
});

test("bloc C2 : paiement fictif puis transaction d'activation", async () => {
  const input = fixture();
  const {db, service} = setup(input);
  input.payment.paymentConfirmed = false;
  assert.equal((await service.activate(input)).action, "none");
  assert.equal(db.raw(`adRequests/${input.campaignId}`).status, "draft");
  assert.deepEqual(await service.publicAdvertisements(today), []);

  input.payment.paymentConfirmed = true;
  const paid = await service.activate(input);
  assert.equal(paid.action, "activate");
  assert.equal(db.raw(`adRequests/${input.campaignId}`).status, "active");
  const ads = await service.publicAdvertisements(today);
  assert.equal(ads.length, 1);
  assert.equal(ads[0].id, input.campaignId);
  assert.equal(ads[0].visibilityType, "pack");
  assert.equal(Object.hasOwn(ads[0], "contactEmail"), false);
  assert.equal(db.count(`adRequests/${input.campaignId}/c2DemoHistory/`), 1);
});

test("bloc C2 : échec de transaction n'écrit rien", async () => {
  const input = fixture();
  const {db, service} = setup(input);
  const transaction = db.runTransaction;
  db.runTransaction = (callback) => transaction(async (tx) => {
    await callback(tx);
    throw new Error("Échec fictif du commit.");
  });
  await assert.rejects(service.activate(input), /Échec fictif/);
  assert.equal(db.raw(`adRequests/${input.campaignId}`).status, "draft");
  assert.equal(db.count("c2DemoPaymentClaims/"), 0);
  assert.equal(db.count(`adRequests/${input.campaignId}/c2DemoHistory/`), 0);
});

test("bloc C2 : même facture et demandes simultanées", async () => {
  const first = fixture();
  const second = fixture("_another");
  const db = fakeFirestore();
  for (const input of [first, second]) {
    db.seed(`advertiserRequests/${input.requestId}`, input.request);
    db.seed(`adRequests/${input.campaignId}`, input.campaign);
  }
  const service = createC2EmulatorService(db);
  const results = await Promise.all([
    service.activate(first), service.activate(first),
    service.activate(second),
  ]);
  assert.deepEqual(results.map((r) => r.action),
      ["activate", "none", "none"]);
  assert.equal(results[2].reason, "invoice_already_claimed");
  assert.equal(db.count("c2DemoPaymentClaims/"), 1);
  assert.equal(db.count(`adRequests/${first.campaignId}/c2DemoHistory/`), 1);
  assert.equal(db.raw(`adRequests/${second.campaignId}`).status, "draft");
});

test("bloc C2 : refus de liaison à une autre commande", async () => {
  const input = fixture();
  const {db, service} = setup(input);
  input.order.reference = secureReferenceFor("another_case_c2");
  assert.equal((await service.activate(input)).reason, "odoo_order_unlinked");
  assert.equal(db.count("c2DemoPaymentClaims/"), 0);
});

test("bloc C2 : visuel et dossier refusés sans écriture", async () => {
  const changes = [
    (v) => {
      v.request.status = "pending";
    },
    (v) => {
      v.campaign.bannerUrl = "http://example.test/image.jpg";
    },
    (v) => {
      v.invoice.paymentState = "not_paid";
    },
    (v) => {
      v.payment.transactions[0].provider = "demo";
    },
  ];
  for (const change of changes) {
    const input = fixture();
    change(input);
    const {db, service} = setup(input);
    assert.equal((await service.activate(input)).action, "none");
    assert.equal(db.raw(`adRequests/${input.campaignId}`).status, "draft");
    assert.equal(db.count("c2DemoPaymentClaims/"), 0);
  }
});

test("bloc C2 : avant la période, aucune publicité visible", async () => {
  const input = fixture();
  input.nowMs = Date.parse(start) - 1;
  const {service} = setup(input);
  assert.equal((await service.activate(input)).phase, "scheduled");
  assert.deepEqual(await service.publicAdvertisements(input.nowMs), []);
});

test("bloc C2 : expiration atomique et répétition sans doublon", async () => {
  const input = fixture();
  const {db, service} = setup(input);
  await service.activate(input);
  assert.equal((await service.expire({campaignId: input.campaignId,
    nowMs: today})).action, "wait");
  const expired = await service.expire({campaignId: input.campaignId,
    nowMs: Date.parse(end)});
  assert.equal(expired.action, "expire");
  assert.deepEqual(await service.publicAdvertisements(Date.parse(end)), []);
  assert.equal((await service.expire({campaignId: input.campaignId,
    nowMs: Date.parse(end) + 1})).action, "none");
  assert.equal(db.count(`adRequests/${input.campaignId}/c2DemoHistory/`), 2);
  assert.equal(db.raw(`adRequests/${input.campaignId}`).status, "inactive");
  assert.equal((await service.activate(input)).action, "none");
});

test("bloc C2 : retrait du dossier approuvé retire la projection", async () => {
  const input = fixture();
  const {db, service} = setup(input);
  await service.activate(input);
  assert.equal((await service.publicAdvertisements(today)).length, 1);
  db.seed(`advertiserRequests/${input.requestId}`,
      {...input.request, status: "rejected"});
  assert.deepEqual(await service.publicAdvertisements(today), []);
});

test("bloc C2 : nouveau visuel non approuvé masque la publicité", async () => {
  const input = fixture();
  const {db, service} = setup(input);
  await service.activate(input);
  db.seed(`advertiserRequests/${input.requestId}`, {...input.request,
    approvedApplication: {visual: {
      url: "https://example.test/other-approved.jpg",
    }}});
  assert.deepEqual(await service.publicAdvertisements(today), []);
});

test("bloc C2 : refuse l'adoption d'une activation étrangère", async () => {
  const input = fixture();
  const {db, service} = setup(input);
  db.seed(`adRequests/${input.campaignId}`,
      {...input.campaign, status: "active", activationProofKey: "forged"});
  const result = await service.activate(input);
  assert.equal(result.phase, "blocked");
  assert.equal(db.count("c2DemoPaymentClaims/"), 0);
  assert.deepEqual(await service.publicAdvertisements(today), []);
  db.seed(`adRequests/${input.campaignId}`,
      {...input.campaign, status: "active", c2Simulated: true,
        c2InvoiceId: 12, activationProofKey: "forged"});
  assert.deepEqual(await service.publicAdvertisements(today), []);
});
