"use strict";

// Lance un seul scénario C2 fictif dans l'émulateur Firestore local.
// Ce programme refuse toute connexion au projet Firebase en ligne.
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {secureReferenceFor} = require("./odoo_secure_checkout_client");
const {DEMO_PROJECT_ID, assertDemoEmulator,
  createC2EmulatorService} = require("./odoo_c2_firestore_emulator");

const start = "2026-10-25T00:00:00Z";
const end = "2026-11-01T00:00:00Z";
const today = Date.parse("2026-10-29T09:00:00Z");

/**
 * @return {Promise<void>} Test concret sur l'émulateur, puis fermeture.
 */
async function main() {
  // La CLI --project demo-sphot-c2 définit normalement GCLOUD_PROJECT.
  // Si elle ne le fait pas, l'identifiant forcé reste celui sans production.
  if (!process.env.GCLOUD_PROJECT) {
    process.env.GCLOUD_PROJECT = DEMO_PROJECT_ID;
  }
  assertDemoEmulator();

  // Le SDK est chargé seulement APRÈS vérification du projet et de l'hôte.
  const admin = require("firebase-admin");
  const app = admin.initializeApp({projectId: DEMO_PROJECT_ID},
      `sphot-c2-${crypto.randomUUID()}`);
  try {
    const db = admin.firestore(app);
    const service = createC2EmulatorService(db);
    const suffix = crypto.randomBytes(6).toString("hex");
    const requestId = `case_c2_${suffix}`;
    const campaignId = `campaign_c2_${suffix}`;
    const bannerUrl = "https://example.test/c2-approved-banner.jpg";
    const request = {
      status: "approved", advertisingSpotCompleted: true,
      diffusionCompleted: true, planningCompleted: true,
      diffusion: {visibilityType: "pack"},
      advertisingTerritory: {level: "radius_5km", radiusKm: 5},
      planning: {campaignStartDate: start, campaignEndDate: end},
      approvedApplication: {visual: {url: bannerUrl}},
    };
    const campaign = {
      status: "draft", advertiserRequestId: requestId,
      visibilityType: "pack", broadcastType: "local",
      centerLat: 46.4, centerLng: -1.5, radiusKm: 5,
      campaignStartDate: start, campaignEndDate: end,
      bannerUrl, destinationUrl: "https://example.test/",
      advertiserName: "Annonceur fictif C2",
    };
    const requestRef = db.collection("advertiserRequests").doc(requestId);
    const campaignRef = db.collection("adRequests").doc(campaignId);
    await requestRef.create(request);
    await campaignRef.create(campaign);

    const invoiceId = Math.floor(Math.random() * 900000000) + 100000000;
    const data = {requestId, campaignId, nowMs: today,
      order: {testOnly: true, odooState: "sale", odooOrderId: 7,
        reference: secureReferenceFor(requestId), odooTotalCents: 15480},
      invoice: {testOnly: true, odooInvoiceId: invoiceId,
        odooInvoiceName: "FAC/SIMULATED/C2", state: "posted",
        paymentState: "paid", amountTotalCents: 15480,
        amountResidualCents: 0, odooPaymentRecorded: true},
      payment: {paymentConfirmed: false, transactions: [{
        id: invoiceId + 1, reference: "FAC/SIMULATED/C2",
        provider: "stripe", state: "done", currency: "EUR",
        testOnly: true, amountCents: 15480,
      }]},
    };
    const unpaid = await service.activate(data);
    assert.equal(unpaid.action, "none");
    assert.deepEqual(await service.publicAdvertisements(today), []);
    data.payment.paymentConfirmed = true;
    const paid = await service.activate(data);
    assert.equal(paid.action, "activate");
    assert.equal((await service.activate(data)).action, "none");
    const visible = await service.publicAdvertisements(today);
    assert.equal(visible.length, 1);
    assert.equal(visible[0].id, campaignId);
    const expired = await service.expire({campaignId,
      nowMs: Date.parse(end)});
    assert.equal(expired.action, "expire");
    assert.deepEqual(await service.publicAdvertisements(Date.parse(end)), []);
    const final = await campaignRef.get();
    assert.equal(final.data().status, "inactive");
    const history = await campaignRef.collection("c2DemoHistory").get();
    assert.equal(history.size, 2);

    process.stdout.write(
        "C2 ÉMULATEUR : paiement bloqué, activation unique, " +
        "carte visible, expiration et historique OK.\n");
  } finally {
    await app.delete();
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error("C2 ÉMULATEUR ÉCHEC :", error.message);
    process.exitCode = 1;
  });
}

module.exports = {main};
