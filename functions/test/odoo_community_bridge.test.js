/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createLocalBridge, receipt, firestoreValue} =
    require("../local/odoo_community_bridge_server");

function fsValue(value) {
  if (value instanceof Date) return {timestampValue: value.toISOString()};
  if (typeof value === "string") return {stringValue: value};
  if (typeof value === "boolean") return {booleanValue: value};
  if (Number.isInteger(value)) return {integerValue: String(value)};
  if (value == null) return {nullValue: null};
  if (Array.isArray(value)) return {arrayValue: {values: value.map(fsValue)}};
  return {mapValue: {fields: Object.fromEntries(Object.entries(value)
      .map(([name, item]) => [name, fsValue(item)]))}};
}

function fixture() {
  const customer = {
    status: "approved", firebaseUid: "uid-blue", advertisingSpotCompleted: true,
    diffusionCompleted: true, planningCompleted: true,
    acceptedDocuments: {cgu: true, privacy: true, rgpd: true,
      advertiserCgv: true},
    legalAcceptance: {representativeDeclaration: true},
    advertisingTerritory: {level: "radius_5km"},
    diffusion: {visibilityType: "pack"},
    planning: {durationLabel: "1 semaine",
      campaignStartDate: new Date("2026-11-05T00:00:00.000Z")},
    establishment: {businessName: "BLUE SURF SCHOOL", city: "LONGEVILLE-SUR-MER",
      postalCode: "85560", country: "FRANCE", address: "Rue de test"},
    professionalProfile: {professionalEmail: "bluesurfschool@example.test"},
  };
  const quote = {
    market: "ADVERTISER_RADIUS", version: 1,
    pricingReference: "FR_ADVERTISER_RADIUS-V1", country: "FR",
    currency: "EUR", amountExclTax: 129, discountPercent: 0,
    payableExclTaxCents: 12900, previewOnly: true,
  };
  const expected = {territory: "radius_5km", offer: "pack",
    duration: "1 semaine", startDate: "2026-11-05",
    pricingReference: quote.pricingReference, payableExclTaxCents: 12900};
  const calls = [];
  const partners = [];
  const products = [];
  const orders = [];
  const invoices = [];
  const wizards = [];
  const controls = {wrongInvoiceAmount: false};
  function json(value, status = 200) {
    return {ok: status < 400, status, json: async () => value};
  }
  const fetchImpl = async (url) => {
    if (url.includes("firestore.googleapis.com")) {
      return json({fields: fsValue(customer).mapValue.fields});
    }
    if (url.includes("previewPublishedCommercialQuote")) {
      return json({success: true, quote});
    }
    throw new Error("URL externe non prévue : " + url);
  };
  const odooClient = {
    async call(model, method, body) {
      calls.push({model, method, body});
      if (model === "res.country") return [{id: 75}];
      if (model === "res.partner") {
        if (method === "search_read") {
          return partners.filter((p) => p.name === body.domain[1][2] &&
              p.email === body.domain[0][2]);
        }
        const id = partners.length + 1;
        partners.push({...body.vals_list[0], id});
        return [id];
      }
      if (model === "product.product") {
        if (method === "search_read") return [...products];
        const id = products.length + 1;
        products.push({...body.vals_list[0], id});
        return [id];
      }
      if (model === "sale.order") {
        if (method === "search_read") {
          return orders.filter((o) => o.client_order_ref === body.domain[0][2]);
        }
        if (method === "read") {
          return orders.filter((o) => body.ids.includes(o.id))
              .map((o) => ({id: o.id,
                invoice_ids: invoices.filter((i) => i.order_id === o.id)
                    .map((i) => i.id)}));
        }
        if (method === "create") {
          const values = body.vals_list[0];
          const line = values.order_line[0][2];
          const untaxed = line.price_unit * (100 - line.discount) / 100;
          const tax = Math.round(untaxed * 20) / 100;
          const id = orders.length + 1;
          orders.push({id, name: "S00001", state: "draft",
            client_order_ref: values.client_order_ref,
            invoice_status: "no", amount_untaxed: untaxed,
            amount_tax: tax, amount_total: untaxed + tax});
          return [id];
        }
        if (method === "action_confirm") {
          orders.find((o) => o.id === body.ids[0]).state = "sale";
          return true;
        }
      }
      if (model === "sale.advance.payment.inv") {
        if (method === "create") {
          const value = body.vals_list[0];
          assert.equal(value.advance_payment_method, "delivered");
          const ids = value.sale_order_ids[0][2];
          assert.deepEqual(value.sale_order_ids[0].slice(0, 2), [6, 0]);
          const id = wizards.length + 1;
          wizards.push({id, order_ids: ids});
          return [id];
        }
        if (method === "create_invoices") {
          const wizard = wizards.find((w) => w.id === body.ids[0]);
          assert.ok(wizard);
          for (const orderId of wizard.order_ids) {
            const order = orders.find((o) => o.id === orderId);
            const untaxed = controls.wrongInvoiceAmount ?
              order.amount_untaxed + 1 : order.amount_untaxed;
            invoices.push({id: invoices.length + 1,
              order_id: orderId, name: "/", move_type: "out_invoice",
              state: "draft", payment_state: "not_paid",
              amount_untaxed: untaxed, amount_tax: order.amount_tax,
              amount_total: untaxed + order.amount_tax,
              amount_residual: untaxed + order.amount_tax,
              invoice_origin: order.name});
          }
          return {type: "ir.actions.act_window_close"};
        }
      }
      if (model === "account.move") {
        if (method === "read") {
          return invoices.filter((i) => body.ids.includes(i.id))
              .map((i) => ({...i}));
        }
        if (method === "action_post") {
          for (const invoice of invoices.filter((i) => body.ids.includes(i.id))) {
            invoice.state = "posted";
            invoice.name = "INV/2026/00001";
          }
          return true;
        }
      }
      throw new Error("Appel Odoo inconnu : " + model + "/" + method);
    },
  };
  const verifyToken = async (token) => token === "valid-token" ?
    {uid: "uid-blue", role: "ANNONCEUR", advertiserRequestId: "blue-surf-001",
      email: "bluesurfschool@example.test"} :
    (() => { throw new Error("Invalid token"); })();
  const bridge = () => createLocalBridge({fetchImpl, verifyToken, odooClient});
  return {bridge, customer, quote, expected, calls, partners, products,
    orders, invoices, wizards, controls};
}

