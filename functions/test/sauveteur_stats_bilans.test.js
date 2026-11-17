"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  searchCaseIdForNotification,
  seasonPeriodsForStation,
} = require("../sauveteur_stats_support");

const root = path.join(__dirname, "../..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

test("une republication de la même recherche garde son identifiant", () => {
  let generated = 0;
  const createId = () => {
    generated++;
    return "nouveau-" + generated;
  };
  const active = {
    active: true,
    source: "recherche_personne",
    searchCaseId: "recherche-123",
  };
  assert.equal(searchCaseIdForNotification(active, createId),
      "recherche-123");
  assert.equal(searchCaseIdForNotification(active, createId),
      "recherche-123");
  assert.equal(generated, 0);
});

test("après clôture ou notification différente, nouvelle recherche", () => {
  const createId = () => "recherche-456";
  assert.equal(searchCaseIdForNotification(
      {active: false, source: "recherche_personne",
        searchCaseId: "ancienne"}, createId), "recherche-456");
  assert.equal(searchCaseIdForNotification(
      {active: true, source: "autre",
        searchCaseId: "ancienne"}, createId), "recherche-456");
  assert.equal(searchCaseIdForNotification(
      {active: true, source: "recherche_personne"}, createId),
  "recherche-456");
});

test("une saison réunit les périodes affectées sans prendre les autres", () => {
  const station = {periodesSurveillanceIds: ["mai", "aout", "automne"]};
  const periods = [
    {id: "mai", startDate: new Date("2026-05-01T12:00:00Z"),
      endDate: new Date("2026-05-31T12:00:00Z")},
    {id: "aout", startDate: new Date("2026-08-01T12:00:00Z"),
      endDate: new Date("2026-08-31T12:00:00Z")},
    {id: "automne", startDate: new Date("2026-08-20T12:00:00Z"),
      endDate: new Date("2026-09-15T12:00:00Z")},
    {id: "non-affectee", startDate: new Date("2026-06-01T12:00:00Z"),
      endDate: new Date("2026-06-30T12:00:00Z")},
  ];
  assert.deepEqual(seasonPeriodsForStation({
    station, assigned: [], periods, year: 2026,
  }), [
    {startDay: 20260501, endDay: 20260531},
    {startDay: 20260801, endDay: 20260831},
    {startDay: 20260820, endDay: 20260915},
  ]);
});

test("le bilan n'inclut pas une saison d'une autre année", () => {
  const station = {periodesSurveillanceIds: ["ancienne", "traversante"]};
  const periods = [
    {id: "ancienne", startDate: new Date("2025-05-01T12:00:00Z"),
      endDate: new Date("2025-08-31T12:00:00Z")},
    {id: "traversante", startDate: new Date("2025-12-15T12:00:00Z"),
      endDate: new Date("2026-01-15T12:00:00Z")},
  ];
  const result = seasonPeriodsForStation({
    station, assigned: [], periods, year: 2026,
  });
  assert.deepEqual(result, [
    {startDay: 20251215, endDay: 20260115},
  ]);
});

test("les statistiques conservent les protections et suppriment le " +
    "plafond 500", () => {
  const backend = read("functions/index.js");
  const start = backend.indexOf("exports.getSauveteurStats =");
  const end = backend.indexOf("function sanitizeMainCouranteVictim(", start);
  const stats = backend.slice(start, end);
  assert.match(stats, /resolveSauveteurSession/);
  assert.match(stats, /legalAcceptanceCurrent/);
  assert.match(stats, /context\.realtimeSpotIds\.includes\(spotId\)/);
  assert.match(stats, /context\.canManageRestrictedOperationalData/);
  assert.match(stats, /pageQuery\.startAfter\(cursor\)/);
  assert.match(stats, /seasonPeriodsForStation/);
  assert.match(stats, /searchCaseId: entry\.searchCaseId \|\| ""/);
  assert.match(stats, /qualification: entry\.victim\.qualification/);
});

test("les bilans et le PDF utilisent les recherches distinctes " +
    "par périmètre", () => {
  const ui = read("lib/pages/sauveteur/sauveteur_stats_page.dart");
  assert.match(ui, /_summaryCard\(\s*title: 'BILAN MENSUEL'/);
  assert.match(ui, /title: 'BILAN SAISONNIER '/);
  assert.match(ui, /searches\.add\(caseId\.isNotEmpty/);
  assert.match(ui,
      /_seasonPeriods\.any\(\(period\) => period\.contains\(key\)\)/);
  assert.match(ui, /Bilan de saison /);
  assert.match(ui, /Recherches distinctes : /);
  assert.match(ui, /_eventRow\(stats\.summary\)/);
  assert.ok(ui.includes("'Autres faits : aucun'"));
});

test("les faits journaliers ne répètent pas les trois compteurs", () => {
  const ui = read("lib/pages/sauveteur/sauveteur_stats_page.dart");
  const day = ui.split("Widget _dayCard(_DailyStats stats) {")[1]
      .split("Future<Uint8List> _buildPdf()")[0];
  assert.ok(day.includes("stats.facts.entries.where((entry)"));
  for (const category of ["incident", "intervention", "personne recherchée"]) {
    assert.ok(day.includes("type != '" + category + "'"));
  }
  assert.ok(day.includes("if (stats.facts.isEmpty)"));
  assert.ok(day.includes("else if (factEntries.isNotEmpty)"));
  assert.ok(day.includes("_eventRow(stats.summary)"));
  assert.ok(day.includes("stats.rescueQualifications.isNotEmpty"));
});

test("libellés des compteurs agrandis et adaptés à la largeur", () => {
  const ui = read("lib/pages/sauveteur/sauveteur_stats_page.dart");
  const count = ui.split("Widget _eventCount({")[1]
      .split("Widget _eventRow(")[0];
  for (const token of ["fontSize: 16", "fontSize: 10.5",
    "FittedBox(", "BoxFit.scaleDown",
    "crossAxisAlignment: CrossAxisAlignment.stretch",
    "textAlign: TextAlign.center"]) {
    assert.ok(count.includes(token));
  }
});

test("accès rapide aux bilans conservant le défilement et PARTAGER", () => {
  const ui = read("lib/pages/sauveteur/sauveteur_stats_page.dart");
  const build = ui.split("Widget build(BuildContext context) {")[1]
      .split("class _SeasonPeriod {")[0];
  assert.ok(ui.includes("Scrollable.ensureVisible("));
  assert.ok(ui.includes("_monthlySummaryKey.currentContext"));
  for (const token of ["'VOIR LES BILANS'", "SingleChildScrollView(",
    "key: _monthlySummaryKey", "title: 'BILAN MENSUEL'",
    "title: 'BILAN SAISONNIER '", "'PARTAGER'"]) {
    assert.ok(build.includes(token));
  }
});

test("la flèche suivante et le calcul bloquent les mois futurs", () => {
  const ui = read("lib/pages/sauveteur/sauveteur_stats_page.dart");
  assert.ok(ui.includes("bool get _canGoToNextMonth"));
  assert.ok(ui.includes(
      "if (target.isAfter(DateTime(now.year, now.month))) return;"));
  assert.ok(ui.includes("onPressed: _canGoToNextMonth ?"));
});
