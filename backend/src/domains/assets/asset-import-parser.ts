// Adapted from the ToolDeck opt-in import source contract.
import { json, type RequestHandler } from 'express';
import { ASSET_IMPORT_MAX_BYTES } from './asset-import';

/** Install before Nest initialization; preserve default limits for every other route. */
export function createAssetImportParser(): RequestHandler {
  const parse = json({ limit: ASSET_IMPORT_MAX_BYTES, inflate: false });
  return (req, res, next) => {
    if (
      req.method === 'POST' &&
      /^\/api\/v1\/assets\/import\/?$/iu.test(req.path)
    ) {
      parse(req, res, next);
    } else {
      next();
    }
  };
}
