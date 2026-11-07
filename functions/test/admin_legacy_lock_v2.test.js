"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {transformWidgetSource} = require("../local/admin_legacy_lock_v2");

function historical() {
  return [
    "class SuperAdminAdminWorkflowPanel {",
    "  // Exemple de code préservé en dehors des méthodes ciblées.",
    "  //" + "x".repeat(1100),
    "  String _firstNonEmpty(Iterable<dynamic> values) {",
    "    for (final value in values) {",
    "      if (value.toString().isNotEmpty) return value.toString();",
    "    }",
    "    return '';",
    "  }",
    "",
    "  String _formatMoney(dynamic value) { return 'test'; }",
    "  Future<void> _approveTrial(BuildContext context) async {",
    "    await SuperAdminTrialAuthorizationService.authorize();",
    "  }",
    "  // Renouvellement de huit jours, compatible avec les variantes historiques",
    "  // des dossiers. Les champs facultatifs absents ne sont jamais exigés.",
    "  Future<void> _renewTrial(",
    "    BuildContext context,",
    "    DocumentSnapshot<Map<String, dynamic>> requestSnapshot,",
    "  ) async {",
    "    await db.runTransaction<void>((transaction) async {",
    "      transaction.update(ref, {'trialRenewalHistory': []});",
    "    });",
    "    _firstNonEmpty([requestSnapshot.id]);",
    "  }",
    "",
    "  Future<void> _approveOrder(",
    "    BuildContext context,",
    "    QueryDocumentSnapshot<Map<String, dynamic>> order,",
    "  ) async {",
    "    await order.reference.set({'status': 'approved'});",
    "  }",
    "",
    "  String _documentRubricKey(Map<String, dynamic> data) {return '';}",
    "  onPressed: () => _renewTrial(context, requestSnapshot),",
    "  onPressed: () => _approveOrder(context, order),",
    "}",
    "",
  ].join("\n");
}

test("ADMIN V2 : retrait des anciens chemins d'écriture Flutter", () => {
  const newSource = transformWidgetSource(historical());
  const renewal = newSource.slice(newSource.indexOf("Future<void> _renewTrial("),
      newSource.indexOf("Future<void> _approveOrder("));
  const order = newSource.slice(newSource.indexOf("Future<void> _approveOrder("),
      newSource.indexOf("String _documentRubricKey("));
  assert.match(renewal, /RENOUVELLEMENT SOUMIS À VALIDATION SERVEUR/);
  assert.doesNotMatch(renewal, /runTransaction|transaction\.update|trialRenewalHistory/);
  assert.match(order, /APPROBATION ODOO REQUISE/);
  assert.doesNotMatch(order, /order\.reference\.set|approvedAt/);
  assert.doesNotMatch(newSource, /String _firstNonEmpty\(/);
  assert.match(newSource, /SuperAdminTrialAuthorizationService\.authorize/);
  assert.match(newSource, /onPressed: \(\) => _renewTrial\(/);
  assert.match(newSource, /onPressed: \(\) => _approveOrder\(/);
});

test("ADMIN V2 : mise en forme Windows différente acceptée", () => {
  const modified = historical()
      .replace("runTransaction<void>((transaction) async {",
          "runTransaction<void>((transaction)async {")
      .replace("{'status': 'approved'}", "{'status' : 'approved'}")
      .replace("'trialRenewalHistory': []", "'trialRenewalHistory' : []");
  assert.match(transformWidgetSource(modified), /APPROBATION ODOO REQUISE/);
});

test("ADMIN V2 : refus si modification imprévue ou verrou déjà présent", () => {
  const locked = transformWidgetSource(historical());
  assert.throws(() => transformWidgetSource(locked), /VERROU_DEJA_PRESENT/);
  assert.throws(() => transformWidgetSource(historical().replace(
      "runTransaction<void>", "unknownTransaction<void>")),
  /ANCIEN_CODE_INATTENDU/);
});
