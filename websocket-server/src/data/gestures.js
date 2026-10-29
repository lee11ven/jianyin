import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

export const gesturesCatalog = JSON.parse(
  readFileSync(join(__dirname, 'gestures.json'), 'utf8'),
);