test("SPHOT Odoo local : aucun client ni commande avant confirmation", async () => {
  const f = fixture();
  const response = await f.bridge().handle({action: "status", token: "valid-token",
    requestId: "blue-surf-001"});
  assert.equal(response.found, false);
  assert.equal(f.partners.length, 0);
  assert.equal(f.products.length, 0);
  assert.equal(f.orders.length, 0);
});

test("SPHOT Odoo local : client/produit/commande créés une fois, reprise après navigation", async () => {
  const f = fixture();
  const bridge = f.bridge();
  const request = {action: "confirm", token: "valid-token",
    requestId: "blue-surf-001", expected: f.expected};
  const first = await bridge.handle(request);
  assert.equal(first.ok, true);
  assert.equal(first.alreadyExists, false);
  assert.equal(first.order.odooOrderName, "S00001");
  assert.equal(first.order.odooState, "sale");
  assert.equal(first.order.odooUntaxedCents, 12900);
  assert.equal(first.order.paymentStatus, "not_started");
  assert.equal(first.order.campaignActivationAllowed, false);
  assert.equal(f.partners.length, 1);
  assert.equal(f.products.length, 1);
  assert.equal(f.orders.length, 1);
  assert.equal(f.partners[0].country_id, 75);
  assert.equal(f.partners[0].vat, undefined);
  const second = await bridge.handle(request);
  assert.equal(second.alreadyExists, true);
  const afterRestart = await f.bridge().handle({action: "status",
    token: "valid-token", requestId: "blue-surf-001"});
  assert.equal(afterRestart.order.odooOrderName, "S00001");
  assert.equal(f.orders.length, 1);
  assert.equal(f.partners.length, 1);
});

test("SPHOT Odoo local : deux confirmations simultanées ne dupliquent pas", async () => {
  const f = fixture();
  const bridge = f.bridge();
  const request = {action: "confirm", token: "valid-token",
    requestId: "blue-surf-001", expected: f.expected};
  const result = await Promise.all([bridge.handle(request), bridge.handle(request)]);
  assert.equal(result[0].order.reference, result[1].order.reference);
  assert.equal(f.orders.length, 1);
});

