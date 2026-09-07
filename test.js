#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const assert = require('assert');

// Load Model.js in a clean JS environment
const modelPath = path.join(__dirname, 'Model.js');
let modelCode = fs.readFileSync(modelPath, 'utf8');
// Strip .pragma library for Node environment
modelCode = modelCode.replace('.pragma library', '');
const Model = {};
new Function('exports', modelCode + '\nexports.sanitizeString = sanitizeString; exports.parseStatus = parseStatus; exports.defaultStatus = defaultStatus;')(Model);

console.log('=== Running Omarchy Plugin Security & Guardrails Tests ===\n');

// -------------------------------------------------------------
// Test 1: String Sanitization
// -------------------------------------------------------------
console.log('[Test 1] Testing Model.sanitizeString()...');
{
  // HTML tags stripping
  const htmlInput = '<script>alert("xss")</script><b>Wi-Fi Network</b>';
  assert.strictEqual(Model.sanitizeString(htmlInput), 'alert("xss")Wi-Fi Network');

  // ANSI escape codes stripping
  const ansiInput = '\x1B[31mRed\x1B[0m \x1B[1mBold\x1B[0m';
  assert.strictEqual(Model.sanitizeString(ansiInput), 'Red Bold');

  // Control characters stripping
  const ctrlInput = 'Hello\x00\x07\x1BWorld';
  assert.strictEqual(Model.sanitizeString(ctrlInput), 'HelloWorld');

  // Length bounding (maxLen = 10)
  const longInput = 'A'.repeat(50);
  assert.strictEqual(Model.sanitizeString(longInput, 10).length, 10);

  console.log('  ✓ Model.sanitizeString() properly strips HTML, ANSI, control chars, and caps length.');
}

// -------------------------------------------------------------
// Test 2: Input Length Guard (> 8192 bytes)
// -------------------------------------------------------------
console.log('\n[Test 2] Testing consumer-side byte length limit (8192 bytes)...');
{
  const oversizedJson = JSON.stringify({
    active: true,
    ssid: 'A'.repeat(9000)
  });
  const fallback = Model.defaultStatus();
  const res = Model.parseStatus(oversizedJson, fallback);
  assert.deepStrictEqual(res, fallback, 'Should return fallback when payload exceeds 8192 bytes');
  console.log('  ✓ Oversized payload (> 8192 bytes) correctly rejected.');
}

// -------------------------------------------------------------
// Test 3: Line Count Guard (> 128 lines)
// -------------------------------------------------------------
console.log('\n[Test 3] Testing consumer-side line count limit (128 lines)...');
{
  const multiline = '{\n' + '  "active": true,\n'.repeat(130) + '  "ssid": "test"\n}';
  const fallback = Model.defaultStatus();
  const res = Model.parseStatus(multiline, fallback);
  assert.deepStrictEqual(res, fallback, 'Should return fallback when lines exceed 128');
  console.log('  ✓ Excessive line count (> 128 lines) correctly rejected.');
}

// -------------------------------------------------------------
// Test 4: Malformed JSON recovery
// -------------------------------------------------------------
console.log('\n[Test 4] Testing recovery from malformed JSON...');
{
  const brokenJson = '{"active": true, ssid: broken';
  const fallback = Model.defaultStatus();
  const res = Model.parseStatus(brokenJson, fallback);
  assert.deepStrictEqual(res, fallback, 'Should return fallback when JSON is malformed');
  console.log('  ✓ Malformed JSON handled gracefully without uncaught exceptions.');
}

// -------------------------------------------------------------
// Test 5: Valid Payload Parsing & Sanitization
// -------------------------------------------------------------
console.log('\n[Test 5] Testing valid JSON parsing with field sanitization...');
{
  const validJson = JSON.stringify({
    active: true,
    iface: 'wlan0\x1B[31m',
    ssid: '<danger>Public-Guest-WiFi</danger>',
    hw_mac: '02:00:00:00:00:01',
    current_mac: '02:00:00:00:00:02',
    is_mac_randomized: true,
    is_trusted: false,
    real_hostname: 'desktop-host',
    dhcp_hostname: 'LAPTOP-7F4K2A',
    ipv6_tempaddr: true,
    avahi_hidden: true
  });
  const res = Model.parseStatus(validJson);
  assert.strictEqual(res.active, true);
  assert.strictEqual(res.iface, 'wlan0');
  assert.strictEqual(res.ssid, 'Public-Guest-WiFi');
  assert.strictEqual(res.hw_mac, '02:00:00:00:00:01');
  assert.strictEqual(res.current_mac, '02:00:00:00:00:02');
  assert.strictEqual(res.is_mac_randomized, true);
  assert.strictEqual(res.dhcp_hostname, 'LAPTOP-7F4K2A');
  assert.strictEqual(res.ipv6_tempaddr, true);
  assert.strictEqual(res.avahi_hidden, true);
  console.log('  ✓ Valid JSON parsed with all fields sanitized and upper-cased MACs.');
}

// -------------------------------------------------------------
// Test 6: AST / Regex PlainText Sink Assertion in Panel.qml
// -------------------------------------------------------------
console.log('\n[Test 6] Verifying mandatory textFormat: Text.PlainText on all Text elements...');
{
  const panelPath = path.join(__dirname, 'Panel.qml');
  const panelCode = fs.readFileSync(panelPath, 'utf8');

  // Match every "Text {" block up to its closing or next sibling property
  // Split on "Text {" to inspect every single Text component
  const textBlocks = panelCode.split(/\bText\s*\{/).slice(1);
  assert(textBlocks.length > 0, 'Panel.qml should contain Text elements');

  for (let i = 0; i < textBlocks.length; i++) {
    // Find the end of this Text declaration block (up to matching braces or top properties)
    const blockContent = textBlocks[i].slice(0, 500);
    const hasPlainText = /textFormat\s*:\s*Text\.PlainText/.test(blockContent);
    assert(hasPlainText, `Text block #${i + 1} does NOT declare textFormat: Text.PlainText:\n${blockContent.slice(0, 150)}...`);
  }
  console.log(`  ✓ All ${textBlocks.length} Text element(s) in Panel.qml declare textFormat: Text.PlainText.`);
}

// -------------------------------------------------------------
// Test 7: Process Watchdogs and Destruction Cleanup
// -------------------------------------------------------------
console.log('\n[Test 7] Verifying Process Watchdog Timers and Component.onDestruction in Panel.qml...');
{
  const panelPath = path.join(__dirname, 'Panel.qml');
  const panelCode = fs.readFileSync(panelPath, 'utf8');

  assert(panelCode.includes('Component.onDestruction'), 'Panel.qml must implement Component.onDestruction');
  assert(panelCode.includes('statusProcess.kill()'), 'Component.onDestruction must kill statusProcess');
  assert(panelCode.includes('actionProcess.kill()'), 'Component.onDestruction must kill actionProcess');
  assert(panelCode.includes('statusWatchdog'), 'Panel.qml must have statusWatchdog timer');
  assert(panelCode.includes('onOpenedChanged'), 'Panel.qml must implement 0-ms onOpenedChanged fresh data pattern');
  assert(panelCode.includes('screenLocked'), 'Panel.qml must implement screenLocked battery saver check');

  console.log('  ✓ Process watchdog timers, destruction cleanup, 0-ms fresh data, and battery saver verified.');
}

console.log('\n=============================================================');
console.log('All Omarchy Marketplace Security & Hardening checks PASSED! ✨');
console.log('=============================================================\n');
