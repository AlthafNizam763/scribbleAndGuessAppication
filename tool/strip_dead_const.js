// Removes the `const` keywords that localisation invalidated.
//
//   flutter analyze > analyze.txt && node tool/strip_dead_const.js analyze.txt
//
// A string that now comes from `context.l10n` is no longer a compile-time
// constant, so every `const` constructor that contained one has to go. The
// analyzer reports the position of the offending *expression*, not of the
// `const` that made it illegal, so this walks backwards to the nearest `const`
// — which is always the enclosing one, because `flutter_lints` forbids writing
// a nested `const` inside a const context.
//
// Bottom-up per file, so removing a keyword never shifts a line still to come.

const fs = require('fs');

const report = fs.readFileSync(process.argv[2], 'utf8');

const wanted = /(lib[\\/][^\s:]+\.dart):(\d+):\d+ - (invalid_constant|const_constructor_with_non_constant_argument|non_constant_list_element|non_constant_map_element|const_initialized_with_non_constant_value|non_constant_record_field)/g;

const byFile = new Map();
let m;
while ((m = wanted.exec(report)) !== null) {
  const file = m[1].split('\\').join('/');
  if (!byFile.has(file)) byFile.set(file, new Set());
  byFile.get(file).add(Number(m[2]));
}

// `const X(` / `const <T>[` / `const [` / `const {`
const CONST_OPENER = /\bconst\s+(?=[A-Z_<[{])/;

let removals = 0;

for (const [file, lineSet] of byFile) {
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  const targets = new Set();

  for (const lineNo of lineSet) {
    // 1-indexed -> 0-indexed.
    for (let i = lineNo - 1; i >= 0 && i >= lineNo - 40; i -= 1) {
      if (CONST_OPENER.test(lines[i])) {
        targets.add(i);
        break;
      }
    }
  }

  for (const i of [...targets].sort((a, b) => b - a)) {
    lines[i] = lines[i].replace(CONST_OPENER, '');
    removals += 1;
  }

  fs.writeFileSync(file, lines.join('\n'));
}

console.error('removed ' + removals + ' const keywords across ' + byFile.size + ' files');
