"use strict";

// V2 : remplacement de deux méthodes par bornes, sans dépendance à
// l'indentation historique du widget Windows. Aucun accès réseau/Firestore.
const fs = require("node:fs");
const path = require("node:path");

const relativePath =
    "lib/web/super_admin/widgets/super_admin_admin_workflow_panel.dart";
const root = path.resolve(__dirname, "../..");
const target = path.join(root, relativePath);

const trialReplacement = [
  "  // Renouvellement exceptionnel : circuit serveur dédié requis.",
  "  Future<void> _renewTrial(",
  "    BuildContext context,",
  "    DocumentSnapshot<Map<String, dynamic>> requestSnapshot,",
  "  ) async {",
  "    if (!context.mounted) return;",
  "    await showDialog<void>(",
  "      context: context,",
  "      builder: (dialogContext) => AlertDialog(",
  "        title: const Text(",
  "          'RENOUVELLEMENT SOUMIS À VALIDATION SERVEUR',",
  "          style: TextStyle(color: _blue, fontWeight: FontWeight.w900),",
  "        ),",
  "        content: Text(",
  "          'Dossier ${requestSnapshot.id} : aucune prolongation de huit jours. '",
  "          'Le renouvellement devra être vérifié et historisé '",
  "          'par une fonction serveur Super Admin distincte.',",
  "        ),",
  "        actions: [",
  "          TextButton(",
  "            onPressed: () => Navigator.of(dialogContext).pop(),",
  "            child: const Text('FERMER'),",
  "          ),",
  "        ],",
  "      ),",
  "    );",
  "  }",
  "",
  "",
].join("\n");

const orderReplacement = [
  "  // Ancien bouton conservé, sans approbation ou écriture client.",
  "  Future<void> _approveOrder(",
  "    BuildContext context,",
  "    QueryDocumentSnapshot<Map<String, dynamic>> order,",
  "  ) async {",
  "    if (!context.mounted) return;",
  "    await showDialog<void>(",
  "      context: context,",
  "      builder: (dialogContext) => AlertDialog(",
  "        title: const Text(",
  "          'APPROBATION ODOO REQUISE',",
  "          style: TextStyle(color: _blue, fontWeight: FontWeight.w900),",
  "        ),",
  "        content: Text(",
  "          'Commande ${order.id} : aucune approbation ni activation. '",
  "          'Un engagement public contrôlé ou un paiement Odoo/Stripe '",
  "          'rapproché doit être vérifié côté serveur.',",
  "        ),",
  "        actions: [",
  "          TextButton(",
  "            onPressed: () => Navigator.of(dialogContext).pop(),",
  "            child: const Text('FERMER'),",
  "          ),",
  "        ],",
  "      ),",
  "    );",
  "  }",
  "",
  "",
].join("\n");

function uniqueMarker(source, marker) {
  const at = source.indexOf(marker);
  if (at < 0 || source.indexOf(marker, at + marker.length) >= 0) {
    throw new Error("BORNE_ABSENTE_OU_MULTIPLE : " + marker);
  }
  return at;
}

function replaceBetween(source, beginMarker, endMarker, newText, checkOld) {
  const begin = uniqueMarker(source, beginMarker);
  const end = uniqueMarker(source, endMarker);
  if (end <= begin) throw new Error("ORDRE_METHODES_INVALIDE");
  const existing = source.slice(begin, end);
  if (!checkOld(existing)) {
    throw new Error("ANCIEN_CODE_INATTENDU : " + beginMarker);
  }
  return source.slice(0, begin) + newText + source.slice(end);
}

