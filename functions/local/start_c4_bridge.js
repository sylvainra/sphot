"use strict";
/* eslint-disable require-jsdoc */

// Le lancement C4 exige des identifiants liés au PROJET DE TEST, jamais ceux
// de SPHOT production. L'ADC de gcloud suffit pour les tests locaux.
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const {spawn} = require("node:child_process");
const {TEST_PROJECT_ID} = require("./odoo_c4_test_firestore");

// Authentification locale Google Cloud CLI : aucun fichier de clé de
// compte de service ne doit être créé pour cette étape de test.
function readC4Credentials() {
  const explicit = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const localAdc = process.platform === "win32" ?
    path.join(process.env.APPDATA ||
      path.join(os.homedir(), "AppData", "Roaming"),
    "gcloud", "application_default_credentials.json") :
    path.join(os.homedir(), ".config", "gcloud",
        "application_default_credentials.json");
  const credentialPath = explicit || localAdc;
  let credential;
  try {
    credential = JSON.parse(fs.readFileSync(credentialPath, "utf8"));
  } catch (_) {
    throw new Error("Identifiants C4 TEST introuvables. Exécutez " +
      "gcloud auth application-default login, puis définissez " +
      "le quota sur le projet C4 TEST.");
  }
  const serviceAccount = explicit && credential.type === "service_account" &&
      credential.project_id === TEST_PROJECT_ID;
  const localUser = !explicit && credential.type === "authorized_user" &&
      credential.quota_project_id === TEST_PROJECT_ID;
  if (!serviceAccount && !localUser) {
    throw new Error("Identifiants refusés : projet Firebase C4 TEST requis.");
  }
}

function main() {
  if (!process.env.SPHOT_ODOO_LOCAL_API_KEY) {
    throw new Error("Clé Odoo absente dans ce terminal PowerShell.");
  }
  readC4Credentials();
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("Fermez la configuration émulateur avant C4 CLOUD TEST.");
  }
  const env = {...process.env,
    GCLOUD_PROJECT: TEST_PROJECT_ID,
    GOOGLE_CLOUD_PROJECT: TEST_PROJECT_ID,
    SPHOT_C4_PROJECT_ID: TEST_PROJECT_ID,
    SPHOT_C4_TEST_CLOUD_WRITES: "true",
    SPHOT_ODOO_SECURE_CHECKOUT_TEST: "true",
    SPHOT_ODOO_TO_C4_TEST_FIRESTORE: "true",
    SPHOT_ODOO_TO_FIRESTORE_EMULATOR: "false",
  };
  const script = path.join(__dirname, "odoo_community_bridge_server.js");
  const child = spawn(process.execPath, [script],
      {env, stdio: "inherit", windowsHide: false});
  child.once("error", (error) => {
    console.error("C4 : démarrage refusé :", error.message);
    process.exitCode = 1;
  });
  child.once("exit", (code) => {
    process.exitCode = code === null ? 1 : code;
  });
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error("C4 :", error.message);
    process.exitCode = 1;
  }
}

module.exports = {main, readC4Credentials};
