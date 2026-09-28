'use strict';

/**
 * Branded HTML for every email the system sends, in the warehouse app's own look ("Broadsheet":
 * paper ground, white sheet, ink text, a dark masthead with a cyan rule, serif type).
 *
 * Email clients are not browsers: layout is nested tables, every style is inline, no web fonts are
 * relied on (Georgia is the fallback for Source Serif 4), no images (they are blocked by default in
 * most clients, and a missing logo looks worse than none). Every piece of text is HTML-escaped — user
 * data (names, reasons, notes) ends up in here.
 *
 * content: {
 *   preheader   inbox preview line (hidden in the body)
 *   eyebrow     small caps label above the heading, e.g. "Approval needed"
 *   tone        'info' | 'success' | 'warning' | 'danger' — colours the eyebrow tag and the side rule
 *   heading     the one-line headline
 *   paragraphs  [string]  body copy
 *   code        a one-time code, shown large and spaced
 *   codeNote    line under the code, e.g. "Expires in 10 minutes"
 *   details     [[label, value]] — a two-column fact table
 *   quote       { label, text } — a free-text note (reason, review note), set apart
 *   button      { label, url } — one call to action
 *   footnote    small print under the sheet (security advice, why you got this)
 * }
 */

const C = {
  paper: '#f3f2f2',
  sheet: '#ffffff',
  ink: '#1a1a1a',
  muted: '#5c5c5c',
  rule: '#dedcdc',
  masthead: '#16181a',
  accent: '#0088b0',
  accentInk: '#006486',
  codeGround: '#eef6f9',
};

const TONES = {
  info: { fg: '#006486', bg: '#dceef4' },
  success: { fg: '#1c6b3a', bg: '#e1efe6' },
  warning: { fg: '#8a5a00', bg: '#f6ead2' },
  danger: { fg: '#a1262c', bg: '#f7e1e2' },
};

const FONT = "'Source Serif 4','Source Serif Pro',Georgia,'Times New Roman',serif";
const MONO = "'SFMono-Regular',Consolas,'Liberation Mono',Menlo,monospace";

const escapeHtml = (value) =>
  String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

