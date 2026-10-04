// Browser integration test. Set AFTERLIGHT_DEMO_URL for localhost or live Pages.
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const base = process.env.AFTERLIGHT_DEMO_URL || 'http://127.0.0.1:8765/';
const out = process.env.AFTERLIGHT_WEB_REPORT_DIR || path.resolve('build/web-qa');
const windows = 'https://github.com/MOYISEY/poslesvet/releases/download/v0.2.0/Poslesvet-Windows-x64.zip';
fs.mkdirSync(out, { recursive: true });

(async () => {
  const browser = await chromium.launch({ headless: true, ...(process.env.BROWSER_EXECUTABLE ? { executablePath: process.env.BROWSER_EXECUTABLE } : {}) });
  const checks = [], errors = [];
  let current;
  const check = (value, name) => { assert.ok(value, name); checks.push(name); };
  try {
    const missing = await browser.newContext({ viewport: { width: 1366, height: 768 } });
    await missing.addInitScript(() => {
      const original = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function (type, ...args) {
        return /^(experimental-)?webgl2$/i.test(type) ? null : original.call(this, type, ...args);
      };
    });
    const blocked = await missing.newPage(); current = blocked;
    const missingRequests = [];
    blocked.on('request', r => missingRequests.push(r.url()));
    blocked.on('pageerror', e => errors.push(e.message));
    await blocked.goto(base);
    await blocked.locator('#fallback:not([hidden])').waitFor();
    check(await blocked.locator('#fallback-title').textContent() === 'Для браузерной версии нужен WebGL2', 'No-WebGL2 uses the exact Russian heading');
    const download = blocked.locator('#fallback a');
    check(await download.isVisible() && await download.getAttribute('href') === windows, 'Fallback offers the published Windows build');
    check(await blocked.locator('#fallback').evaluate(el => !el.closest('canvas')), 'Fallback lives outside canvas');
    check(!missingRequests.some(url => /\.wasm(?:\?|$)/.test(url)), 'Unsupported browser does not download the WebAssembly game');
    check(!await blocked.locator('#status-notice').isVisible(), 'Generic English Godot error is hidden');
    await blocked.screenshot({ path: path.join(out, 'no-webgl2.png') });
    await blocked.setViewportSize({ width: 390, height: 640 });
    check(await download.isVisible(), 'Fallback download remains visible on a narrow viewport');
    await blocked.screenshot({ path: path.join(out, 'no-webgl2-narrow.png') });
    await missing.close();

    const normal = await browser.newContext({ viewport: { width: 1366, height: 768 } });
    const page = await normal.newPage(); current = page;
    page.on('pageerror', e => errors.push(e.message));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    await page.goto(base + '?qa=1');
    await page.waitForFunction(() => window.__afterlight?.modal === 'welcome', null, { timeout: 90000 });
    check(!await page.locator('#fallback').isVisible(), 'WebGL2 browser loads the normal game');
    check(await page.locator('#windows-download').isVisible() && await page.locator('#windows-download').getAttribute('href') === windows, 'Normal game keeps a small Windows link');
    const rect = await page.locator('#canvas').boundingBox();
    check(rect.width === 1366 && rect.height === 768 && rect.x === 0 && rect.y === 0, 'Shell preserves the full-size canvas');
    await page.keyboard.press('Enter');
    await page.keyboard.press('Tab');
    await page.keyboard.press('Digit1');
    await page.keyboard.press('Space');
    await page.waitForFunction(() => window.__afterlight?.state.turn === 1);
    check(true, 'Keyboard starts tutorial and confirms one turn');
    await page.waitForTimeout(750);
    await page.keyboard.press('F11');
    await page.waitForFunction(() => document.fullscreenElement?.id === 'canvas');
    check(true, 'F11 enters canvas fullscreen');
    await page.keyboard.press('F11');
    await page.waitForFunction(() => document.fullscreenElement === null);
    check(true, 'F11 exits fullscreen');
    await page.keyboard.press('KeyZ');
    await page.waitForFunction(() => window.__afterlight?.state.turn === 0);
    check(true, 'Keyboard undo works after fullscreen');
    await page.screenshot({ path: path.join(out, 'normal-game.png') });
    check(errors.length === 0, 'Normal startup has no browser errors');
    await normal.close();
  } catch (error) {
    errors.push(error.stack);
    await current?.screenshot({ path: path.join(out, 'failure.png') }).catch(() => {});
  } finally {
    const report = { url: base, checks, errors, browser: browser.version(), no_webgl2: 'Simulated by returning null from webgl2 getContext; normal browser uses actual WebGL2', input: 'Playwright keyboard; not a human playtest' };
    fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify({ checks: checks.length, errors }));
    await browser.close();
    if (errors.length) process.exitCode = 1;
  }
})();
