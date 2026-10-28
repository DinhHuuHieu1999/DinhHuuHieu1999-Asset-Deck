import express from 'express';
import request from 'supertest';
import { gzipSync } from 'node:zlib';
import { createAssetImportV3Parser } from './asset-import-v3-parser';

/** Transport-only fixture: no product app, authentication or database. */
function fixture() {
  const app = express();
  app.use(createAssetImportV3Parser());
  app.use(express.json());
  app.all('/api/v1/assets/import/v3', (req, res) =>
    res.json({ size: req.body?.value?.length ?? 0 }),
  );
  app.all('/api/v1/other', (req, res) =>
    res.json({ size: req.body?.value?.length ?? 0 }),
  );
  return app;
}

describe('bounded import parser scope', () => {
  it.each([
    '{"value":1,"value":2}',
    '{"value":1,"\\u0076alue":2}',
    '{"nested":{"a":1,"a":2}}',
    '{"value":"\\ud800"}',
    '{"\\udc00":1}',
    '['.repeat(34) + '1' + ']'.repeat(34),
  ])(
    'rejects ambiguous or malformed JSON before handling: %s',
    async (body) => {
      await request(fixture())
        .post('/api/v1/assets/import/v3')
        .set('Content-Type', 'application/json')
        .send(body)
        .expect(400);
    },
  );
  it.each(['/api/v1/assets/import/v3', '/API/V1/ASSETS/IMPORT/V3/'])(
    'enforces exact raw byte boundary on framework alias %s',
    async (path) => {
      const prefix = '{"value":"';
      const suffix = '"}';
      const exact =
        prefix +
        'x'.repeat(1024 * 1024 - prefix.length - suffix.length) +
        suffix;
      expect(Buffer.byteLength(exact, 'utf8')).toBe(1024 * 1024);
      await request(fixture())
        .post(path)
        .set('Content-Type', 'application/json')
        .send(exact)
        .expect(200);
      await request(fixture())
        .post(path)
        .set('Content-Type', 'application/json')
        .send(exact + ' ')
        .expect(413);
      await request(fixture())
        .post(path)
        .set('Content-Type', 'application/json')
        .send('{"value":1,"value":2}')
        .expect(400);
    },
  );
  it('rejects malformed raw UTF-8', async () => {
    await request(fixture())
      .post('/api/v1/assets/import/v3')
      .set('Content-Type', 'application/json')
      .serialize(
        () =>
          Buffer.from([
            0x7b, 0x22, 0xff, 0x22, 0x3a, 0x31, 0x7d,
          ]) as unknown as string,
      )
      .send('raw')
      .expect(400);
  });
  it.each([
    '/api/v1/assets/import/v3',
    '/API/V1/ASSETS/IMPORT/V3/',
    '/api/v1/assets/import/v3?x=1',
  ])(
    'accepts a bounded large POST only on the import route %s',
    async (path) => {
      await request(fixture())
        .post(path)
        .send({ value: 'x'.repeat(120000) })
        .expect(200, { size: 120000 });
    },
  );
  it('does not widen another route or another method', async () => {
    await request(fixture())
      .post('/api/v1/other')
      .send({ value: 'x'.repeat(120000) })
      .expect(413);
    await request(fixture())
      .put('/api/v1/assets/import/v3')
      .send({ value: 'x'.repeat(120000) })
      .expect(413);
  });
  it('rejects raw bytes exceeding the import limit', async () => {
    await request(fixture())
      .post('/api/v1/assets/import/v3')
      .send({ value: 'x'.repeat(1024 * 1024) })
      .expect(413);
  });
  it('rejects compressed JSON instead of expanding untrusted bodies', async () => {
    await request(fixture())
      .post('/api/v1/assets/import/v3')
      .set('Content-Type', 'application/json')
      .set('Content-Encoding', 'gzip')
      .send(gzipSync(Buffer.from('{"value":"synthetic"}')))
      .expect(415);
  });
  it('rejects malformed JSON before invoking a handler', async () => {
    await request(fixture())
      .post('/api/v1/assets/import/v3')
      .set('Content-Type', 'application/json')
      .send('{"value":')
      .expect(400);
  });
});
