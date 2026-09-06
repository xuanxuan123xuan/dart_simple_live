// Run with node --test; OHOS_TYPESCRIPT_PATH points to the SDK's typescript.js.
// Execute the actual ArkTS bridge with native calls stubbed at its boundary.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.OHOS_TYPESCRIPT_PATH || 'typescript');

function fixture() {
  const calls = [];
  let size = { width: 1920, height: 1080 };
  const native = {
    init() {},
    getSurfaceSize: () => ({ ...size }),
    reconfigureSurface: async (width, height, generation) => {
      calls.push(['resize', width, height, generation]);
      size = { width, height };
    },
    switchSurface: async (id, generation, width, height) => {
      calls.push(['switch', id, generation, width, height]);
      if (width !== undefined) size = { width, height };
    },
  };
  const source = fs.readFileSync(path.join(__dirname,
    '../ohos/entry/src/main/ets/plugins/OhosMpvPlugin.ets'), 'utf8');
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
  }).outputText;
  const exports = {};
  vm.runInNewContext(compiled, {
    exports,
    require(name) {
      if (name === 'libmpv_napi.so') return { default: native };
      if (name === '@kit.PerformanceAnalysisKit') {
        return { hilog: { info() {}, error() {} } };
      }
      if (name === '@ohos/flutter_ohos') return {};
      if (name === '../pip/OhosPipManager') return {};
      throw new Error(`Unexpected runtime dependency: ${name}`);
    },
  });
  const plugin = new exports.default({});
  plugin.textureRegistry = {
    getTextureId: () => 4,
    registerTexture: () => ({ getSurfaceId: () => '100' }),
  };
  const invoke = (method, args = {}) => new Promise((resolve, reject) => {
    plugin.onMethodCall({ method, argument: key => ({ generation: 1, ...args })[key] }, {
      success: resolve,
      error: (code, message) => reject(new Error(`${code}: ${message}`)),
      notImplemented: () => reject(new Error('Not implemented')),
    });
  });
  return { plugin, invoke, calls, native };
}

test('PiP restore explicitly restores the Flutter buffer size', async () => {
  const { plugin, invoke, calls } = fixture();
  await invoke('create');
  await invoke('reconfigureSurface', { width: 1280, height: 720 });
  plugin.useOutputSurface('200', 320, 180);
  plugin.useOutputSurface('200', 480, 270);
  plugin.restoreOutputSurface();
  assert.deepEqual(calls.at(-1), ['switch', '100', 1, 1280, 720]);
});

test('stream geometry during PiP is deferred until Flutter is restored', async () => {
  const { plugin, invoke, calls } = fixture();
  await invoke('create');
  plugin.useOutputSurface('200', 320, 180);
  await invoke('reconfigureSurface', { width: 720, height: 1280 });
  assert.equal(calls.filter(call => call[0] === 'resize').length, 0);
  const size = await invoke('getSurfaceSize');
  assert.equal(size.width, 720);
  assert.equal(size.height, 1280);
  plugin.restoreOutputSurface();
  assert.deepEqual(calls.at(-1), ['switch', '100', 1, 720, 1280]);
  await invoke('reconfigureSurface', { width: 1440, height: 1080 });
  assert.deepEqual(calls.at(-1), ['resize', 1440, 1080, 1]);
});

test('invalid PiP-time geometry cannot corrupt the restore dimensions', async () => {
  const { plugin, invoke, calls } = fixture();
  await invoke('create');
  plugin.useOutputSurface('200', 320, 180);
  await assert.rejects(invoke('reconfigureSurface', { width: NaN, height: 720 }),
    /Invalid Flutter surface dimensions/);
  plugin.restoreOutputSurface();
  assert.deepEqual(calls.at(-1), ['switch', '100', 1, 1920, 1080]);
});

test('main-output size queries report native state after a failed resize', async () => {
  const { invoke, native } = fixture();
  await invoke('create');
  native.reconfigureSurface = async () => { throw new Error('surface busy'); };
  await assert.rejects(invoke('reconfigureSurface', { width: 720, height: 1280 }));
  const size = await invoke('getSurfaceSize');
  assert.equal(size.width, 1920);
  assert.equal(size.height, 1080);
});

test('failed PiP handoff releases the deferred main-surface state', async () => {
  const { plugin, invoke, calls, native } = fixture();
  await invoke('create');
  native.switchSurface = async (id, generation, width, height) => {
    calls.push(['switch-failed', id, generation, width, height]);
    throw new Error('surface unavailable');
  };
  plugin.useOutputSurface('200', 320, 180);
  await new Promise(resolve => setImmediate(resolve));
  await invoke('reconfigureSurface', { width: 720, height: 1280 });
  assert.deepEqual(calls.at(-1), ['resize', 720, 1280, 1]);
});

test('failed PiP restore keeps main-surface updates deferred', async () => {
  const { plugin, invoke, calls, native } = fixture();
  await invoke('create');
  plugin.useOutputSurface('200', 320, 180);
  native.switchSurface = async (id, generation, width, height) => {
    calls.push(['switch-failed', id, generation, width, height]);
    throw new Error('surface unavailable');
  };
  plugin.restoreOutputSurface();
  await new Promise(resolve => setImmediate(resolve));
  await invoke('reconfigureSurface', { width: 720, height: 1280 });
  assert.equal(calls.some(call => call[0] === 'resize'), false);
});

test('failed PiP resize retains an already active PiP output', async () => {
  const { plugin, invoke, calls, native } = fixture();
  await invoke('create');
  plugin.useOutputSurface('200', 320, 180);
  await new Promise(resolve => setImmediate(resolve));
  native.switchSurface = async () => { throw new Error('resize failed'); };
  plugin.useOutputSurface('200', 480, 270);
  await new Promise(resolve => setImmediate(resolve));
  await invoke('reconfigureSurface', { width: 720, height: 1280 });
  assert.equal(calls.some(call => call[0] === 'resize'), false);
});
