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
  const orderLines = [];
  const invoices = [];
  const wizards = [];
  const paymentWizards = [];
  const payments = [];
  const demoTransactions = [];
  const controls = {wrongInvoiceAmount: false, noCashJournal: false,
    wrongPaymentAmount: false, paymentStaysUnpaid: false,
    demoProviderUnpublished: false};
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
        if (method === "read") {
          return products.filter((p) => body.ids.includes(p.id));
        }
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
              .map((o) => ({id: o.id, partner_id: [o.partner_id, "Client"],
                origin: o.origin, order_line: o.order_line,
                invoice_ids: invoices.filter((i) => i.order_id === o.id)
                    .map((i) => i.id)}));
        }
        if (method === "create") {
          const values = body.vals_list[0];
          const line = values.order_line[0][2];
          const untaxed = line.price_unit * (100 - line.discount) / 100;
          const tax = Math.round(untaxed * 20) / 100;
          const id = orders.length + 1;
          const lineId = orderLines.length + 1;
          orderLines.push({id: lineId, order_id: id,
            product_id: [line.product_id, "SPHOT PUBLICITAIRE"],
            product_uom_qty: line.product_uom_qty,
            price_unit: line.price_unit, discount: line.discount,
            name: line.name, tax_id: [1]});
          orders.push({id, name: `S${String(id).padStart(5, "0")}`,
            state: "draft", partner_id: values.partner_id,
            origin: values.origin, order_line: [lineId],
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
      if (model === "sale.order.line" && method === "read") {
        return orderLines.filter((line) => body.ids.includes(line.id));
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
              matched_payment_ids: [], invoice_origin: order.name});
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
            invoice.name = `INV/2026/${String(invoice.id).padStart(5, "0")}`;
          }
          return true;
        }
      }
      if (model === "account.move" && method === "get_portal_url") {
        return `/my/invoices/${body.ids[0]}?access_token=test-token`;
      }
      if (model === "payment.provider" && method === "search_read") {
        return [{id: 6, code: "demo", state: "test",
          is_published: !controls.demoProviderUnpublished}];
      }
      if (model === "payment.transaction" && method === "search_read") {
        const invoiceId = body.domain[0][2][0];
        return demoTransactions.filter((tx) => tx.invoice_ids.includes(invoiceId));
      }
      if (model === "account.journal" && method === "search_read") {
        assert.deepEqual(body.domain, [["type", "=", "cash"]]);
        return controls.noCashJournal ? [] : [{id: 10, name: "Cash TEST", type: "cash"}];
      }
      if (model === "account.payment.method.line" && method === "search_read") {
        assert.deepEqual(body.domain, [["journal_id", "=", 10],
          ["code", "=", "manual"], ["payment_type", "=", "inbound"]]);
        return [{id: 20, code: "manual", payment_type: "inbound",
          journal_id: [10, "Cash TEST"]}];
      }
      if (model === "account.move.line" && method === "search_read") {
        const invoice = invoices.find((i) => i.id === body.domain[0][2]);
        assert.ok(invoice);
        return [{id: 30, amount_residual: invoice.amount_residual,
          reconciled: false}];
      }
      if (model === "account.payment.register") {
        if (method === "create") {
          const values = body.vals_list[0];
          const id = paymentWizards.length + 1;
          paymentWizards.push({id, amount: controls.wrongPaymentAmount ?
            values.amount - 1 : values.amount,
          journal_id: [values.journal_id, "Cash TEST"],
          payment_method_line_id: [values.payment_method_line_id, "Manual"],
          payment_type: "inbound", partner_type: "customer",
          line_ids: values.line_ids[0][2]});
          return [id];
        }
        if (method === "read") {
          return paymentWizards.filter((w) => body.ids.includes(w.id));
        }
        if (method === "action_create_payments") {
          const wizard = paymentWizards.find((w) => w.id === body.ids[0]);
          assert.ok(wizard);
          const invoice = invoices[0];
          const id = payments.length + 1;
          payments.push({id, amount: wizard.amount});
          invoice.matched_payment_ids.push(id);
          if (!controls.paymentStaysUnpaid) {
            invoice.payment_state = "in_payment";
            invoice.amount_residual = 0;
          }
          return {res_model: "account.payment", res_id: id};
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
    orders, orderLines, invoices, wizards, paymentWizards, payments, controls,
    demoTransactions};
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

async function firstCyclePaid(f) {
  const bridge = f.bridge();
  const base = {token: "valid-token", requestId: "blue-surf-001"};
  await bridge.handle({...base, action: "confirm", expected: f.expected});
  await bridge.handle({...base, action: "invoice"});
  f.invoices[0].payment_state = "paid";
  f.invoices[0].amount_residual = 0;
  f.invoices[0].matched_payment_ids = [50];
  return {bridge, base};
}

test("Démo native : Odoo seul conserve le devis ; facture et reprise sans doublon", async () => {
  const f = fixture();
  const {bridge, base} = await firstCyclePaid(f);
  assert.equal(f.customer.quoteOrderCompleted, undefined);
  assert.equal(f.customer.order, undefined);
  const empty = await bridge.handle({...base, action: "demo_status"});
  assert.equal(empty.found, false);
  const first = await bridge.handle({...base, action: "demo_confirm"});
  assert.equal(first.alreadyExists, false);
  assert.equal(first.order.odooOrderName, "S00002");
  assert.equal(first.order.odooUntaxedCents, 12900);
  assert.equal(f.orders[1].partner_id, f.orders[0].partner_id);
  assert.equal(f.orders[1].origin, f.orders[0].origin);
  assert.equal(f.orderLines[1].name, f.orderLines[0].name);
  assert.equal(f.orderLines[1].price_unit, f.orderLines[0].price_unit);
  assert.equal(f.orderLines[1].discount, f.orderLines[0].discount);
  const again = await bridge.handle({...base, action: "demo_confirm"});
  assert.equal(again.alreadyExists, true);
  const restarted = await f.bridge().handle({...base, action: "demo_status"});
  assert.equal(restarted.order.odooOrderName, "S00002");
  assert.equal(f.orders.length, 2);
  assert.equal(f.partners.length, 1);
  const invoice = await bridge.handle({...base, action: "demo_invoice"});
  assert.equal(invoice.invoice.state, "posted");
  assert.equal(invoice.invoice.paymentState, "not_paid");
  assert.equal(invoice.invoice.odooInvoiceName, "INV/2026/00002");
  await bridge.handle({...base, action: "demo_invoice"});
  assert.equal(f.invoices.length, 2);
  assert.equal(f.invoices[0].payment_state, "paid");
  const link = await bridge.handle({...base, action: "demo_checkout"});
  assert.equal(link.portalUrl,
      "http://127.0.0.1:8069/my/invoices/2?access_token=test-token");
  assert.equal(link.campaignActivationAllowed, false);
  const status = await bridge.handle({...base, action: "demo_status"});
  assert.equal(status.found, true);
  assert.equal(status.transactions.length, 0);
  assert.equal(status.invoice.paymentState, "not_paid");
  assert.equal(status.campaignActivationAllowed, false);
});

test("Démo native : une ligne historique Odoo altérée empêche un second achat", async () => {
  const f = fixture();
  const {bridge, base} = await firstCyclePaid(f);
  f.orderLines[0].product_id = [99, "Produit étranger"];
  await assert.rejects(
      () => bridge.handle({...base, action: "demo_confirm"}),
      /tarif ou produit/i);
  assert.equal(f.orders.length, 1);
  assert.equal(f.invoices.length, 1);
});

test("Démo native : transaction Odoo lue, jamais inventée ni activante", async () => {
  const f = fixture();
  const {bridge, base} = await firstCyclePaid(f);
  await bridge.handle({...base, action: "demo_confirm"});
  await bridge.handle({...base, action: "demo_invoice"});
  f.demoTransactions.push({id: 1, reference: "DEMO-TEST-2", state: "done",
    provider_code: "demo", amount: 154.8, invoice_ids: [2]});
  f.invoices[1].payment_state = "in_payment";
  f.invoices[1].amount_residual = 0;
  const status = await bridge.handle({...base, action: "demo_status"});
  assert.equal(status.transactions.length, 1);
  assert.equal(status.transactions[0].provider, "demo");
  assert.equal(status.transactions[0].state, "done");
  assert.equal(status.invoice.paymentState, "in_payment");
  assert.equal(status.campaignActivationAllowed, false);
  await assert.rejects(
      () => bridge.handle({...base, action: "demo_checkout"}),
      /déjà en cours ou confirmée/i);
  assert.equal(f.invoices[0].payment_state, "paid");
});

test("Démo native : sans premier règlement confirmé, aucun deuxième achat", async () => {
  const f = fixture();
  const bridge = f.bridge();
  const base = {token: "valid-token", requestId: "blue-surf-001"};
  await assert.rejects(
      () => bridge.handle({...base, action: "demo_confirm"}),
      /première commande/i);
  assert.equal(f.orders.length, 0);
});

test("Démo native : prestataire non publié et transaction inattendue refusés", async () => {
  const f = fixture();
  const {bridge, base} = await firstCyclePaid(f);
  await bridge.handle({...base, action: "demo_confirm"});
  await bridge.handle({...base, action: "demo_invoice"});
  f.controls.demoProviderUnpublished = true;
  await assert.rejects(
      () => bridge.handle({...base, action: "demo_checkout"}),
      /non publié/i);
  f.controls.demoProviderUnpublished = false;
  f.demoTransactions.push({id: 1, reference: "REAL-TEST", state: "done",
    provider_code: "stripe", amount: 154.8, invoice_ids: [2]});
  await assert.rejects(
      () => bridge.handle({...base, action: "demo_status"}),
      /non Démo/i);
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

test("SPHOT Odoo local : règlement de caisse manuel, jamais de banque ou carte", async () => {
  const f = fixture();
  const bridge = f.bridge();
  const base = {token: "valid-token", requestId: "blue-surf-001"};
  await bridge.handle({action: "confirm", ...base, expected: f.expected});
  await assert.rejects(() => bridge.handle({action: "payment", ...base}),
      /facture Odoo validée/);
  await bridge.handle({action: "invoice", ...base});
  assert.equal(f.payments.length, 0);
  const first = await bridge.handle({action: "payment", ...base});
  assert.equal(first.alreadyExists, false);
  assert.equal(first.invoice.paymentState, "in_payment");
  assert.equal(first.invoice.odooPaymentRecorded, true);
  assert.equal(first.invoice.paymentInitiated, false);
  assert.equal(first.invoice.campaignActivationAllowed, false);
  assert.equal(f.payments.length, 1);
  assert.equal(f.payments[0].amount, 154.8);
  assert.equal(f.paymentWizards[0].journal_id[0], 10);
  assert.equal(f.paymentWizards[0].payment_method_line_id[0], 20);
  assert.equal(f.calls.filter((c) => c.model === "account.payment" ||
      c.model === "payment.transaction").length, 0);
  const afterNav = await f.bridge().handle({action: "invoice_status", ...base});
  assert.equal(afterNav.invoice.paymentState, "in_payment");
  const restoredOrder = await f.bridge().handle({action: "status", ...base});
  assert.equal(restoredOrder.order.paymentStatus, "in_payment");
  assert.equal(restoredOrder.order.odooInvoiceName, "INV/2026/00001");
  const second = await f.bridge().handle({action: "payment", ...base});
  assert.equal(second.alreadyExists, true);
  assert.equal(f.payments.length, 1);
});

test("SPHOT Odoo local : double clic règlement sans doublon", async () => {
  const f = fixture();
  const bridge = f.bridge();
  const base = {token: "valid-token", requestId: "blue-surf-001"};
  await bridge.handle({action: "confirm", ...base, expected: f.expected});
  await bridge.handle({action: "invoice", ...base});
  const two = await Promise.all([
    bridge.handle({action: "payment", ...base}),
    bridge.handle({action: "payment", ...base}),
  ]);
  assert.equal(two[0].invoice.paymentState, two[1].invoice.paymentState);
  assert.equal(f.payments.length, 1);
});

test("SPHOT Odoo local : règlement interdit sans caisse ou si montant erroné", async () => {
  const f = fixture();
  const bridge = f.bridge();
  const base = {token: "valid-token", requestId: "blue-surf-001"};
  await bridge.handle({action: "confirm", ...base, expected: f.expected});
  await bridge.handle({action: "invoice", ...base});
  f.controls.noCashJournal = true;
  await assert.rejects(() => bridge.handle({action: "payment", ...base}),
      /journal de caisse/);
  assert.equal(f.payments.length, 0);
  f.controls.noCashJournal = false;
  f.controls.wrongPaymentAmount = true;
  await assert.rejects(() => bridge.handle({action: "payment", ...base}),
      /Assistant Odoo non conforme/);
  assert.equal(f.payments.length, 0);
});

test("SPHOT Odoo local : paiement inconclus n'est jamais répété", async () => {
  const f = fixture();
  const bridge = f.bridge();
  const base = {token: "valid-token", requestId: "blue-surf-001"};
  await bridge.handle({action: "confirm", ...base, expected: f.expected});
  await bridge.handle({action: "invoice", ...base});
  f.controls.paymentStaysUnpaid = true;
  await assert.rejects(() => bridge.handle({action: "payment", ...base}),
      /Ne pas relancer/);
  assert.equal(f.payments.length, 1);
  await assert.rejects(() => f.bridge().handle({action: "payment", ...base}),
      /éviter un doublon/);
  assert.equal(f.payments.length, 1);
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
