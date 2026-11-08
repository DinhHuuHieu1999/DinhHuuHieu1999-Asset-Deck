import { json, type RequestHandler } from 'express';
import { ASSET_IMPORT_MAX_BYTES } from './asset-import';

/** Inspect valid JSON tokens before object construction can discard duplicate keys. */
export function validateAssetImportV2Json(source: string): void {
  JSON.parse(source);
  const tokens =
    source.match(
      /"(?:\\.|[^"\\])*"|[{}\[\]:,]|true|false|null|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/gu,
    ) ?? [];
  let offset = 0;
  const invalid = (): never => {
    throw new Error('Invalid import JSON');
  };
  const string = (): string => {
    const value: unknown = JSON.parse(tokens[offset++]);
    if (
      typeof value !== 'string' ||
      Buffer.from(value, 'utf8').toString('utf8') !== value
    )
      return invalid();
    return value;
  };
  const value = (depth: number): void => {
    if (depth > 32 || offset >= tokens.length) invalid();
    const token = tokens[offset++];
    if (token === '{') {
      const keys = new Set<string>();
      if (tokens[offset] === '}') {
        offset++;
        return;
      }
      do {
        const key = string();
        if (keys.has(key) || tokens[offset++] !== ':') invalid();
        keys.add(key);
        value(depth + 1);
        if (tokens[offset] === '}') {
          offset++;
          return;
        }
      } while (tokens[offset++] === ',');
      invalid();
    } else if (token === '[') {
      if (tokens[offset] === ']') {
        offset++;
        return;
      }
      do {
        value(depth + 1);
        if (tokens[offset] === ']') {
          offset++;
          return;
        }
      } while (tokens[offset++] === ',');
      invalid();
    } else if (token.startsWith('"')) {
      offset--;
      string();
    }
  };
  value(0);
  if (offset !== tokens.length) invalid();
}

/** Bound only v2 POST aliases; reject compression, malformed UTF-8 and duplicate keys. */
export function createAssetImportV2Parser(): RequestHandler {
  const parse = json({
    limit: ASSET_IMPORT_MAX_BYTES,
    inflate: false,
    verify: (_req, _res, bytes) => {
      try {
        const source = new TextDecoder('utf-8', {
          fatal: true,
          ignoreBOM: true,
        }).decode(bytes);
        validateAssetImportV2Json(source);
      } catch {
        throw Object.assign(new Error('Invalid import JSON'), { status: 400 });
      }
    },
  });
  return (req, res, next) => {
    if (
      req.method === 'POST' &&
      /^\/api\/v1\/assets\/import\/v2\/?$/iu.test(req.path)
    )
      parse(req, res, next);
    else next();
  };
}
