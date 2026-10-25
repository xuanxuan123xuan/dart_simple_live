// Execute the production directory script against a mocked official PC runtime.
// This verifies the bridge contract; it does not claim live-service acceptance.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../lib/src/xiaohongshu_discovery_session.dart', import.meta.url), 'utf8');
const template = source.match(/return '''([\s\S]*?)''';/)[1];
const categoryPath = '/api/sns/red/live/web/feed/category';
const feedPath = '/api/sns/red/live/web/feed/v1/squarefeed';
let count = 0;
for (const path of [categoryPath, feedPath]) {
  for (const mode of ['ok', 'business-error', 'http406', 'offline', 'missing-runtime', 'delayed-runtime']) {
    const args = {id: 'discovery:1', path, query: path === categoryPath ? {} : {category: '0', cursorScore: '0', size: 27, topRoomIds: []}};
    const messages = [];
    const calls = [];
    let waits = 0;
    const body = mode === 'business-error' ? {success: false, code: -101} : {feeds: [], categories: []};
    async function invoke(kind, options) {
      calls.push({kind, options});
      if (mode === 'http406') throw {response: {status: 406}};
      if (mode === 'offline') throw new Error('offline');
      return body;
    }
    const api = {
      BR: function getApiSnsRedLiveWebFeedCategory(options) { return invoke('category', options); },
      i9: function getApiSnsRedLiveWebFeedV1Squarefeed(options) { return invoke('feed', options); },
      sendComment() { throw new Error('writes must never be invoked'); },
    };
    const runtime = (id) => { assert.equal(id, '76565'); return api; };
    runtime.m = {
      decoy: function() { return '/api/sns/red/live/web/feed/category'; },
      76565: function() {
        return ['/api/sns/red/live/web/feed/category', '/api/sns/red/live/web/feed/v1/squarefeed'];
      },
    };
    const window = {
      chrome: {webview: {postMessage: value => messages.push(JSON.parse(value))}},
      // The H5 signer must not be used for PC directory calls.
      sign() { throw new Error('wrong signer'); },
    };
    if (mode !== 'missing-runtime') window.webpackChunkxhs_pc_web = {
      push(chunk) { if (mode !== 'delayed-runtime' || waits >= 2) chunk[2](runtime); },
    };
    await vm.runInNewContext(template.replace('$payload', JSON.stringify(args)), {
      window, setTimeout(callback) { waits++; callback(); },
    });
    assert.equal(messages.length, 1, mode);
    const result = messages[0];
    assert.equal(result.id, args.id);
    if (mode === 'missing-runtime') {
      assert.equal(waits, 100);
      assert.equal(calls.length, 0);
      assert.deepEqual(result, {id: args.id, ok: false, status: 406});
    } else {
      assert.equal(calls.length, 1);
      assert.equal(calls[0].kind, path === categoryPath ? 'category' : 'feed');
      assert.deepEqual(JSON.parse(JSON.stringify(calls[0].options)), {
        params: args.query, baseURL: 'https://live-room.xiaohongshu.com',
        transform: true, withCredentials: true,
      });
      if (mode === 'http406' || mode === 'offline') {
        assert.deepEqual(result, {id: args.id, ok: false, status: mode === 'http406' ? 406 : 0});
      } else {
        assert.deepEqual(result, {id: args.id, ok: true, status: 200,
          data: mode === 'business-error' ? body : {success: true, data: body}});
      }
    }
    count++;
  }
}
console.log(`Directory JavaScript contract: ${count} cases passed`);
