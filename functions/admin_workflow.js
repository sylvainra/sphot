"use strict";

const {sendSphotMail} = require("./sphot_email_design");

const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const {getDownloadURL} = require("firebase-admin/storage");
const nodemailer = require("nodemailer");
const PDFDocument = require("pdfkit");

if (!admin.apps.length) {
  admin.initializeApp();
}

const REGION = "europe-west1";
const SMTP_USER = "admin@sphot.app";
const MAIL_FROM = "\"SPHOT\" <no-reply@sphot.app>";
const SPHOT_LOGIN_URL = "https://sphot.app/#/professional-login";
const DEFAULT_TRIAL_DAYS = 8;
const DEFAULT_PRICE_PER_STATION_EXCL_TAX = 500;
const DEFAULT_VAT_RATE = 20;

function cleanValue(value, fallback = "") {
  const result = (value ?? "").toString().trim();
  return result || fallback;
}

function escapeHtml(value) {
  return cleanValue(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("\"", "&quot;")
      .replaceAll("'", "&#039;");
}

function toDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === "function") return value.toDate();
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function formatFrenchDate(value, withTime = true) {
  const date = value instanceof Date ? value : toDate(value);
  if (!date) return "Non renseignée";

  return new Intl.DateTimeFormat("fr-FR", {
    timeZone: "Europe/Paris",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    ...(withTime ? {hour: "2-digit", minute: "2-digit"} : {}),
  }).format(date);
}

function buildGreeting(data) {
  const profile = data.profile || {};
  const proConnect = data.proConnect || {};
  const civilite = cleanValue(profile.civilite || data.civilite);
  const nom = cleanValue(
      profile.nomAffiche || data.nomResponsable || proConnect.nom,
  ).toUpperCase();

  if (civilite && nom) return `Bonjour ${civilite} ${nom},`;
  if (nom) return `Bonjour ${nom},`;
  return "Bonjour,";
}

function organisationDisplay(data) {
  const structure = data.structure || {};
  const proConnect = data.proConnect || {};
  return cleanValue(
      structure.organisationDisplay ||
      data.organisationDisplay ||
      structure.nom ||
      data.organisation ||
      proConnect.organisation,
      "votre structure",
  );
}

function recipientEmail(data) {
  const profile = data.profile || {};
  const proConnect = data.proConnect || {};
  return cleanValue(profile.email || data.email || proConnect.email);
}

function requestUid(data, requestId) {
  return cleanValue(data.uid || data.adminUid || requestId);
}

function transporter() {
  return nodemailer.createTransport({
    service: "gmail",
    auth: {
      user: SMTP_USER,
      pass: process.env.GMAIL_APP_PASSWORD,
    },
  });
}

function currency(value) {
  const number = Number(value || 0);
  return new Intl.NumberFormat("fr-FR", {
    style: "currency",
    currency: "EUR",
    minimumFractionDigits: 2,
  }).format(number);
}

function yearInParis(date = new Date()) {
  return Number(new Intl.DateTimeFormat("fr-FR", {
    timeZone: "Europe/Paris",
    year: "numeric",
  }).format(date));
}

function safeDocumentId(value) {
  return cleanValue(value)
      .replaceAll(/[^A-Za-z0-9_-]/g, "_")
      .replaceAll(/_+/g, "_")
      .slice(0, 700);
}

