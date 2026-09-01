import fs from 'node:fs';

const adapter=fs.readFileSync(new URL('../../../assets/js/voucher-theme-integration.js',import.meta.url),'utf8');
const library=fs.readFileSync(new URL('../../../voucher-theme-system-v1.js',import.meta.url),'utf8');

const required=[
  "templateTheme",
  "versionTheme",
  "voucherCard",
  "voucherState",
  "voucherThemeExperience",
  "EOVoucherThemes",
  "applyToVoucher",
  "options()"
];

for(const token of required){
  if(!adapter.includes(token))throw new Error(`Theme integration adapter missing contract token: ${token}`);
}

for(const theme of ['classic','birthday','promo','premium','cny','christmas','raya','deepavali','kids','valentine','mothers_day','corporate','elegant','minimal','anniversary']){
  if(!library.includes(`${theme}:`))throw new Error(`Shared theme library missing ${theme}`);
}

if(/supabase\.|\.rpc\(|from\(/.test(adapter))throw new Error('Theme integration adapter must remain frontend-only');

console.log('Voucher theme integration contract OK');
