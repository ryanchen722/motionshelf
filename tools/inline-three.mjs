// 把 Three.js 內嵌進 3D 效果：把 effect.html 裡的 /*THREE_MIN_JS*/ 換成 skills/make-effect/vendor/three.min.js。
// Usage: node tools/inline-three.mjs effects/<name>/effect.html
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const target = process.argv[2];
if (!target) { console.log('Usage: node tools/inline-three.mjs effects/<name>/effect.html'); process.exit(1); }
const html = fs.readFileSync(target, 'utf8');
if (!html.includes('/*THREE_MIN_JS*/')) { console.log('No /*THREE_MIN_JS*/ marker found (already inlined?)'); process.exit(0); }
const three = fs.readFileSync(path.join(root, 'skills/make-effect/vendor/three.min.js'), 'utf8');
fs.writeFileSync(target, html.split('/*THREE_MIN_JS*/').join(three));
console.log(`Inlined Three.js into ${target}`);
