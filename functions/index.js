const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const {getDownloadURL} = require("firebase-admin/storage");
const nodemailer = require("nodemailer");
const PDFDocument = require("pdfkit");

admin.initializeApp();

const SMTP_USER = "admin@sphot.app";
const MAIL_FROM = "\"SPHOT\" <no-reply@sphot.app>";
const SPHOT_LOGIN_URL = "https://sphot.app";


setGlobalOptions({maxInstances: 10});

/**
 * Nettoie une valeur texte et applique une valeur par défaut.
 *
 * @param {*} value Valeur à nettoyer.
 * @param {string} fallback Valeur utilisée lorsque le texte est vide.
 * @return {string} Valeur nettoyée.
 */
function cleanValue(value, fallback = "Non renseigné") {
  const result = (value || "").toString().trim();
  return result || fallback;
}

/**
 * Formate une date selon le format français.
 *
 * @param {Date} date Date à formater.
 * @return {string} Date et heure formatées.
 */
function formatFrenchDate(date) {
  return new Intl.DateTimeFormat("fr-FR", {
    timeZone: "Europe/Paris",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

/**
 * Génère un numéro unique de demande administrateur SPHOT.
 *
 * @param {string} uid Identifiant de la demande ou de l'utilisateur.
 * @param {Date} date Date de création de la demande.
 * @return {string} Numéro de demande SPHOT.
 */
/**
 * Attribue un numéro séquentiel unique à une demande administrateur.
 *
 * Le numéro est généré une seule fois, même en cas de nouvelle exécution
 * de la fonction Cloud.
 *
 * @param {FirebaseFirestore.DocumentReference} requestReference
 * Référence Firestore de la demande.
 * @param {Date} date Date de création de la demande.
 * @return {Promise<string>} Numéro administratif de la demande.
 */
/**
 * Attribue un numéro séquentiel unique à une demande administrateur.
 *
 * @param {FirebaseFirestore.DocumentReference} requestReference
 * Référence Firestore de la demande.
 * @param {Date} date Date de création de la demande.
 * @return {Promise<string>} Numéro administratif de la demande.
 */
async function assignAdminRequestNumber(requestReference, date) {
  const db = admin.firestore();

  const year = Number(
      new Intl.DateTimeFormat("fr-FR", {
        timeZone: "Europe/Paris",
        year: "numeric",
      }).format(date),
  );

  const counterReference = db
      .collection("counters")
      .doc(`adminRequests_${year}`);

  return db.runTransaction(async (transaction) => {
    const requestSnapshot =
        await transaction.get(requestReference);

    const requestData = requestSnapshot.data() || {};

    const existingRequestNumber =
        (requestData.requestNumber || "").toString().trim();

    if (existingRequestNumber) {
      return existingRequestNumber;
    }

    const counterSnapshot =
        await transaction.get(counterReference);

    const counterData = counterSnapshot.data() || {};

    const currentNumber =
        Number(counterData.lastNumber || 0);

    const nextNumber = currentNumber + 1;

    const requestNumber =
        `SPHOT-ADM-${year}-${nextNumber
            .toString()
            .padStart(6, "0")}`;

    transaction.set(
        counterReference,
        {
          year: year,
          lastNumber: nextNumber,
          updatedAt:
              admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
    );

    transaction.set(
        requestReference,
        {
          requestNumber: requestNumber,
          requestSequence: nextNumber,
          requestYear: year,
          updatedAt:
              admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
    );

    return requestNumber;
  });
}

/**
 * Génère le PDF d'accusé de réception d'une demande administrateur.
 *
 * @param {Object} params Paramètres nécessaires à la génération du PDF.
 * @param {string} params.requestNumber Numéro de la demande.
 * @param {Date} params.createdAt Date de création de la demande.
 * @param {Object} params.profile Profil SPHOT du demandeur.
 * @param {Object} params.proConnect Identité transmise par ProConnect.
 * @param {Object} params.structure Informations concernant la structure.
 * @param {Object} params.territoire Informations concernant le territoire.
 * @param {Object} params.trialRequest Informations concernant l'essai.
 * @param {Object} params.subscriptionPreview Informations commerciales.
 * @return {Promise<Buffer>} Contenu du document PDF.
 */
/**
 * Génère le PDF d'accusé de réception d'une demande administrateur.
 *
 * @param {Object} params Paramètres nécessaires à la génération du PDF.
 * @param {string} params.requestNumber Numéro de la demande.
 * @param {Date} params.createdAt Date de création de la demande.
 * @param {Object} params.profile Profil SPHOT du demandeur.
 * @param {Object} params.proConnect Identité transmise par ProConnect.
 * @param {Object} params.structure Informations concernant la structure.
 * @param {Object} params.territoire Informations concernant le territoire.
 * @param {Object} params.trialRequest Informations concernant l'essai.
 * @return {Promise<Buffer>} Contenu du document PDF.
 */
function createAdminRequestPdf({
  requestNumber,
  createdAt,
  profile,
  proConnect,
  structure,
  territoire,
  trialRequest,
}) {
  return new Promise((resolve, reject) => {
    try {
      const doc = new PDFDocument({
        size: "A4",
        margins: {
          top: 34,
          bottom: 34,
          left: 42,
          right: 42,
        },
        info: {
          Title: "Accusé de réception d'une demande d'accès SPHOT",
          Author: "SPHOT",
          Subject: requestNumber,
        },
      });

      const chunks = [];

      doc.on("data", (chunk) => chunks.push(chunk));

      doc.on("end", () => {
        resolve(Buffer.concat(chunks));
      });

      doc.on("error", reject);

      const blue = "#1E3A8A";
      const red = "#DC2626";
      const dark = "#263238";
      const grey = "#607D8B";
      const lightBlue = "#F3F6FB";

      const contentWidth =
          doc.page.width -
          doc.page.margins.left -
          doc.page.margins.right;

      /**
       * Affiche un titre de section compact.
       *
       * @param {string} title Titre à afficher.
       */
      const sectionTitle = (title) => {
  const left = doc.page.margins.left;
  const iconSize = 18;
  const titleY = doc.y + 8;
  const titleX = left + iconSize + 10;

  doc
      .circle(
          left + (iconSize / 2),
          titleY + (iconSize / 2),
          iconSize / 2,
      )
      .lineWidth(1)
      .strokeColor(red)
      .stroke();

  doc
      .font("Helvetica-Bold")
      .fontSize(9)
      .fillColor(red)
      .text(
          "S",
          left,
          titleY + 1,
          {
            width: iconSize,
            align: "center",
          },
      );

  doc
      .font("Helvetica-Bold")
      .fontSize(10)
      .fillColor(red)
      .text(
          title.toUpperCase(),
          titleX,
          titleY + 1,
          {
            width: contentWidth - iconSize - 10,
            align: "left",
          },
      );

  const lineY = titleY + iconSize + 4;

  doc
      .strokeColor(blue)
      .lineWidth(0.8)
      .moveTo(titleX, lineY)
      .lineTo(
          doc.page.width - doc.page.margins.right,
          lineY,
      )
      .stroke();

  doc.x = left;
  doc.y = lineY + 8;
};

      /**
       * Affiche une ligne d'information compacte.
       *
       * @param {string} label Libellé du champ.
       * @param {*} value Valeur du champ.
       */
      const informationLine = (label, value) => {
        const labelWidth = 105;
        const startY = doc.y;
        const startX = doc.page.margins.left + 12;

        doc
            .font("Helvetica-Bold")
            .fontSize(8.2)
            .fillColor(blue)
            .text(
                `${label}`,
                startX,
                startY,
                {
                  width: labelWidth,
                  align: "left",
                },
            );

        doc
            .font("Helvetica")
            .fontSize(8.6)
            .fillColor(dark)
            .text(
                cleanValue(value),
                startX + labelWidth + 4,
                startY,
                {
                  width: contentWidth - labelWidth - 8,
                  align: "left",
                },
            );

        doc.y = startY + 13;
      };

      doc
          .font("Helvetica-Bold")
          .fontSize(26)
          .fillColor(red)
          .text("SPHOT", {
            align: "center",
          });

      doc
          .moveDown(0.08)
          .font("Helvetica-Bold")
          .fontSize(12)
          .fillColor(blue)
          .text(
              "ACCUSÉ DE RÉCEPTION D'UNE DEMANDE D'ACCÈS " +
              "ADMINISTRATEUR",
              {
                align: "center",
                lineGap: 0,
              },
          );

      doc.moveDown(0.35);

      const summaryTop = doc.y;

      doc
          .roundedRect(
              doc.page.margins.left,
              summaryTop,
              contentWidth,
              82,
              10,
          )
          .fillAndStroke(lightBlue, blue);

      doc
          .font("Helvetica-Bold")
          .fontSize(7.8)
          .fillColor(blue)
          .text(
              "NUMÉRO DE DEMANDE",
              doc.page.margins.left + 13,
              summaryTop + 18,
          );

      doc
          .font("Helvetica-Bold")
          .fontSize(12)
          .fillColor(red)
          .text(
              requestNumber,
              doc.page.margins.left + 13,
              summaryTop + 42,
          );

      doc
          .font("Helvetica")
          .fontSize(6.8)
          .fillColor(grey)
          .text(
              `Demande transmise le ${formatFrenchDate(createdAt)}`,
              doc.page.margins.left + 13,
              summaryTop + 69,
          );

      doc.y = summaryTop + 100;

      doc
    .font("Helvetica")
    .fontSize(8.5)
    .fillColor(blue)
    .text(
        "Votre demande d'accès au portail d'administration SPHOT " +
        "a bien été enregistrée.",
        {
          align: "center",
          lineGap: 0,
        },
    );

      sectionTitle("Demandeur");

      informationLine("Nom", profile.nomAffiche);
      informationLine("Prénom", profile.prenomAffiche);
      informationLine("Fonction", profile.fonction);
      informationLine("Email", profile.email);
      informationLine("Téléphone", profile.telephone);

      sectionTitle("Identité transmise par ProConnect");

      informationLine("Nom", proConnect.nom);
      informationLine("Prénom", proConnect.prenom);
      informationLine("Email", proConnect.email);
      informationLine("Organisation", proConnect.organisation);
      informationLine("SIRET", proConnect.siret);
      informationLine("SIREN", proConnect.siren);

      sectionTitle("Structure");

      informationLine("Nom", structure.nom);
      informationLine("Type", structure.type);
      informationLine("SIRET", structure.siret);
      informationLine("SIREN", structure.siren);

      sectionTitle("Territoire");

      informationLine("Pays", territoire.pays);
      informationLine("Région", territoire.region);
      informationLine("Département", territoire.departement);
      informationLine("Ville", territoire.ville);

      sectionTitle("Votre essai SPHOT");

      doc
          .font("Helvetica-Bold")
          .fontSize(9.6)
          .fillColor(red)
          .text(
              "Essai gratuit, sans engagement ni facturation.",
              {
                lineGap: 0,
              },
          );

      doc
          .moveDown(0.08)
          .font("Helvetica")
          .fontSize(8.1)
          .fillColor(blue)
          .text(
              "Après validation de votre demande par l'équipe SPHOT, " +
              "vous pourrez accéder au portail d'administration SPHOT " +
              "afin de créer vos SPHOTS, vos sauveteurs et vos périodes " +
              "de surveillance.",
              {
                lineGap: 1,
              },
          );

      doc
          .moveDown(0.12)
          .text(
              "Vous recevrez prochainement, par courrier électronique, " +
              "une réponse vous informant de la décision prise concernant " +
              "votre demande.",
              {
                lineGap: 1,
              },
          );

      doc
          .moveDown(0.12)
          .text(
              "La période d'essai gratuite de 8 jours débutera uniquement " +
              "lorsque votre configuration sera complète et que l'essai " +
              "aura été activé.",
              {
                lineGap: 1,
              },
          );

      sectionTitle("Conditions acceptées");

      const acceptedDocuments =
          trialRequest.acceptedDocuments || {};

      informationLine(
          "Habilitation à représenter la structure",
          trialRequest.certifyRepresentative === true ?
            "Oui" :
            "Non",
      );

      informationLine(
          "Conditions Générales d'Utilisation",
          acceptedDocuments.cgu === true ?
            "Acceptées" :
            "Non acceptées",
      );

      informationLine(
          "Politique de confidentialité",
          acceptedDocuments.privacy === true ?
            "Acceptée" :
            "Non acceptée",
      );

      informationLine(
          "Traitement des données personnelles",
          acceptedDocuments.rgpd === true ?
            "Accepté" :
            "Non accepté",
      );

      informationLine(
          "Version des documents",
          acceptedDocuments.version,
      );

      sectionTitle("Information importante");

      doc
          .font("Helvetica")
          .fontSize(8)
          .fillColor(blue)
          .text(
              "Ce document confirme uniquement la bonne réception et " +
              "l'enregistrement de votre demande d'accès au portail " +
              "d'administration SPHOT.",
              {
                lineGap: 1,
              },
          );

      doc
          .moveDown(0.05)
          .text(
              "Il ne vaut ni acceptation, ni refus de votre demande et " +
              "ne confère, à ce stade, aucun droit d'accès au portail.",
              {
                lineGap: 1,
              },
          );

      doc
          .moveDown(0.05)
          .text(
              "La période d'essai gratuite n'est pas encore ouverte et " +
              "aucune facturation ne peut intervenir avant la validation " +
              "de votre demande et l'activation effective de votre essai.",
              {
                lineGap: 1,
              },
          );

      doc
          .moveDown(0.70)
          .font("Helvetica")
          .fontSize(6.8)
          .fillColor(grey)
          .text(
              `Document généré automatiquement par SPHOT — ${requestNumber}`,
              {
                align: "center",
                lineGap: 0,
              },
          );

      doc.end();
    } catch (error) {
      reject(error);
    }
  });
}

exports.generateAdminRequestAcknowledgement = onDocumentCreated(
    {
      document: "adminRequests/{requestId}",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "512MiB",
    },
    async (event) => {
      const requestSnapshot = event.data;

      if (!requestSnapshot) {
        console.error("Document adminRequests introuvable.");
        return;
      }

      const requestReference = requestSnapshot.ref;
      const data = requestSnapshot.data() || {};
      const requestId = event.params.requestId;

      const existingDocument = data.acknowledgementDocument || {};

      if (
        existingDocument.status === "generated" ||
        existingDocument.status === "sent"
      ) {
        console.log(
            "Accusé de réception déjà généré pour:",
            requestId,
        );
        return;
      }

      const profile = data.profile || {};
      const proConnect = data.proConnect || {};
      const structure = data.structure || {};
      const territoire = data.territoire || {};
      const trialRequest = data.trialRequest || {};
      const subscriptionPreview = data.subscriptionPreview || {};

      const recipientEmail = cleanValue(
          profile.email || proConnect.email,
          "",
      );

      if (!recipientEmail) {
        await requestReference.set(
            {
              acknowledgementDocument: {
                status: "failed",
                error: "Adresse email du demandeur absente.",
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },
              acknowledgementEmail: {
                status: "failed",
                error: "Adresse email du demandeur absente.",
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },
            },
            {merge: true},
        );

        console.error(
            "Adresse email absente pour la demande:",
            requestId,
        );

        return;
      }

      const createdAt =
          data.requestedAt &&
          typeof data.requestedAt.toDate === "function" ?
            data.requestedAt.toDate() :
            new Date();

      const requestNumber =
    data.requestNumber ||
    await assignAdminRequestNumber(
        requestReference,
        createdAt,
    );

      const fileName =
          `SPHOT_Accuse_Reception_${requestNumber}.pdf`;

      const storagePath =
          `adminRequests/${requestId}/documents/${fileName}`;

      await requestReference.set(
          {
            requestNumber: requestNumber,

            acknowledgementDocument: {
              status: "generating",
              documentType: "admin_request_acknowledgement",
              fileName: fileName,
              storagePath: storagePath,
              version: "1.0",
              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },

            acknowledgementEmail: {
              status: "pending",
              recipient: recipientEmail,
              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
          },
          {merge: true},
      );

      try {
        const pdfBuffer = await createAdminRequestPdf({
          requestNumber: requestNumber,
          createdAt: createdAt,
          profile: profile,
          proConnect: proConnect,
          structure: structure,
          territoire: territoire,
          trialRequest: trialRequest,
          subscriptionPreview: subscriptionPreview,
        });

        const bucket = admin.storage().bucket();
        const file = bucket.file(storagePath);

        await file.save(pdfBuffer, {
          contentType: "application/pdf",
          resumable: false,
          metadata: {
            contentDisposition:
                `attachment; filename="${fileName}"`,
            metadata: {
              requestId: requestId,
              requestNumber: requestNumber,
              documentType: "admin_request_acknowledgement",
            },
          },
        });

        const downloadUrl = await getDownloadURL(file);

        const firstName = cleanValue(
            profile.prenomAffiche || proConnect.prenom,
            "",
        );

        const organisation = cleanValue(
            structure.nom || proConnect.organisation,
            "votre structure",
        );

        const transporter = nodemailer.createTransport({
          service: "gmail",
          auth: {
            user: SMTP_USER,
            pass: process.env.GMAIL_APP_PASSWORD,
          },
        });

        const mailResult = await transporter.sendMail({
          from: MAIL_FROM,
          to: recipientEmail,
          subject:
              "SPHOT – Confirmation de votre demande d'accès administrateur",

          html: `
<div style="
  margin:0;
  padding:40px 20px;
  background:#eef3f8;
  font-family:Arial,Helvetica,sans-serif;
">
  <div style="
    max-width:620px;
    margin:auto;
    background:#ffffff;
    border-radius:18px;
    overflow:hidden;
    border:1px solid #d9e2ec;
    box-shadow:0 4px 12px rgba(0,0,0,.08);
  ">
    <div style="padding:30px 30px 18px;text-align:center;">
      <a href="${SPHOT_LOGIN_URL}">
        <img
          src="https://sphot.app/assets/data/icons/title.png"
          alt="SPHOT"
          style="max-width:320px;width:100%;height:auto;border:0;"
        >
      </a>
    </div>

    <div style="
      padding:0 34px 34px;
      color:#263238;
      font-size:16px;
      line-height:1.6;
    ">
      <p>
        Bonjour${firstName ? ` <strong>${firstName}</strong>` : ""},
      </p>

      <p>
        Votre demande d'accès au portail d'administration SPHOT
        pour <strong>${organisation}</strong> a bien été enregistrée.
      </p>

      <div style="
        margin:26px 0;
        padding:20px;
        background:#f3f6fb;
        border:1px solid #1e3a8a;
        border-radius:14px;
      ">
        <div style="
          color:#607d8b;
          font-size:12px;
          font-weight:bold;
          text-transform:uppercase;
        ">
          Numéro de demande
        </div>

        <div style="
          margin-top:5px;
          color:#dc2626;
          font-size:21px;
          font-weight:bold;
        ">
          ${requestNumber}
        </div>
      </div>

      <p style="
        color:#dc2626;
        font-size:18px;
        font-weight:bold;
      ">
        Essai gratuit, sans engagement ni facturation.
      </p>

      <p>
        Après validation de votre demande par l'équipe SPHOT,
vous pourrez accéder au portail d'administration SPHOT
afin de créer vos SPHOTS, vos sauveteurs et vos périodes
de surveillance.

Vous recevrez prochainement, par courrier électronique,
une réponse vous informant de la décision prise concernant
votre demande.
      </p>

      <p>
        La période d'essai gratuite de 8 jours débutera uniquement
lorsque votre configuration sera complète et que l'essai
aura été activé.
      </p>

      <p>
        Votre accusé de réception est joint à ce message.
      </p>

      <p style="
        margin-top:28px;
        padding:16px;
        background:#fff8e1;
        border-left:5px solid #ff9800;
        border-radius:8px;
      ">
        Ce message confirme l'enregistrement de votre demande.
        Aucun essai ni aucune facturation ne sont en cours à ce stade.
      </p>

      <p style="margin-top:34px;">
        À bientôt sur SPHOT,<br>
        <strong>L'équipe SPHOT</strong>
      </p>
    </div>
  </div>
</div>
`,

          text:
`Bonjour${firstName ? ` ${firstName}` : ""},

Votre demande d'accès au portail d'administration SPHOT
pour ${organisation} a bien été enregistrée.

Numéro de demande : ${requestNumber}

Essai gratuit, sans engagement ni facturation.

Après validation de votre demande, vous pourrez accéder au portail
afin de créer vos SPHOTS, vos sauveteurs et vos périodes de surveillance.

La période d'essai de 8 jours ne commencera qu'une fois
ces informations renseignées et l'essai activé.

Votre accusé de réception est joint à ce message.

Ce message confirme l'enregistrement de votre demande.
Aucun essai ni aucune facturation ne sont en cours à ce stade.

À bientôt sur SPHOT,

L'équipe SPHOT`,

          attachments: [
            {
              filename: fileName,
              content: pdfBuffer,
              contentType: "application/pdf",
            },
          ],
        });

        await requestReference.set(
            {
              requestNumber: requestNumber,

              acknowledgementDocument: {
                status: "generated",
                documentType: "admin_request_acknowledgement",
                fileName: fileName,
                storagePath: storagePath,
                downloadUrl: downloadUrl,
                version: "1.0",
                generatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                generatedBy: "system",
              },

              acknowledgementEmail: {
                status: "sent",
                recipient: recipientEmail,
                messageId: mailResult.messageId || null,
                sentAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                error: null,
              },

              lastEvent: {
                type: "request_acknowledgement_sent",
                category: "administrative",
                label:
                    "Accusé de réception généré et envoyé",
                createdAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                createdByRole: "system",
              },

              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        console.log(
            "Accusé de réception généré et envoyé:",
            requestNumber,
            recipientEmail,
        );
      } catch (error) {
        console.error(
            "Erreur génération ou envoi accusé de réception:",
            error,
        );

        await requestReference.set(
            {
              acknowledgementDocument: {
                status: "failed",
                error: error.message || error.toString(),
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },

              acknowledgementEmail: {
                status: "failed",
                recipient: recipientEmail,
                error: error.message || error.toString(),
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },

              lastEvent: {
                type: "request_acknowledgement_failed",
                category: "administrative",
                label:
                    "Échec de génération ou d'envoi de l'accusé de réception",
                createdAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                createdByRole: "system",
              },

              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );
      }
    },
);

/**
 * Envoie le mail d'acceptation d'une demande administrateur SPHOT.
 *
 * Le mail est envoyé une seule fois lorsque approvalEmail.status
 * passe à "pending" sur une demande approuvée.
 */
exports.sendAdminRequestApprovalEmail = onDocumentUpdated(
    {
      document: "adminRequests/{requestId}",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const beforeSnapshot = event.data.before;
      const afterSnapshot = event.data.after;

      if (!afterSnapshot.exists) {
        return;
      }

      const beforeData = beforeSnapshot.data() || {};
      const afterData = afterSnapshot.data() || {};

      const beforeApprovalEmail =
          beforeData.approvalEmail || {};

      const afterApprovalEmail =
          afterData.approvalEmail || {};

      const requestStatus =
          cleanValue(afterData.status, "").toLowerCase();

      const previousEmailStatus =
          cleanValue(beforeApprovalEmail.status, "").toLowerCase();

      const currentEmailStatus =
          cleanValue(afterApprovalEmail.status, "").toLowerCase();

      if (requestStatus !== "approved") {
        return;
      }

      if (currentEmailStatus !== "pending") {
        return;
      }

      if (previousEmailStatus === "sending" ||
          previousEmailStatus === "sent") {
        return;
      }

      const requestReference = afterSnapshot.ref;

      const email = cleanValue(
          afterApprovalEmail.recipient ||
          (afterData.profile && afterData.profile.email) ||
          (afterData.proConnect && afterData.proConnect.email),
          "",
      );

      if (!email) {
        await requestReference.set(
            {
              approvalEmail: {
                ...afterApprovalEmail,
                status: "failed",
                sentAt: null,
                messageId: null,
                error: "Adresse email du demandeur absente.",
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },
            },
            {merge: true},
        );

        return;
      }

      const transactionResult =
          await admin.firestore().runTransaction(
              async (transaction) => {
                const freshSnapshot =
                    await transaction.get(requestReference);

                const freshData =
                    freshSnapshot.data() || {};

                const freshApprovalEmail =
                    freshData.approvalEmail || {};

                const freshStatus = cleanValue(
                    freshApprovalEmail.status,
                    "",
                ).toLowerCase();

                if (freshStatus !== "pending") {
                  return false;
                }

                transaction.set(
                    requestReference,
                    {
                      approvalEmail: {
                        ...freshApprovalEmail,
                        status: "sending",
                        sentAt: null,
                        messageId: null,
                        error: null,
                        updatedAt:
                            admin.firestore.FieldValue
                                .serverTimestamp(),
                      },
                    },
                    {merge: true},
                );

                return true;
              },
          );

      if (!transactionResult) {
        return;
      }

      const profile =
          afterData.profile || {};

      const structure =
          afterData.structure || {};

      const territoire =
          afterData.territoire || {};

      const firstName = cleanValue(
          profile.prenomAffiche ||
          afterData.prenomResponsable ||
          (afterData.proConnect && afterData.proConnect.prenom),
          "",
      );

      const organisation = cleanValue(
          structure.nom ||
          afterData.organisation ||
          (afterData.proConnect && afterData.proConnect.organisation),
          "votre structure",
      );

      const city = cleanValue(
          territoire.ville,
          "",
      );

      const requestNumber = cleanValue(
          afterData.requestNumber ||
          event.params.requestId,
          event.params.requestId,
      );

      const dashboardUrl = SPHOT_LOGIN_URL;

      const greeting = firstName ?
        `Bonjour ${firstName},` :
        "Bonjour,";

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: SMTP_USER,
          pass: process.env.GMAIL_APP_PASSWORD,
        },
      });

      try {
        const mailResult = await transporter.sendMail({
          from: MAIL_FROM,
          to: email,
          subject:
              "Votre demande d'accès administrateur SPHOT est acceptée",
          text:
`${greeting}

Votre demande d'accès au portail d'administration SPHOT
pour ${organisation} a été acceptée.

Référence administrative : ${requestNumber}

Vous pouvez désormais accéder à votre tableau de bord afin de
renseigner vos SPHOTS, vos sauveteurs et vos périodes de surveillance.

Accéder à mon tableau de bord :
${dashboardUrl}

Essai gratuit, sans engagement ni facturation.

La période d'essai de 8 jours ne commencera qu'une fois la
configuration complète et l'essai activé.

${city ? `Territoire : ${city}\n\n` : ""}À bientôt sur SPHOT,
L'équipe SPHOT`,

          html: `
<div style="
  margin:0;
  padding:40px 20px;
  background:#eef3f8;
  font-family:Arial,Helvetica,sans-serif;
  color:#172033;
">
  <div style="
    max-width:640px;
    margin:0 auto;
    background:#ffffff;
    border-radius:18px;
    padding:34px;
    box-shadow:0 8px 26px rgba(30,58,138,0.12);
  ">
    <div style="
      text-align:center;
      color:#1e3a8a;
      font-size:32px;
      font-weight:900;
      letter-spacing:8px;
      margin-bottom:28px;
    ">
      SPHOT
    </div>

    <p style="font-size:16px;line-height:1.6;">
      ${greeting}
    </p>

    <p style="font-size:16px;line-height:1.6;">
      Votre demande d'accès au portail d'administration SPHOT
      pour <strong>${organisation}</strong> a été acceptée.
    </p>

    <div style="
      margin:24px 0;
      padding:16px 18px;
      border:1.5px solid #1e3a8a;
      border-radius:14px;
      background:#f5f7fc;
    ">
      <div style="
        color:#60758a;
        font-size:12px;
        font-weight:700;
        text-transform:uppercase;
      ">
        Référence administrative
      </div>

      <div style="
        margin-top:7px;
        color:#dc2626;
        font-size:19px;
        font-weight:900;
      ">
        ${requestNumber}
      </div>
    </div>

    <p style="font-size:16px;line-height:1.6;">
      Vous pouvez désormais accéder à votre tableau de bord afin
      de renseigner vos SPHOTS, vos sauveteurs et vos périodes
      de surveillance.
    </p>

    <div style="text-align:center;margin:30px 0;">
      <a
        href="${dashboardUrl}"
        style="
          display:inline-block;
          padding:15px 28px;
          border-radius:14px;
          background:#1e3a8a;
          color:#ffffff;
          text-decoration:none;
          font-size:16px;
          font-weight:900;
        "
      >
        ACCÉDER À MON TABLEAU DE BORD
      </a>
    </div>

    <p style="
      color:#dc2626;
      font-size:16px;
      line-height:1.6;
      font-weight:900;
    ">
      Essai gratuit, sans engagement ni facturation.
    </p>

    <div style="
      margin-top:20px;
      padding:16px;
      border-left:4px solid #f59e0b;
      border-radius:8px;
      background:#fff7df;
      font-size:14px;
      line-height:1.6;
    ">
      La période d'essai de 8 jours ne commencera qu'une fois
      vos SPHOTS, vos sauveteurs et vos périodes de surveillance
      renseignés, puis l'essai activé.
    </div>

    ${city ? `
      <p style="margin-top:20px;font-size:14px;">
        <strong>Territoire :</strong> ${city}
      </p>
    ` : ""}

    <p style="margin-top:28px;font-size:15px;line-height:1.6;">
      À bientôt sur SPHOT,<br>
      <strong>L'équipe SPHOT</strong>
    </p>
  </div>
</div>
`,
        });

        await requestReference.set(
            {
              approvalEmail: {
                ...afterApprovalEmail,
                status: "sent",
                recipient: email,
                sentAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                messageId: mailResult.messageId || null,
                error: null,
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },

              lastEvent: {
                type: "admin_approval_email_sent",
                category: "administrative",
                label:
                    "Email d'acceptation envoyé au demandeur",
                createdAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                createdByRole: "system",
                createdByUid: null,
              },

              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        console.log(
            "Email d'acceptation administrateur envoyé :",
            email,
            requestNumber,
        );
      } catch (error) {
        console.error(
            "Erreur envoi email acceptation administrateur :",
            error,
        );

        await requestReference.set(
            {
              approvalEmail: {
                ...afterApprovalEmail,
                status: "failed",
                recipient: email,
                sentAt: null,
                messageId: null,
                error: error.message || error.toString(),
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },

              lastEvent: {
                type: "admin_approval_email_failed",
                category: "administrative",
                label:
                    "Échec de l'envoi de l'email d'acceptation",
                createdAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                createdByRole: "system",
                createdByUid: null,
              },

              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        throw error;
      }
    },
);

/**
 * Envoie le mail de refus d'une demande administrateur SPHOT.
 *
 * Le mail contient le motif du refus et un lien permettant
 * au demandeur de corriger la demande existante.
 */
exports.sendAdminRequestRejectionEmail = onDocumentUpdated(
    {
      document: "adminRequests/{requestId}",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const beforeSnapshot = event.data.before;
      const afterSnapshot = event.data.after;

      if (!afterSnapshot.exists) {
        return;
      }

      const beforeData = beforeSnapshot.data() || {};
      const afterData = afterSnapshot.data() || {};

      const beforeRejectionEmail =
          beforeData.rejectionEmail || {};

      const afterRejectionEmail =
          afterData.rejectionEmail || {};

      const requestStatus = cleanValue(
          afterData.status,
          "",
      ).toLowerCase();

      const previousEmailStatus = cleanValue(
          beforeRejectionEmail.status,
          "",
      ).toLowerCase();

      const currentEmailStatus = cleanValue(
          afterRejectionEmail.status,
          "",
      ).toLowerCase();

      if (requestStatus !== "rejected") {
        return;
      }

      if (currentEmailStatus !== "pending") {
        return;
      }

      if (previousEmailStatus === "sending" ||
          previousEmailStatus === "sent") {
        return;
      }

      const requestReference = afterSnapshot.ref;

      const email = cleanValue(
          afterRejectionEmail.recipient ||
          (afterData.profile && afterData.profile.email) ||
          (afterData.proConnect && afterData.proConnect.email),
          "",
      );

      if (!email) {
        await requestReference.set(
            {
              rejectionEmail: {
                ...afterRejectionEmail,
                status: "failed",
                sentAt: null,
                messageId: null,
                error: "Adresse email du demandeur absente.",
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },
            },
            {merge: true},
        );

        return;
      }

      const transactionStarted =
          await admin.firestore().runTransaction(
              async (transaction) => {
                const freshSnapshot =
                    await transaction.get(requestReference);

                const freshData =
                    freshSnapshot.data() || {};

                const freshRejectionEmail =
                    freshData.rejectionEmail || {};

                const freshStatus = cleanValue(
                    freshRejectionEmail.status,
                    "",
                ).toLowerCase();

                if (freshStatus !== "pending") {
                  return false;
                }

                transaction.set(
                    requestReference,
                    {
                      rejectionEmail: {
                        ...freshRejectionEmail,
                        status: "sending",
                        sentAt: null,
                        messageId: null,
                        error: null,
                        updatedAt:
                            admin.firestore.FieldValue
                                .serverTimestamp(),
                      },
                    },
                    {merge: true},
                );

                return true;
              },
          );

      if (!transactionStarted) {
        return;
      }

      const profile = afterData.profile || {};
      const structure = afterData.structure || {};
      const administrativeTracking =
          afterData.administrativeTracking || {};

      const firstName = cleanValue(
          profile.prenomAffiche ||
          afterData.prenomResponsable ||
          (afterData.proConnect &&
           afterData.proConnect.prenom),
          "",
      );

      const organisation = cleanValue(
          structure.nom ||
          afterData.organisation ||
          (afterData.proConnect &&
           afterData.proConnect.organisation),
          "votre structure",
      );

      const requestNumber = cleanValue(
          afterData.requestNumber ||
          event.params.requestId,
          event.params.requestId,
      );

      const rejectionReason = cleanValue(
          administrativeTracking.rejectionReason,
          "Des informations doivent être corrigées.",
      );

      const correctionUrl =
          `${SPHOT_LOGIN_URL}/#/admin-request-correction` +
          `?requestId=${encodeURIComponent(event.params.requestId)}`;

      const greeting = firstName ?
        `Bonjour ${firstName},` :
        "Bonjour,";

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: SMTP_USER,
          pass: process.env.GMAIL_APP_PASSWORD,
        },
      });

      try {
        const mailResult = await transporter.sendMail({
          from: MAIL_FROM,
          to: email,
          subject:
              "Votre demande administrateur SPHOT doit être corrigée",

          text:
`${greeting}

Votre demande d'accès au portail d'administration SPHOT
pour ${organisation} ne peut pas être validée en l'état.

Référence administrative : ${requestNumber}

Motif :
${rejectionReason}

Vous ne devez pas créer une nouvelle demande.

Utilisez le lien suivant pour corriger les informations
de votre demande existante :

${correctionUrl}

Après validation de vos corrections, votre demande sera
automatiquement remise en attente d'instruction.

À bientôt sur SPHOT,

L'équipe SPHOT`,

          html: `
<div style="
  margin:0;
  padding:40px 20px;
  background:#eef3f8;
  font-family:Arial,Helvetica,sans-serif;
  color:#172033;
">
  <div style="
    max-width:640px;
    margin:0 auto;
    background:#ffffff;
    border-radius:18px;
    padding:34px;
    box-shadow:0 8px 26px rgba(30,58,138,0.12);
  ">
    <div style="
      text-align:center;
      color:#1e3a8a;
      font-size:32px;
      font-weight:900;
      letter-spacing:8px;
      margin-bottom:28px;
    ">
      SPHOT
    </div>

    <p style="font-size:16px;line-height:1.6;">
      ${greeting}
    </p>

    <p style="font-size:16px;line-height:1.6;">
      Votre demande d'accès au portail d'administration SPHOT
      pour <strong>${organisation}</strong> ne peut pas être
      validée en l'état.
    </p>

    <div style="
      margin:24px 0;
      padding:16px 18px;
      border:1.5px solid #1e3a8a;
      border-radius:14px;
      background:#f5f7fc;
    ">
      <div style="
        color:#60758a;
        font-size:12px;
        font-weight:700;
        text-transform:uppercase;
      ">
        Référence administrative
      </div>

      <div style="
        margin-top:7px;
        color:#dc2626;
        font-size:19px;
        font-weight:900;
      ">
        ${requestNumber}
      </div>
    </div>

    <div style="
      margin:24px 0;
      padding:18px;
      background:#fff1f1;
      border-left:5px solid #dc2626;
      border-radius:8px;
      font-size:15px;
      line-height:1.6;
    ">
      <strong>Motif :</strong><br><br>
      ${rejectionReason}
    </div>

    <p style="font-size:16px;line-height:1.6;">
      Vous ne devez pas créer une nouvelle demande.
      Les informations déjà renseignées seront conservées.
    </p>

    <div style="text-align:center;margin:30px 0;">
      <a
        href="${correctionUrl}"
        style="
          display:inline-block;
          padding:15px 28px;
          border-radius:14px;
          background:#1e3a8a;
          color:#ffffff;
          text-decoration:none;
          font-size:16px;
          font-weight:900;
        "
      >
        CORRIGER MA DEMANDE
      </a>
    </div>

    <p style="font-size:15px;line-height:1.6;">
      Après validation de vos corrections, votre demande sera
      automatiquement remise en attente d'instruction.
    </p>

    <p style="margin-top:28px;font-size:15px;line-height:1.6;">
      À bientôt sur SPHOT,<br>
      <strong>L'équipe SPHOT</strong>
    </p>
  </div>
</div>
`,
        });

        await requestReference.set(
            {
              rejectionEmail: {
                ...afterRejectionEmail,
                status: "sent",
                recipient: email,
                sentAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                messageId: mailResult.messageId || null,
                error: null,
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },

              lastEvent: {
                type: "admin_rejection_email_sent",
                category: "administrative",
                label:
                    "Email de refus envoyé au demandeur",
                createdAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                createdByRole: "system",
                createdByUid: null,
              },

              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        console.log(
            "Email de refus administrateur envoyé :",
            email,
            requestNumber,
        );
      } catch (error) {
        console.error(
            "Erreur envoi email refus administrateur :",
            error,
        );

        await requestReference.set(
            {
              rejectionEmail: {
                ...afterRejectionEmail,
                status: "failed",
                recipient: email,
                sentAt: null,
                messageId: null,
                error: error.message || error.toString(),
                updatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
              },

              lastEvent: {
                type: "admin_rejection_email_failed",
                category: "administrative",
                label:
                    "Échec de l'envoi de l'email de refus",
                createdAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                createdByRole: "system",
                createdByUid: null,
              },

              updatedAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        throw error;
      }
    },
);

exports.sendSubscriptionActivatedEmail = onDocumentUpdated(
    {
      document: "subscriptions/{subscriptionId}",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();

      if (before.status === "active") {
        return;
      }

      if (after.status !== "active") {
        return;
      }

      if (after.activationEmailSentAt) {
        return;
      }

      const email = after.billingContactEmail;

      if (!email) {
        console.log(
            "Email facturation absent, aucun email envoyé.",
        );
        return;
      }

      const organisation =
          after.billingOrganisation || "votre organisation";

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: SMTP_USER,
          pass: process.env.GMAIL_APP_PASSWORD,
        },
      });

      await transporter.sendMail({
        from: MAIL_FROM,
        to: email,
        subject: "Activation de votre abonnement SPHOT",
        text:
`Bonjour,

Votre abonnement SPHOT pour ${organisation} est maintenant actif.

Vous pouvez désormais utiliser les services associés
à votre espace administrateur.

Cordialement,
L'équipe SPHOT`,
      });

      await event.data.after.ref.set(
          {
            activationEmailSentAt:
                admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true},
      );

      console.log(
          "Email activation abonnement envoyé à:",
          email,
      );
    },
);

exports.updateSubscriptionStatuses = onSchedule(
    {
      schedule: "0 1 * * *",
      timeZone: "Europe/Paris",
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async () => {
      const db = admin.firestore();
      const now = admin.firestore.Timestamp.now();

      const trialSnapshot = await db
          .collection("subscriptions")
          .where("status", "==", "trial")
          .where("trialEndDate", "<", now)
          .get();

      const activeSnapshot = await db
          .collection("subscriptions")
          .where("status", "==", "active")
          .where("nextInvoiceDate", "<", now)
          .get();

      const batch = db.batch();

      trialSnapshot.docs.forEach((doc) => {
        batch.set(
            doc.ref,
            {
              status: "overdue",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );
      });

      activeSnapshot.docs.forEach((doc) => {
        batch.set(
            doc.ref,
            {
              status: "overdue",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );
      });

      await batch.commit();

      console.log(
          "Statuts abonnements mis à jour:",
          trialSnapshot.size + activeSnapshot.size,
      );
    },
);

exports.sendTrialEndingReminderEmails = onSchedule(
    {
      schedule: "0 9 * * *",
      timeZone: "Europe/Paris",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async () => {
      const db = admin.firestore();
      const now = new Date();

      const start = new Date(
          now.getFullYear(),
          now.getMonth(),
          now.getDate() + 3,
          0,
          0,
          0,
      );

      const end = new Date(
          now.getFullYear(),
          now.getMonth(),
          now.getDate() + 4,
          0,
          0,
          0,
      );

      const startTimestamp = admin.firestore.Timestamp.fromDate(start);
      const endTimestamp = admin.firestore.Timestamp.fromDate(end);

      const snapshot = await db
          .collection("subscriptions")
          .where("status", "==", "trial")
          .where("trialEndDate", ">=", startTimestamp)
          .where("trialEndDate", "<", endTimestamp)
          .get();

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: SMTP_USER,
          pass: process.env.GMAIL_APP_PASSWORD,
        },
      });

      let sentCount = 0;

      for (const doc of snapshot.docs) {
        const data = doc.data();

        if (data.trialReminderEmailSentAt) {
          continue;
        }

        const email = data.billingContactEmail;

        if (!email) {
          continue;
        }

        const organisation =
            data.billingOrganisation || "votre organisation";

        await transporter.sendMail({
          from: MAIL_FROM,
          to: email,
          subject: "Votre essai SPHOT arrive bientôt à échéance",
          text:
`Bonjour,

Votre période d'essai SPHOT pour ${organisation}
arrive bientôt à échéance.

Pour continuer à utiliser SPHOT sans interruption,
vous pouvez activer votre abonnement depuis votre espace administrateur.

Cordialement,
L'équipe SPHOT`,
        });

        await doc.ref.set(
            {
              trialReminderEmailSentAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        sentCount += 1;
      }

      console.log(
          "Emails rappel fin essai envoyés:",
          sentCount,
      );
    },
);

exports.sendOverdueSubscriptionReminderEmails = onSchedule(
    {
      schedule: "0 10 * * *",
      timeZone: "Europe/Paris",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async () => {
      const db = admin.firestore();

      const snapshot = await db
          .collection("subscriptions")
          .where("status", "==", "overdue")
          .get();

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: SMTP_USER,
          pass: process.env.GMAIL_APP_PASSWORD,
        },
      });

      let sentCount = 0;

      for (const doc of snapshot.docs) {
        const data = doc.data();

        if (data.overdueReminderEmailSentAt) {
          continue;
        }

        const email = data.billingContactEmail;

        if (!email) {
          continue;
        }

        const organisation =
            data.billingOrganisation || "votre organisation";

        await transporter.sendMail({
          from: MAIL_FROM,
          to: email,
          subject: "Votre abonnement SPHOT nécessite une régularisation",
          text:
`Bonjour,

Votre abonnement SPHOT pour ${organisation}
nécessite une régularisation.

Pour éviter toute interruption de service,
merci de régulariser votre abonnement depuis votre espace administrateur.

Cordialement,
L'équipe SPHOT`,
        });

        await doc.ref.set(
            {
              overdueReminderEmailSentAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        sentCount += 1;
      }

      console.log(
          "Emails relance abonnements en retard envoyés:",
          sentCount,
      );
    },
);

exports.testEmailSphot = onRequest(
    {
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      try {
        const transporter = nodemailer.createTransport({
          service: "gmail",
          auth: {
            user: SMTP_USER,
            pass: process.env.GMAIL_APP_PASSWORD,
          },
        });

        await transporter.sendMail({
          from: MAIL_FROM,
          to: "rabreau.sylvain@gmail.com",
          subject: "Test email SPHOT",
          text: "Test email Firebase Functions SPHOT.",
        });

        response.status(200).send("Email SPHOT envoyé avec succès.");
      } catch (error) {
        console.error("Erreur envoi email SPHOT:", error);
        response.status(500).send("Erreur lors de l'envoi email SPHOT.");
      }
    },
);

exports.sendSauveteurCredentialsEmail = onRequest(
    {
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "GET, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const email = request.query.email;
        const prenom = request.query.prenom || "Sauveteur";
        const identifiant = request.query.identifiant || "";
        const motDePasse = request.query.motdepasse || "";
        const type = request.query.type || "creation";
        const isReset = type === "reset";

        if (!email) {
          response.status(400).send("Email manquant.");
          return;
        }

        const transporter = nodemailer.createTransport({
          service: "gmail",
          auth: {
            user: SMTP_USER,
            pass: process.env.GMAIL_APP_PASSWORD,
          },
        });

        await transporter.sendMail({
          from: MAIL_FROM,
          to: email,
          subject: isReset ?
    "Vos nouveaux accès SPHOT" :
    "Vos accès SPHOT",
          html: `
<div style="margin:0;padding:40px 20px;
background:#eef3f8 url('https://sphot.app/assets/data/images/map_background.jpg')
center center / cover no-repeat;
font-family:Arial,Helvetica,sans-serif;">

    <div style="max-width:620px;margin:auto;
background:rgba(255,255,255,0.94);
border-radius:18px;overflow:hidden;border:1px solid #d9e2ec;
box-shadow:0 4px 12px rgba(0,0,0,.08);">

    <div style="padding:30px 30px 20px 30px;text-align:center;">

      <a href="${SPHOT_LOGIN_URL}">
        <img
          src="https://sphot.app/assets/data/icons/title.png"
          alt="SPHOT"
          style="max-width:320px;width:100%;height:auto;border:0;">
      </a>
      
    </div>

    <div style="padding:0 34px 30px 34px;color:#263238;
font-size:16px;line-height:1.6;">

      <p>Bonjour <strong>${prenom}</strong>,</p>

${isReset ?
  `` :
  `
<p>
  Bienvenue sur SPHOT.
</p>
`
}

${isReset ? `
<p>
  Votre administrateur SPHOT a procédé à la réinitialisation
de votre mot de passe.
</p>

<p>
  Votre identifiant reste inchangé.
</p>

<p>
  Vous trouverez ci-dessous votre nouveau mot de passe temporaire.
</p>
`:
`
<p>
  Votre compte SPHOT a été créé par votre administrateur.
</p>

<p>
  Vous trouverez ci-dessous votre identifiant
  et votre mot de passe temporaire.
</p>
`
}

      <div style="
          margin:28px 0;
          background:#f7f9fc;
          border:1px solid #d9e2ec;
          border-radius:14px;
          padding:22px;">

        <div style="margin-bottom:18px;">
          <div style="font-size:13px;color:#607d8b;text-transform:uppercase;">
            Identifiant
          </div>

          <div style="font-size:22px;font-weight:bold;color:#1e3a8a;">
            ${identifiant}
          </div>
        </div>

        <div>
          <div style="font-size:13px;color:#607d8b;text-transform:uppercase;">
            Mot de passe temporaire
          </div>

          <div style="font-size:22px;font-weight:bold;color:#d91c1c;">
            ${motDePasse}
          </div>
        </div>

      </div>

      ${isReset ? `
<div style="
    background:#e3f2fd;
    border-left:5px solid #1976d2;
    padding:16px;
    border-radius:8px;
    margin-bottom:28px;">

<strong>Important</strong><br><br>

À votre prochaine connexion,
vous devrez modifier votre mot de passe.

</div>
`:
`
<div style="
    background:#fff8e1;
    border-left:5px solid #ff9800;
    padding:16px;
    border-radius:8px;
    margin-bottom:28px;">

<strong>Important</strong><br>

Lors de votre première connexion,
vous devrez modifier votre mot de passe.

</div>
`
}

      <div style="text-align:center;margin:35px 0;">

        <a
          href="${SPHOT_LOGIN_URL}"
          style="
            background:#d91c1c;
            color:#ffffff;
            text-decoration:none;
            padding:16px 30px;
            border-radius:10px;
            display:inline-block;
            font-size:17px;
            font-weight:bold;">

          SE CONNECTER À SPHOT

        </a>

      </div>

      <p style="margin-top:40px;">
        À bientôt sur SPHOT,<br>
        <strong>L'équipe SPHOT</strong>
      </p>

    </div>

  </div>

</div>
`,
          text: isReset ?
`Bonjour ${prenom},

Votre administrateur SPHOT a réinitialisé votre mot de passe.

Identifiant : ${identifiant}
Mot de passe temporaire : ${motDePasse}

Utilisez le mot de passe temporaire ci-dessus.

À votre prochaine connexion, vous devrez le modifier.

Se connecter à SPHOT :
${SPHOT_LOGIN_URL}

À bientôt sur SPHOT,

L'équipe SPHOT` :
`Bonjour ${prenom},

Votre compte SPHOT a été créé par votre administrateur.

Identifiant : ${identifiant}
Mot de passe temporaire : ${motDePasse}

Lors de votre première connexion, vous devrez modifier votre mot de passe.

Se connecter à SPHOT :
${SPHOT_LOGIN_URL}

À bientôt sur SPHOT,

L'équipe SPHOT`,
        });

        response.status(200).send("Email d'identifiants envoyé.");
      } catch (error) {
        console.error(
            "Erreur envoi email identifiants SPHOT:",
            error,
        );
        response.status(500).send("Erreur lors de l'envoi.");
      }
    },
);

exports.loginSauveteur = onRequest(
    {
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const login = (request.body.login || "")
            .toString()
            .trim()
            .toLowerCase();

        const password = (request.body.password || "")
            .toString()
            .trim();

        if (!login || !password) {
          response.status(400).json({success: false});
          return;
        }

        const accountDoc = await admin.firestore()
            .collection("sauveteurAccounts")
            .doc(login)
            .get();

        if (!accountDoc.exists) {
          response.status(401).json({success: false});
          return;
        }

        const data = accountDoc.data();

        if (data.accountStatus !== "ACTIVE") {
          response.status(401).json({success: false});
          return;
        }

        if (data.temporaryPassword !== password) {
          response.status(401).json({success: false});
          return;
        }

        const doc = accountDoc;

        let userRole = "Sauveteur";

        if (Array.isArray(data.fonctions) && data.fonctions.length > 0) {
          userRole = data.fonctions[0].toString();
        } else if ((data.role || "").toString().trim() !== "") {
          userRole = data.role.toString();
        }

        await doc.ref.set(
            {
              lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        response.status(200).json({
          success: true,
          sauveteurId: doc.id,
          territoireId: (data.territoireId || "").toString(),
          userRole: userRole,
          mustChangePassword: data.mustChangePassword === true,
        });
      } catch (error) {
        console.error("Erreur login sauveteur:", error);
        response.status(500).json({success: false});
      }
    },
);

exports.upsertSauveteurAccount = onRequest(
    {
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const data = request.body || {};
        const login = (data.login || "").toString().trim().toLowerCase();

        if (!login) {
          response.status(400).json({success: false});
          return;
        }

        await admin.firestore()
            .collection("sauveteurAccounts")
            .doc(login)
            .set(
                {
                  ...data,
                  login: login,
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                {merge: true},
            );

        response.status(200).json({success: true});
      } catch (error) {
        console.error("Erreur upsert sauveteurAccount:", error);
        response.status(500).json({success: false});
      }
    },
);

exports.changeSauveteurPassword = onRequest(
    {
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const login = (request.body.login || "")
            .toString()
            .trim()
            .toLowerCase();

        const newPassword = (request.body.newPassword || "")
            .toString()
            .trim();

        let email = "";
        let prenom = "Sauveteur";

        const accountBeforeUpdate = await admin.firestore()
            .collection("sauveteurAccounts")
            .doc(login)
            .get();

        if (accountBeforeUpdate.exists) {
          const accountData = accountBeforeUpdate.data();

          email = (accountData.email || "").toString().trim();
          console.log("Email confirmation mdp sauveteur:", email);
          prenom = (accountData.prenom || "Sauveteur")
              .toString()
              .trim();
        }

        if (!login || !newPassword) {
          response.status(400).json({success: false});
          return;
        }

        await admin.firestore()
            .collection("sauveteurAccounts")
            .doc(login)
            .set(
                {
                  temporaryPassword: newPassword,
                  mustChangePassword: false,
                  passwordUpdatedAt:
                      admin.firestore.FieldValue.serverTimestamp(),
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                {merge: true},
            );

        if (email) {
          try {
            const transporter = nodemailer.createTransport({
              service: "gmail",
              auth: {
                user: SMTP_USER,
                pass: process.env.GMAIL_APP_PASSWORD,
              },
            });

            await transporter.sendMail({
              from: MAIL_FROM,
              to: email,
              subject: "Mise à jour de votre compte SPHOT",
              html: `
<div style="margin:0;padding:40px 20px;
background:#eef3f8 url('https://sphot.app/assets/data/images/map_background.jpg')
center center / cover no-repeat;
font-family:Arial,Helvetica,sans-serif;">

  <div style="max-width:620px;margin:auto;
background:rgba(255,255,255,0.94);
border-radius:18px;
overflow:hidden;
border:1px solid #d9e2ec;
box-shadow:0 4px 12px rgba(0,0,0,.08);">

    <div style="padding:30px 30px 20px;text-align:center;">

      <a href="${SPHOT_LOGIN_URL}">
        <img
          src="https://sphot.app/assets/data/icons/title.png"
          alt="SPHOT"
          style="max-width:320px;width:100%;height:auto;border:0;">
      </a>

    </div>

    <div
      style="padding:0 34px 30px;color:#263238;
      font-size:16px;line-height:1.6;">

      <p>Bonjour <strong>${prenom}</strong>,</p>

      <p>
        Nous vous confirmons que votre mot de passe
        SPHOT a été modifié avec succès.
      </p>

      <p>
        Si vous n'êtes pas à l'origine de cette modification,
        contactez immédiatement votre administrateur.
      </p>

      <div style="text-align:center;margin:35px 0;">

        <a
          href="${SPHOT_LOGIN_URL}"
          style="
            background:#d91c1c;
            color:#ffffff;
            text-decoration:none;
            padding:16px 30px;
            border-radius:10px;
            display:inline-block;
            font-size:17px;
            font-weight:bold;">

          SE CONNECTER À SPHOT

        </a>

      </div>

      <p>
        À bientôt sur SPHOT,<br>
        <strong>L'équipe SPHOT</strong>
      </p>

    </div>

  </div>

</div>
`,
              text: `Bonjour ${prenom},

Nous vous confirmons que votre mot de passe SPHOT
a été modifié avec succès.

Si vous n'êtes pas à l'origine de cette modification,
contactez immédiatement votre administrateur.

À bientôt sur SPHOT,

L'équipe SPHOT`,
            });
          } catch (mailError) {
            console.error("Erreur email confirmation mot de passe:", mailError);
          }
        }

        response.status(200).json({success: true});
      } catch (error) {
        console.error("Erreur changement mot de passe sauveteur:", error);
        response.status(500).json({success: false});
      }
    },
);

exports.deleteSauveteurAccount = onRequest(
    {
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      try {
        const login = (request.body.login || "")
            .toString()
            .trim()
            .toLowerCase();

        if (!login) {
          response.status(400).json({success: false});
          return;
        }

        await admin.firestore()
            .collection("sauveteurAccounts")
            .doc(login)
            .delete();

        response.status(200).json({success: true});
      } catch (error) {
        console.error("Erreur suppression sauveteurAccount:", error);
        response.status(500).json({success: false});
      }
    },
);
