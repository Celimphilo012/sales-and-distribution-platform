'use strict';

/**
 * The approved brand fonts an administrator can choose (Settings → Branding → Typography).
 *
 * A closed list on purpose: every entry is a Google Font the console can load, and each carries the
 * CSS stack emails fall back to (email clients rarely load web fonts, so the second and later names
 * are what most recipients actually see). The console keeps the same list (copied — no shared code).
 */
const BRAND_FONTS = {
  Inter: "'Inter',Arial,Helvetica,sans-serif",
  Roboto: "'Roboto',Arial,Helvetica,sans-serif",
  'Open Sans': "'Open Sans',Arial,Helvetica,sans-serif",
  Lato: "'Lato',Arial,Helvetica,sans-serif",
  Montserrat: "'Montserrat',Arial,Helvetica,sans-serif",
  Poppins: "'Poppins',Arial,Helvetica,sans-serif",
  'Nunito Sans': "'Nunito Sans',Arial,Helvetica,sans-serif",
  'Source Sans 3': "'Source Sans 3','Source Sans Pro',Arial,Helvetica,sans-serif",
  'Work Sans': "'Work Sans',Arial,Helvetica,sans-serif",
  'IBM Plex Sans': "'IBM Plex Sans',Arial,Helvetica,sans-serif",
  'DM Sans': "'DM Sans',Arial,Helvetica,sans-serif",
  Manrope: "'Manrope',Arial,Helvetica,sans-serif",
  Merriweather: "'Merriweather',Georgia,'Times New Roman',serif",
  'Playfair Display': "'Playfair Display',Georgia,'Times New Roman',serif",
  'Source Serif 4': "'Source Serif 4','Source Serif Pro',Georgia,'Times New Roman',serif",
};

const DEFAULT_FONT = 'Inter';

module.exports = { BRAND_FONTS, DEFAULT_FONT };
