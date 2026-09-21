const test = require('node:test');
const assert = require('node:assert');
const { createStore } = require('./todos');

test('add and list', () => {
  const store = createStore();
  store.add('  buy milk ');
  assert.deepStrictEqual(store.list(), [{ id: 1, title: 'buy milk', done: false }]);
});

test('add rejects empty title', () => {
  assert.throws(() => createStore().add('  '), /title is required/);
});

test('complete marks done', () => {
  const store = createStore();
  const { id } = store.add('walk');
  assert.strictEqual(store.complete(id).done, true);
});
