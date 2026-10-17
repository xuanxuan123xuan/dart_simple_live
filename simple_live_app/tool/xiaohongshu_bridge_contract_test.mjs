// Executes the actual WebView request scripts with a mocked page runtime.
// No request leaves this process.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const source = fs.readFileSync(new URL('../lib/services/xiaohongshu_web_session_service.dart', import.meta.url), 'utf8');

function scriptTemplate(source, methodName) {
  const method = source.match(new RegExp(String.raw`^  static String ${methodName}\([\s\S]*?^  }\r?$`, 'm'))?.[0];
  assert.ok(method, `Missing Dart method: ${methodName}`);
  const templates = [...method.matchAll(/return '''([\s\S]*?)''';/g)];
  assert.equal(templates.length, 1, `Expected one script template in ${methodName}`);
  return templates[0][1];
}

const scripts = {
  room: scriptTemplate(source, 'buildRequestScript'),
  profile: scriptTemplate(source, 'buildHostRequestScript'),
};
const roomArgs = {
  id: 'room-probe',
  path: '/api/sns/red/live/h5/v1/interaction/get_simple_interaction',
  query: {roomId: '570493541297105186', startTimestamp: 0, needViewer: true},
};
const profileArgs = {id: 'profile-probe', hostId: '5a1234567890abcdef123456'};
const paths = {
  room: `${roomArgs.path}?roomId=570493541297105186&startTimestamp=0&needViewer=true`,
  profile: '/api/sns/web/v1/user/hover_card?target_user_id=5a1234567890abcdef123456&image_formats=jpg%2Cwebp&xsec_source=pc_hovercard&xsec_token=',
};
const origins = {room: 'https://live-room.xiaohongshu.com', profile: 'https://edith.xiaohongshu.com'};
const bridges = ['webview2', 'webkit', 'ohos', 'inappwebview'];
let cases = 0;

function bridgeWindow(bridge, messages) {
  const postMessage = text => messages.push(JSON.parse(text));
  switch (bridge) {
    case 'webview2': return {chrome: {webview: {postMessage}}};
    case 'webkit': return {webkit: {messageHandlers: {XiaohongshuBridge: {postMessage}}}};
    case 'ohos': return {XiaohongshuBridge: {postMessage}};
    case 'inappwebview': return {flutter_inappwebview: {callHandler: (name, text) => {
      assert.equal(name, 'XiaohongshuBridge');
      postMessage(text);
    }}};
    default: throw new Error(`Unknown bridge: ${bridge}`);
  }
}

