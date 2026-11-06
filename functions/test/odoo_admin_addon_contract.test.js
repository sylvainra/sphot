/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, brace-style, operator-linebreak, object-curly-spacing, comma-dangle */
"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {MODEL, DRAFT_METHOD, INVOICE_METHOD, STRIPE_EVIDENCE_METHOD,
  ORDER_CONTRACT, INVOICE_CONTRACT, STRIPE_EVIDENCE_CONTRACT} =
  require("../local/odoo_admin_checkout_client");

const root = path.join(__dirname, "../local/odoo_addon_patch/sphot_admin_checkout");
const python = fs.readFileSync(path.join(root, "models/admin_checkout.py"), "utf8");
const manifest = fs.readFileSync(path.join(root, "__manifest__.py"), "utf8");
const access = fs.readFileSync(path.join(root, "security/ir.access.csv"), "utf8");

test("Addon ADMIN : modèle distinct et dépendance PUBLICITAIRE", () => {
  assert.match(python, /_name = "sphot\.admin\.checkout"/);
  assert.equal(MODEL, "sphot.admin.checkout");
  assert.match(manifest, /"depends": \["sphot_advertiser_checkout"\]/);
  assert.doesNotMatch(python, /_inherit = "sphot\.advertiser\.checkout"/);
});

test("Addon ADMIN : signatures Python cohérentes avec l'adaptateur Node", () => {
  assert.match(python, new RegExp(`def ${DRAFT_METHOD}\\(self, sphot_reference, sphot_fingerprint,\\s+expected_untaxed_cents,\\s+expected_total_cents, order_values\\):`));
  assert.match(python, new RegExp(`def ${INVOICE_METHOD}\\(self, sphot_reference,\\s+sphot_fingerprint, sale_order_id,\\s+expected_total_cents\\):`));
  assert.match(python, new RegExp(`def ${STRIPE_EVIDENCE_METHOD}\\(self, sphot_reference,\\s+sphot_fingerprint, invoice_id\\):`));
  assert.ok(python.includes(`ORDER_CONTRACT = "${ORDER_CONTRACT}"`));
  assert.ok(python.includes(`INVOICE_CONTRACT = "${INVOICE_CONTRACT}"`));
  assert.ok(python.includes(`STRIPE_CONTRACT = "${STRIPE_EVIDENCE_CONTRACT}"`));
});

test("Addon ADMIN : accès restreint et sérialisation des factures", () => {
  assert.match(access, /sphot\.admin\.checkout,sphot_advertiser_checkout\.group_sphot_checkout_gateway,r,/);
  assert.match(python, /def _require_gateway\(self\):/);
  assert.match(python, /FOR UPDATE/);
  assert.match(python, /self\.env\.cr\.savepoint\(\)/);
  assert.match(python, /_create_invoices\(\)/);
  assert.match(python, /\(\"invoice_ids\", \"in\", \[invoice_id\]\)/);
});

test("Addon ADMIN : aucune opération de paiement ni écriture Firebase", () => {
  const executable = python.replace(/^"""[\s\S]*?"""/, "");
  assert.doesNotMatch(executable, /firebase|firestore|stripe\.Charge|payment\.register|payment\.transaction.*create/i);
  assert.match(python, /provider\.code|provider_code/);
});
