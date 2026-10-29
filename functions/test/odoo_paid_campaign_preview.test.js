"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {previewPaidCampaign} = require("../local/odoo_paid_campaign_preview");

const start = "2026-10-25T00:00:00Z";
const end = "2026-11-01T00:00:00Z";
const today = Date.parse("2026-10-29T09:00:00Z");

/**
 * @return {Object} Dossier strictement fictif sans accès réseau.
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
    order: {
      testOnly: true, odooState: "sale", odooOrderId: 7,
      reference: "SPHOT-PUB-PROD-SIMULATED", odooTotalCents: 15480,
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
    nowMs: today,
  };
}

test("bloc B : preuve de paiement, prévisualisation sans écriture", () => {
  const input = fixture();
  const before = structuredClone(input);
  const result = previewPaidCampaign(input);
  assert.equal(result.simulationOnly, true);
  assert.equal(result.phase, "active");
  assert.equal(result.action, "activate");
  assert.match(result.activationKey, /^SPHOT-TEST-ACT-[A-F0-9]{20}$/);
  assert.equal(result.publicPreview.radiusKm, 5);
  assert.equal(result.publicPreview.visibilityType, "pack");
  assert.equal(Object.hasOwn(result.publicPreview, "email"), false);
  assert.deepEqual(input, before);
  assert.equal(input.campaign.status, "draft");
});

test("bloc B : paiement absent ou incohérent ne déclenche rien", () => {
  const changes = [
    (v) => {
      v.payment.paymentConfirmed = false;
    },
    (v) => {
      v.invoice.paymentState = "not_paid";
    },
    (v) => {
      v.invoice.amountResidualCents = 15480;
    },
    (v) => {
      v.invoice.odooPaymentRecorded = false;
    },
    (v) => {
      v.order.odooState = "draft";
    },
    (v) => {
      v.order.odooTotalCents = 9999;
    },
    (v) => {
      v.invoice.testOnly = false;
    },
    (v) => {
      v.payment.transactions[0].provider = "demo";
    },
    (v) => {
      v.payment.transactions[0].state = "pending";
    },
    (v) => {
      v.payment.transactions[0].currency = "USD";
    },
    (v) => {
      v.payment.transactions[0].amountCents = 15479;
    },
    (v) => {
      v.payment.transactions[0].testOnly = false;
    },
    (v) => {
      v.payment.transactions.push({...v.payment.transactions[0]});
    },
  ];
  for (const change of changes) {
    const input = fixture();
    change(input);
    const result = previewPaidCampaign(input);
    assert.equal(result.phase, "blocked");
    assert.equal(result.action, "none");
    assert.equal(result.publicPreview, null);
    assert.equal(input.campaign.status, "draft");
  }
});

test("bloc B : dossier, visuel, rayon et dates doivent correspondre", () => {
  const changes = [
    (v) => {
      v.request.status = "pending";
    },
    (v) => {
      v.request.diffusionCompleted = false;
    },
    (v) => {
      v.campaign.advertiserRequestId = "another_case";
    },
    (v) => {
      v.campaign.visibilityType = "map";
    },
    (v) => {
      v.campaign.bannerUrl = "https://example.test/other.webp";
    },
    (v) => {
      v.campaign.bannerUrl = "http://example.test/approved-banner.webp";
    },
    (v) => {
      v.campaign.radiusKm = 15;
    },
    (v) => {
      v.campaign.centerLat = 200;
    },
    (v) => {
      v.campaign.campaignEndDate = "2026-11-02T00:00:00Z";
    },
  ];
  for (const change of changes) {
    const input = fixture();
    change(input);
    const result = previewPaidCampaign(input);
    assert.equal(result.phase, "blocked");
    assert.equal(result.action, "none");
  }
});

test("bloc B : avant la période, seul un état programmé est simulé", () => {
  const input = fixture();
  input.nowMs = Date.parse("2026-10-24T23:59:59Z");
  const result = previewPaidCampaign(input);
  assert.equal(result.phase, "scheduled");
  assert.equal(result.action, "wait");
  assert.equal(result.publicPreview, null);
  assert.equal(input.campaign.status, "draft");
});

test("bloc B : répétitions identiques, activation unique simulée", () => {
  const input = fixture();
  const first = previewPaidCampaign(input);
  const repeated = previewPaidCampaign(input);
  assert.deepEqual(first, repeated);
  const hypotheticallyActivated = structuredClone(input);
  hypotheticallyActivated.campaign.status = "active";
  hypotheticallyActivated.campaign.activationProofKey = first.activationKey;
  const after = previewPaidCampaign(hypotheticallyActivated);
  assert.equal(after.phase, "active");
  assert.equal(after.action, "none");
  assert.equal(after.activationKey, first.activationKey);
  assert.equal(hypotheticallyActivated.campaign.status, "active");
});

test("bloc B : refuse de récupérer une campagne déjà activée autrement", () => {
  const input = fixture();
  input.campaign.status = "active";
  input.campaign.activationProofKey = "another_payment";
  const result = previewPaidCampaign(input);
  assert.equal(result.phase, "blocked");
  assert.equal(result.reason, "existing_activation_unrelated");
});

test("bloc B : expiration sans réactivation ni doublon", () => {
  const input = fixture();
  const first = previewPaidCampaign(input);
  input.nowMs = Date.parse(end);
  const expiredBeforeActivation = previewPaidCampaign(input);
  assert.equal(expiredBeforeActivation.phase, "expired");
  assert.equal(expiredBeforeActivation.action, "none");
  assert.equal(expiredBeforeActivation.publicPreview, null);

  input.campaign.status = "active";
  input.campaign.activationProofKey = first.activationKey;
  const expiredAfterActivation = previewPaidCampaign(input);
  assert.equal(expiredAfterActivation.phase, "expired");
  assert.equal(expiredAfterActivation.action, "expire");
  assert.equal(expiredAfterActivation.publicPreview, null);
  assert.equal(input.campaign.status, "active");
});