test("SPHOT Odoo local : facturation uniquement sur demande, liée à S00001", async () => {
  const f = fixture();
  const bridge = f.bridge();
  await bridge.handle({action: "confirm", token: "valid-token",
    requestId: "blue-surf-001", expected: f.expected});
  assert.equal(f.invoices.length, 0);
  const status = await bridge.handle({action: "invoice_status",
    token: "valid-token", requestId: "blue-surf-001"});
  assert.equal(status.invoice, null);
  assert.equal(f.invoices.length, 0);
  const result = await bridge.handle({action: "invoice",
    token: "valid-token", requestId: "blue-surf-001"});
  assert.equal(result.alreadyExists, false);
  assert.equal(result.order.odooOrderName, "S00001");
  assert.equal(result.invoice.odooInvoiceName, "INV/2026/00001");
  assert.equal(result.invoice.state, "posted");
  assert.equal(result.invoice.paymentState, "not_paid");
  assert.equal(result.invoice.amountUntaxedCents, 12900);
  assert.equal(result.invoice.amountTaxCents, 2580);
  assert.equal(result.invoice.amountTotalCents, 15480);
  assert.equal(result.invoice.paymentInitiated, false);
  assert.equal(result.invoice.campaignActivationAllowed, false);
  assert.equal(f.invoices.length, 1);
  assert.equal(f.invoices[0].order_id, f.orders[0].id);
  assert.equal(f.wizards.length, 1);
  assert.equal(f.calls.some((c) => c.model === "account.payment"), false);
});

test("SPHOT Odoo local : retrouver facture sans duplication après navigation", async () => {
  const f = fixture();
  const bridge = f.bridge();
  await bridge.handle({action: "confirm", token: "valid-token",
    requestId: "blue-surf-001", expected: f.expected});
  const invoiceRequest = {action: "invoice", token: "valid-token",
    requestId: "blue-surf-001"};
  const both = await Promise.all([
    bridge.handle(invoiceRequest), bridge.handle(invoiceRequest),
  ]);
  assert.equal(both[0].invoice.odooInvoiceId, both[1].invoice.odooInvoiceId);
  assert.equal(f.invoices.length, 1);
  const fromNewBridge = await f.bridge().handle({action: "invoice_status",
    token: "valid-token", requestId: "blue-surf-001"});
  assert.equal(fromNewBridge.invoice.odooInvoiceId, both[0].invoice.odooInvoiceId);
  const again = await f.bridge().handle(invoiceRequest);
  assert.equal(again.alreadyExists, true);
  assert.equal(f.invoices.length, 1);
  assert.equal(f.wizards.length, 1);
});

test("SPHOT Odoo local : écart comptable interdit avant validation facture", async () => {
  const f = fixture();
  const bridge = f.bridge();
  await bridge.handle({action: "confirm", token: "valid-token",
    requestId: "blue-surf-001", expected: f.expected});
  f.controls.wrongInvoiceAmount = true;
  await assert.rejects(() => bridge.handle({action: "invoice",
    token: "valid-token", requestId: "blue-surf-001"}), /Montants de facture/);
  assert.equal(f.invoices.length, 1);
  assert.equal(f.invoices[0].state, "draft");
  assert.equal(f.calls.filter((c) => c.model === "account.move" &&
      c.method === "action_post").length, 0);
});

test("SPHOT Odoo local : refuse prix falsifié et autre identité", async () => {
  const f = fixture();
  const bridge = f.bridge();
  await assert.rejects(() => bridge.handle({action: "confirm",
    token: "valid-token", requestId: "blue-surf-001",
    expected: {...f.expected, payableExclTaxCents: 1}}), /diffère/);
  assert.equal(f.partners.length, 0);
  f.customer.firebaseUid = "someone-else";
  await assert.rejects(() => bridge.handle({action: "confirm",
    token: "valid-token", requestId: "blue-surf-001",
    expected: f.expected}), /non autorisé/);
  assert.equal(f.orders.length, 0);
});

test("SPHOT Odoo local : bloqué sans consentement et sans prix publié", async () => {
  const f = fixture();
  f.customer.acceptedDocuments.advertiserCgv = false;
  await assert.rejects(() => f.bridge().handle({action: "confirm",
    token: "valid-token", requestId: "blue-surf-001",
    expected: f.expected}), /juridiques/);
  assert.equal(f.orders.length, 0);
});

test("SPHOT Odoo local : refuse un total Odoo différent", () => {
  assert.throws(() => receipt({client_order_ref: "SPHOT-ABC",
    id: 1, name: "S00001", amount_untaxed: 130, amount_tax: 0,
    amount_total: 130}, "SPHOT-ABC", {
    payableExclTaxCents: 12900,
  }), /total HT Odoo/);
});

test("SPHOT Odoo local : décodage Firestore du dossier", () => {
  const parsed = firestoreValue({mapValue: {fields: {
    established: {booleanValue: true},
    name: {stringValue: "BLUE SURF SCHOOL"},
    price: {integerValue: "129"},
    date: {timestampValue: "2026-11-05T00:00:00Z"},
  }}});
  assert.equal(parsed.established, true);
  assert.equal(parsed.name, "BLUE SURF SCHOOL");
  assert.equal(parsed.price, 129);
  assert.equal(parsed.date.toISOString(), "2026-11-05T00:00:00.000Z");
});
