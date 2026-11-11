import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import test from 'node:test';

const source = readFileSync(new URL('../static/app.js', import.meta.url), 'utf8');
const start = source.indexOf("  const sidebarNewChatBtn = el('sidebar-new-chat-btn');");
const end = source.indexOf('  // Delete session button on icon rail', start);
assert.ok(start >= 0 && end > start);

for (const width of [390, 767, 768, 1280]) {
  test(`New Chat drawer behavior at ${width}px`, async () => {
    let click;
    let calls = 0;
    let syncs = 0;
    let finish;
    const pending = new Promise(resolve => { finish = resolve; });
    const sidebar = new Set();
    const backdrop = new Set(['visible']);
    const nodes = {
      'sidebar-new-chat-btn': { addEventListener: (event, handler) => { click = handler; } },
      sidebar: { classList: { add: value => sidebar.add(value) } },
      'sidebar-backdrop': { classList: { remove: value => backdrop.delete(value) } },
    };
    runInNewContext(source.slice(start, end), {
      el: id => nodes[id],
      window: { innerWidth: width, syncRailSide: () => { syncs++; } },
      _handleNewChatAction: () => { calls++; return pending; },
    });
    const result = click({ preventDefault() {}, stopImmediatePropagation() {} });
    // Drawer closes before asynchronous model/session setup finishes.
    assert.equal(sidebar.has('hidden'), width < 768);
    assert.equal(backdrop.has('visible'), width >= 768);
    assert.equal(syncs, width < 768 ? 1 : 0);
    assert.equal(calls, 1);
    finish();
    await result;
  });
}

const codeStart = source.indexOf("  const sidebarCodeBtn = el('sidebar-code-btn');");
const codeEnd = source.indexOf('  // Delete session button on icon rail', codeStart);
assert.ok(codeStart >= 0 && codeEnd > codeStart);

for (const width of [390, 1280]) {
  test(`Code action opens a scoped Agent task at ${width}px`, async () => {
    let click;
    let chatOptions;
    let selectedMode = '';
    let defaultLoads = 0;
    let pickerOpens = 0;
    let toast = '';
    let focused = false;
    const sidebar = new Set();
    const backdrop = new Set(['visible']);
    const input = { placeholder: '', focus: () => { focused = true; } };
    const nodes = {
      'sidebar-code-btn': { addEventListener: (event, handler) => { click = handler; } },
      sidebar: { classList: { add: value => sidebar.add(value) } },
      'sidebar-backdrop': { classList: { remove: value => backdrop.delete(value) } },
      message: input,
    };
    const workspaceModule = {
      getWorkspace: () => '',
      loadDefaultWorkspace: async () => { defaultLoads++; return { ok: false, path: null }; },
      openWorkspaceBrowser: async () => { pickerOpens++; },
    };

    runInNewContext(source.slice(codeStart, codeEnd), {
      el: id => nodes[id],
      window: {
        innerWidth: width,
        syncRailSide() {},
        __odysseusSetChatMode: mode => { selectedMode = mode; },
      },
      _handleNewChatAction: async options => { chatOptions = options; },
      workspaceModule,
      uiModule: { showToast: message => { toast = message; } },
    });

    await click({ preventDefault() {}, stopImmediatePropagation() {} });

    assert.equal(chatOptions.preferModel, false);
    assert.equal(chatOptions.focus, false);
    assert.equal(selectedMode, 'agent');
    assert.equal(defaultLoads, 1);
    assert.equal(pickerOpens, 1);
    assert.match(input.placeholder, /coding task for your project/);
    assert.equal(focused, true);
    assert.equal(toast, 'Choose a project for the code agent');
    assert.equal(sidebar.has('hidden'), width < 768);
    assert.equal(backdrop.has('visible'), width >= 768);
  });
}
