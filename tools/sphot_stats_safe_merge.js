"use strict";

/**
 * SPHOT STATS: conservative local three-way integration.
 *
 * Usage:
 *   node tools/sphot_stats_safe_merge.js --check
 *   node tools/sphot_stats_safe_merge.js --apply
 *
 * - Does NOT check out a branch, stage, commit, push or deploy anything.
 * - Does NOT touch firebase.json, Odoo, Admin, legal files or the UI.
 * - Never overwrites a conflicting local functions/index.js.
 * - Stores a copy of the original and the merge proposal outside the repo.
 */
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const cp = require("node:child_process");

const BASE = "5580e2278bdfbea5521335960644f6c73d393ed6";
const FEATURE = "f876d4f00011e4e74f562898ffd6989e548eabf3";
const TARGET = "functions/index.js";
const AUXILIARY = [
  "functions/sauveteur_stats_support.js",
  "functions/test/sauveteur_stats_bilans.test.js",
];

const mode = process.argv[2];
if (mode !== "--check" && mode !== "--apply") {
  process.stderr.write("Usage: node tools/sphot_stats_safe_merge.js --check|--apply\n");
  process.exit(2);
}

function git(args, options = {}) {
  return cp.execFileSync("git", args, {
    maxBuffer: 30 * 1024 * 1024,
    ...options,
  });
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function run() {
  const root = git(["rev-parse", "--show-toplevel"], {encoding: "utf8"}).trim();
  const indexPath = path.join(root, TARGET);
  const pagePath = path.join(
      root, "lib/pages/sauveteur/sauveteur_stats_page.dart");
  assert(fs.existsSync(indexPath), "functions/index.js absent");
  assert(fs.existsSync(pagePath), "Page STATS absente");
  const ui = fs.readFileSync(pagePath, "utf8");
  assert(ui.includes("'VOIR LES BILANS'"),
      "Installer d'abord le nouvel écran STATS, sans changer de branche.");

  // A pinned, immutable commit is used: later work on the feature branch
  // cannot unexpectedly change what is merged into the local installation.
  const base = git(["show", BASE + ":" + TARGET]);
  const proposed = git(["show", FEATURE + ":" + TARGET]);
  const current = fs.readFileSync(indexPath);
  const session = fs.mkdtempSync(path.join(os.tmpdir(), "sphot-stats-merge-"));
  const currentFile = path.join(session, "current-index.js");
  const baseFile = path.join(session, "reference-index.js");
  const proposedFile = path.join(session, "incoming-index.js");
  const mergePreview = path.join(session, "merged-index.js");
  const backup = path.join(session, "index-before-merge.js");

  fs.writeFileSync(currentFile, current);
  fs.writeFileSync(baseFile, base);
  fs.writeFileSync(proposedFile, proposed);
  fs.writeFileSync(backup, current);

  const merged = cp.spawnSync("git", [
    "merge-file", "--diff3", "--stdout",
    currentFile, baseFile, proposedFile,
  ], {maxBuffer: 30 * 1024 * 1024});
  assert(!merged.error, "git merge-file non disponible");
  fs.writeFileSync(mergePreview, merged.stdout);
  if (merged.status !== 0) {
    process.stderr.write(
        "CONFLIT : index.js inchangé.\n" +
        "Aucune modification effectuée.\n" +
        "Proposition à examiner : " + mergePreview + "\n" +
        "Code de retour Git : " + merged.status + "\n");
    process.exit(3);
  }

  const result = merged.stdout.toString("utf8");
  const expected = [
    "exports.getSauveteurStats =",
    "exports.updateSauveteurLiveState =",
    "const {searchCaseIdForNotification, seasonPeriodsForStation}",
    "searchCaseId: automaticNotificationMainCourante.searchCaseId",
    "const seasonPeriods = seasonPeriodsForStation({",
    "pageQuery = pageQuery.startAfter(cursor);",
    "context.canManageRestrictedOperationalData",
    "searchCaseId: entry.searchCaseId ||",
    "          seasonPeriods,",
  ];
  for (const marker of expected) {
    assert(result.includes(marker),
        "Merge incomplet / règle absente : " + marker);
  }
  assert(!result.includes("<<<<<<<") &&
      !result.includes(">>>>>>>") &&
      !result.includes("======="),
  "Marqueur de conflit détecté.");

  const syntax = cp.spawnSync("node", ["--check", mergePreview], {
    encoding: "utf8",
  });
  if (syntax.status !== 0) {
    throw new Error("Syntaxe JS invalide : " + syntax.stderr);
  }

  const auxiliaries = AUXILIARY.map((p) => {
    const dest = path.join(root, p);
    const data = git(["show", FEATURE + ":" + p]);
    if (fs.existsSync(dest) &&
        !fs.readFileSync(dest).equals(data)) {
      throw new Error("Fichier existant différent, préservé : " + dest);
    }
    return {dest, data};
  });

  process.stdout.write(
      "Fusion trois voies réussie (sans toucher au reste du projet).\n" +
      "Original sauvegardé : " + backup + "\n" +
      "Aperçu du résultat : " + mergePreview + "\n");

  if (mode === "--check") {
    process.stdout.write(
        "PRÉCONTRÔLE OK : aucun fichier local modifié.\n" +
        "Pour appliquer : node tools/sphot_stats_safe_merge.js --apply\n");
    return;
  }

  // Every check has passed before the first file is written.
  fs.writeFileSync(indexPath, merged.stdout);
  for (const {dest, data} of auxiliaries) {
    if (!fs.existsSync(dest)) {
      fs.mkdirSync(path.dirname(dest), {recursive: true});
      fs.writeFileSync(dest, data);
    }
  }
  process.stdout.write(
      "INTÉGRATION LOCALE EFFECTUÉE. Aucun commit ni déploiement.\n" +
      "Contrôles suivants :\n" +
      "  node --check functions/index.js\n" +
      "  npm --prefix functions run lint\n" +
      "  node --test functions/test/sauveteur_stats_bilans.test.js\n" +
      "  git diff -- functions/index.js\n" +
      "Original de secours : " + backup + "\n");
}

try {
  run();
} catch (error) {
  process.stderr.write("Arrêt sécurisé : " + error.message + "\n");
  process.exitCode = 1;
}