function renderEmail(content, { appName }) {
  const tone = TONES[content.tone] ?? TONES.info;
  const e = escapeHtml;
  const parts = [];

  if (content.eyebrow) {
    parts.push(
      `<p style="margin:0 0 14px;"><span style="display:inline-block;border:1px solid ${tone.fg};background:${tone.bg};color:${tone.fg};font-family:${FONT};font-size:11px;font-weight:700;letter-spacing:1.2px;text-transform:uppercase;padding:3px 8px;">${e(content.eyebrow)}</span></p>`,
    );
  }
  parts.push(
    `<h1 style="margin:0 0 16px;font-family:${FONT};font-size:24px;line-height:1.3;font-weight:600;color:${C.ink};">${e(content.heading)}</h1>`,
  );
  for (const p of content.paragraphs ?? []) {
    parts.push(`<p style="margin:0 0 14px;font-family:${FONT};font-size:16px;line-height:1.6;color:${C.ink};">${e(p)}</p>`);
  }

  if (content.code) {
    const spaced = e(content.code).split('').join('&#8202;');
    parts.push(
      `<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:8px 0 20px;"><tr>` +
        `<td align="center" style="background:${C.codeGround};border:1px solid ${C.rule};border-top:3px solid ${C.accent};padding:22px 12px;">` +
        `<div style="font-family:${MONO};font-size:34px;line-height:1;font-weight:700;letter-spacing:10px;color:${C.ink};">${spaced}</div>` +
        (content.codeNote
          ? `<div style="margin-top:12px;font-family:${FONT};font-size:13px;color:${C.muted};">${e(content.codeNote)}</div>`
          : '') +
        `</td></tr></table>`,
    );
  }

  if (content.details?.length) {
    const rows = content.details
      .filter(([, value]) => value !== undefined && value !== null && value !== '')
      .map(
        ([label, value], i) =>
          `<tr><td valign="top" style="padding:10px 12px 10px 0;${i ? `border-top:1px solid ${C.rule};` : ''}font-family:${FONT};font-size:13px;color:${C.muted};white-space:nowrap;width:1%;">${e(label)}</td>` +
          `<td valign="top" style="padding:10px 0;${i ? `border-top:1px solid ${C.rule};` : ''}font-family:${FONT};font-size:15px;color:${C.ink};">${e(value)}</td></tr>`,
      )
      .join('');
    parts.push(
      `<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:6px 0 20px;border-top:2px solid ${C.ink};border-bottom:1px solid ${C.rule};">${rows}</table>`,
    );
  }

  if (content.quote?.text) {
    parts.push(
      `<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:0 0 20px;"><tr>` +
        `<td style="border-left:3px solid ${tone.fg};background:${C.paper};padding:12px 16px;">` +
        `<div style="font-family:${FONT};font-size:11px;font-weight:700;letter-spacing:1.2px;text-transform:uppercase;color:${C.muted};margin-bottom:4px;">${e(content.quote.label)}</div>` +
        `<div style="font-family:${FONT};font-size:15px;line-height:1.5;font-style:italic;color:${C.ink};">${e(content.quote.text)}</div>` +
        `</td></tr></table>`,
    );
  }

  if (content.button?.url) {
    parts.push(
      `<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 6px;"><tr>` +
        `<td style="background:${C.accentInk};">` +
        `<a href="${e(content.button.url)}" style="display:inline-block;padding:12px 22px;font-family:${FONT};font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;">${e(content.button.label)} &rarr;</a>` +
        `</td></tr></table>`,
    );
  }

  const year = new Date().getUTCFullYear();
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>${e(content.heading)}</title>
</head>
<body style="margin:0;padding:0;background:${C.paper};-webkit-text-size-adjust:100%;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:${C.paper};">${e(content.preheader ?? content.heading)}</div>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:${C.paper};">
<tr><td align="center" style="padding:28px 12px;">
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="max-width:580px;">
<tr><td style="background:${C.masthead};border-bottom:3px solid ${C.accent};padding:16px 28px;">
<span style="font-family:${FONT};font-size:18px;font-weight:600;letter-spacing:.3px;color:#ffffff;">${e(appName)}</span>
</td></tr>
<tr><td style="background:${C.sheet};border:1px solid ${C.rule};border-top:0;border-left:4px solid ${tone.fg};padding:32px 28px 26px;">
${parts.join('\n')}
</td></tr>
<tr><td style="padding:18px 6px 0;font-family:${FONT};font-size:12px;line-height:1.6;color:${C.muted};">
${content.footnote ? `<p style="margin:0 0 8px;">${e(content.footnote)}</p>` : ''}
<p style="margin:0;">This is an automated message from ${e(appName)} &middot; please do not reply. &copy; ${year}</p>
</td></tr>
</table>
</td></tr>
</table>
</body>
</html>`;
}

/** The same message as plain text, for clients that don't show HTML (and for SMS-length logs). */
function renderText(content, { appName }) {
  const lines = [content.heading, ''];
  for (const p of content.paragraphs ?? []) lines.push(p, '');
  if (content.code) lines.push(`    ${content.code}`, ...(content.codeNote ? [content.codeNote] : []), '');
  for (const [label, value] of content.details ?? []) {
    if (value !== undefined && value !== null && value !== '') lines.push(`${label}: ${value}`);
  }
  if (content.details?.length) lines.push('');
  if (content.quote?.text) lines.push(`${content.quote.label}: "${content.quote.text}"`, '');
  if (content.button?.url) lines.push(`${content.button.label}: ${content.button.url}`, '');
  if (content.footnote) lines.push(content.footnote, '');
  lines.push(`— ${appName}`);
  return lines.join('\n');
}

module.exports = { renderEmail, renderText, escapeHtml };
