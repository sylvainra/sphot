/* eslint-disable max-len, require-jsdoc */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createOdooCommercialSimulator} =
    require("../odoo_commercial_simulator");

function advertiserQuote({amount = 129, discount = 0} = {}) {
  return {
    market: "ADVERTISER_RADIUS",
    version: 1,
    pricingReference: "FR_ADVERTISER_RADIUS-V1",
    currency: "EUR",
    amountExclTax: amount,
    payableExclTaxCents: amount * (100 - discount),
    territory: "radius_5km",
    offer: "pack",
    duration: "1 semaine",
    discountPercent: discount,
  };
}

function draftOptions(sphotReference = "SPHOT-TEST-BSS-001", quote = advertiserQuote()) {
  return {
    quote,
    partnerId: 12,
    productIds: {advertiser: 42},
    sphotReference,
  };
}

function readyInvoice(simulator, reference) {
  simulator.createDraftOrder(draftOptions(reference));
  simulator.confirmOrder(reference);
  simulator.createInvoiceDraft(reference);
  return simulator.confirmInvoice(reference);
}

test("Odoo SIM: achat fictif 129 HT, 20 % illustratif, 154,80 TTC", () => {
  const simulator = createOdooCommercialSimulator({
    taxRateBasisPoints: 2000,
  });
  const ref = "SPHOT-TEST-BSS-001";
  const draft = simulator.createDraftOrder(draftOptions(ref));
  assert.equal(draft.order.status, "simulated_draft");
  assert.equal(draft.order.reference, "SIM-SO-000001");
  assert.equal(draft.sphotReference, ref);
  assert.equal(draft.pricingReference, "FR_ADVERTISER_RADIUS-V1");
  assert.equal(draft.partnerId, 12);
  assert.equal(draft.untaxedCents, 12900);
  assert.equal(draft.simulatedTaxCents, 2580);
  assert.equal(draft.simulatedTotalCents, 15480);

  assert.throws(() => simulator.createInvoiceDraft(ref), {status: 409});
  simulator.confirmOrder(ref);
  const invoiceDraft = simulator.createInvoiceDraft(ref);
  assert.equal(invoiceDraft.invoice.reference, "SIM-INV-000001");
  assert.equal(invoiceDraft.invoice.status, "simulated_draft");
  assert.throws(() => simulator.simulatePayment({
    sphotReference: ref, attemptKey: "TRY-0001", outcome: "success",
  }), {status: 409});
  simulator.confirmInvoice(ref);
  const paid = simulator.simulatePayment({
    sphotReference: ref, attemptKey: "TRY-0001", outcome: "success",
  });
  assert.equal(paid.simulatedPaymentStatus, "simulated_success");
  assert.equal(paid.simulatedPaidCents, 15480);
  assert.equal(paid.simulatedAmountDueCents, 0);
  assert.equal(paid.attempts[0].reference, "SIM-TX-000001");
  assert.equal(paid.attempts[0].mode, "DEMO_SIMULATION_ONLY");
  assert.equal(paid.mode, "SIMULATION_ONLY");
  assert.equal(paid.persisted, false);
  assert.equal(paid.odooApiCalled, false);
  assert.equal(paid.paymentProofVerified, false);
  assert.equal(paid.campaignActivationAllowed, false);
  assert.equal(paid.automaticRenewal, false);
});

test("Odoo SIM: doublons sans nouvelle commande, facture ou transaction", () => {
  const simulator = createOdooCommercialSimulator();
  const ref = "SPHOT-TEST-BSS-001";
  const first = simulator.createDraftOrder(draftOptions(ref));
  assert.deepEqual(simulator.createDraftOrder(draftOptions(ref)), first);
  simulator.confirmOrder(ref);
  simulator.confirmOrder(ref);
  const firstInvoice = simulator.createInvoiceDraft(ref);
  assert.deepEqual(simulator.createInvoiceDraft(ref), firstInvoice);
  simulator.confirmInvoice(ref);
  simulator.confirmInvoice(ref);
  const firstPayment = simulator.simulatePayment({
    sphotReference: ref, attemptKey: "TRY-0001", outcome: "success",
  });
  const repeatedPayment = simulator.simulatePayment({
    sphotReference: ref, attemptKey: "TRY-0001", outcome: "success",
  });
  assert.deepEqual(repeatedPayment, firstPayment);
  assert.equal(repeatedPayment.attempts.length, 1);
  assert.throws(() => simulator.simulatePayment({
    sphotReference: ref, attemptKey: "TRY-0002", outcome: "success",
  }), {status: 409});
  assert.throws(() => simulator.createDraftOrder(draftOptions(ref,
      advertiserQuote({amount: 130}))), {status: 409});
});

