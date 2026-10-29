"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createLocalPublicationSimulator} =
  require("../local/odoo_campaign_publication_simulator");
const {secureReferenceFor} =
  require("../local/odoo_secure_checkout_client");

const start = "2026-10-25T00:00:00Z";
const end = "2026-11-01T00:00:00Z";
const today = Date.parse("2026-10-29T09:00:00Z");

/**
 * @return {Object} Dossier et reçus entièrement fictifs.
 */
function fixture() {
  return {
    requestId: "case_2026_stripe",
    campaignId: "campaign_2026_stripe",
    request: {
      status: "approved", advertisingSpotCompleted: true,
      diffusionCompleted: true, planningCompleted: true,
      diffusion: {visibilityType: "pack"},
      advertisingTerritory: {level: "radius_5km", radiusKm: 5},
      planning: {campaignStartDate: start, campaignEndDate: end},
      approvedApplication: {visual: {
        url: "https://example.test/approved-banner.webp",
      }},
    },
    campaign: {
      status: "draft", advertiserRequestId: "case_2026_stripe",
      visibilityType: "pack", broadcastType: "local",
      centerLat: 46.4, centerLng: -1.5, radiusKm: 5,
      campaignStartDate: start, campaignEndDate: end,
      bannerUrl: "https://example.test/approved-banner.webp",
      destinationUrl: "https://example.test/",
      advertiserName: "Commerce fictif",
      email: "private@example.test",
    },
    order: {
      testOnly: true, odooState: "sale", odooOrderId: 7,
      reference: secureReferenceFor("case_2026_stripe"),
      odooTotalCents: 15480,
    },
    invoice: {
      testOnly: true, odooInvoiceId: 12,
      odooInvoiceName: "FAC/2026/00007", state: "posted",
      paymentState: "paid", amountTotalCents: 15480,
      amountResidualCents: 0, odooPaymentRecorded: true,
    },
    payment: {
      paymentConfirmed: true, transactions: [{
        id: 51, reference: "FAC/2026/00007", state: "done",
        provider: "stripe", currency: "EUR", amountCents: 15480,
        testOnly: true,
      }],
    },
    nowMs: today,
  };
}

/**
 * @param {Object} input Données de simulation.
 * @return {Object} Mémoire fictive contenant la campagne.
 */
function withCampaign(input) {
  const sim = createLocalPublicationSimulator();
  sim.register(input);
  return sim;
}

test("bloc C1 : paiement absent, puis activation et carte fictives", () => {
  const input = fixture();
  const original = structuredClone(input);
  const sim = withCampaign(input);
  input.payment.paymentConfirmed = false;
  const unpaid = sim.reconcile(input);
  assert.equal(unpaid.phase, "blocked");
  assert.equal(unpaid.action, "none");
  assert.deepEqual(unpaid.publicAdvertisements, []);
  assert.equal(sim.inspect(input.campaignId).campaign.status, "draft");

  input.payment.paymentConfirmed = true;
  const paid = sim.reconcile(input);
  assert.equal(paid.simulationOnly, true);
  assert.equal(paid.phase, "active");
  assert.equal(paid.action, "activate");
  assert.equal(paid.publicAdvertisements.length, 1);
  assert.equal(paid.publicAdvertisements[0].id, input.campaignId);
  assert.equal(paid.publicAdvertisements[0].visibilityType, "pack");
  assert.equal(paid.publicAdvertisements[0].radiusKm, 5);
  assert.equal(paid.publicAdvertisements[0].campaignEndAt, Date.parse(end));
  assert.equal(Object.hasOwn(paid.publicAdvertisements[0], "email"), false);
  assert.equal(Object.hasOwn(paid.publicAdvertisements[0],
      "activationProofKey"), false);
  assert.equal(input.campaign.status, original.campaign.status);
  assert.equal(input.request.status, original.request.status);
  assert.equal(sim.inspect(input.campaignId).history.length, 1);
});

test("bloc C1 : pas d'affichage avant la date de début", () => {
  const input = fixture();
  const sim = withCampaign(input);
  input.nowMs = Date.parse(start) - 1;
  const scheduled = sim.reconcile(input);
  assert.equal(scheduled.phase, "scheduled");
  assert.equal(scheduled.action, "wait");
  assert.deepEqual(sim.publicAdvertisements(input.nowMs), []);

  input.nowMs = Date.parse(start);
  const active = sim.reconcile(input);
  assert.equal(active.action, "activate");
  assert.equal(active.publicAdvertisements.length, 1);
});

