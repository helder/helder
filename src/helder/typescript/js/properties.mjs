// RegexProperties.hx: the code points of each Unicode property a RegExp's
// \p{...} names (General_Category, Script, Script_Extensions and
// ECMAScript's binary properties), as node's own RegExp matches them: the
// oracle's Unicode version. The names and their aliases come from that
// version's PropertyValueAliases.txt.
//
//   node src/helder/typescript/js/properties.mjs [--check]
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const version=`${process.versions.unicode}.0`;
const cache=path.resolve(`bin/cache/unicode-${version}`);fs.mkdirSync(cache,{recursive:true});
const aliasesFile=path.join(cache,'PropertyValueAliases.txt');
if(!fs.existsSync(aliasesFile)) {
  const r=spawnSync('curl',['-fsSL','--max-time','60',`https://www.unicode.org/Public/${version}/ucd/PropertyValueAliases.txt`,'-o',aliasesFile],{encoding:'utf8'});
  if(r.status!==0)throw Error(r.stderr);
}
// (ECMAScript's binary properties, table-binary-unicode-properties: their names and aliases)
const binary=['ASCII','ASCII_Hex_Digit AHex','Alphabetic Alpha','Any','Assigned','Bidi_Control Bidi_C','Bidi_Mirrored Bidi_M',
  'Case_Ignorable CI','Cased','Changes_When_Casefolded CWCF','Changes_When_Casemapped CWCM','Changes_When_Lowercased CWL',
  'Changes_When_NFKC_Casefolded CWKCF','Changes_When_Titlecased CWT','Changes_When_Uppercased CWU','Dash','Default_Ignorable_Code_Point DI',
  'Deprecated Dep','Diacritic Dia','Emoji','Emoji_Component EComp','Emoji_Modifier EMod','Emoji_Modifier_Base EBase',
  'Emoji_Presentation EPres','Extended_Pictographic ExtPict','Extender Ext','Grapheme_Base Gr_Base','Grapheme_Extend Gr_Ext',
  'Hex_Digit Hex','IDS_Binary_Operator IDSB','IDS_Trinary_Operator IDST','ID_Continue IDC','ID_Start IDS','Ideographic Ideo',
  'Join_Control Join_C','Logical_Order_Exception LOE','Lowercase Lower','Math','Noncharacter_Code_Point NChar','Pattern_Syntax Pat_Syn',
  'Pattern_White_Space Pat_WS','Quotation_Mark QMark','Radical','Regional_Indicator RI','Sentence_Terminal STerm','Soft_Dotted SD',
  'Terminal_Punctuation Term','Unified_Ideograph UIdeo','Uppercase Upper','Variation_Selector VS','White_Space space','XID_Continue XIDC','XID_Start XIDS'
].map(s=>s.split(' '));
const values={gc:[],sc:[]};
for(const line of fs.readFileSync(aliasesFile,'utf8').split('\n')) {
  const f=line.split('#')[0].split(';').map(s=>s.trim());
  if(f[0]!=='gc'&&f[0]!=='sc')continue;
  // (canonical name first: the long one)
  const names=[f[2],f[1],...f.slice(3)].filter(n=>n&&n!=='n/a');
  values[f[0]].push([...new Set(names)]);
}
const valid=(p,flags='u')=>{try{new RegExp(`\\p{${p}}`,flags);return true;}catch{return false;}};
// (every code point in one string, the surrogates apart: a lone one matched alone)
const all=[];for(let c=0;c<0x110000;c++)if(c<0xd800||c>0xdfff)all.push(String.fromCodePoint(c));
const text=all.join('');
const cpAt=k=>k<0xd800?k:k<0xf800?k+0x800:0x10000+(k-0xf800)/2;
function ranges(p) {
  const found=[],re=new RegExp(`\\p{${p}}+`,'gu'),one=new RegExp(`^\\p{${p}}$`,'u');
  for(const m of text.matchAll(re)) {
    const a=cpAt(m.index),u=m[0].charCodeAt(m[0].length-1),last=u>=0xdc00&&u<=0xdfff?2:1,z=cpAt(m.index+m[0].length-last);
    // (a run across the surrogates, which the text leaves out)
    if(a<0xd800&&z>0xdfff)found.push([a,0xd7ff],[0xe000,z]);else found.push([a,z]);
  }
  for(let s=0xd800;s<=0xdfff;s++)if(one.test(String.fromCharCode(s)))found.push([s,s]);
  found.sort((x,y)=>x[0]-y[0]);
  const out=[];
  for(const [a,z] of found)if(out.length&&out[out.length-1]+1>=a)out[out.length-1]=Math.max(out[out.length-1],z);else out.push(a,z);
  return out;
}
// (ranges as base-36 gaps and lengths: start - previous end, end - start)
function encode(rs) {
  const parts=[];let prev=-1;
  for(let k=0;k<rs.length;k+=2){parts.push((rs[k]-prev-1).toString(36),(rs[k+1]-rs[k]).toString(36));prev=rs[k+1];}
  return parts.join(',');
}
const entries=[],aliases=[];
const leaf=values.gc.filter(n=>n[1].length===2);
const groups=values.gc.filter(n=>n[1].length===1||n[1]==='LC');
for(const names of leaf) {
  if(!valid(`gc=${names[0]}`))continue;
  entries.push([`gc=${names[0]}`,encode(ranges(`gc=${names[0]}`))]);
  for(const a of names)aliases.push([a,`gc=${names[0]}`]);
}
// (a group: the union of its categories, its members listed)
for(const names of groups) {
  if(!valid(`gc=${names[0]}`))continue;
  const members=leaf.filter(l=>names[1]==='LC'?['Lu','Ll','Lt'].includes(l[1]):l[1][0]===names[1]).map(l=>l[0]);
  entries.push([`gc=${names[0]}`,'='+members.join('|')]);
  for(const a of names)aliases.push([a,`gc=${names[0]}`]);
}
for(const names of values.sc) {
  if(!valid(`sc=${names[0]}`))continue;
  const sc=ranges(`sc=${names[0]}`),scx=ranges(`scx=${names[0]}`);
  entries.push([`sc=${names[0]}`,encode(sc)]);
  // (Script_Extensions as a difference from Script: the code points it adds and takes away)
  const inSc=new Set(),inScx=new Set();
  for(let k=0;k<sc.length;k+=2)for(let c=sc[k];c<=sc[k+1];c++)inSc.add(c);
  for(let k=0;k<scx.length;k+=2)for(let c=scx[k];c<=scx[k+1];c++)inScx.add(c);
  const diff=[];
  for(const c of [...new Set([...inSc,...inScx])].sort((x,y)=>x-y))if(inSc.has(c)!==inScx.has(c)){if(diff.length&&diff[diff.length-1]+1===c)diff[diff.length-1]=c;else diff.push(c,c);}
  if(diff.length)entries.push([`scx=${names[0]}`,'^'+encode(diff)]);
  for(const a of names)aliases.push([`sc=${a}`,`sc=${names[0]}`]);
}
for(const names of binary) {
  if(!valid(names[0]))throw Error(`node refuses \\p{${names[0]}}`);
  if(['Any','ASCII','Assigned'].includes(names[0]))entries.push([names[0],names[0]==='Assigned'?'!gc=Unassigned':encode(names[0]==='Any'?[0,0x10ffff]:[0,127])]);
  else entries.push([names[0],encode(ranges(names[0]))]);
  for(const a of names)aliases.push([a,names[0]]);
}
const data=entries.map(([k,v])=>`${k}:${v}`).join(';');
const names=aliases.filter(([a,c])=>a!==c&&a!==c.replace(/^(gc|sc)=/,'')).map(([a,c])=>`${a}:${c}`).join(';');
function literal(s){const parts=[];for(let i=0;i<s.length;i+=4096)parts.push(JSON.stringify(s.slice(i,i+4096)));return parts.join('\n\t\t+ ');}
const out=`package helder.typescript.js;

// Generated by properties.mjs (beside it) from node ${process.versions.node}'s RegExp, Unicode ${version}:
// each property's code points (gaps and lengths in base 36; a group of
// General_Category its categories; Script_Extensions its differences from
// Script), and the names' aliases. Installed by programs whose regular
// expressions have \\p{...} (Features: RegExpProperties).
class RegexProperties {
	public static function data():String
		return ${literal(data)};

	public static function aliases():String
		return ${literal(names)};
}
`;
const file='src/helder/typescript/js/RegexProperties.hx';
if(process.argv.includes('--check')) {
  if(fs.readFileSync(file,'utf8')!==out){console.error(`${file} is not what node ${process.versions.node} (Unicode ${version}) makes: node src/helder/typescript/js/properties.mjs`);process.exit(1);}
} else fs.writeFileSync(file,out);
console.log(`${file}: Unicode ${version}, ${entries.length} properties, ${aliases.length} names, ${Math.round(data.length/1024)} KB of ranges`);
