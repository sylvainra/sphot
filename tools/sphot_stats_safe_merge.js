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
const FEATURE = "285602dac43eff8a22e868bef89bf84808960eef";
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


function safeScopedMerge(local, base, feature) {
  function part(source, start, end, label) {
    const a = source.indexOf(start);
    assert(a >= 0 && source.indexOf(start, a + start.length) === -1,
        "Ancre manquante ou multiple : " + label);
    const b = source.indexOf(end, a + start.length);
    assert(b >= 0, "Fin de section manquante : " + label);
    return {a, b, body: source.slice(a, b)};
  }
  function insert(source, old, newer, before, after, label) {
    function between(v) {
      const i = v.indexOf(before);
      assert(i >= 0 && v.indexOf(before, i + before.length) === -1,
          "Ancre introuvable ou multiple : " + label);
      const j = v.indexOf(after, i + before.length);
      assert(j >= 0, "Ancre finale absente : " + label);
      return v.slice(i + before.length, j);
    }
    const was = between(old);
    const will = between(newer);
    const here = between(source);
    assert(was === "" && will.length > 0,
        "Révision distante inattendue : " + label);
    if (here === will) return source;
    assert(here === was, "Modification locale dans " + label +
        " : arrêt sans écrasement");
    assert(source.split(before + after).length === 2,
        "Insertion ambiguë : " + label);
    return source.replace(before + after, before + will + after);
  }
  // La seule variante locale explicitement diagnostiquée et autorisée.
  function knownLocalStatsVariant(here, original) {
    const guardStart =
        '        const spotId = (request.body.spotId || "").toString().trim();\n\n';
    const guardEnd = '          response.status(403).json({';
    const oldGuard =
        '        if (!context.assignedSpotIds.includes(spotId) ||\n' +
        '            !(await supervisedSpotIds(\n' +
        '                admin.firestore(), context.territoireId, [spotId]))\n' +
        '                .includes(spotId)) {\n';
    const localGuard =
        '        if (!context.realtimeSpotIds.includes(spotId)) {\n';
    const queryStart = '        let entriesQuery = admin.firestore()';
    const baseQueryStart =
        '        const bounds = mainCouranteReadBounds(request.body);';
    const queryEnd = '        const canSeeRestricted =';
    const knownQuery = "        let entriesQuery = admin.firestore()\n            .collection(\"territoires\")\n            .doc(context.territoireId)\n            .collection(\"spots\")\n            .doc(spotId)\n            .collection(\"mainCourante\");\n\n        const dayStartMillis = Number(request.body.dayStartMillis);\n        const dayEndMillis = Number(request.body.dayEndMillis);\n        if (Number.isFinite(dayStartMillis) &&\n            Number.isFinite(dayEndMillis) &&\n            dayEndMillis > dayStartMillis) {\n          entriesQuery = entriesQuery\n              .where(\n                  \"occurredAt\",\n                  \">=\",\n                  admin.firestore.Timestamp.fromMillis(dayStartMillis),\n              )\n              .where(\n                  \"occurredAt\",\n                  \"<\",\n                  admin.firestore.Timestamp.fromMillis(dayEndMillis),\n              );\n        }\n\n        const snapshot = await entriesQuery\n            .orderBy(\"occurredAt\", \"desc\")\n            .limit(500)\n            .get();\n\n";
    function span(text, first, last) {
      const a = text.indexOf(first);
      if (a < 0 || text.indexOf(first, a + first.length) >= 0) return null;
      const b = text.indexOf(last, a + first.length);
      return b < 0 ? null : {a, b, value: text.slice(a, b)};
    }
    const bGuard = span(original, guardStart, guardEnd);
    const lGuard = span(here, guardStart, guardEnd);
    if (!bGuard || !lGuard ||
        bGuard.value !== guardStart + oldGuard ||
        lGuard.value !== guardStart + localGuard) return false;
    const bQuery = span(original, baseQueryStart, queryEnd);
    const lQuery = span(here, queryStart, queryEnd);
    if (!bQuery || !lQuery ||
        lQuery.value.replace(/\s+/g, "") !==
        knownQuery.replace(/\s+/g, "")) return false;
    const authBack = here.slice(0, lGuard.a) + bGuard.value +
        here.slice(lGuard.b);
    const queryBack = span(authBack, queryStart, queryEnd);
    if (!queryBack) return false;
    return authBack.slice(0, queryBack.a) + bQuery.value +
        authBack.slice(queryBack.b) === original;
  }

  function apply(src) {
    let result = src;
    const from = "exports.getSauveteurStats = onRequest(";
    const until = "function sanitizeMainCouranteVictim(";
    const original = part(base, from, until, "statistiques origine");
    const incoming = part(feature, from, until, "statistiques cible");
    const existing = part(result, from, until, "statistiques locales");
    if (existing.body !== incoming.body) {
      assert(existing.body === original.body ||
          knownLocalStatsVariant(existing.body, original.body),
      "getSauveteurStats contient d'autres modifications locales : " +
      "arrêt sécurisé sans écrasement");
      result = result.slice(0, existing.a) + incoming.body +
          result.slice(existing.b);
    }

    const liveStart = "exports.updateSauveteurLiveState = onRequest(";
    const liveEnd = "exports.getSauveteurMainCourante = onRequest(";
    const oldLive = part(base, liveStart, liveEnd, "live origine");
    const newLive = part(feature, liveStart, liveEnd, "live cible");
    const localLive = part(result, liveStart, liveEnd, "live local");
    let updated = insert(localLive.body, oldLive.body, newLive.body,
        "          const previousSpot = spotSnapshot.data() || {};\n",
        "          const operationalTerritoryId =",
        "l'identifiant de la recherche");
    updated = insert(updated, oldLive.body, newLive.body,
        '              source: "automatic_person_search_publication",\n',
        "              publicNotificationMessage:",
        "le journal des recherches");
    result = result.slice(0, localLive.a) + updated + result.slice(localLive.b);

    const yearAnchor = "  mainCouranteReadBounds,\n";
    const yearLine = "  parisCivilYear,\n";
    assert(feature.includes(yearAnchor + yearLine) &&
        !base.includes(yearAnchor + yearLine),
    "Import de l'année civile non confirmé");
    if (!result.includes(yearAnchor + yearLine)) {
      assert(result.split(yearAnchor).length === 2,
          "Import mainCouranteReadBounds ambigu");
      result = result.replace(yearAnchor, yearAnchor + yearLine);
    }
    const helperAnchor =
        '} = require("./sauveteur_main_courante_lifecycle");\n';
    const helper =
        'const {searchCaseIdForNotification, seasonPeriodsForStation} =\n' +
        '    require("./sauveteur_stats_support");\n';
    assert(feature.includes(helperAnchor + helper) &&
        !base.includes(helper), "Import du helper non confirmé");
    if (!result.includes(helper)) {
      assert(result.split(helperAnchor).length === 2,
          "Ancre du helper ambiguë");
      result = result.replace(helperAnchor, helperAnchor + helper);
    }
    return result;
  }
  assert(apply(base) === feature,
      "Version cible différente des seules évolutions STATS : abandon");
  return apply(local);
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
  // Git objects use LF, while Windows worktrees often use CRLF.
  // Normalizing only the temporary comparison prevents false conflicts.
  const localUsesCrLf = current.toString("utf8").includes("\r\n");
  const normalizedCurrent = Buffer.from(
      current.toString("utf8").replace(/\r\n/g, "\n"), "utf8");
  const session = fs.mkdtempSync(path.join(os.tmpdir(), "sphot-stats-merge-"));
  const currentFile = path.join(session, "current-index.js");
  const baseFile = path.join(session, "reference-index.js");
  const proposedFile = path.join(session, "incoming-index.js");
  const mergePreview = path.join(session, "merged-index.js");
  const backup = path.join(session, "index-before-merge.js");

  fs.writeFileSync(currentFile, normalizedCurrent);
  fs.writeFileSync(baseFile, base);
  fs.writeFileSync(proposedFile, proposed);
  fs.writeFileSync(backup, current);

  const merged = cp.spawnSync("git", [
    "merge-file", "--diff3", "--stdout",
    currentFile, baseFile, proposedFile,
  ], {maxBuffer: 30 * 1024 * 1024});
  assert(!merged.error, "git merge-file non disponible");
  let output = merged.stdout;
  if (merged.status !== 0) {
    process.stdout.write(
        "Fusion globale en conflit (" + merged.status +
        "). Essai ciblé et vérifié sur STATS uniquement...\n");
    const scoped = safeScopedMerge(
        normalizedCurrent.toString("utf8"),
        base.toString("utf8"), proposed.toString("utf8"));
    output = Buffer.from(scoped, "utf8");
  }
  fs.writeFileSync(mergePreview, output);
  const result = output.toString("utf8");
  const expected = [
    "exports.getSauveteurStats =",
    "exports.updateSauveteurLiveState =",
    "const {searchCaseIdForNotification, seasonPeriodsForStation}",
    "searchCaseId: automaticNotificationMainCourante.searchCaseId",
    "const seasonPeriods = seasonPeriodsForStation({",
    "pageQuery = pageQuery.startAfter(cursor);",
    "context.realtimeSpotIds.includes(spotId)",
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
  const mergedOnDisk = localUsesCrLf ?
    Buffer.from(result.replace(/\n/g, "\r\n"), "utf8") : output;
  fs.writeFileSync(indexPath, mergedOnDisk);
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