function simplePdfBuffer({
  title,
  documentNumber,
  requestNumber,
  rubric = "",
  statusLabel = "ÉMIS",
  introduction = "",
  lines,
  notice = "",
}) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
      size: "A4",
      margins: {top: 30, bottom: 30, left: 40, right: 40},
      info: {
        Title: title,
        Author: "SPHOT",
        Subject: documentNumber,
      },
    });

    const chunks = [];
    doc.on("data", (chunk) => chunks.push(chunk));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    const blue = "#1E3A8A";
    const red = "#DC2626";
    const dark = "#263238";
    const grey = "#607D8B";
    const pale = "#F3F6FB";
    const paleWarm = "#FFF8E1";
    const white = "#FFFFFF";

    const left = doc.page.margins.left;
    const right = doc.page.width - doc.page.margins.right;
    const contentWidth = right - left;

    const headingCount = lines.filter((line) => line?.heading).length;
    const dataCount = lines.filter((line) => line && !line.heading).length;
    const compact = dataCount > 9 || headingCount > 3;
    const valueFontSize = compact ? 7.2 : 7.8;
    const rowHeight = compact ? 11.5 : 13;

    const drawSectionTitle = (heading) => {
      const titleY = doc.y + 3;

      doc
          .font("Helvetica-Bold")
          .fontSize(8.4)
          .fillColor(red)
          .text(cleanValue(heading).toUpperCase(), left, titleY, {
            width: contentWidth,
          });

      doc
          .strokeColor(blue)
          .lineWidth(0.65)
          .moveTo(left, titleY + 14)
          .lineTo(right, titleY + 14)
          .stroke();

      doc.y = titleY + 20;
    };

    doc
        .roundedRect(left, 30, contentWidth, 72, 14)
        .fillAndStroke(white, "#D9E2EC");

    doc
        .font("Helvetica-Bold")
        .fontSize(25)
        .fillColor(red)
        .text("SPHOT", left + 18, 43, {width: 120});

    doc
        .font("Helvetica")
        .fontSize(7.2)
        .fillColor(grey)
        .text(
            "Des plages plus sûres, propres et connectées",
            left + 18,
            73,
            {width: 200},
        );

    doc
        .font("Helvetica-Bold")
        .fontSize(8)
        .fillColor(blue)
        .text(
            "SURVEILLER  •  PRÉSERVER  •  INFORMER  •  ENSEMBLE",
            left + 222,
            56,
            {
              width: contentWidth - 240,
              align: "right",
            },
        );

    doc.y = 116;

    doc
        .font("Helvetica-Bold")
        .fontSize(12.6)
        .fillColor(blue)
        .text(title.toUpperCase(), {
          align: "center",
          width: contentWidth,
          lineGap: 1,
        });

    doc.moveDown(0.35);

    const referenceY = doc.y;
    doc
        .roundedRect(left, referenceY, contentWidth, 76, 12)
        .fillAndStroke(pale, blue);

    doc
        .font("Helvetica-Bold")
        .fontSize(7.1)
        .fillColor(grey)
        .text("RÉFÉRENCE DU DOCUMENT", left + 14, referenceY + 11);

    doc
        .font("Helvetica-Bold")
        .fontSize(10.3)
        .fillColor(red)
        .text(documentNumber, left + 14, referenceY + 27, {
          width: 330,
        });

    doc
        .font("Helvetica")
        .fontSize(7)
        .fillColor(grey)
        .text(
            `Dossier : ${requestNumber}`,
            left + 14,
            referenceY + 50,
        );

    if (rubric) {
      doc
          .font("Helvetica-Bold")
          .fontSize(7.1)
          .fillColor(blue)
          .text("RUBRIQUE", right - 145, referenceY + 11, {
            width: 130,
            align: "right",
          });

      doc
          .font("Helvetica-Bold")
          .fontSize(8.1)
          .fillColor(dark)
          .text(rubric.toUpperCase(), right - 145, referenceY + 27, {
            width: 130,
            align: "right",
          });
    }

    doc
        .font("Helvetica-Bold")
        .fontSize(7.1)
        .fillColor(blue)
        .text("STATUT", right - 145, referenceY + 50, {
          width: 130,
          align: "right",
        });

    doc
        .font("Helvetica-Bold")
        .fontSize(8.1)
        .fillColor(dark)
        .text(statusLabel.toUpperCase(), right - 145, referenceY + 63, {
          width: 130,
          align: "right",
        });

    doc.y = referenceY + 89;

    if (introduction) {
      doc
          .font("Helvetica")
          .fontSize(8)
          .fillColor(dark)
          .text(introduction, left + 8, doc.y, {
            width: contentWidth - 16,
            lineGap: 1.1,
          });
      doc.moveDown(0.45);
    }

    for (const line of lines) {
      if (!line) continue;

      if (line.heading) {
        drawSectionTitle(line.heading);
        continue;
      }

      const rowY = doc.y;
      const label = cleanValue(line.label);
      const value = cleanValue(line.value, "Non renseigné");

      doc
          .font("Helvetica-Bold")
          .fontSize(valueFontSize)
          .fillColor(blue)
          .text(label, left + 10, rowY, {
            width: 118,
          });

      doc
          .font("Helvetica")
          .fontSize(valueFontSize)
          .fillColor(dark)
          .text(value, left + 132, rowY, {
            width: contentWidth - 142,
            ellipsis: true,
          });

      doc.y = rowY + rowHeight;
    }

    if (notice) {
      const noticeY = doc.y + 8;
      const noticeHeight = compact ? 56 : 62;

      doc
          .roundedRect(left, noticeY, contentWidth, noticeHeight, 10)
          .fillAndStroke(paleWarm, "#F59E0B");

      doc
          .font("Helvetica-Bold")
          .fontSize(7.8)
          .fillColor(red)
          .text("INFORMATION IMPORTANTE", left + 12, noticeY + 10);

      doc
          .font("Helvetica")
          .fontSize(compact ? 7.1 : 7.5)
          .fillColor(dark)
          .text(notice, left + 12, noticeY + 25, {
            width: contentWidth - 24,
            lineGap: 0.8,
          });

      doc.y = noticeY + noticeHeight + 10;
    } else {
      doc.y += 10;
    }

    doc
        .font("Helvetica")
        .fontSize(8.1)
        .fillColor(dark)
        .text("À bientôt sur SPHOT,", left, doc.y, {
          width: contentWidth,
          align: "right",
        });

    doc
        .font("Helvetica-Bold")
        .fontSize(8.4)
        .fillColor(blue)
        .text("L'équipe SPHOT", left, doc.y + 2, {
          width: contentWidth,
          align: "right",
        });

    const footerY = doc.page.height - 54;
    doc
        .strokeColor("#D9E2EC")
        .lineWidth(0.7)
        .moveTo(left, footerY)
        .lineTo(right, footerY)
        .stroke();

    doc
        .font("Helvetica")
        .fontSize(6.6)
        .fillColor(grey)
        .text(
            "Document généré automatiquement par SPHOT",
            left,
            footerY + 10,
            {width: 220},
        );

    doc
        .font("Helvetica")
        .fontSize(6.6)
        .fillColor(grey)
        .text(
            `${documentNumber}  •  Version 01  •  Page 1 / 1`,
            left + 210,
            footerY + 10,
            {
              width: contentWidth - 210,
              align: "right",
            },
        );

    doc.end();
  });
}

async function createRegistryPdf({
  requestId,
  adminUid,
  requestNumber,
  documentNumber,
  documentType,
  category,
  subcategory,
  title,
  rubric = "",
  statusLabel = "ÉMIS",
  introduction = "",
  lines,
  notice = "",
  relatedOrderId = null,
  relatedInvoiceId = null,
}) {
  const db = admin.firestore();
  const bucket = admin.storage().bucket();
  const year = yearInParis();
  const fileName = `${documentNumber}.pdf`;
  const folderCategory = category === "financial" ? "financier" : "administratif";
  const storagePath =
      `adminRequests/${requestId}/documents/${folderCategory}/` +
      `${year}/${subcategory}/${fileName}`;
  const registryId = safeDocumentId(`${requestId}_${documentNumber}`);
  const registryRef = db.collection("documents").doc(registryId);

  const existing = await registryRef.get();
  if (existing.exists && existing.data()?.status === "issued") {
    return existing.data();
  }

  const buffer = await simplePdfBuffer({
    title,
    documentNumber,
    requestNumber,
    rubric,
    statusLabel,
    introduction,
    lines,
    notice,
  });
  const file = bucket.file(storagePath);
  await file.save(buffer, {
    contentType: "application/pdf",
    resumable: false,
    metadata: {
      contentDisposition: `attachment; filename="${fileName}"`,
      metadata: {
        requestId,
        adminUid,
        requestNumber,
        documentNumber,
        documentType,
      },
    },
  });
  const downloadUrl = await getDownloadURL(file);

  const payload = {
    requestId,
    adminUid,
    dossierNumber: requestNumber,
    documentNumber,
    documentType,
    category,
    subcategory,
    year,
    version: 1,
    title,
    status: "issued",
    storagePath,
    downloadUrl,
    relatedOrderId,
    relatedInvoiceId,
    issuedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdByRole: "system",
  };
  await registryRef.set(payload, {merge: true});
  return payload;
}

