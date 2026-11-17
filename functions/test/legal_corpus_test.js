'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '../..');
const sourceDir = path.join(root, 'assets/legal/test_corpus');
const cases = [
  ['cgv_admin.md', 13, /FR-ADMIN-2027-01/],
  ['cgv_publicitaire.md', 13, /zone g.ographique|rayon/i],
  ['cgu_grand_public.md', 13, /sans compte|absence de compte/i],
  ['cgu_sauveteur.md', 8, /31 décembre de l’année de surveillance/],
  ['charte_sauveteur.md', 7, /Fin de saison/],
];

test('Corpus juridique C4 TEST : cinq documents complets et isolés', () => {
  for (const [file, expected, marker] of cases) {
    const content = fs.readFileSync(path.join(sourceDir, file), 'utf8');
    const count = (content.match(/^## /gm) || []).length;
    assert.equal(count, expected, file);
    assert.match(content, marker, file);
    if (file !== 'charte_sauveteur.md') {
      assert.ok(content.includes('contact@sphot.app'), file);
    }
  }
});

test('Main courante : clôture, accès retiré, copie ADMIN et échéance annuelle', () => {
  const sav = fs.readFileSync(path.join(sourceDir, 'cgu_sauveteur.md'), 'utf8');
  const charter = fs.readFileSync(
      path.join(sourceDir, 'charte_sauveteur.md'), 'utf8');
  const admin = fs.readFileSync(path.join(sourceDir, 'cgv_admin.md'), 'utf8');
  for (const text of [sav, admin]) {
    assert.match(text, /clôturée automatiquement|automatiquement clôturée/);
    assert.match(text, /31 décembre/);
    assert.match(text, /archives publiques|obligation légale d’archivage/);
    assert.match(text, /SPHOT ADMIN/);
  }
  assert.match(sav, /ne peuvent plus consulter ni modifier/);
  assert.match(charter, /n’est plus consultable par les sauveteurs/);
});

test('CGV ADMIN : ancienne référence d’essai absente des textes destinés au client', () => {
  const admin = fs.readFileSync(path.join(sourceDir, 'cgv_admin.md'), 'utf8');
  assert.match(admin, /FR-ADMIN-2027-01/);
  assert.doesNotMatch(admin, /FR_ADMIN-V3|SPHOT-ADM-TEST/);
});

test('Super Admin : édition TEST désactivée hors C4 et sans activation de commande', () => {
  const widget = fs.readFileSync(path.join(root,
      'lib/web/super_admin/widgets/super_admin_legal_test_corpus_editor.dart'),
      'utf8');
  const dashboard = fs.readFileSync(path.join(root,
      'lib/web/super_admin/pages/super_admin_dashboard_page.dart'), 'utf8');
  const pubspec = fs.readFileSync(path.join(root, 'pubspec.yaml'), 'utf8');
  assert.match(widget, /SPHOT_LEGAL_TEST_MODE/);
  assert.match(widget, /sphot-c4-test-20261029/);
  assert.match(widget, /'testOnly': true/);
  assert.match(widget, /'published': false/);
  assert.match(widget, /\.collection\('legalTestCorpus'\)/);
  assert.doesNotMatch(widget, /\.collection\('legalDocuments'\)/);
  assert.match(widget, /'revision': revision \+ 1/);
  assert.match(widget, /\.collection\('versions'\)/);
  assert.match(widget, /Document existant : aucun écrasement autorisé/);
  assert.match(widget, /Modification hors brouillon C4 TEST interdite/);
  assert.match(dashboard, /SuperAdminLegalTestCorpusEditor/);
  for (const [file] of cases) {
    assert.match(pubspec, new RegExp('assets/legal/test_corpus/' + file));
  }
  assert.doesNotMatch(widget, /stripe\.trigger|odooClient|payment_intent/);
});

test('Aperçu Chrome : point d’entrée C4 isolé et sans accès aux données', () => {
  const standalone = fs.readFileSync(path.join(root,
      'lib/main_web_legal_c4_test.dart'), 'utf8');
  const editor = fs.readFileSync(path.join(root,
      'lib/web/super_admin/widgets/super_admin_legal_test_corpus_editor.dart'),
      'utf8');
  assert.match(standalone, /sphot-c4-test-20261029/);
  assert.match(standalone, /1:46473700026:web:5e266ebd72801b28311883/);
  assert.match(standalone, /SuperAdminLegalTestCorpusEditor\.testFlag/);
  assert.match(standalone, /SuperAdminLegalTestCorpusEditor\.previewOnly/);
  assert.doesNotMatch(standalone, /firebase_options\.dart|main\.dart|WebSuperAdminApp/);
  assert.doesNotMatch(standalone, /sphot-ab80b|https?:\/\/|FirebaseFirestore/);
  assert.match(editor, /SPHOT_LEGAL_C4_PREVIEW_ONLY/);
  assert.match(editor, /if \(SuperAdminLegalTestCorpusEditor\.previewOnly\)/);
  assert.match(editor, /aucune lecture ni écriture Firestore/);
  assert.match(editor, /ENREGISTREMENT DÉSACTIVÉ/);
});

test('Menus juridiques : même composant visuel que les menus SPHOT existants', () => {
  const editor = fs.readFileSync(path.join(root,
      'lib/web/super_admin/widgets/super_admin_legal_test_corpus_editor.dart'),
      'utf8');
  const shared = fs.readFileSync(path.join(root,
      'lib/pages/sauveteur/widgets/sauveteur_styled_dropdown.dart'), 'utf8');
  assert.match(editor, /sauveteur_styled_dropdown\.dart/);
  assert.equal((editor.match(/SauveteurStyledDropdown\(/g) || []).length, 2);
  assert.match(editor, /labelText: 'Profil et document'/);
  assert.match(editor, /labelText: 'Article'/);
  assert.doesNotMatch(editor, /DropdownButtonFormField/);
  assert.match(shared, /Menu déroulant SPHOT SAUVETEUR harmonisé avec les filtres Super Admin/);
  assert.match(shared, /0xFF1E3A8A/);
  assert.match(shared, /0xFFDC2626/);
});

test('Lecture juridique : Markdown mis en forme sans altération des articles', () => {
  const editor = fs.readFileSync(path.join(root,
      'lib/web/super_admin/widgets/super_admin_legal_test_corpus_editor.dart'),
      'utf8');
  const preview = fs.readFileSync(path.join(root,
      'lib/web/super_admin/widgets/sphot_legal_markdown_preview.dart'), 'utf8');
  assert.match(editor, /SphotLegalMarkdownPreview\(source: current\.text\)/);
  assert.match(editor, /ValueListenableBuilder<TextEditingValue>/);
  assert.match(editor, /MODIFIER L’ARTICLE — TEXTE SOURCE/);
  assert.match(preview, /SelectableText\.rich/);
  assert.match(preview, /_boldPattern/);
  assert.match(preview, /_listPattern/);
  assert.doesNotMatch(preview, /FirebaseFirestore|FieldValue|\.set\(|\.update\(/);
  for (const [file] of cases) {
    assert.ok(fs.readFileSync(path.join(sourceDir, file), 'utf8').length > 100);
  }
});
