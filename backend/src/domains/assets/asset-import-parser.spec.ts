import express from 'express';
import request from 'supertest';
import { gzipSync } from 'node:zlib';
import { createAssetImportParser } from './asset-import-parser';

/** Transport-only fixture: no product app, authentication or database. */
function fixture() {
  const app = express();
  app.use(createAssetImportParser());
  app.use(express.json());
  app.all('/api/v1/assets/import', (req, res) =>
    res.json({ size: req.body?.value?.length ?? 0 }),
  );
  app.all('/api/v1/other', (req, res) =>
    res.json({ size: req.body?.value?.length ?? 0 }),
  );
  return app;
}

describe('bounded import parser scope', () => {
  it.each([
    '/api/v1/assets/import',
    '/API/V1/ASSETS/IMPORT/',
    '/api/v1/assets/import?x=1',
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
      .put('/api/v1/assets/import')
      .send({ value: 'x'.repeat(120000) })
      .expect(413);
  });
  it('rejects raw bytes exceeding the import limit', async () => {
    await request(fixture())
      .post('/api/v1/assets/import')
      .send({ value: 'x'.repeat(1024 * 1024) })
      .expect(413);
  });
  it('rejects compressed JSON instead of expanding untrusted bodies', async () => {
    await request(fixture())
      .post('/api/v1/assets/import')
      .set('Content-Type', 'application/json')
      .set('Content-Encoding', 'gzip')
      .send(gzipSync(Buffer.from('{"value":"synthetic"}')))
      .expect(415);
  });
  it('rejects malformed JSON before invoking a handler', async () => {
    await request(fixture())
      .post('/api/v1/assets/import')
      .set('Content-Type', 'application/json')
      .send('{"value":')
      .expect(400);
  });
});