async function registerLegacyAcknowledgement(requestId, data) {
  const requestNumber = cleanValue(data.requestNumber);
  const legacy = data.acknowledgementDocument || {};
  if (!requestNumber || !legacy.downloadUrl) return;

  const docNumber = `${requestNumber}-INS-AR-01`;
  const ref = admin.firestore().collection("documents")
      .doc(safeDocumentId(`${requestId}_${docNumber}`));
  const existing = await ref.get();
  if (existing.exists) return;

  await ref.set({
    requestId,
    adminUid: requestUid(data, requestId),
    dossierNumber: requestNumber,
    documentNumber: docNumber,
    documentType: "registration_acknowledgement",
    category: "administrative",
    subcategory: "inscription",
    year: Number(data.requestYear || yearInParis()),
    version: 1,
    title: "Accusé de réception de la demande d’accès administrateur",
    status: "issued",
    storagePath: legacy.storagePath || null,
    downloadUrl: legacy.downloadUrl,
    issuedAt: legacy.generatedAt || data.requestedAt || null,
    createdAt: legacy.generatedAt || data.requestedAt ||
        admin.firestore.FieldValue.serverTimestamp(),
    createdByRole: "system",
    legacySource: true,
  }, {merge: true});
}

async function ensureRegistrationApprovalDocument(requestId, data) {
  const requestNumber = cleanValue(data.requestNumber);
  const tracking = data.administrativeTracking || {};
  const approvedAt = tracking.approvedAt || data.approvedAt;
  if (!requestNumber || !approvedAt) return;

  const docNumber = `${requestNumber}-INS-VAL-01`;
  const registryId = safeDocumentId(`${requestId}_${docNumber}`);
  const existing = await admin.firestore().collection("documents")
      .doc(registryId).get();
  if (existing.exists) return;

  const profile = data.profile || {};
  const structure = data.structure || {};
  const territoire = data.territoire || {};
  const payload = await createRegistryPdf({
    requestId,
    adminUid: requestUid(data, requestId),
    requestNumber,
    documentNumber: docNumber,
    documentType: "registration_approval",
    category: "administrative",
    subcategory: "inscription",
    title: "Décision d’approbation de l’accès administrateur",
    rubric: "Demande d’accès",
    statusLabel: "APPROUVÉ",
    introduction:
      "Après instruction de votre demande, SPHOT confirme " +
      "l’approbation de votre accès administrateur pour la structure " +
      `${cleanValue(structure.nom, organisationDisplay(data))}.`,
    lines: [
      {heading: "Décision"},
      {label: "Statut", value: "Accès administrateur approuvé"},
      {label: "Décision prise le", value: formatFrenchDate(approvedAt)},
      {heading: "Demandeur"},
      {label: "Responsable", value:
        `${cleanValue(profile.prenomAffiche)} ${cleanValue(profile.nomAffiche)}`.trim()},
      {label: "Email", value: profile.email},
      {heading: "Structure concernée"},
      {label: "Organisation", value: structure.nom},
      {label: "SIRET", value: structure.siret},
      {label: "Commune", value: territoire.ville},
      {label: "Département", value: territoire.departement},
    ],
    notice:
      "Cette décision concerne uniquement l’accès administrateur au " +
      "portail SPHOT. Elle n’ouvre pas automatiquement une période " +
      "d’essai, un abonnement ou des droits de facturation. Ces étapes " +
      "font l’objet de décisions et de documents distincts.",
  });

  await admin.firestore().collection("adminRequests").doc(requestId).set({
    registrationApprovalDocument: {
      status: "generated",
      documentNumber: docNumber,
      storagePath: payload.storagePath,
      downloadUrl: payload.downloadUrl,
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
  }, {merge: true});
}

async function claimEmailState(requestRef, fieldName, expected = "pending") {
  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(requestRef);
    const data = snap.data() || {};
    const state = data[fieldName] || {};
    const status = cleanValue(state.status);
    if (status === "sent" || status === "sending") return null;
    if (expected && status && status !== expected && status !== "error") {
      return null;
    }
    const token = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    tx.set(requestRef, {
      [fieldName]: {
        ...state,
        status: "sending",
        token,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    }, {merge: true});
    return {data, token};
  });
}

