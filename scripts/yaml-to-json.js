#!/usr/bin/env node
/**
 * yaml-to-json.js — lightweight YAML-to-JSON converter (no npm dependencies)
 *
 * Usage:
 *   node scripts/yaml-to-json.js <file.yaml>
 *   cat file.yaml | node scripts/yaml-to-json.js
 *
 * Handles: key-value pairs, nested objects, block sequences (- item),
 * inline arrays, quoted strings, booleans, numbers, null, comments,
 * and {{var}} template variables (passed through as-is).
 */

'use strict';

const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// Scalar parsing
// ---------------------------------------------------------------------------

function parseScalar(raw) {
  const s = raw.trim();

  if (s === '' || s === 'null' || s === '~') return null;
  if (s === 'true') return true;
  if (s === 'false') return false;

  // Quoted strings — single or double
  if ((s.startsWith('"') && s.endsWith('"')) ||
      (s.startsWith("'") && s.endsWith("'"))) {
    return s.slice(1, -1);
  }

  // Inline array [a, b, c]
  if (s.startsWith('[') && s.endsWith(']')) {
    const inner = s.slice(1, -1).trim();
    if (inner === '') return [];
    return splitRespectingQuotes(inner, ',').map(parseScalar);
  }

  // Number
  if (/^-?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(s)) {
    return Number(s);
  }

  // Plain string (includes {{var}} template vars)
  return s;
}

/** Split a string by a delimiter, ignoring delimiters inside quotes. */
function splitRespectingQuotes(str, delimiter) {
  const parts = [];
  let current = '';
  let inSingle = false;
  let inDouble = false;

  for (let i = 0; i < str.length; i++) {
    const ch = str[i];
    if (ch === "'" && !inDouble) { inSingle = !inSingle; current += ch; }
    else if (ch === '"' && !inSingle) { inDouble = !inDouble; current += ch; }
    else if (ch === delimiter && !inSingle && !inDouble) {
      parts.push(current.trim());
      current = '';
    } else {
      current += ch;
    }
  }
  if (current.trim() !== '' || parts.length > 0) parts.push(current.trim());
  return parts;
}

// ---------------------------------------------------------------------------
// Line tokeniser
// ---------------------------------------------------------------------------

function tokenise(text) {
  return text
    .split('\n')
    .map((line, idx) => ({ raw: line, num: idx + 1 }))
    .filter(({ raw }) => {
      const trimmed = raw.trim();
      return trimmed !== '' && !trimmed.startsWith('#');
    })
    .map(({ raw, num }) => {
      const indent = raw.match(/^( *)/)[1].length;
      const content = raw.trim();
      return { indent, content, num };
    });
}

// ---------------------------------------------------------------------------
// Recursive parser
// ---------------------------------------------------------------------------

/**
 * Parse a slice of tokens starting at `pos` where all lines belong to the
 * current block (indent > parentIndent).  Returns { value, pos }.
 *
 * @param {Array}  tokens
 * @param {number} pos          current index into tokens
 * @param {number} blockIndent  indent level of the first line of this block
 */
function parseBlock(tokens, pos, blockIndent) {
  // Peek at first token to decide: sequence or mapping?
  if (pos >= tokens.length) return { value: null, pos };

  const first = tokens[pos];

  if (first.content.startsWith('- ') || first.content === '-') {
    return parseSequence(tokens, pos, blockIndent);
  }
  return parseMapping(tokens, pos, blockIndent);
}

function parseSequence(tokens, pos, blockIndent) {
  const arr = [];

  while (pos < tokens.length && tokens[pos].indent === blockIndent) {
    const tok = tokens[pos];
    if (!tok.content.startsWith('- ') && tok.content !== '-') break;

    const itemContent = tok.content.slice(2).trim(); // strip '- '
    pos++;

    if (itemContent === '') {
      // The value is on the next indented lines
      if (pos < tokens.length && tokens[pos].indent > blockIndent) {
        const childIndent = tokens[pos].indent;
        const { value, pos: newPos } = parseBlock(tokens, pos, childIndent);
        arr.push(value);
        pos = newPos;
      } else {
        arr.push(null);
      }
    } else if (itemContent.includes(': ') || /^[a-zA-Z_][a-zA-Z0-9_-]*:$/.test(itemContent)) {
      // Inline key: value — treat as a single-entry mapping object,
      // then merge any following indented keys at same level
      const syntheticTokens = [{ indent: blockIndent + 2, content: itemContent, num: tok.num }];

      // Collect subsequent lines that belong to this item (deeper indent)
      while (pos < tokens.length && tokens[pos].indent > blockIndent) {
        syntheticTokens.push(tokens[pos]);
        pos++;
      }

      const childIndent = syntheticTokens[0].indent;
      const { value } = parseMapping(syntheticTokens, 0, childIndent);
      arr.push(value);
    } else {
      arr.push(parseScalar(itemContent));
    }
  }

  return { value: arr, pos };
}

function parseMapping(tokens, pos, blockIndent) {
  const obj = {};

  while (pos < tokens.length && tokens[pos].indent === blockIndent) {
    const tok = tokens[pos];

    // Key-only line (e.g. "phases:") or key: value
    const colonIdx = tok.content.indexOf(': ');
    const trailingColon = tok.content.endsWith(':');

    let key, rawValue;

    if (colonIdx !== -1) {
      key = tok.content.slice(0, colonIdx).trim();
      rawValue = tok.content.slice(colonIdx + 2).trim();
    } else if (trailingColon) {
      key = tok.content.slice(0, -1).trim();
      rawValue = '';
    } else {
      // Not a mapping line — stop
      break;
    }

    pos++;

    if (rawValue === '|' || rawValue === '>') {
      // Block scalar: literal (|) preserves newlines, folded (>) joins with spaces
      const lines = [];
      while (pos < tokens.length && tokens[pos].indent > blockIndent) {
        lines.push(tokens[pos].content);
        pos++;
      }
      obj[key] = rawValue === '|' ? lines.join('\n') : lines.join(' ');
    } else if (rawValue !== '') {
      // Scalar or inline value on this line
      obj[key] = parseScalar(rawValue);
    } else {
      // Value is on the next indented block
      if (pos < tokens.length && tokens[pos].indent > blockIndent) {
        const childIndent = tokens[pos].indent;
        const { value, pos: newPos } = parseBlock(tokens, pos, childIndent);
        obj[key] = value;
        pos = newPos;
      } else {
        obj[key] = null;
      }
    }
  }

  return { value: obj, pos };
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

function parseYaml(text) {
  const tokens = tokenise(text);
  if (tokens.length === 0) return {};
  const rootIndent = tokens[0].indent;
  const { value } = parseBlock(tokens, 0, rootIndent);
  return value;
}

function main() {
  let input = '';

  const filePath = process.argv[2];
  if (filePath) {
    const abs = path.resolve(filePath);
    if (!fs.existsSync(abs)) {
      process.stderr.write(`yaml-to-json: file not found: ${filePath}\n`);
      process.exit(1);
    }
    input = fs.readFileSync(abs, 'utf8');
  } else {
    // Read from stdin
    try {
      input = fs.readFileSync('/dev/stdin', 'utf8');
    } catch {
      process.stderr.write('yaml-to-json: no input file and stdin unavailable\n');
      process.exit(1);
    }
  }

  try {
    const result = parseYaml(input);
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
    process.exit(0);
  } catch (err) {
    process.stderr.write(`yaml-to-json: parse error: ${err.message}\n`);
    process.exit(1);
  }
}

main();
