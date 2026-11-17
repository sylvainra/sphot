'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '../..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('CGV ADMIN : absentes de la demande d’accès, consultation en phase 2', () => {
  const registration = read('lib/web/admin/pages/admin_trial_request_page.dart');
  const subscription = read('lib/web/admin/pages/admin_subscription_panel.dart');
  assert.doesNotMatch(registration, /documentId:\s*'adminCgv'/);
  assert.match(subscription, /documentId:\s*'adminCgv'/);
  assert.doesNotMatch(subscription, /Le document de CGV publié, sa version/);
});

test('Confidentialité et RGPD : références communes aux profils et au Super Admin', () => {
  const registration = read('lib/web/admin/pages/admin_trial_request_page.dart');
  const advertiser = read('lib/web/advertiser/widgets/advertiser_legal_acceptance_section.dart');
  const rescue = read('lib/pages/sauveteur/sauveteur_legal_acceptance_page.dart');
  const dashboard = read('lib/web/super_admin/pages/super_admin_dashboard_page.dart');
  for (const id of ['privacyPolicy', 'rgpdNotice']) {
    for (const [file, source] of [
      ['Admin', registration], ['Publicitaire', advertiser],
      ['Sauveteur', rescue], ['Super Admin', dashboard],
    ]) {
      assert.ok(source.includes(`'${id}'`), `${file}: ${id}`);
    }
  }
});

test('Consultation des documents : aucune acceptation ou commande implicite', () => {
  const viewer = read('lib/widgets/sphot_legal_document_card.dart');
  assert.match(viewer, /collection\('legalDocuments'\)/);
  assert.doesNotMatch(viewer, /\.set\(|\.update\(|payment_intent|createOrder/);
  assert.doesNotMatch(viewer, /Document en cours de préparation/);
});

test('Super Admin : édition unique de tous les documents propres aux profils', () => {
  const editor = read('lib/web/super_admin/widgets/super_admin_profile_legal_editor.dart');
  const dashboard = read('lib/web/super_admin/pages/super_admin_dashboard_page.dart');
  for (const id of ['adminCgv', 'advertiserCgv', 'sauveteurCgu',
    'sauveteurCharter']) {
    assert.ok(editor.includes(`'${id}'`), id);
  }
  assert.match(editor, /'version': '1\.0'/);
  assert.match(editor, /SauveteurStyledDropdown/);
  assert.match(dashboard, /SuperAdminProfileLegalEditor/);
});

test('Sauveteur : CGU professionnelle puis repli compatible, charte commune', () => {
  const page = read('lib/pages/sauveteur/sauveteur_legal_acceptance_page.dart');
  assert.match(page, /_loadDocument\('sauveteurCgu'\)/);
  assert.match(page, /_loadDocument\('cgu'\)/);
  assert.match(page, /documentId:\s*'sauveteurCharter'/);
});
