"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../..");

// Sous Windows, Git peut extraire les Markdown avec CRLF alors que les
// sources JSON approuvées contiennent LF. Seules les fins de ligne varient.
const normalizeEndOfLines = (value) => value.replace(/\r\n?/g, "\n");
const documents = [
  ["adminCgu", "cgu_admin.md", 14],
  ["advertiserCgu", "cgu_publicitaire.md", 12],
  ["sauveteurCgu", "cgu_sauveteur.md", 8],
  ["sauveteurCharter", "charte_sauveteur.md", 7],
];

test("les textes approuvés sont strictement identiques aux sources Firebase", () => {
  for (const [id, filename, expected] of documents) {
    const markdown = normalizeEndOfLines(fs.readFileSync(path.join(root,
        "assets/legal/prepublication_2026_11_11", filename), "utf8"));
    const json = JSON.parse(fs.readFileSync(path.join(root,
        "functions-legal/legal_sources", id + ".json"), "utf8"));
    const headings = [...markdown.matchAll(/^##\s+(.+)$/gm)];
    const rows = headings.map((m, i) => ({
      id: String(i + 1).padStart(2, "0"),
      title: m[1].trim(),
      content: markdown.substring(m.index + m[0].length,
          i + 1 < headings.length ? headings[i + 1].index :
            markdown.length).trim(),
    }));
    assert.equal(rows.length, expected, id + " nombre de rubriques");
    assert.deepEqual(rows, json.chapters.map((c) => ({
      id: c.id, title: c.title,
      content: normalizeEndOfLines(c.content),
    })), id + " correspondance exacte");
    assert.equal(json.status, "PREPUBLICATION_NON_PUBLIE");
  }
});

test("Windows CRLF et Unix LF ne changent pas le texte approuvé", () => {
  const approved = "premier paragraphe\n\ndeuxième paragraphe";
  const windows = "premier paragraphe\r\n\r\ndeuxième paragraphe";
  assert.equal(normalizeEndOfLines(windows), approved);
  assert.notEqual(normalizeEndOfLines(windows + " modifié"), approved);
});

test("les cinq documents sont branchés au bon acteur", () => {
  const read = (p) => fs.readFileSync(path.join(root, p), "utf8");
  const panel = read("lib/web/super_admin/widgets/super_admin_legal_audience_panel.dart");
  for (const [id] of documents) {
    assert.ok(panel.includes("'" + id + "'"),
        id + " absent du dashboard");
  }
  assert.match(panel, /ENREGISTRER DANS FIREBASE \(BROUILLON\)/);

  const publicGate = read("lib/map/public_legal_gate.dart");
  assert.match(publicGate, /PublicLegalDocument\.load\('cgu'/);

  const admin = read("lib/web/admin/pages/admin_trial_request_page.dart");
  assert.match(admin, /loadLegalDoc\('adminCgu'\)/);
  assert.match(admin, /cguId: 'adminCgu'/);
  assert.match(admin, /LegalPublishedVersion\.identifier/);

  const advertiser = read("lib/web/advertiser/widgets/advertiser_legal_acceptance_section.dart");
  assert.match(advertiser, /_loadLegalDocument\('advertiserCgu'\)/);
  assert.match(advertiser, /cguId: 'advertiserCgu'/);
  assert.match(advertiser, /LegalPublishedVersion\.identifier/);

  const rescuer = read("lib/pages/sauveteur/sauveteur_legal_acceptance_page.dart");
  assert.match(rescuer, /_loadDocument\('sauveteurCgu'\)/);
  assert.match(rescuer, /_loadDocument\('sauveteurCharter'\)/);
  assert.match(rescuer, /charterId: 'sauveteurCharter'/);
  assert.match(rescuer, /LegalPublishedVersion\.identifier/);

  const login = read("lib/map/profil_login_page.dart");
  for (const id of ["adminCgu", "advertiserCgu", "sauveteurCgu",
    "sauveteurCharter"]) {
    assert.ok(login.includes("'" + id + "'"),
        id + " absent de la connexion commune");
  }
  assert.match(login, /LegalPublishedVersion\.identifier/);
});
