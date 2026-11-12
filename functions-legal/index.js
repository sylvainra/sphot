"use strict";

// Independent Firebase codebase: no Odoo, no Stripe, no other SPHOT functions.
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {onRequest} = require("firebase-functions/v2/https");

const app = initializeApp();
const firestore = Object.assign(() => getFirestore(app), {FieldValue});
const admin = {auth: () => getAuth(app), firestore};

// Allows protected browsing, draft changes and approval of editorial drafts.
// A separate future release is required to unlock publishing here.
exports.manageSphotLegalDocumentEditing =
  require("./legal_document_editor").register({admin, onRequest});

// NEW: initial group of five legal texts, 54 articles. Only status is enabled.
// To permit human validation/publication later, BOTH code and release checks
// must be reviewed again. No automatic publish on deploy.
exports.manageSphotInitialLegalPack =
  require("./legal_pack_gateway").register({admin, onRequest,
    reviewEnabled: true, publishEnabled: true});

// Les comptes ADMIN et PUBLICITAIRE acceptent à nouveau uniquement
// leurs CGU lorsque la révision correspondante est publiée.
exports.acceptSphotProfessionalLegal =
  require("./professional_legal_acceptance").register({admin, onRequest});
