'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { renderEmail, renderText } = require('../src/core/email-template');

const content = { heading: 'Adjustment approved', paragraphs: ['Your request <ADJ-1> was approved.'], code: '123456', button: { label: 'Open', url: 'https://x.example' } };

describe('branded emails', () => {
  it('wear the company brand: colour, fonts, tagline, signature and letterhead line', () => {
    const html = renderEmail(content, {
      appName: 'Acme & Sons',
      tagline: 'Wholesale · Mbabane',
      accent: '#F2C200', // a bright yellow: buttons must still carry readable white text
      headingFont: "'Playfair Display',Georgia,serif",
      bodyFont: "'Lato',Arial,sans-serif",
      signature: 'Kind regards,\nThe <Acme> team',
      contact: ['Plot 12, Mbabane', '+268 2404 0000'],
      registration: 'Reg. 123/2020 · VAT 456',
    });
    assert.match(html, /Acme &amp; Sons/);
    assert.match(html, /Wholesale · Mbabane/);
    assert.match(html, /border-bottom:3px solid #f2c200/);
    assert.match(html, /font-family:'Playfair Display'/);
    assert.match(html, /font-family:'Lato'/);
    assert.match(html, /Kind regards,<br>The &lt;Acme&gt; team/, 'signature keeps its lines and is escaped');
    assert.match(html, /Plot 12, Mbabane &middot; \+268 2404 0000/);
    assert.match(html, /Reg\. 123\/2020/);
    assert.match(html, /Your request &lt;ADJ-1&gt;/);

    // The button's background is the brand colour darkened until white text passes 4.5:1.
    const bg = /<td style="background:(#[0-9a-f]{6});"><a /.exec(html)[1];
    const lum = (hex) => {
      const ch = (i) => {
        const c = parseInt(hex.slice(i, i + 2), 16) / 255;
        return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
      };
      return 0.2126 * ch(1) + 0.7152 * ch(3) + 0.0722 * ch(5);
    };
    assert.ok(1.05 / (lum(bg) + 0.05) >= 4.5, `white on ${bg} is readable`);

    const text = renderText(content, { appName: 'Acme', signature: 'Kind regards', contact: ['+268 1'] });
    assert.match(text, /Kind regards\n\n— Acme\n\+268 1/);
  });

  it('fall back to the built-in look without branding', () => {
    const html = renderEmail(content, { appName: 'Warehouse System' });
    assert.match(html, /#6d60c6/);
    assert.match(html, /Source Serif 4/);
    assert.doesNotMatch(html, /undefined|null/);
  });
});
