import fs from 'node:fs';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
// The TypeScript frontend against node, bun and Haxe: each program of bench/
// compiled by tsc (run on node), by `bun build --compile` (bun-jit: bun's JIT
// in one executable, when bun is installed), by helder's compiler (native),
// and its Haxe version if it has one (bench/<Name>.hx: binary-trees.ts's
// BinaryTrees.hx; the app-* programs have none) by the same compiler, the
// outputs checked equal, timed as the minimum of N fresh processes after one
// untimed run each (startup and output included, compilation not). The runs
// are interleaved, one of each per round, so a loaded machine slows them alike.
// node tests/typescript/bench.mjs [--runs N] [--base dir] [--save dir] [names]
// --save copies the helder executables to dir, --base times dir's (an earlier
// --save) beside them: before and after a change, in the same rounds.
const T='tests/typescript',dir='bin/typescript/bench';fs.mkdirSync(dir,{recursive:true});
function run(cmd,args){const r=spawnSync(cmd,args,{encoding:'utf8',timeout:600000});if(r.error)throw r.error;assert.equal(r.status,0,r.stderr+'\n'+r.stdout);return r.stdout;}
const argv=process.argv.slice(2),only=[];let runs=5,base=null,save=null;
for(let i=0;i<argv.length;i++){if(argv[i]==='--runs')runs=Number(argv[++i]);else if(argv[i]==='--base')base=argv[++i];else if(argv[i]==='--save')save=argv[++i];else only.push(argv[i]);}
if(save)fs.mkdirSync(save,{recursive:true});
const compiler=run(process.execPath,['src/helder/compiler/build.mjs','--quiet']).trim();
const bun=spawnSync('bun',['--version'],{encoding:'utf8'}).status===0;
function timed(runners,oracle){
    for(const r of runners)assert.equal(run(r.cmd,r.args),oracle,r.name);
    const best=runners.map(()=>Infinity);
    for(let i=0;i<runs;i++)runners.forEach((r,k)=>{const start=process.hrtime.bigint();run(r.cmd,r.args);best[k]=Math.min(best[k],Number(process.hrtime.bigint()-start)/1e6);});
    return Object.fromEntries(runners.map((r,k)=>[r.name,best[k]]));
}
const cols=['node',...(bun?['bun-jit']:[]),'helder','/node',...(base?['base','base/now']:[]),'haxe','/haxe'];
console.log(`load ${os.loadavg().map(l=>l.toFixed(1)).join(' ')}, min of ${runs}, node ${process.version}${bun?', bun '+spawnSync('bun',['--version'],{encoding:'utf8'}).stdout.trim():''}`);
console.log('program'.padEnd(16)+cols.map(c=>c.padStart(9)).join(''));
const ms=v=>v===undefined?'':v.toFixed(0),ratio=(a,b)=>a===undefined||b===undefined?'':(a/b).toFixed(2);
for(const file of fs.readdirSync(`${T}/bench`).filter(f=>f.endsWith('.ts')).sort()){
    const name=file.slice(0,-3);
    if(only.length&&!only.includes(name))continue;
    run(process.execPath,['node_modules/typescript/bin/tsc','--target','esnext','--strict','--skipLibCheck','--module','commonjs','--outDir',`${dir}/js`,`${T}/bench/${file}`]);
    run(compiler,[`${T}/bench/${file}`,'-o',`${dir}/${name}`]);
    if(save)fs.copyFileSync(`${dir}/${name}`,`${save}/${name}`);
    const oracle=run(process.execPath,[`${dir}/js/${name}.js`]);
    const runners=[{name:'node',cmd:process.execPath,args:[`${dir}/js/${name}.js`]},{name:'helder',cmd:`${dir}/${name}`,args:[]}];
    if(bun){run('bun',['build','--compile',`${T}/bench/${file}`,'--outfile',`${dir}/bun/${name}`]);runners.push({name:'bun-jit',cmd:`${dir}/bun/${name}`,args:[]});}
    if(base&&fs.existsSync(`${base}/${name}`))runners.push({name:'base',cmd:`${base}/${name}`,args:[]});
    const hx=name.split('-').map(w=>w[0].toUpperCase()+w.slice(1)).join('');
    if(fs.existsSync(`${T}/bench/${hx}.hx`)){
        run(compiler,['-D','hxmc.markup-braces','-cp',`${T}/bench`,'-main',hx,'--custom-target',`hxmc=${dir}/${hx}`]);
        runners.push({name:'haxe',cmd:`${dir}/${hx}`,args:[]});
    }
    const t=timed(runners,oracle);
    const cells={node:ms(t.node),'bun-jit':ms(t['bun-jit']),helder:ms(t.helder),'/node':ratio(t.helder,t.node),base:ms(t.base),'base/now':ratio(t.base,t.helder),haxe:ms(t.haxe),'/haxe':ratio(t.helder,t.haxe)};
    console.log(name.padEnd(16)+cols.map(c=>cells[c].padStart(9)).join(''));
}
