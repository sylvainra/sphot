"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "../..");
const read = (name) => fs.readFileSync(path.join(root, name), "utf8");
const between = (source, first, last) => {
  const begin = source.indexOf(first);
  const end = source.indexOf(last, begin + first.length);
  assert.ok(begin >= 0 && end > begin, `Bornes absentes : ${first}`);
  return source.slice(begin, end);
};

test("ADMIN historique : changer orders.status ne donne aucun droit", () => {
  const block = between(read("functions/admin_workflow.js"),
      "exports.activateApprovedAdminOrder =", "exports.syncAdminDocumentRegistry =");
  assert.match(block, /orders\/\{orderId\}/);
  assert.match(block, /commande historique ignorée/);
  assert.doesNotMatch(block, /\.batch\(|\.set\(|\.update\(|\.create\(|status: "active"/);
  assert.doesNotMatch(block, /diffusionAccessGranted|subscriptionActivatedAt/);
});

test("ADMIN Super Admin : aucun statut ni faux paiement depuis le bouton", () => {
  const block = between(read("lib/web/super_admin/pages/super_admin_subscriptions_page.dart"),
      "Future<void> _updateSubscriptionStatus(", "@override\n  Widget build(");
  assert.match(block, /MODIFICATION COMMERCIALE BLOQUÉE/);
  assert.doesNotMatch(block, /\.set\(|\.update\(|lastPaymentDate|nextInvoiceDate/);
});

test("ADMIN Super Admin : ancienne commande sans approbation Firestore", () => {
  const block = between(read("lib/web/super_admin/widgets/super_admin_admin_workflow_panel.dart"),
      "Future<void> _approveOrder(", "String _documentRubricKey(");
  assert.match(block, /APPROBATION ODOO REQUISE/);
  assert.doesNotMatch(block, /\.reference\.set\(|\.batch\(|\.runTransaction\(/);
});

test("ADMIN Super Admin : renouvellement sans transaction Flutter", () => {
  const source = read("lib/web/super_admin/widgets/super_admin_admin_workflow_panel.dart");
  const block = between(source, "Future<void> _renewTrial(", "Future<void> _approveOrder(");
  assert.match(block, /RENOUVELLEMENT SOUMIS À VALIDATION SERVEUR/);
  assert.doesNotMatch(block, /\.set\(|\.update\(|\.runTransaction\(|trialStartDate|diffusionAccessGranted/);
  assert.match(source, /onPressed: \(\) => _renewTrial\(/);
});

test("ADMIN : prix et postes affichables mais pas écrits depuis Flutter", () => {
  const block = between(read("lib/web/admin/pages/admin_subscription_panel.dart"),
      "Future<void> _saveSection(", "Future<");
  assert.match(block, /if \(section == 'offer'\) \{/);
  const guard = block.indexOf("if (section == 'offer') {");
  const write = block.indexOf("_subscriptionReference.set(");
  assert.ok(guard >= 0 && write > guard);
  const guarded = block.slice(guard, block.indexOf("setState(()", guard));
  assert.match(guarded, /return;/);
});

test("ADMIN Odoo : un impayé ne bascule pas en retard automatique", () => {
  const block = between(read("functions/index.js"),
      "exports.updateSubscriptionStatuses =", "exports.sendTrialEndingReminderEmails =");
  assert.match(block, /if \(\(doc\.data\(\) \|\| \{\}\)\.odooAdminManaged === true\) return;/);
});