test("Odoo SIM: refus puis nouvelle tentative réussie, même facture", () => {
  const simulator = createOdooCommercialSimulator();
  const ref = "SPHOT-REFUS-001";
  const invoice = readyInvoice(simulator, ref);
  const denied = simulator.simulatePayment({
    sphotReference: ref, attemptKey: "TRY-FAIL-001", outcome: "failure",
  });
  assert.equal(denied.simulatedPaymentStatus, "simulated_failure");
  assert.equal(denied.simulatedPaidCents, 0);
  assert.equal(denied.simulatedAmountDueCents, 12900);
  assert.throws(() => simulator.simulatePayment({
    sphotReference: ref, attemptKey: "TRY-FAIL-001", outcome: "success",
  }), {status: 409});

  const success = simulator.simulatePayment({
    sphotReference: ref, attemptKey: "TRY-RETRY-002", outcome: "success",
  });
  assert.equal(success.invoice.reference, invoice.invoice.reference);
  assert.equal(success.attempts.length, 2);
  assert.notEqual(success.attempts[0].reference,
      success.attempts[1].reference);
  assert.equal(success.simulatedAmountDueCents, 0);
  assert.equal(success.campaignActivationAllowed, false);
});

test("Odoo SIM: attente empêche une seconde tentative concurrente", () => {
  const simulator = createOdooCommercialSimulator();
  const ref = "SPHOT-ATTENTE-001";
  readyInvoice(simulator, ref);
  const pending = simulator.simulatePayment({
    sphotReference: ref, attemptKey: "TRY-PENDING-001", outcome: "pending",
  });
  assert.equal(pending.simulatedPaymentStatus, "simulated_pending");
  assert.equal(pending.simulatedAmountDueCents, 12900);
  assert.deepEqual(simulator.simulatePayment({
    sphotReference: ref, attemptKey: "TRY-PENDING-001", outcome: "pending",
  }), pending);
  assert.throws(() => simulator.simulatePayment({
    sphotReference: ref, attemptKey: "TRY-PENDING-002", outcome: "success",
  }), {status: 409});
});

test("Odoo SIM: 0, 5, 10 et 90 % de remise, taxes non figées", () => {
  for (const discount of [0, 5, 10, 90]) {
    const reference = "SPHOT-REMISE-" + String(discount).padStart(2, "0");
    const simulator = createOdooCommercialSimulator({
      taxRateBasisPoints: 2000,
    });
    const draft = simulator.createDraftOrder(draftOptions(reference,
        advertiserQuote({discount})));
    const expectedUntaxedCents = 129 * (100 - discount);
    assert.equal(draft.untaxedCents, expectedUntaxedCents);
    assert.equal(draft.discountPercent, discount);
    assert.equal(draft.simulatedTaxCents,
        Math.round(expectedUntaxedCents * 0.2));
  }
  const simulatorWithoutTax = createOdooCommercialSimulator({
    taxRateBasisPoints: 0,
  });
  const withoutTax = simulatorWithoutTax.createDraftOrder(
      draftOptions("SPHOT-ZERO-TAX"));
  assert.equal(withoutTax.simulatedTaxCents, 0);
  assert.equal(withoutTax.simulatedTotalCents, 12900);
});

test("Odoo SIM: rejette les identités, devis et résultats invalides", () => {
  const simulator = createOdooCommercialSimulator();
  assert.throws(() => createOdooCommercialSimulator({
    taxRateBasisPoints: 20000,
  }), {status: 400});
  assert.throws(() => simulator.createDraftOrder(draftOptions(
      "SPHOT-ADMIN-001", {...advertiserQuote(), market: "ADMIN"})),
  {status: 400});
  assert.throws(() => simulator.createDraftOrder({
    ...draftOptions(), partnerId: null,
  }));
  assert.throws(() => simulator.createDraftOrder({
    ...draftOptions(), productIds: {advertiser: 0},
  }));
  assert.throws(() => simulator.createDraftOrder({
    ...draftOptions(), quote: {...advertiserQuote(), discountPercent: 99},
  }));
  assert.throws(() => simulator.getPurchase("SPHOT-ABSENT"), {status: 404});
  readyInvoice(simulator, "SPHOT-VALID-001");
  assert.throws(() => simulator.simulatePayment({
    sphotReference: "SPHOT-VALID-001", attemptKey: "TRY-001",
    outcome: "unknown",
  }), {status: 400});
  assert.throws(() => simulator.simulatePayment({
    sphotReference: "SPHOT-VALID-001", attemptKey: "*",
    outcome: "success",
  }), {status: 400});
});

test("Odoo SIM: une réponse modifiée ne change jamais la simulation", () => {
  const simulator = createOdooCommercialSimulator();
  const ref = "SPHOT-COPIE-001";
  const external = simulator.createDraftOrder(draftOptions(ref));
  external.order.status = "simulated_confirmed";
  external.attempts.push({reference: "SIM-FAKE"});
  const stored = simulator.getPurchase(ref);
  assert.equal(stored.order.status, "simulated_draft");
  assert.equal(stored.attempts.length, 0);
  assert.equal(stored.campaignActivationAllowed, false);
});

test("Odoo SIM: commandes distinctes et aucun état persistant", () => {
  const simulator = createOdooCommercialSimulator();
  const first = simulator.createDraftOrder(draftOptions("SPHOT-PREMIER-001"));
  const second = simulator.createDraftOrder(draftOptions("SPHOT-SECOND-001"));
  assert.notEqual(first.order.reference, second.order.reference);
  assert.equal(simulator.getPurchase("SPHOT-PREMIER-001").sphotReference,
      "SPHOT-PREMIER-001");
  assert.throws(() => createOdooCommercialSimulator()
      .getPurchase("SPHOT-PREMIER-001"), {status: 404});
});
