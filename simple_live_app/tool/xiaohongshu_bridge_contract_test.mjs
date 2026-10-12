// Executes the actual WebView request script with a mocked page runtime.
// No request leaves this process.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source = fs.readFileSync(new URL('../lib/services/xiaohongshu_web_session_service.dart', import.meta.url), 'utf8');
const template = source.match(/return '''([\s\S]*?)''';/)[1];
const args = {id: 'probe', path: '/api/sns/red/live/h5/v1/interaction/get_simple_interaction', query: {roomId: '570493541297105186', startTimestamp: 0, needViewer: true}};
let cases = 0;
for (const mode of ['signed', 'missing-sign', 'rejected']) {
  const messages = [];
  let requested = false;
  const window = {
    XiaohongshuBridge: {postMessage: text => messages.push(JSON.parse(text))},
    f: () => ({f: 'mock-fingerprint'}),
  };
  if (mode !== 'missing-sign') window.sign = (path, body) => {
    assert.equal(body, undefined);
    assert.equal(path, args.path + '?roomId=570493541297105186&startTimestamp=0&needViewer=true');
    return {'x-s': 'mock-signature', 'x-t': 'mock-timestamp'};
  };
  await vm.runInNewContext(template.replace('$payload', JSON.stringify(args)), {
    window, URLSearchParams,
    setTimeout: callback => callback(),
    fetch: async (url, options) => {
      requested = true;
      assert.equal(new URL(url).origin, 'https://live-room.xiaohongshu.com');
      assert.equal(options.method, 'GET');
      assert.equal(options.credentials, 'include');
      assert.equal(options.body, undefined);
      assert.deepEqual({...options.headers}, {'x-s': 'mock-signature', 'x-t': 'mock-timestamp', f: 'mock-fingerprint'});
      return {ok: mode !== 'rejected', status: mode === 'rejected' ? 406 : 200,
        json: async () => ({success: mode !== 'rejected', data: {comments: []}})};
    },
  });
  assert.equal(messages.length, 1);
  assert.equal(messages[0].id, args.id);
  assert.equal(messages[0].ok, mode === 'signed');
  assert.equal(requested, mode !== 'missing-sign');
  if (mode !== 'signed') assert.equal(messages[0].status, 406);
  cases++;
}
console.log(`WebView JavaScript contract: ${cases} cases passed`);
