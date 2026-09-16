// One-shot migration: `AppStrings.x` -> `context.l10n.x` in widget code.
//
//   node tool/migrate_l10n.js <dir> [<dir> ...]
//
// Kept in the repo because it documents exactly what was mechanical about the
// change and what was not: it rewrites call sites, fixes up the imports and
// re-sorts them, and deliberately leaves comments, const contexts and
// context-free code alone for the analyzer to flag.

const fs = require('fs');
const path = require('path');

const APP = path.join(__dirname, '..');
const L10N_IMPORT = "import 'package:scribble_guess/core/i18n/app_text.dart';";
const STRINGS_IMPORT =
  "import 'package:scribble_guess/core/constants/app_strings.dart';";

function walk(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.endsWith('.dart')) out.push(full);
  }
  return out;
}

const targets = [];
for (const dir of process.argv.slice(2)) walk(path.join(APP, dir), targets);

let changed = 0;

for (const file of targets) {
  const original = fs.readFileSync(file, 'utf8');
  if (!original.includes('AppStrings.')) continue;

  const lines = original.split('\n');

  // Rewrite call sites, but never inside a comment: a doc comment that names
  // `AppStrings.foo` is describing the catalogue, not calling it.
  const rewritten = lines.map((line) =>
    /^\s*\/\//.test(line) ? line : line.split('AppStrings.').join('context.l10n.'),
  );

  let body = rewritten.join('\n');

  // Drop the old import when nothing refers to the class any more.
  const stillUsesAppStrings = /\bAppStrings\b/.test(
    body
      .split('\n')
      .filter((l) => !/^\s*\/\//.test(l) && l.trim() !== STRINGS_IMPORT)
      .join('\n'),
  );

  // Replace the package-import block in place. Reassembling the file from
  // parts is what mangled the class doc comment on the first attempt: comments
  // live both above and below the imports, so only the import lines themselves
  // can safely be moved.
  const out = body.split('\n');
  const isPkg = (l) => /^import ['"]package:/.test(l);
  const first = out.findIndex(isPkg);
  if (first === -1) {
    console.error('no package imports: ' + file);
    continue;
  }
  let last = first;
  for (let i = first; i < out.length; i += 1) if (isPkg(out[i])) last = i;

  let imports = out.slice(first, last + 1).filter(isPkg);
  if (!stillUsesAppStrings) {
    imports = imports.filter((l) => l.trim() !== STRINGS_IMPORT);
  }
  if (!imports.includes(L10N_IMPORT)) imports.push(L10N_IMPORT);
  imports = [...new Set(imports)].sort();

  out.splice(first, last - first + 1, ...imports);
  body = out.join('\n');

  if (body !== original) {
    fs.writeFileSync(file, body);
    changed += 1;
  }
}

console.error('rewrote ' + changed + ' files');
