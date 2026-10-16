/* eslint-disable max-len, require-jsdoc, valid-jsdoc, indent, object-curly-spacing, operator-linebreak */
"use strict";

const PDFDocument = require("pdfkit");

function cleanValue(value, fallback = "") {
  const result = (value ?? "").toString().trim();
  return result || fallback;
}

// Référentiel documentaire Admin SPHOT extrait sans modifier le rendu
// des accusés de réception, décisions, périodes d'essai, etc.
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

module.exports = {simplePdfBuffer};