test("bloc C1 : expiration sans nouvelle lecture du paiement", () => {
  const input = fixture();
  const sim = withCampaign(input);
  sim.reconcile(input);
  const tick = sim.advanceTime(Date.parse(end));
  assert.deepEqual(tick.expiredCampaignIds, [input.campaignId]);
  assert.deepEqual(tick.publicAdvertisements, []);
  assert.equal(sim.inspect(input.campaignId).campaign.status, "inactive");
  assert.deepEqual(sim.advanceTime(Date.parse(end) + 1).expiredCampaignIds,
      []);
  assert.equal(sim.inspect(input.campaignId).history.length, 2);
  assert.equal(sim.reconcile({...input, nowMs: today}).action, "none");
  assert.deepEqual(sim.publicAdvertisements(today), []);
});

test("bloc C1 : campagne expirée avant paiement jamais publiée", () => {
  const input = fixture();
  const sim = withCampaign(input);
  assert.equal(sim.reconcile({...input, nowMs: Date.parse(end)}).phase,
      "expired");
  assert.deepEqual(sim.publicAdvertisements(Date.parse(end)), []);
  assert.equal(sim.reconcile(input).action, "none");
  assert.equal(sim.inspect(input.campaignId).history.length, 0);
});

test("bloc C1 : même facture Stripe refusée pour deux campagnes", () => {
  const first = fixture();
  const second = fixture();
  second.campaignId = "campaign_2026_stripe_b";
  second.requestId = "case_2026_stripe_b";
  second.campaign.advertiserRequestId = second.requestId;
  second.order.reference = secureReferenceFor(second.requestId);
  const sim = createLocalPublicationSimulator();
  sim.register(first);
  sim.register(second);
  assert.equal(sim.reconcile(first).action, "activate");
  const duplicate = sim.reconcile(second);
  assert.equal(duplicate.phase, "blocked");
  assert.equal(duplicate.reason, "payment_already_used");
  assert.equal(duplicate.publicAdvertisements.length, 1);
  second.payment.transactions[0].id = 52;
  assert.equal(sim.reconcile(second).reason, "payment_already_used");
  assert.equal(sim.inspect(second.campaignId).campaign.status, "draft");
});

test("bloc C1 : les répétitions n'activent qu'une fois", async () => {
  const input = fixture();
  const sim = withCampaign(input);
  const results = await Promise.all([
    Promise.resolve().then(() => sim.reconcile(input)),
    Promise.resolve().then(() => sim.reconcile(input)),
    Promise.resolve().then(() => sim.reconcile(input)),
  ]);
  assert.deepEqual(results.map((result) => result.action),
      ["activate", "none", "none"]);
  assert.equal(sim.inspect(input.campaignId).history.length, 1);
  assert.equal(sim.publicAdvertisements(today).length, 1);
});

test("bloc C1 : contrôle du dossier et du visuel avant la carte", () => {
  const cases = [
    (v) => {
      v.request.status = "pending";
    },
    (v) => {
      v.campaign.bannerUrl = "http://example.test/visual.jpg";
    },
    (v) => {
      v.campaign.centerLat = 123;
    },
    (v) => {
      v.campaign.radiusKm = 50;
    },
    (v) => {
      v.payment.transactions[0].currency = "USD";
    },
    (v) => {
      v.invoice.paymentState = "not_paid";
    },
    (v) => {
      v.order.reference = secureReferenceFor("another_case");
    },
  ];
  for (const change of cases) {
    const input = fixture();
    change(input);
    const sim = withCampaign(input);
    assert.equal(sim.reconcile(input).action, "none");
    assert.deepEqual(sim.publicAdvertisements(today), []);
    assert.deepEqual(sim.inspect(input.campaignId).history, []);
  }
});

test("bloc C1 : aucune campagne active ne peut être importée", () => {
  const input = fixture();
  input.campaign.status = "active";
  assert.throws(() => withCampaign(input), /active/);
});

test("bloc C1 : mémoire protégée, lecture sans données privées", () => {
  const input = fixture();
  const sim = withCampaign(input);
  const state = sim.inspect(input.campaignId);
  state.campaign.bannerUrl = "https://example.test/forged.webp";
  input.campaign.bannerUrl = "https://example.test/forged.webp";
  const result = sim.reconcile(input);
  assert.equal(result.action, "activate");
  assert.equal(result.publicAdvertisements[0].bannerUrl,
      "https://example.test/approved-banner.webp");
  assert.equal(Object.hasOwn(result.publicAdvertisements[0], "email"), false);
});

test("bloc C1 : horodatage invalide interdit toute transition", () => {
  const input = fixture();
  const sim = withCampaign(input);
  const result = sim.reconcile({...input, nowMs: NaN});
  assert.equal(result.phase, "blocked");
  assert.equal(result.action, "none");
  assert.equal(sim.inspect(input.campaignId).campaign.status, "draft");
  assert.throws(() => sim.advanceTime(Infinity), /Horodatage/);
});
