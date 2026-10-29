const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('Sources/translate/PhoneStudyPage.swift', 'utf8');
const code = source.slice(source.indexOf('const imageCache = new Map();'), source.indexOf('// Two related photos, like the Mac card.'));
let requests = 0;
const context = vm.createContext({
  setTimeout: () => 0,
  api: async () => { requests++; return { json: async () => ['https://example.com/image'] }; },
  Image: class { set src(value) { queueMicrotask(() => this.onload()); } },
});
(async () => {
  await vm.runInContext(code + `
    (async () => {
      await Promise.all([prepareImages('one'), prepareImages('one')]);
      for (let i = 0; i < 25; i++) await prepareImages(String(i));
      if (imageCache.size !== 20) throw new Error('cache exceeds 20 entries');
    })()`, context);
  assert.strictEqual(requests, 26, 'duplicate requests must share a lookup');
  console.log('phone image prefetch check passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
