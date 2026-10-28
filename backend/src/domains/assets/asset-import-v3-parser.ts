import { json, type RequestHandler } from 'express';
import { ASSET_IMPORT_MAX_BYTES } from './asset-import';
import { validateAssetImportV2Json as validateAssetImportV3Json } from './asset-import-v2-parser';

/** Bound only v3 POST aliases; reject compression, malformed UTF-8 and duplicate keys. */
export function createAssetImportV3Parser(): RequestHandler {
  const parse = json({
    limit: ASSET_IMPORT_MAX_BYTES,
    inflate: false,
    verify: (_req, _res, bytes) => {
      try {
        const source = new TextDecoder('utf-8', {
          fatal: true,
          ignoreBOM: true,
        }).decode(bytes);
        validateAssetImportV3Json(source);
      } catch {
        throw Object.assign(new Error('Invalid import JSON'), { status: 400 });
      }
    },
  });
  return (req, res, next) => {
    if (
      req.method === 'POST' &&
      /^\/api\/v1\/assets\/import\/v3\/?$/iu.test(req.path)
    )
      parse(req, res, next);
    else next();
  };
}
