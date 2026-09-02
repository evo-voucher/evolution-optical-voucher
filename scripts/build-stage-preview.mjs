import fs from 'node:fs';
import path from 'node:path';

const ROOT = process.cwd();
const DEST = path.join(ROOT, 'stage-preview');

const PROD_REF = 'xfivcfwexcxsyiylgryn';
const PROD_URL = `https://${PROD_REF}.supabase.co`;
const PROD_KEY = 'sb_publishable_uu1Qyx-M3dldpZn9jq7jXw_RLTHOMh_';
const PROD_SITE = 'https://evo-voucher.github.io/evolution-optical-voucher/';

const STAGE_REF = 'tagusbcluzoxueixjmwh';
const STAGE_URL = `https://${STAGE_REF}.supabase.co`;
const STAGE_KEY = 'sb_publishable_R86zjGv4yso-krORZdj3IQ_7QZUtMMB';
const STAGE_SITE = 'https://evo-voucher.github.io/evolution-optical-voucher/stage-preview/';

const ROOT_FILE_EXTENSIONS = new Set(['.html', '.json', '.webmanifest', '.png']);
const ROOT_SPECIAL_FILES = new Set(['service-worker.js', 'sw.js']);
const SOURCE_DIRS = ['assets', 'experience'];
const TEXT_EXTENSIONS = new Set(['.html', '.js', '.json', '.webmanifest', '.css', '.txt']);

function copyRecursive(src, dest) {
  const stat = fs.statSync(src);
  if (stat.isDirectory()) {
    fs.mkdirSync(dest, { recursive: true });
    for (const name of fs.readdirSync(src)) copyRecursive(path.join(src, name), path.join(dest, name));
    return;
  }
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

function transformText(text) {
  return text
    .split(PROD_REF).join(STAGE_REF)
    .split(PROD_URL).join(STAGE_URL)
    .split(PROD_KEY).join(STAGE_KEY)
    .split(PROD_SITE).join(STAGE_SITE)
    .split('evolution-voucher-auth-').join('evolution-voucher-stage-auth-');
}

function transformRecursive(target) {
  const stat = fs.statSync(target);
  if (stat.isDirectory()) {
    for (const name of fs.readdirSync(target)) transformRecursive(path.join(target, name));
    return;
  }
  if (!TEXT_EXTENSIONS.has(path.extname(target))) return;
  const before = fs.readFileSync(target, 'utf8');
  const after = transformText(before);
  if (after !== before) fs.writeFileSync(target, after);
}

function scanForForbidden(target, findings = []) {
  const stat = fs.statSync(target);
  if (stat.isDirectory()) {
    for (const name of fs.readdirSync(target)) scanForForbidden(path.join(target, name), findings);
    return findings;
  }
  if (!TEXT_EXTENSIONS.has(path.extname(target))) return findings;
  const text = fs.readFileSync(target, 'utf8');
  if (text.includes(PROD_REF) || text.includes(PROD_URL) || text.includes(PROD_KEY)) {
    findings.push(path.relative(ROOT, target));
  }
  return findings;
}

fs.rmSync(DEST, { recursive: true, force: true });
fs.mkdirSync(DEST, { recursive: true });

for (const name of fs.readdirSync(ROOT)) {
  const full = path.join(ROOT, name);
  if (!fs.statSync(full).isFile()) continue;
  if (ROOT_FILE_EXTENSIONS.has(path.extname(name)) || ROOT_SPECIAL_FILES.has(name)) {
    copyRecursive(full, path.join(DEST, name));
  }
}

for (const dir of SOURCE_DIRS) copyRecursive(path.join(ROOT, dir), path.join(DEST, dir));
transformRecursive(DEST);

const backendConfig = path.join(DEST, 'assets/js/backend-config.js');
if (!fs.existsSync(backendConfig)) throw new Error('Stage build failed: backend-config.js missing');
let configText = fs.readFileSync(backendConfig, 'utf8');
if (!configText.includes(STAGE_REF) || !configText.includes(STAGE_URL) || !configText.includes(STAGE_KEY)) {
  throw new Error('Stage build failed: Stage backend contract not present');
}

configText += `\n\n(function enforceVoucherStageBoundary(){\n  const expectedRef='${STAGE_REF}';\n  const expectedUrl='${STAGE_URL}';\n  const cfg=window.EVOLUTION_VOUCHER_BACKEND;\n  if(!cfg||cfg.projectId!==expectedRef||cfg.supabaseUrl!==expectedUrl||cfg.environment!=='stage'){\n    document.documentElement.innerHTML='<body style="font-family:system-ui;background:#111;color:#fff;padding:32px"><h1>Voucher Stage blocked</h1><p>Environment isolation check failed. No request was sent.</p></body>';\n    throw new Error('Voucher Stage environment isolation failure');\n  }\n  const show=()=>{if(document.getElementById('voucherStageBoundaryBadge'))return;const badge=document.createElement('div');badge.id='voucherStageBoundaryBadge';badge.textContent='VOUCHER STAGE';badge.style.cssText='position:fixed;right:10px;bottom:10px;z-index:2147483647;background:#5b3a00;color:#ffe08a;border:1px solid #9b6b00;border-radius:999px;padding:6px 10px;font:700 11px system-ui;letter-spacing:.08em;pointer-events:none';document.body.appendChild(badge);};\n  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',show,{once:true});else show();\n})();\n`;
fs.writeFileSync(backendConfig, configText);

fs.writeFileSync(path.join(DEST, 'STAGE_BUILD.txt'), [
  'GENERATED FILES - DO NOT EDIT MANUALLY',
  `environment=stage`,
  `project_ref=${STAGE_REF}`,
  `source=repository root frontend`,
  `site=${STAGE_SITE}`,
  ''
].join('\n'));

const forbidden = scanForForbidden(DEST);
if (forbidden.length) throw new Error(`Stage build blocked: Production backend reference found in ${forbidden.join(', ')}`);

console.log(`Voucher Stage mirror generated safely for ${STAGE_REF}`);
