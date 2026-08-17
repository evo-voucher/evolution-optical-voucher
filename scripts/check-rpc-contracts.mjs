#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const migrationDir = path.join(root, 'supabase', 'migrations');
const scanExt = new Set(['.html', '.js', '.mjs']);
const ignoredDirs = new Set(['.git', 'node_modules', 'offline-backup', 'uat', 'uat-preview']);
const ignoredRootFiles = new Set(['xiaoe-brain.html']);

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (ignoredDirs.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (scanExt.has(path.extname(entry.name))) {
      const rel = path.relative(root, full);
      if (!ignoredRootFiles.has(rel)) out.push(full);
    }
  }
  return out;
}

function splitSqlParams(text) {
  const parts = [];
  let buf = '';
  let depth = 0;
  let quote = null;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quote) {
      buf += c;
      if (c === quote && text[i - 1] !== '\\') quote = null;
      continue;
    }
    if (c === '"' || c === "'") { quote = c; buf += c; continue; }
    if (c === '(' || c === '[') depth++;
    if (c === ')' || c === ']') depth--;
    if (c === ',' && depth === 0) { parts.push(buf.trim()); buf = ''; continue; }
    buf += c;
  }
  if (buf.trim()) parts.push(buf.trim());
  return parts;
}

function loadRpcSignatures() {
  const map = new Map();
  if (!fs.existsSync(migrationDir)) return map;
  const files = fs.readdirSync(migrationDir).filter(f => f.endsWith('.sql')).sort();
  const re = /create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-zA-Z0-9_]+)\s*\(([^)]*)\)/gim;
  for (const file of files) {
    const text = fs.readFileSync(path.join(migrationDir, file), 'utf8');
    let m;
    while ((m = re.exec(text))) {
      const params = splitSqlParams(m[2])
        .map(p => (p.match(/^\s*(p_[a-zA-Z0-9_]+)\b/i) || [])[1])
        .filter(Boolean)
        .map(s => s.toLowerCase());
      const name = m[1].toLowerCase();
      const sig = [...new Set(params)].sort();
      const key = sig.join(',');
      const list = map.get(name) || [];
      if (!list.some(x => x.key === key)) list.push({ key, params: sig, file });
      map.set(name, list);
    }
  }
  return map;
}

function balancedObject(source, start) {
  let depth = 0;
  let quote = null;
  let escape = false;
  for (let i = start; i < source.length; i++) {
    const c = source[i];
    if (quote) {
      if (escape) { escape = false; continue; }
      if (c === '\\') { escape = true; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
    if (c === '{') depth++;
    if (c === '}') {
      depth--;
      if (depth === 0) return source.slice(start, i + 1);
    }
  }
  return null;
}

function topLevelKeys(objectText) {
  const body = objectText.slice(1, -1);
  const keys = new Set();
  let depth = 0;
  let quote = null;
  let escape = false;
  let tokenStart = 0;
  const chunks = [];
  for (let i = 0; i <= body.length; i++) {
    const c = body[i];
    if (quote) {
      if (escape) { escape = false; continue; }
      if (c === '\\') { escape = true; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
    if (c === '{' || c === '[' || c === '(') depth++;
    if (c === '}' || c === ']' || c === ')') depth--;
    if ((c === ',' && depth === 0) || i === body.length) {
      chunks.push(body.slice(tokenStart, i).trim());
      tokenStart = i + 1;
    }
  }
  for (const chunk of chunks) {
    const m = chunk.match(/^\s*(?:['"])?(p_[a-zA-Z0-9_]+)(?:['"])?\s*:/i);
    if (m) keys.add(m[1].toLowerCase());
  }
  return [...keys].sort();
}

function findCalls(file) {
  const source = fs.readFileSync(file, 'utf8');
  const calls = [];
  const re = /\.rpc\s*\(\s*(['"])([a-zA-Z0-9_]+)\1\s*,\s*/g;
  let m;
  while ((m = re.exec(source))) {
    let i = re.lastIndex;
    while (/\s/.test(source[i] || '')) i++;
    const line = source.slice(0, m.index).split('\n').length;
    if (source[i] !== '{') {
      calls.push({ name: m[2], params: null, line, reason: 'dynamic payload' });
      continue;
    }
    const obj = balancedObject(source, i);
    if (!obj) {
      calls.push({ name: m[2], params: null, line, reason: 'unbalanced object' });
      continue;
    }
    calls.push({ name: m[2], params: topLevelKeys(obj), line });
  }
  return calls;
}

const signatures = loadRpcSignatures();
const files = walk(root);
const failures = [];
const skipped = [];
let checked = 0;

for (const file of files) {
  for (const call of findCalls(file)) {
    const rel = path.relative(root, file);
    const name = call.name.toLowerCase();
    if (!call.params) {
      skipped.push(`${rel}:${call.line} ${call.name} (${call.reason})`);
      continue;
    }
    checked++;
    const candidates = signatures.get(name) || [];
    if (!candidates.length) {
      failures.push(`${rel}:${call.line} rpc('${call.name}') has no matching function declaration in supabase/migrations`);
      continue;
    }
    const actual = call.params.join(',');
    if (!candidates.some(c => c.key === actual)) {
      const expected = candidates.map(c => `[${c.params.join(', ')}] @ ${c.file}`).join(' OR ');
      failures.push(`${rel}:${call.line} rpc('${call.name}') args [${call.params.join(', ')}] do not match ${expected}`);
    }
  }
}

if (failures.length) {
  console.error(`RPC contract check FAILED (${failures.length} mismatch${failures.length === 1 ? '' : 'es'}):`);
  for (const f of failures) console.error(`- ${f}`);
  if (skipped.length) console.error(`\nSkipped ${skipped.length} dynamic RPC payload(s).`);
  process.exit(1);
}

console.log(`RPC contract check PASS: ${checked} static RPC call(s) matched migration signatures.`);
if (skipped.length) {
  console.log(`Skipped ${skipped.length} dynamic RPC payload(s) that require targeted runtime/contract tests.`);
  for (const s of skipped.slice(0, 20)) console.log(`- ${s}`);
  if (skipped.length > 20) console.log(`- ... ${skipped.length - 20} more`);
}