function transformWidgetSource(original) {
  if (typeof original !== "string" || original.length < 1000) {
    throw new Error("WIDGET_INVALIDE");
  }
  if (original.includes("RENOUVELLEMENT SOUMIS À VALIDATION SERVEUR") ||
      original.includes("APPROBATION ODOO REQUISE")) {
    throw new Error("VERROU_DEJA_PRESENT_OU_PARTIEL");
  }

  const trialStart = "  Future<void> _renewTrial(";
  const orderStart = "  Future<void> _approveOrder(";
  const nextStart = "  String _documentRubricKey(";
  let source = replaceBetween(original, trialStart, orderStart,
      trialReplacement, (block) =>
        /runTransaction\s*</.test(block) &&
        /trialRenewalHistory/.test(block));
  source = replaceBetween(source, orderStart, nextStart,
      orderReplacement, (block) =>
        /order\.reference\.set\s*\(/.test(block) &&
        /'status'\s*:\s*'approved'/.test(block));

  // Les commentaires historiques avant les méthodes sont retirés si connus.
  source = source.replace(
      /  \/\/ Renouvellement de huit jours[^\r\n]*\r?\n  \/\/ des dossiers\.[^\r\n]*\r?\n/,
      "");

  const helperStart = source.indexOf("  String _firstNonEmpty(");
  if (helperStart >= 0) {
    const helperEnd = uniqueMarker(source, "  String _formatMoney(");
    if (helperEnd <= helperStart) throw new Error("HELPER_INVALIDE");
    const helper = source.slice(helperStart, helperEnd);
    if (helper.length > 700 || !/for\s*\(final value in values\)/.test(helper) ||
        !/return\s+'';/.test(helper)) {
      throw new Error("HELPER_MODIFIE_INATTENDU");
    }
    source = source.slice(0, helperStart) + source.slice(helperEnd);
  }
  if (/_firstNonEmpty\s*\(/.test(source)) {
    throw new Error("HELPER_UTILISE_AILLEURS");
  }
  if (!source.includes("onPressed: () => _renewTrial(") ||
      !source.includes("onPressed: () => _approveOrder(")) {
    throw new Error("BOUTON_NON_RACCORDE");
  }
  // Ne normaliser que les morceaux ajoutés ; conserver le reste à l'identique.
  const newline = original.includes("\r\n") ? "\r\n" : "\n";
  if (newline === "\r\n") {
    // Le texte préexistant conserve son encodage et ses fins de lignes.
    source = source.replace(trialReplacement, trialReplacement.replace(/\n/g, newline))
        .replace(orderReplacement, orderReplacement.replace(/\n/g, newline));
  }
  return source;
}

function main(mode) {
  if (!["--check", "--apply"].includes(mode)) {
    throw new Error("UTILISATION : node functions/local/admin_legacy_lock_v2.js --check|--apply");
  }
  if (!fs.existsSync(path.join(root, "functions", "index.js"))) {
    throw new Error("DOSSIER_SPHOT_INCORRECT");
  }
  const original = fs.readFileSync(target, "utf8");
  const updated = transformWidgetSource(original);
  if (mode === "--check") {
    console.log("WIDGET SUPER ADMIN V2 : VERIFICATION OK, ZERO ECRITURE");
    return;
  }
  const stamp = new Date().toISOString().replace(/[^0-9]/g, "").slice(0, 14);
  const backup = target + ".before_admin_lock_v2_" + stamp + ".bak";
  fs.copyFileSync(target, backup, fs.constants.COPYFILE_EXCL);
  const temporary = target + ".admin_lock_v2_" + process.pid + ".tmp";
  try {
    fs.writeFileSync(temporary, updated, {encoding: "utf8", flag: "wx"});
    fs.renameSync(temporary, target);
  } catch (error) {
    try {fs.unlinkSync(temporary);} catch (_) { /* Aucun temporaire. */ }
    console.error("SAUVEGARDE CONSERVEE :", backup);
    throw error;
  }
  console.log("WIDGET SUPER ADMIN V2 : VERROUILLAGE EFFECTUE");
  console.log("SAUVEGARDE LOCALE :", backup);
}

if (require.main === module) {
  try {
    main(process.argv[2]);
  } catch (error) {
    console.error("VERROUILLAGE V2 REFUSE :", error.message);
    process.exitCode = 1;
  }
}

module.exports = {transformWidgetSource};
