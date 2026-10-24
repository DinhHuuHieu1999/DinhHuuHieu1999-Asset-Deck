import * as fs from 'fs';
import * as path from 'path';
import * as dotenv from 'dotenv';
import { expand } from 'dotenv-expand';

export function getWorkspaceRoot(startDir = process.cwd()) {
  // nosemgrep: javascript.lang.security.audit.path-traversal.path-traversal -- startDir is a trusted process/tooling path, not request input.
  let currentDir = path.resolve(startDir);

  for (;;) {
    // The candidate is derived only from the current ancestor directory.
    // nosemgrep: javascript.lang.security.audit.path-traversal.path-traversal -- Only a fixed workspace marker is appended.
    // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal -- currentDir is a trusted ancestor path.
    const workspaceMarker = path.join(currentDir, 'pnpm-workspace.yaml');
    try {
      // nosemgrep: javascript_pathtraversal_rule-non-literal-fs-filename, javascript.lang.security.audit.detect-non-literal-fs-filename.detect-non-literal-fs-filename
      fs.accessSync(workspaceMarker, fs.constants.F_OK);
      return currentDir;
    } catch {
      // Keep walking toward the filesystem root.
    }

    const parentDir = path.dirname(currentDir);
    if (parentDir === currentDir) return path.resolve(startDir);
    currentDir = parentDir;
  }
}

export function getEnvFilePaths() {
  const appEnvDir = path.resolve(process.cwd(), 'env');

  return getEnvFilesFromDir(appEnvDir);
}

function getEnvFilesFromDir(envDir: string) {
  // envDir is the application-owned, resolved env directory.
  // nosemgrep: javascript_pathtraversal_rule-non-literal-fs-filename, javascript.lang.security.audit.detect-non-literal-fs-filename.detect-non-literal-fs-filename
  // eslint-disable-next-line -- trusted application env path; see the preceding boundary explanation.
  if (!fs.existsSync(envDir)) return [];

  const nodeEnvValue: unknown = Reflect.get(process.env, 'NODE_ENV');
  const nodeEnv =
    typeof nodeEnvValue === 'string' ? nodeEnvValue.trim() : undefined;
  const isProduction = nodeEnv === 'production';
  const fileNames = [
    '.env',
    nodeEnv ? `.env.${nodeEnv}` : undefined,
    isProduction ? undefined : '.env.local',
    nodeEnv && !isProduction ? `.env.${nodeEnv}.local` : undefined,
  ].filter((fileName): fileName is string => Boolean(fileName));

  return (
    fileNames
      .map((fileName) => path.join(envDir, fileName))
      // Each candidate is restricted to the allow-listed filenames above.
      // nosemgrep: javascript_pathtraversal_rule-non-literal-fs-filename, javascript.lang.security.audit.detect-non-literal-fs-filename.detect-non-literal-fs-filename
      // eslint-disable-next-line -- trusted allow-listed env path; see the preceding boundary explanation.
      .filter((filePath) => fs.existsSync(filePath))
  );
}

export function loadEnvFiles() {
  const appEnvDir = path.resolve(process.cwd(), 'env');
  const initialKeys = new Set(Object.keys(process.env));
  const fileEnv: Record<string, string> = {};

  for (const envFilePath of getEnvFilesFromDir(appEnvDir)) {
    // getEnvFilesFromDir returns only allow-listed files inside appEnvDir.
    // nosemgrep: javascript_pathtraversal_rule-non-literal-fs-filename, javascript.lang.security.audit.detect-non-literal-fs-filename.detect-non-literal-fs-filename
    // eslint-disable-next-line -- trusted allow-listed env path; see the preceding boundary explanation.
    Object.assign(fileEnv, dotenv.parse(fs.readFileSync(envFilePath)));
  }

  // Expand ${VAR_NAME} references in .env values
  // Supports: VAR=value, OTHER=${VAR}:port, etc.
  expand({ parsed: fileEnv });

  for (const [key, value] of Object.entries(fileEnv)) {
    if (!initialKeys.has(key)) {
      Reflect.set(process.env, key, value);
    }
  }
}
