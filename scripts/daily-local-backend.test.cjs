'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { PassThrough } = require('node:stream');
const { supervise } = require('./daily-local-backend.cjs');

test('ready then private shutdown closes exactly once', async () => {
  const input = new PassThrough();
  const events = [];
  let closed = 0;
  const done = supervise(
    async () => ({
      close: async () => {
        closed++;
      },
    }),
    input,
    (event) => {
      events.push(event);
      if (event === 'ready') input.end('shutdown\n');
    },
  );
  await done;
  assert.equal(closed, 1);
  assert.deepEqual(events, ['ready', 'stopped']);
});

test('EOF during startup closes returned application without ready', async () => {
  const input = new PassThrough();
  const events = [];
  let closed = 0;
  await supervise(
    async () => {
      input.emit('end');
      return {
        close: async () => {
          closed++;
        },
      };
    },
    input,
    (event) => events.push(event),
  );
  assert.equal(closed, 1);
  assert.deepEqual(events, ['stopped']);
});

test('invalid oversized control input closes without executing a command', async () => {
  const input = new PassThrough();
  let closed = 0;
  await supervise(
    async () => ({
      close: async () => {
        closed++;
      },
    }),
    input,
    (event) => {
      if (event === 'ready') input.write('x'.repeat(65));
    },
  );
  assert.equal(closed, 1);
});

test('shutdown error is generic and listeners removed', async () => {
  const input = new PassThrough();
  await assert.rejects(
    supervise(
      async () => ({
        close: async () => {
          throw new Error('private-secret');
        },
      }),
      input,
      (event) => {
        if (event === 'ready') input.end();
      },
    ),
    /^Error: Backend shutdown failed$/,
  );
  assert.equal(input.listenerCount('data'), 0);
});