async function markEmail(requestRef, fieldName, status, extra = {}) {
  await requestRef.set({
    [fieldName]: {
      status,
      ...extra,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
  }, {merge: true});
}

async function sendTrialReceipt(requestId) {
  const db = admin.firestore();
  const requestRef = db.collection("adminRequests").doc(requestId);
  const claimed = await claimEmailState(requestRef, "trialReceiptEmail", null);
  if (!claimed) return;

  const data = claimed.data;
  const email = recipientEmail(data);
  if (!email) {
    await markEmail(requestRef, "trialReceiptEmail", "error", {
      error: "Adresse email absente.",
    });
    return;
  }

  const requestNumber = cleanValue(data.requestNumber, requestId);
  const trial = data.trialRequest || {};
  const requestedAt = data.trialRequestedAt || trial.requestedAt || new Date();
  const duration = Number(trial.trialDurationDays || DEFAULT_TRIAL_DAYS);
  const docNumber = `${requestNumber}-ESS-AR-01`;

  try {
    const pdf = await createRegistryPdf({
      requestId,
      adminUid: requestUid(data, requestId),
      requestNumber,
      documentNumber: docNumber,
      documentType: "trial_acknowledgement",
      category: "administrative",
      subcategory: "essai",
      title: "Accusé de réception de la demande de période d’essai",
      rubric: "Période d’essai",
      statusLabel: "EN ATTENTE",
      introduction:
        "Nous accusons réception de votre demande d’ouverture d’une " +
        `période d’essai gratuite de ${duration} jours pour ` +
        `${organisationDisplay(data)}.`,
      lines: [
        {heading: "Demande"},
        {label: "Demande reçue le", value: formatFrenchDate(requestedAt)},
        {label: "Durée sollicitée", value: `${duration} jours`},
        {label: "Statut", value: "En attente de validation"},
        {heading: "Structure concernée"},
        {label: "Organisation", value: organisationDisplay(data)},
      ],
      notice:
        "La période d’essai n’est pas active à ce stade. Aucun droit de " +
        "diffusion n’est ouvert par le présent document. Vous recevrez " +
        "une décision distincte lors de l’activation éventuelle de " +
        "votre période d’essai.",
    });

    const greeting = buildGreeting(data);
    const organisation = organisationDisplay(data);
    const html = `
<p style="font-size:16px;line-height:1.6;">
  ${escapeHtml(greeting)}
</p>

<p style="font-size:16px;line-height:1.6;">
  Nous accusons réception de votre demande de
  <strong>
    période d’essai gratuite SPHOT ADMIN de ${duration} jours
  </strong>
  pour <strong>${escapeHtml(organisation)}</strong>.
</p>

<p style="
  color:#dc2626;
  font-size:16px;
  line-height:1.6;
  font-weight:900;
">
  Demande de période d’essai bien enregistrée.
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
  Votre demande est actuellement
  <strong>en attente de validation par l’équipe SPHOT</strong>.
  <br><br>
  La période d’essai gratuite ne débutera
  <strong>qu’après cette validation</strong>.
  Vous recevrez un nouvel email dès son activation.
</div>

<div style="
  margin:20px 0;
  padding:16px;
  border-left:4px solid #1e3a8a;
  border-radius:8px;
  background:#f3f6fb;
  font-size:14px;
  line-height:1.6;
">
  Référence du dossier :
  <strong style="color:#dc2626;">
    ${escapeHtml(requestNumber)}
  </strong>
</div>

<div style="text-align:center;margin:30px 0;">
  <a
    href="${SPHOT_LOGIN_URL}"
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
    SE CONNECTER À SPHOT ADMIN
  </a>
</div>

<p style="
  margin-top:28px;
  font-size:15px;
  line-height:1.6;
">
  À bientôt sur SPHOT,<br>
  <strong>L'équipe SPHOT</strong>
</p>`;

    const mailResult = await sendSphotMail(
        transporter(),
        {
          from: MAIL_FROM,
          to: email,
          subject: "SPHOT ADMIN — Demande d’essai bien reçue",
          html,
          attachments: [{
            filename: `${docNumber}.pdf`,
            href: pdf.downloadUrl,
          }],
        },
    );

    await requestRef.set({
      "trialTracking.status": "pending",
      "trialTracking.requestedAt": requestedAt,
      "trialTracking.durationDays": duration,
      "trialRequestStatus": "pending",
      trialReceiptDocument: {
        status: "generated",
        documentNumber: docNumber,
        storagePath: pdf.storagePath,
        downloadUrl: pdf.downloadUrl,
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      trialReceiptEmail: {
        status: "sent",
        recipient: email,
        messageId: mailResult.messageId || null,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        error: null,
      },
    }, {merge: true});
  } catch (error) {
    await markEmail(requestRef, "trialReceiptEmail", "error", {
      recipient: email,
      error: error.message || error.toString(),
    });
    throw error;
  }
}

async function sendTrialApproval(requestId) {
  const db = admin.firestore();
  const requestRef = db.collection("adminRequests").doc(requestId);
  const claimed = await claimEmailState(requestRef, "trialApprovalEmail", "pending");
  if (!claimed) return;

  const data = claimed.data;
  const email = recipientEmail(data);
  if (!email) {
    await markEmail(requestRef, "trialApprovalEmail", "error", {
      error: "Adresse email absente.",
    });
    return;
  }

  const uid = requestUid(data, requestId);
  const subscriptionSnap = await db.collection("subscriptions").doc(uid).get();
  const subscription = subscriptionSnap.data() || {};
  const start = subscription.trialStartDate || data.trialTracking?.approvedAt;
  const end = subscription.trialEndDate;
  const duration = Number(subscription.trialDurationDays || DEFAULT_TRIAL_DAYS);
  const requestNumber = cleanValue(data.requestNumber, requestId);
  const docNumber = `${requestNumber}-ESS-VAL-01`;

  try {
    const pdf = await createRegistryPdf({
      requestId,
      adminUid: uid,
      requestNumber,
      documentNumber: docNumber,
      documentType: "trial_approval",
      category: "administrative",
      subcategory: "essai",
      title: "Décision d’ouverture de la période d’essai",
      rubric: "Période d’essai",
      statusLabel: "ACTIVÉE",
      introduction:
        "SPHOT confirme l’ouverture de votre période d’essai gratuite. " +
        "Les droits associés à cette phase sont activés pour la durée " +
        "indiquée ci-dessous.",
      lines: [
        {heading: "Période d’essai"},
        {label: "Statut", value: "Période d’essai activée"},
        {label: "Durée", value: `${duration} jours`},
        {label: "Début", value: formatFrenchDate(start)},
        {label: "Fin", value: formatFrenchDate(end)},
        {label: "Droits de diffusion", value: "Autorisés pendant l’essai"},
        {heading: "Structure concernée"},
        {label: "Organisation", value: organisationDisplay(data)},
      ],
      notice:
        "L’activation de la période d’essai ne constitue pas une " +
        "souscription payante. Toute activation d’un abonnement annuel " +
        "fera l’objet d’une démarche, d’une référence et d’un document " +
        "distincts.",
    });

    const html = `
<p style="font-size:16px;line-height:1.6;">
  ${escapeHtml(buildGreeting(data))}
</p>

<p style="font-size:16px;line-height:1.6;">
  Votre demande de
  <strong>période d’essai gratuite SPHOT ADMIN</strong>
  a été validée.
</p>

<div style="
  margin:22px 0;
  padding:18px;
  border-left:4px solid #16a34a;
  border-radius:8px;
  background:#f0fdf4;
  font-size:15px;
  line-height:1.6;
">
  Votre essai débute le
  <strong>${escapeHtml(formatFrenchDate(start))}</strong>
  et prendra fin le
  <strong>${escapeHtml(formatFrenchDate(end))}</strong>.
  <br><br>
  <strong>Vos droits de diffusion SPHOT ADMIN sont désormais activés.</strong>
</div>

<div style="
  margin:24px 0;
  padding:18px;
  border-left:4px solid #f59e0b;
  border-radius:8px;
  background:#fff7df;
  font-size:15px;
  line-height:1.65;
">
  <strong style="color:#dc2626;">
    IMPORTANT — PRÉVENEZ RAPIDEMENT VOS SAUVETEURS
  </strong>
  <br><br>
  Pour profiter pleinement de la période d’essai, prévenez dès maintenant
  les sauveteurs affectés à vos SPHOTS.
  <br><br>
  Ils doivent se connecter à SPHOT avec leurs identifiants afin de
  <strong>renseigner leur partie de l’application</strong> et compléter
  les informations nécessaires au fonctionnement du service.
  <br><br>
  Si certains sauveteurs ne disposent pas encore de leurs accès,
  créez ou vérifiez leur compte depuis SPHOT ADMIN puis transmettez-leur
  rapidement leurs identifiants.
</div>

<div style="text-align:center;margin:30px 0;">
  <a
    href="${SPHOT_LOGIN_URL}"
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
    ACCÉDER À SPHOT ADMIN
  </a>
</div>

<p style="
  margin-top:28px;
  font-size:15px;
  line-height:1.6;
">
  À bientôt sur SPHOT,<br>
  <strong>L'équipe SPHOT</strong>
</p>`;

    const mailResult = await sendSphotMail(
        transporter(),
        {
          from: MAIL_FROM,
          to: email,
          subject:
          "SPHOT ADMIN — Votre période d’essai est activée",
          html,
          attachments: [
            {
              filename: `${docNumber}.pdf`,
              href: pdf.downloadUrl,
            },
          ],
        },
    );

    await requestRef.set({
      trialApprovalDocument: {
        status: "generated",
        documentNumber: docNumber,
        storagePath: pdf.storagePath,
        downloadUrl: pdf.downloadUrl,
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      trialApprovalEmail: {
        status: "sent",
        recipient: email,
        messageId: mailResult.messageId || null,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        error: null,
      },
    }, {merge: true});
  } catch (error) {
    await markEmail(requestRef, "trialApprovalEmail", "error", {
      recipient: email,
      error: error.message || error.toString(),
    });
    throw error;
  }
}

exports.processAdminTrialWorkflow = onDocumentUpdated(
    {
      document: "adminRequests/{requestId}",
      region: REGION,
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const before = event.data?.before.data() || {};
      const after = event.data?.after.data() || {};
      const requestId = event.params.requestId;

      const beforeTrial = cleanValue(
          before.trialRequestStatus || before.trialRequest?.status,
      ).toLowerCase();
      const afterTrial = cleanValue(
          after.trialRequestStatus || after.trialRequest?.status,
      ).toLowerCase();

      if (afterTrial === "pending" && beforeTrial !== "pending") {
        const requestRef = event.data.after.ref;
        await requestRef.set({
          trialTracking: {
            status: "pending",
            requestedAt: after.trialRequestedAt ||
                after.trialRequest?.requestedAt ||
                admin.firestore.FieldValue.serverTimestamp(),
            durationDays: Number(
                after.trialRequest?.trialDurationDays || DEFAULT_TRIAL_DAYS,
            ),
          },
          trialReceiptEmail: {
            status: "pending",
            recipient: recipientEmail(after),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        }, {merge: true});
      }

      const receiptStatus = cleanValue(after.trialReceiptEmail?.status);
      if (afterTrial === "pending" &&
          (receiptStatus === "pending" || receiptStatus === "error")) {
        await sendTrialReceipt(requestId);
      }

      const approvalStatus = cleanValue(after.trialApprovalEmail?.status);
      if (approvalStatus === "pending" || approvalStatus === "error") {
        await sendTrialApproval(requestId);
      }

      const beforeStatus = cleanValue(before.status).toLowerCase();
      const afterStatus = cleanValue(after.status).toLowerCase();
      if (afterStatus === "approved" && beforeStatus !== "approved") {
        await ensureRegistrationApprovalDocument(requestId, after);
        await registerLegacyAcknowledgement(requestId, after);
      }
    },
);

async function getRequestByUid(uid) {
  const db = admin.firestore();
  const direct = await db.collection("adminRequests").doc(uid).get();
  if (direct.exists) return direct;

  const snapshot = await db.collection("adminRequests")
      .where("uid", "==", uid).limit(1).get();
  return snapshot.empty ? null : snapshot.docs[0];
}

async function sendLifecycleMail({requestSnap, fieldName, subject, html}) {
  if (!requestSnap) return false;
  const requestRef = requestSnap.ref;
  const data = requestSnap.data() || {};
  const email = recipientEmail(data);
  if (!email) return false;

  const state = data[fieldName] || {};
  if (state.status === "sent" || state.status === "sending") return false;

  await requestRef.set({
    [fieldName]: {
      status: "sending",
      recipient: email,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
  }, {merge: true});

  try {
    const result = await sendSphotMail(
        transporter(),
        {
          from: MAIL_FROM,
          to: email,
          subject,
          html,
        },
    );
    await requestRef.set({
      [fieldName]: {
        status: "sent",
        recipient: email,
        messageId: result.messageId || null,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        error: null,
      },
    }, {merge: true});
    return true;
  } catch (error) {
    await requestRef.set({
      [fieldName]: {
        status: "error",
        recipient: email,
        error: error.message || error.toString(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    }, {merge: true});
    return false;
  }
}

async function expireTrial(subscriptionDoc, now) {
  const db = admin.firestore();
  const subscription = subscriptionDoc.data() || {};
  const uid = cleanValue(subscription.adminUid || subscriptionDoc.id);
  const requestSnap = await getRequestByUid(uid);
  const requestData = requestSnap?.data() || {};
  const stations = Number(subscription.numberOfRescueStations || 0);
  const price = Number(
      subscription.pricePerStationExclTax || DEFAULT_PRICE_PER_STATION_EXCL_TAX,
  );
  const annual = stations * price;
  const batch = db.batch();

  batch.set(subscriptionDoc.ref, {
    status: "awaiting_subscription",
    trialExpiredAt: admin.firestore.FieldValue.serverTimestamp(),
    subscriptionOffer: {
      status: "available",
      numberOfRescueStations: stations,
      pricePerStationExclTax: price,
      annualAmountExclTax: annual,
      vatRate: Number(subscription.vatRate || DEFAULT_VAT_RATE),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  batch.set(db.collection("admins").doc(uid), {
    diffusionAccessGranted: false,
    diffusionAccessClosedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  if (requestSnap) {
    batch.set(requestSnap.ref, {
      accessPhase: "awaiting_subscription",
      trialRequestStatus: "expired",
      "trialTracking.status": "expired",
      "trialTracking.expiredAt": admin.firestore.FieldValue.serverTimestamp(),
      "commercialTracking.status": "awaiting_subscription",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastEvent: {
        type: "trial_ended",
        category: "commercial",
        label: "Fin de la période d’essai SPHOT ADMIN",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdByRole: "system",
      },
    }, {merge: true});
  }
  await batch.commit();

  if (requestSnap) {
    const end = subscription.trialEndDate;
    const html = `
      <p>${escapeHtml(buildGreeting(requestData))}</p>
      <p>Votre <strong>période d’essai gratuite SPHOT ADMIN</strong> est arrivée
      à son terme le <strong>${escapeHtml(formatFrenchDate(end))}</strong>.</p>
      <p><strong>Vos droits de diffusion sont désormais suspendus.</strong>
      Votre configuration, vos SPHOTS, vos périodes et vos sauveteurs restent enregistrés.</p>
      <p>Vous pouvez poursuivre la diffusion avec l’abonnement annuel SPHOT ADMIN
      au tarif de <strong>${currency(price)} HT par an et par poste de secours</strong>.</p>
      <p>Montant prévisionnel actuel : <strong>${currency(annual)} HT / an</strong>
      pour ${stations} poste(s) de secours.</p>
      <p><a href="${SPHOT_LOGIN_URL}">Accéder à SPHOT ADMIN</a></p>
      <p>Cordialement,<br>L’équipe SPHOT</p>`;
    await sendLifecycleMail({
      requestSnap,
      fieldName: "trialEndEmail",
      subject: "SPHOT ADMIN — Fin de votre période d’essai",
      html,
    });
  }
}

async function sendTrialReminder(subscriptionDoc) {
  const subscription = subscriptionDoc.data() || {};
  const uid = cleanValue(subscription.adminUid || subscriptionDoc.id);
  const requestSnap = await getRequestByUid(uid);
  if (!requestSnap) return;
  const data = requestSnap.data() || {};
  const price = Number(
      subscription.pricePerStationExclTax || DEFAULT_PRICE_PER_STATION_EXCL_TAX,
  );
  const stations = Number(subscription.numberOfRescueStations || 0);
  const annual = price * stations;
  const html = `
    <p>${escapeHtml(buildGreeting(data))}</p>
    <p>Votre <strong>période d’essai gratuite SPHOT ADMIN</strong> prendra fin le
    <strong>${escapeHtml(formatFrenchDate(subscription.trialEndDate))}</strong>.</p>
    <p>Afin d’éviter toute interruption de diffusion, vous pouvez dès maintenant
    préparer votre abonnement annuel SPHOT ADMIN.</p>
    <p>Tarif : <strong>${currency(price)} HT / an / poste de secours</strong>.<br>
    Montant prévisionnel : <strong>${currency(annual)} HT / an</strong>
    pour ${stations} poste(s).</p>
    <p><a href="${SPHOT_LOGIN_URL}">Accéder à SPHOT ADMIN</a></p>
    <p>Cordialement,<br>L’équipe SPHOT</p>`;
  const sent = await sendLifecycleMail({
    requestSnap,
    fieldName: "trialReminder48hEmail",
    subject: "SPHOT ADMIN — Votre essai se termine dans moins de 48 heures",
    html,
  });
  if (sent) {
    await subscriptionDoc.ref.set({
      trialReminder48hSentAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }
}

async function sendRenewalReminder(subscriptionDoc, days) {
  const subscription = subscriptionDoc.data() || {};
  const uid = cleanValue(subscription.adminUid || subscriptionDoc.id);
  const requestSnap = await getRequestByUid(uid);
  if (!requestSnap) return;
  const data = requestSnap.data() || {};
  const price = Number(
      subscription.pricePerStationExclTax || DEFAULT_PRICE_PER_STATION_EXCL_TAX,
  );
  const stations = Number(subscription.numberOfRescueStations || 0);
  const annual = price * stations;
  const fieldName = `renewalReminder${days}dEmail`;
  const html = `
    <p>${escapeHtml(buildGreeting(data))}</p>
    <p>Votre abonnement annuel SPHOT ADMIN arrive à échéance le
    <strong>${escapeHtml(formatFrenchDate(subscription.subscriptionEndDate, false))}</strong>.</p>
    <p>Vous pouvez préparer son renouvellement dès maintenant.</p>
    <p>Base tarifaire actuelle : <strong>${currency(price)} HT / an / poste de secours</strong>.<br>
    Montant prévisionnel : <strong>${currency(annual)} HT / an</strong>
    pour ${stations} poste(s).</p>
    <p>Lors du renouvellement, vos informations administratives et de facturation
    seront préremplies et devront être confirmées. Les références propres à la
    nouvelle commande (bon de commande / engagement) pourront être mises à jour.</p>
    <p><a href="${SPHOT_LOGIN_URL}">RENOUVELER MON ABONNEMENT</a></p>
    <p>Cordialement,<br>L’équipe SPHOT</p>`;
  await sendLifecycleMail({
    requestSnap,
    fieldName,
    subject: `SPHOT ADMIN — Échéance de votre abonnement à J-${days}`,
    html,
  });
}

async function expireAnnualSubscription(subscriptionDoc) {
  const db = admin.firestore();
  const subscription = subscriptionDoc.data() || {};
  const uid = cleanValue(subscription.adminUid || subscriptionDoc.id);
  const requestSnap = await getRequestByUid(uid);
  const requestData = requestSnap?.data() || {};
  const batch = db.batch();
  batch.set(subscriptionDoc.ref, {
    status: "awaiting_renewal",
    subscriptionExpiredAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  batch.set(db.collection("admins").doc(uid), {
    diffusionAccessGranted: false,
    diffusionAccessClosedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  if (requestSnap) {
    batch.set(requestSnap.ref, {
      accessPhase: "awaiting_renewal",
      "commercialTracking.status": "awaiting_renewal",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  await batch.commit();

  if (requestSnap) {
    const html = `
      <p>${escapeHtml(buildGreeting(requestData))}</p>
      <p>Votre abonnement annuel SPHOT ADMIN est arrivé à échéance.</p>
      <p><strong>Vos droits de diffusion sont suspendus dans l’attente du renouvellement.</strong></p>
      <p>Vos données et votre configuration restent conservées dans votre espace.</p>
      <p><a href="${SPHOT_LOGIN_URL}">RENOUVELER MON ABONNEMENT</a></p>
      <p>Cordialement,<br>L’équipe SPHOT</p>`;
    await sendLifecycleMail({
      requestSnap,
      fieldName: "subscriptionEndEmail",
      subject: "SPHOT ADMIN — Votre abonnement annuel est arrivé à échéance",
      html,
    });
  }
}

exports.processSubscriptionLifecycle = onSchedule(
    {
      schedule: "15 * * * *",
      timeZone: "Europe/Paris",
      region: REGION,
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async () => {
      const db = admin.firestore();
      const now = new Date();

      const trialDocs = [];
      const trialSnapshot = await db.collection("subscriptions")
          .where("status", "==", "trial").get();
      trialDocs.push(...trialSnapshot.docs);

      // Compatibilité avec l’ancien scheduler qui transformait l’essai expiré en overdue.
      const overdueSnapshot = await db.collection("subscriptions")
          .where("status", "==", "overdue").get();
      for (const doc of overdueSnapshot.docs) {
        const data = doc.data() || {};
        if (data.trialEndDate && !data.subscriptionStartDate) trialDocs.push(doc);
      }

      for (const doc of trialDocs) {
        const data = doc.data() || {};
        const end = toDate(data.trialEndDate);
        if (!end) continue;
        const ms = end.getTime() - now.getTime();
        const hours = ms / 3600000;
        if (hours <= 0) {
          await expireTrial(doc, now);
        } else if (hours <= 48 && !data.trialReminder48hSentAt) {
          await sendTrialReminder(doc);
        }
      }

      const activeSnapshot = await db.collection("subscriptions")
          .where("status", "==", "active").get();
      for (const doc of activeSnapshot.docs) {
        const data = doc.data() || {};
        const end = toDate(data.subscriptionEndDate);
        if (!end) continue;
        const days = (end.getTime() - now.getTime()) / 86400000;
        if (days <= 0) {
          await expireAnnualSubscription(doc);
          continue;
        }

        // Un seul rappel est envoyé par passage de seuil.
        if (days <= 7 && !data.renewalReminder7dSentAt) {
          await sendRenewalReminder(doc, 7);
          await doc.ref.set({
            renewalReminder7dSentAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
        } else if (days <= 30 && !data.renewalReminder30dSentAt) {
          await sendRenewalReminder(doc, 30);
          await doc.ref.set({
            renewalReminder30dSentAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
        } else if (days <= 60 && !data.renewalReminder60dSentAt) {
          await sendRenewalReminder(doc, 60);
          await doc.ref.set({
            renewalReminder60dSentAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
        }
      }
    },
);

async function nextOrderNumber(requestId, requestNumber, year) {
  const db = admin.firestore();
  const counterRef = db.collection("counters")
      .doc(safeDocumentId(`orders_${requestId}_${year}`));
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(counterRef);
    const next = Number(snap.data()?.lastNumber || 0) + 1;
    tx.set(counterRef, {
      lastNumber: next,
      year,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return `${requestNumber}-CMD-${year}-${String(next).padStart(2, "0")}`;
  });
}

exports.processAdminOrderCreated = onDocumentCreated(
    {
      document: "orders/{orderId}",
      region: REGION,
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const orderSnap = event.data;
      if (!orderSnap) return;
      const db = admin.firestore();
      const order = orderSnap.data() || {};
      const orderId = event.params.orderId;
      const requestId = cleanValue(order.requestId || order.adminUid);
      if (!requestId) return;
      const requestSnap = await getRequestByUid(requestId);
      if (!requestSnap) return;
      const requestData = requestSnap.data() || {};
      const requestNumber = cleanValue(
          order.dossierNumber || requestData.requestNumber,
          requestId,
      );
      const year = Number(order.subscriptionYear || yearInParis());
      const orderNumber = cleanValue(order.orderNumber) ||
          await nextOrderNumber(requestSnap.id, requestNumber, year);

      await orderSnap.ref.set({
        orderNumber,
        dossierNumber: requestNumber,
        requestId: requestSnap.id,
        status: cleanValue(order.status, "submitted"),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      const pdf = await createRegistryPdf({
        requestId: requestSnap.id,
        adminUid: cleanValue(order.adminUid || requestUid(requestData, requestSnap.id)),
        requestNumber,
        documentNumber: orderNumber,
        documentType: "subscription_order",
        category: "financial",
        subcategory: "commandes",
        title: "Enregistrement de la commande d’abonnement annuel",
        rubric: "Abonnement",
        statusLabel: "ENREGISTRÉE",
        introduction:
          "Votre commande d’abonnement annuel SPHOT ADMIN a bien été " +
          "enregistrée. Le présent document récapitule les éléments " +
          "transmis pour son traitement.",
        relatedOrderId: orderId,
        lines: [
          {heading: "Organisme payeur"},
          {label: "Organisation", value: order.billingOrganisation},
          {label: "SIRET", value: order.billingSiret},
          {heading: "Commande"},
          {label: "Nombre de postes", value: order.numberOfRescueStations},
          {label: "Prix unitaire HT", value:
            currency(order.unitPriceExclTax || DEFAULT_PRICE_PER_STATION_EXCL_TAX)},
          {label: "Montant HT", value: currency(order.totalExclTax)},
          {label: "TVA", value: `${Number(order.vatRate || DEFAULT_VAT_RATE)} %`},
          {label: "Montant TTC", value: currency(order.totalInclTax)},
          {heading: "Règlement"},
          {label: "Mode de règlement", value:
            order.paymentMethod === "card" ? "Carte bancaire" : "Facturation publique / Chorus Pro"},
          {label: "Bon de commande", value: order.purchaseOrderNumber},
          {label: "Engagement", value: order.engagementNumber},
          {label: "Code service Chorus", value: order.chorusServiceCode},
        ],
        notice:
          "Ce document atteste de l’enregistrement de la commande. Il ne " +
          "constitue pas une facture. La facturation, le règlement et " +
          "leurs références propres sont suivis dans des documents " +
          "distincts.",
      });

      // Prépare la future facture électronique sans l’émettre juridiquement.
      const invoiceRef = db.collection("invoices").doc();
      await invoiceRef.set({
        invoiceId: invoiceRef.id,
        requestId: requestSnap.id,
        adminUid: cleanValue(order.adminUid),
        organisationId: cleanValue(order.organisationId || order.adminUid),
        relatedOrderId: orderId,
        relatedOrderNumber: orderNumber,
        dossierNumber: requestNumber,
        invoiceNumber: null,
        status: "draft",
        customerType: order.paymentMethod === "card" ? "private_or_card" : "public",
        billingOrganisation: order.billingOrganisation || "",
        billingSiret: order.billingSiret || "",
        billingAddress: order.billingAddress || "",
        billingPostalCode: order.billingPostalCode || "",
        billingCity: order.billingCity || "",
        billingContactName: order.billingContactName || "",
        billingContactEmail: order.billingContactEmail || "",
        purchaseOrderNumber: order.purchaseOrderNumber || "",
        engagementNumber: order.engagementNumber || "",
        chorusServiceCode: order.chorusServiceCode || "",
        numberOfRescueStations: Number(order.numberOfRescueStations || 0),
        unitPriceExclTax: Number(order.unitPriceExclTax || DEFAULT_PRICE_PER_STATION_EXCL_TAX),
        subtotalExclTax: Number(order.totalExclTax || 0),
        vatRate: Number(order.vatRate || DEFAULT_VAT_RATE),
        vatAmount: Number(order.vatAmount || 0),
        totalInclTax: Number(order.totalInclTax || 0),
        paymentMethod: order.paymentMethod || "public_invoice",
        paymentStatus: order.paymentMethod === "card" ?
          "awaiting_card_payment" : "not_invoiced",
        electronicInvoiceStatus: "draft",
        chorusInvoiceId: null,
        chorusSubmittedAt: null,
        chorusStatus: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await orderSnap.ref.set({
        orderDocument: {
          documentNumber: orderNumber,
          storagePath: pdf.storagePath,
          downloadUrl: pdf.downloadUrl,
        },
        invoiceDraftId: invoiceRef.id,
      }, {merge: true});

      const email = recipientEmail(requestData);

      if (email) {
        await sendSphotMail(
            transporter(),
            {
              from: MAIL_FROM,
              to: email,
              subject:
                  "SPHOT ADMIN — Commande d’abonnement bien reçue",

              html: `
<p style="font-size:16px;line-height:1.6;">
  ${escapeHtml(buildGreeting(requestData))}
</p>

<p style="font-size:16px;line-height:1.6;">
  Votre commande d’abonnement annuel
  <strong>SPHOT ADMIN</strong>
  a bien été enregistrée.
</p>

<div style="
  margin:20px 0;
  padding:16px;
  border-left:4px solid #1e3a8a;
  border-radius:8px;
  background:#f3f6fb;
  font-size:14px;
  line-height:1.6;
">
  Référence :
  <strong style="color:#dc2626;">
    ${escapeHtml(orderNumber)}
  </strong>
  <br><br>
  Montant :
  <strong>
    ${escapeHtml(currency(order.totalExclTax))} HT
  </strong>
</div>

<p style="font-size:16px;line-height:1.6;">
  Le traitement de la facture électronique et du règlement
  sera suivi dans votre espace SPHOT ADMIN.
</p>

<div style="text-align:center;margin:30px 0;">
  <a
    href="${SPHOT_LOGIN_URL}"
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
    SE CONNECTER À SPHOT ADMIN
  </a>
</div>

<p style="
  margin-top:28px;
  font-size:15px;
  line-height:1.6;
">
  À bientôt sur SPHOT,<br>
  <strong>L'équipe SPHOT</strong>
</p>`,

              attachments: [
                {
                  filename: `${orderNumber}.pdf`,
                  href: pdf.downloadUrl,
                },
              ],
            },
        );
      }
    },
);

exports.activateApprovedAdminOrder = onDocumentUpdated(
    {
      document: "orders/{orderId}",
      region: REGION,
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const before = event.data?.before.data() || {};
      const after = event.data?.after.data() || {};
      if (cleanValue(before.status) === cleanValue(after.status)) return;
      if (!["approved", "paid"].includes(cleanValue(after.status))) return;
      if (after.subscriptionActivatedAt) return;

      const db = admin.firestore();
      const uid = cleanValue(after.adminUid);
      if (!uid) return;
      const start = new Date();
      const end = new Date(start);
      end.setFullYear(end.getFullYear() + 1);
      const batch = db.batch();
      batch.set(db.collection("subscriptions").doc(uid), {
        status: "active",
        subscriptionStartDate: admin.firestore.Timestamp.fromDate(start),
        subscriptionEndDate: admin.firestore.Timestamp.fromDate(end),
        billingCycle: "annual",
        currentOrderId: event.params.orderId,
        currentOrderNumber: after.orderNumber || null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      batch.set(db.collection("admins").doc(uid), {
        diffusionAccessGranted: true,
        diffusionAccessOpenedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      if (after.requestId) {
        batch.set(db.collection("adminRequests").doc(after.requestId), {
          accessPhase: "subscription_active",
          "commercialTracking.status": "subscription_active",
          "commercialTracking.subscriptionActivatedAt":
              admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      }
      batch.set(event.data.after.ref, {
        subscriptionActivatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      await batch.commit();
    },
);

exports.syncAdminDocumentRegistry = onSchedule(
    {
      schedule: "25 2 * * *",
      timeZone: "Europe/Paris",
      region: REGION,
      cpu: 1,
      memory: "256MiB",
    },
    async () => {
      const snapshot = await admin.firestore().collection("adminRequests").get();
      for (const doc of snapshot.docs) {
        const data = doc.data() || {};
        await registerLegacyAcknowledgement(doc.id, data);
        if (cleanValue(data.status).toLowerCase() === "approved") {
          await ensureRegistrationApprovalDocument(doc.id, data);
        }
      }
    },
);