async function checkRequest(kind, mode, bridge = 'webview2') {
  const args = kind === 'room' ? roomArgs : profileArgs;
  const messages = [];
  const signed = [];
  const fetched = [];
  const headers = Object.freeze({'X-S': 'mock-signature', 'X-T': 'mock-timestamp', 'X-S-Common': 'preserve-me'});
  const body = mode === 'business-rejected'
    ? {success: false, code: -101, msg: '登录已过期', data: null}
    : {success: mode !== 'http-rejected', data: {comments: []}};
  const window = bridgeWindow(bridge, messages);
  let fingerprintCalls = 0;
  window.f = () => {
    fingerprintCalls++;
    return {f: 'mock-fingerprint'};
  };
  if (mode !== 'missing-signer') {
    window[kind === 'room' ? 'sign' : '_webmsxyw'] = (path, body) => {
      signed.push({path, body});
      return mode === 'invalid-headers' ? null : headers;
    };
  }
  let waits = 0;
  await vm.runInNewContext(scripts[kind].replace('$payload', JSON.stringify(args)), {
    window, URLSearchParams,
    setTimeout: callback => { waits++; callback(); },
    fetch: async (url, options) => {
      fetched.push({url, options});
      if (mode === 'network-error') throw new Error('offline');
      return {ok: mode !== 'http-rejected', status: mode === 'http-rejected' ? 406 : 200,
        json: async () => body};
    },
  });

  const label = `${kind}/${mode}/${bridge}`;
  assert.equal(messages.length, 1, label);
  assert.equal(messages[0].id, args.id, label);
  if (mode === 'missing-signer') {
    assert.equal(waits, 100, label);
    assert.equal(signed.length, 0, label);
  } else {
    assert.equal(signed.length, 1, `${label}: no script-level signing retry`);
    assert.equal(signed[0].path, paths[kind], `${label}: sign the full path and query`);
    assert.equal(signed[0].body, undefined, label);
  }
  if (mode === 'missing-signer' || mode === 'invalid-headers') {
    assert.equal(fetched.length, 0, label);
    assert.deepEqual(messages[0], {id: args.id, ok: false, status: 406}, label);
  } else {
    assert.equal(fetched.length, 1, `${label}: no script-level HTTP or business retry`);
    const {url, options} = fetched[0];
    assert.equal(url, origins[kind] + paths[kind], label);
    assert.equal(options.method, 'GET', label);
    assert.equal(options.credentials, 'include', label);
    assert.equal(options.body, undefined, label);
    if (kind === 'profile') {
      assert.equal(options.redirect, 'error', label);
      assert.equal(options.headers, headers, `${label}: preserve the signer's header object`);
      assert.equal(fingerprintCalls, 0, label);
    } else {
      assert.deepEqual({...options.headers}, {...headers, f: 'mock-fingerprint'}, label);
      assert.equal(fingerprintCalls, 1, label);
    }
    if (mode === 'network-error') {
      assert.deepEqual(messages[0], {id: args.id, ok: false, status: 0}, label);
    } else {
      assert.deepEqual(messages[0], {id: args.id, ok: mode !== 'http-rejected',
        status: mode === 'http-rejected' ? 406 : 200, data: body}, label);
    }
  }
  cases++;
}

for (const kind of ['room', 'profile']) {
  for (const bridge of bridges) await checkRequest(kind, 'signed', bridge);
  for (const mode of ['missing-signer', 'http-rejected', 'business-rejected', 'network-error']) {
    await checkRequest(kind, mode);
  }
}
await checkRequest('profile', 'invalid-headers');

const desktopSource = fs.readFileSync(new URL('../lib/services/xiaohongshu_desktop_webview_window_host.dart', import.meta.url), 'utf8');
const documentTemplate = scriptTemplate(desktopSource, 'buildDocumentStartScript');
for (const bridge of ['webview2', 'webkit']) {
  for (const readyState of ['loading', 'complete']) {
    const messages = [];
    const cookies = [];
    const listeners = [];
    const location = {href: 'https://www.xiaohongshu.com/user/profile/5a1234567890abcdef123456'};
    const entries = [['a1', 'cookie=value'], ['web_session', 'abc==/+']];
    const document = {
      readyState,
      documentElement: {},
      querySelectorAll: () => [],
      addEventListener: (event, listener) => {
        assert.equal(event, 'DOMContentLoaded');
        listeners.push(listener);
      },
      set cookie(value) { cookies.push(value); },
    };
    vm.runInNewContext(documentTemplate.replace('$encoded', JSON.stringify(entries)), {
      window: bridgeWindow(bridge, messages), document, location,
      MutationObserver: class { observe() {} },
    });
    assert.deepEqual(cookies, entries.map(([name, value]) =>
      `${name}=${value}; path=/; domain=.xiaohongshu.com; Secure; SameSite=Lax`));
    if (readyState === 'loading') {
      assert.equal(messages.length, 0, `${bridge}: wait for the initial document`);
      for (const listener of listeners) listener();
    }
    assert.deepEqual(messages, [{type: 'xhs_document_ready', url: location.href}],
      `${bridge}/${readyState}: notify the native session once`);
    cases++;
  }
}

console.log(`WebView JavaScript contract: ${cases} cases passed`);
