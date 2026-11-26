import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
import os from 'node:os';
import { takeShard } from '../shard.mjs';
// The TypeScript frontend's checks (bun run test typescript): every program
// of cases/ and modules/ compiled by tsc and run on node, then compiled by
// helder's compiler natively and as wasm32-wasi, their outputs compared; standards/
// throw on a mismatch themselves; reject/ must fail with a diagnostic.
// --shard i/n selects this machine's work. --jobs sets its local worker count.
// (UTC, as CI's machines: node, the oracle, writes local times in the
// machine's zone, a WASI program in UTC)
process.env.TZ='UTC';
const T='tests/typescript';
const args=process.argv.slice(2);
const [partI,partN]=takeShard(args);
const jobs=args[0]==='--jobs' ? Number(args[1]) : Math.max(1,Math.min(4,os.availableParallelism()));
if((args.length && (args[0]!=='--jobs' || args.length!==2)) || !Number.isSafeInteger(jobs) || jobs<1) {
    throw new Error('usage: run.mjs [--shard i/n] [--jobs n]');
}
if(jobs>1) {
    const b=spawnSync(process.execPath,['src/helder/compiler/build.mjs'],{stdio:['ignore','ignore','inherit']});
    if(b.status!==0)process.exit(1);
    const {spawn}=await import('node:child_process');
    const t0=Date.now();
    const shards=Array.from({length:jobs},(_,i)=>`${partI*jobs+i}/${partN*jobs}`);
    const codes=await Promise.all(shards.map(shard=>new Promise(resolve=>{
        const p=spawn(process.execPath,[process.argv[1],'--shard',shard,'--jobs','1'],{stdio:['ignore','inherit','inherit']});
        p.on('close',code=>resolve(code));
    })));
    const failed=shards.filter((_,i)=>codes[i]!==0);
    console.log(`typescript: ${jobs} workers for shard ${partI}/${partN} in ${Math.round((Date.now()-t0)/1000)} s${failed.length?`, failed: ${failed.join(', ')}`:', all passed'}`);
    process.exit(failed.length?1:0);
}
const [shardI,shardN]=[partI,partN];
let unit=0;
const mine=()=>unit++%shardN===shardI;
const dir=`bin/typescript/run-${process.pid}`; fs.mkdirSync(dir,{recursive:true});
const built=spawnSync(process.execPath,['src/helder/compiler/build.mjs'],{encoding:'utf8',stdio:['ignore','pipe','inherit']});
if(built.status!==0)process.exit(1);
const compiler=built.stdout.trim();
// (the IR checks: the verifier, the text form and its golden file)
const hxmc=spawnSync(process.execPath,['src/helder/compiler/build.mjs','--sources','--quiet'],{encoding:'utf8'}).stdout.trim();
const launcher='node_modules/@hxmc/cli/hxmc/bootstrap/haxe.mjs';
if(mine()) {
ok(run(process.execPath,[launcher,'-D','hxmc.markup-braces','-cp','src','-cp',T,'-cp',`${hxmc}/haxe/src`,'-cp',`${hxmc}/hxmc/src`,'-main','IrTests','-D','hih_no_generators','-D','disable-parallelism','--custom-target',`hxmc=${dir}/ir-tests`]),'IR checks build');
const ir=run(`${dir}/ir-tests`,process.env.BLESS?['--write-golden']:[]);ok(ir,'IR checks');process.stdout.write(ir.stdout);
}
const tsc=['node_modules/typescript/bin/tsc','--target','esnext','--strict','--skipLibCheck'];
// (maxBuffer: definitions/pbr.ts prints every variant's shader text in four languages, past spawnSync's 1 MB)
function run(cmd,args) {const r=spawnSync(cmd,args,{encoding:'utf8',timeout:120000,maxBuffer:64*1024*1024});if(r.error)throw r.error;return r;}
// (util.inspect's symbol keys: Node 24 writes Symbol(k): v, earlier ones
// [Symbol(k)]: v; helder's one way: both outputs written one way, so the
// oracle's version does not matter)
// (and Float16Array, DataView's float16s: Node 24's, behind V8's flag before)
const oracleFlags=typeof Float16Array==='undefined'?['--js-float16array']:[];
function inspected(s) {return s.replace(/\[(Symbol\((?:[^()]|\([^()]*\))*\))\]: /g,'$1: ');}
function ok(r,what) {assert.equal(r.status,0,`${what}\n${r.stdout}\n${r.stderr}`);}
// (natively this machine's own target: linux-x86_64 on CI, a Mac's on a
// Mac, its programs linked with that platform package's runtime objects)
const HOST=`${{linux:'linux',darwin:'macos',win32:'windows'}[process.platform]}-${{x64:'x86_64',arm64:'arm64'}[process.arch]}`;
const targets=[HOST,'wasm32-wasi'];
const files=fs.readdirSync(`${T}/cases`).filter(f=>f.endsWith('.ts')).sort();
let passed=0;
for(const file of files) {
    if(!mine())continue;
    const stem=path.basename(file,'.ts');
    // (a known failure: `// skip: <why>` in it, run by nothing until fixed)
    const skip=fs.readFileSync(`${T}/cases/${file}`,'utf8').match(/^\/\/ skip: (.*)$/m);
    if(skip) {console.log(`SKIP ${stem}: ${skip[1]}`);continue;}
    const reference=run(process.execPath,[...tsc,'--module','commonjs','--outDir',`${dir}/js`,`${T}/cases/${file}`]); ok(reference,'reference tsc');
    // (a case of what only a newer Node has, Promise.try, RegExp.escape,
    // Error.isError: its output as Node 24 writes it beside it, <stem>.out,
    // the oracle where this Node cannot run it, checked against it where it can)
    const saved=`${T}/cases/${stem}.out`;
    let oracle=run(process.execPath,[...oracleFlags,`${dir}/js/${stem}.js`]);
    if(fs.existsSync(saved)) {
        const want=fs.readFileSync(saved,'utf8');
        if(oracle.status!==0) {console.log(`(${stem}: node ${process.version} cannot run it, ${stem}.out the oracle)`);oracle={status:0,stdout:want};}
        else assert.equal(inspected(oracle.stdout),inspected(want),`${stem}.out is not what node writes`);
    }
    ok(oracle,'reference node');
    for(const target of targets) {
        const out=`${dir}/${stem}${target!==HOST?`-${target}.wasm`:''}`;
        const compiled=run(compiler,[`${T}/cases/${file}`,'--roundtrip-ir','--target',target,'-o',out,'--dump-ir',`${out}.ir`]);
        ok(compiled,`${stem} compile ${target}`);
        const launchers=target===HOST?[[out,[]]]:[[process.execPath,[`${T}/run-wasi.cjs`,out]]];
        for(const [cmd,args] of launchers) {
            const result=run(cmd,args);
            assert.equal(result.status,oracle.status,`${stem} exit ${target} ${args[0]??''}\n${result.stderr}`);
            assert.equal(inspected(result.stdout),inspected(oracle.stdout),`${stem} stdout ${target} ${args[0]??''}`);
        }
        console.log(`PASS ${stem} ${target}`); passed++;
    }
}
// Multi-file programs: tests/modules/<name>/main.ts, referenced as ES modules.
const programs=fs.existsSync(`${T}/modules`)?fs.readdirSync(`${T}/modules`).sort():[];
for(const name of programs) {
    if(!mine())continue;
    const out=`${dir}/modules/${name}`;fs.mkdirSync(out,{recursive:true});
    fs.writeFileSync(`${out}/package.json`,'{"type":"module"}');
    const reference=run(process.execPath,[...tsc,'--module','esnext','--moduleResolution','bundler','--outDir',out,`${T}/modules/${name}/main.ts`]); ok(reference,'reference tsc');
    const oracle=run(process.execPath,[...oracleFlags,`${out}/main.js`]); ok(oracle,'reference node');
    for(const target of targets) {
        const binary=`${dir}/module-${name}${target!==HOST?`-${target}.wasm`:''}`;
        ok(run(compiler,[`${T}/modules/${name}/main.ts`,'--roundtrip-ir','--target',target,'-o',binary]),`${name} compile ${target}`);
        const launcher=target===HOST?[binary,[]]:[process.execPath,[`${T}/run-wasi.cjs`,binary]];
        const result=run(launcher[0],launcher[1]);
        assert.equal(result.status,oracle.status,`module ${name} exit ${target}\n${result.stderr}`);
        assert.equal(inspected(result.stdout),inspected(oracle.stdout),`module ${name} stdout ${target}`);
        console.log(`PASS module ${name} ${target}`); passed++;
    }
}

// Self-checking programs for current specified behavior where Node, the
// oracle, still differs: each throws on a mismatch.
const standards=fs.readdirSync(`${T}/standards`).filter(f=>/\.[jt]s$/.test(f)).sort();
for(const file of standards)for(const target of targets) {
    if(!mine())continue;
    const out=`${dir}/standard-${file}${target!==HOST?`-${target}.wasm`:''}`;
    ok(run(compiler,[`${T}/standards/${file}`,'--roundtrip-ir','--target',target,'-o',out]),`${file} compile ${target}`);
    ok(target===HOST?run(out,[]):run(process.execPath,[`${T}/run-wasi.cjs`,out]),`${file} ${target}`);
    console.log(`PASS standard ${file} ${target}`); passed++;
}
for(const file of fs.readdirSync(`${T}/reject`).filter(f=>/\.tsx?$/.test(f)).sort()) {
    if(!mine())continue;
    const out=`${dir}/reject-${file.replace(/\.tsx?$/,'')}`; fs.rmSync(out,{force:true});
    const r=run(compiler,[`${T}/reject/${file}`,'-o',out]);
    assert.notEqual(r.status,0,`${file} should be rejected`);
    assert.match(r.stderr,/TS(HX)?[0-9]+:/,`${file} needs a diagnostic code`);
    const expected=fs.readFileSync(`${T}/reject/${file}`,'utf8').match(/expect: (.*?)(?: \*\/)?$/m)?.[1];
    if(expected)assert.ok(r.stderr.includes(expected),`${file} should report ${expected}, got ${r.stderr}`);
    assert.equal(fs.existsSync(out),false,`${file} must not emit an executable`);
    console.log(`PASS diagnostic ${file}`);
}
// src/helder/ui/style.d.ts, written by hand: its StyleProps naming
// helder.ui.StyleProps' properties, no more, no fewer
if(mine()) {
const hx=[...fs.readFileSync('src/helder/ui/StyleProps.hx','utf8').matchAll(/^\t\?(\w+):/gm)].map(m=>m[1]).sort().join(' ');
const ts=[...fs.readFileSync('src/helder/ui/style.d.ts','utf8').split('export type StyleProps = {')[1].split('};')[0].matchAll(/^\t(\w+)\?:/gm)].map(m=>m[1]).sort().join(' ');
assert.equal(ts,hx,'src/helder/ui/style.d.ts: its StyleProps are not helder.ui.StyleProps\' properties');
console.log('PASS style.d.ts');
}
// Programs calling helder's Haxe API (and TSX), rendering headless with
// tests/view's TestRenderer: their output checked against <name>.out
for(const file of fs.readdirSync(`${T}/helder`).filter(f=>/\.tsx?$/.test(f)&&!f.endsWith('.d.ts')).sort())for(const target of targets) {
    if(!mine())continue;
    const stem=file.replace(/\.tsx?$/,''),out=`${dir}/helder-${stem}${target!==HOST?`-${target}.wasm`:''}`;
    ok(run(compiler,[`${T}/helder/${file}`,'--cp','tests/view','--cp','tests/ui','--roundtrip-ir','--target',target,'-o',out]),`${file} compile ${target}`);
    const r=target===HOST?run(out,[]):run(process.execPath,[`${T}/run-wasi.cjs`,out]);ok(r,`${file} ${target}`);
    assert.equal(r.stdout,fs.readFileSync(`${T}/helder/${stem}.out`,'utf8'),`${file} stdout ${target}`);
    console.log(`PASS helder ${file} ${target}`);
}
// helder/native/platform's constants folded as Haxe's Platform.os() is: platform/main.ts
// and Main.hx built for Linux (glibc's dynamic mode, where a C function of a
// shared library is an import) and wasm32-wasi, their Windows branch
// (kernel32's GetTickCount64) not in the binary; the same TS with a condition
// that is no constant names it (the check's control)
if(mine()) {
    const P=`${T}/platform`,has=(f,s)=>fs.readFileSync(f).includes(Buffer.from(s));
    // (its expected output Linux x86-64's and WASI's)
    for(const target of targets.filter(t=>t==='linux-x86_64'||t==='wasm32-wasi')) {
        const glibc=target===HOST?['-D','hxmc.libc=glibc']:[];
        const ts=`${dir}/platform-ts${target!==HOST?'.wasm':''}`,hx=`${dir}/platform-hx${target!==HOST?'.wasm':''}`;
        ok(run(compiler,[`${P}/main.ts`,'--cp',P,'--target',target,...glibc,'-o',ts]),`platform/main.ts compile ${target}`);
        ok(run(compiler,['-D','hxmc.markup-braces','-cp',P,'-main','Main','-D',`hxmc.target=${target}`,...glibc,'--custom-target',`hxmc=${hx}`]),`platform/Main.hx compile ${target}`);
        const os=target===HOST?'linux':'wasi';
        const exec=f=>target===HOST?run(f,[]):run(process.execPath,[`${T}/run-wasi.cjs`,f]);
        const a=exec(ts);ok(a,`platform/main.ts ${target}`);
        assert.equal(a.stdout,`not windows: ${os} ${target}\n${os==='wasi'?'no x86-64 code':'x86-64'}\na Linux or a WASI build\n`,`platform/main.ts stdout ${target}`);
        const h=exec(hx);ok(h,`platform/Main.hx ${target}`);
        assert.equal(h.stdout,`not windows: ${os}\n`,`platform/Main.hx stdout ${target}`);
        for(const f of [ts,hx]) assert.ok(!has(f,'GetTickCount64')&&!has(f,'kernel32'),`${f}: a Windows branch linked for ${target}`);
        console.log(`PASS platform ${target} (main.ts ${Math.round(fs.statSync(ts).size/1024)} KB, Main.hx ${Math.round(fs.statSync(hx).size/1024)} KB: no GetTickCount64)`);
    }
    if(process.platform==='linux') {
        const src=fs.readFileSync(`${P}/main.ts`,'utf8').replace('if (platform.os === "windows")','if (Math.random() > 2)');
        fs.writeFileSync(`${P}/control.ts`,src);
        try {
            const c=`${dir}/platform-control`;
            ok(run(compiler,[`${P}/control.ts`,'--cp',P,'-D','hxmc.libc=glibc','-o',c]),'platform/control.ts compile');
            assert.ok(has(c,'GetTickCount64'),'the control names GetTickCount64');
        } finally {fs.rmSync(`${P}/control.ts`);}
        console.log('PASS platform control (a condition that is no constant: GetTickCount64 linked)');
    }
}
// helder/native's definitions: native.mjs (native.c, objc, com, jni where
// their systems are; refused elsewhere)
if(mine()) {
ok(run(process.execPath,[`${T}/native.mjs`]),'helder/native\'s checks (native.mjs)');
console.log('PASS native (native.mjs)');
}
// helder's declaration files written by a build when stale (stamp.mjs)
if(mine()) {
const r=run(process.execPath,[`${T}/stamp.mjs`]);ok(r,'the declarations\' stamp (stamp.mjs)');process.stdout.write(r.stdout);
}
// Programs whose values their types do not describe: compiled, then stopped
// where such a value enters a typed slot (TSHX100, at the line of expect)
for(const file of fs.readdirSync(`${T}/diverge`).filter(f=>f.endsWith('.ts')).sort())for(const target of targets) {
    if(!mine())continue;
    const out=`${dir}/diverge-${path.basename(file,'.ts')}${target!==HOST?`-${target}.wasm`:''}`;
    ok(run(compiler,[`${T}/diverge/${file}`,'--target',target,'-o',out]),`${file} compile ${target}`);
    const r=target===HOST?run(out,[]):run(process.execPath,[`${T}/run-wasi.cjs`,out]);
    const expected=fs.readFileSync(`${T}/diverge/${file}`,'utf8').match(/expect: (.*)$/m)[1];
    assert.notEqual(r.status,0,`${file} should diverge ${target}`);
    assert.ok(r.stderr.includes(expected),`${file} should report ${expected} ${target}, got ${r.stderr}`);
    console.log(`PASS diverge ${file} ${target}`);
}
// Projects with a tsconfig.json: built and run, or refused at the option's line (expect)
for(const name of fs.readdirSync(`${T}/configs`).sort()) {
    if(!mine())continue;
    const d=`${T}/configs/${name}`,out=`${dir}/config-${name}`;
    const r=run(compiler,[`${d}/main.ts`,'-o',out]);
    if(fs.existsSync(`${d}/expect`)) {
        const expected=fs.readFileSync(`${d}/expect`,'utf8').trim();
        assert.notEqual(r.status,0,`${name} should be refused`);
        assert.ok(r.stderr.includes(expected),`${name} should report ${expected}, got ${r.stderr}`);
    } else {
        ok(r,`${name} compile`);
        ok(run(out,[]),`${name} run`);
    }
    console.log(`PASS config ${name}`);
}
// Definitions (src/helder/compiler/README.md) in both languages:
// definitions/<name>.ts (or .tsx) and the Haxe program <Name>.hx, built natively and
// as wasm32-wasi, print the same (a shader's text in all four languages,
// its writers' bytes); each pair of definitions/reject is refused by both
// with the same diagnostic (expect)
const D=`${T}/definitions`;
for(const file of fs.readdirSync(D).filter(f=>/\.tsx?$/.test(f)&&f!=='print.ts').sort())for(const target of targets) {
    if(!mine())continue;
    const stem=file.replace(/\.tsx?$/,''),main=stem[0].toUpperCase()+stem.slice(1),wasm=target!==HOST;
    // (a case for some targets only: `// targets: <t>,...` in it)
    const only=fs.readFileSync(`${D}/${file}`,'utf8').match(/^\/\/ targets: (.*)$/m)?.[1].split(',');
    if(only&&!only.includes(target))continue;
    const ts=`${dir}/def-${stem}${wasm?'.wasm':''}`,hx=`${dir}/def-${main}${wasm?'.wasm':''}`;
    ok(run(compiler,[`${D}/${file}`,'-D','helder.gfx.shaders=all','--target',target,'-o',ts]),`${file} compile ${target}`);
    ok(run(compiler,['-D','hxmc.markup-braces','-cp','src','-cp',D,'-main',main,'-D','helder.gfx.shaders=all','-D',`hxmc.target=${target}`,'--custom-target',`hxmc=${hx}`]),`${main}.hx compile ${target}`);
    const exec=f=>wasm?run(process.execPath,[`${T}/run-wasi.cjs`,f]):run(f,[]);
    const a=exec(ts),b=exec(hx);ok(a,`${file} ${target}`);ok(b,`${main}.hx ${target}`);
    assert.ok(a.stdout.length>0,`${file} printed nothing`);
    assert.equal(a.stdout,b.stdout,`${file} and ${main}.hx print alike ${target}`);
    console.log(`PASS definition ${file} = ${main}.hx ${target}`);
}
for(const file of fs.readdirSync(`${D}/reject`).filter(f=>/\.tsx?$/.test(f)).sort()) {
    if(!mine())continue;
    const main='Reject'+file.replace(/\.tsx?$/,'').split('-').map(p=>p[0].toUpperCase()+p.slice(1)).join('');
    const expect=f=>fs.readFileSync(f,'utf8').match(/expect: (.*)$/m)[1];
    const want=expect(`${D}/reject/${file}`);
    assert.equal(expect(`${D}/reject/${main}.hx`),want,`${file} and ${main}.hx expect the same diagnostic`);
    const out=`${dir}/def-reject`;fs.rmSync(out,{force:true});
    const a=run(compiler,[`${D}/reject/${file}`,'-o',out]);
    assert.notEqual(a.status,0,`${file} should be rejected`);
    assert.ok(a.stderr.includes(want),`${file} should report ${want}, got ${a.stderr}`);
    // (typed for hxmc: a job's checks are its)
    const b=run(compiler,['-D','hxmc.markup-braces','-cp','src','-cp',`${D}/reject`,'-main',main,'--custom-target',`hxmc=${out}-hx`]);
    assert.notEqual(b.status,0,`${main}.hx should be rejected`);
    assert.ok((b.stdout+b.stderr).includes(want),`${main}.hx should report ${want}, got ${b.stdout}${b.stderr}`);
    console.log(`PASS definition rejected: ${file}, ${main}.hx`);
}
// tsgo's error through a compilation server (helder dev's, the fuzzer's):
// at its line and column after non-ASCII text (Haxe's positions count code
// points, not bytes)
if(mine()) {
    const {Server}=await import('./fuzz/Server.mjs');
    const file=`${dir}/positions.ts`;
    fs.writeFileSync(file,'const a: string = "😀é"\nconst b: string = "ﬀ"\nconst n: number = "oops"\nconsole.log(a, b, n)\n');
    const server=await Server.start(compiler,process.cwd());
    try {
        const r=await server.build(file,`${dir}/positions`);
        assert.match(r.messages,/positions\.ts:3: characters 7-8/,`a compilation server's position of tsgo's error\n${r.messages}`);
    } finally {server.stop();}
    console.log('PASS a compilation server\'s position of tsgo\'s error');
}
// The fuzzer's short run (tests/typescript/fuzz): random programs of a
// fixed seed against node, natively and a sample as wasm32-wasi, in a
// directory of this run's (its findings kept there, not shrunk)
if(mine()) {
    const r=spawnSync(process.execPath,['tests/typescript/fuzz/fuzz.mjs','--seed','0','--programs','8','--out',`${dir}/fuzz`,'--no-shrink'],{encoding:'utf8',timeout:900000,maxBuffer:64*1024*1024});
    ok(r,'the fuzzer\'s short run (fuzz.mjs)');
    process.stdout.write(r.stdout.split('\n').filter(l=>l.startsWith('typescript fuzz: 8')).join('\n')+'\n');
    console.log('PASS fuzz (seed 0, 8 programs)');
}
// helder/math's and helder/gfx's TypeScript, as their typescript.mjs write them
if(mine())ok(run(process.execPath,['src/helder/math/typescript.mjs','--check']),'src/helder/math/index.ts');
if(mine())ok(run(process.execPath,['src/helder/gfx/typescript.mjs','--check']),'src/helder/gfx/index.ts');
// The CLI end to end: TypeScript entries built and run by `helder run` (a file, a directory)
// (one unit with helder dev's below: the CLI built once)
if(mine()) {
for(const entry of ['examples/ts-hello/main.ts','examples/ts-hello']) {
    const r=run(process.execPath,['src/helder/cli/run.mjs','run',entry]);ok(r,`helder run ${entry}`);
    assert.match(r.stdout,/1\. hello, helder\n2\. hello, TypeScript\ndone\n/,`helder run ${entry}`);
    console.log(`PASS helder run ${entry}`);
}
// `helder dev` of examples/ts-ticker (a copy): an edit to label.ts rebuilds
// it and swaps it in, its signal's count going on (fast refresh's keys),
// its builds counted by keep (a value kept by its key)
{
    const work=`${dir}/ticker`;fs.mkdirSync(work,{recursive:true});
    for(const f of ['main.ts','label.ts'])fs.copyFileSync(`examples/ts-ticker/${f}`,`${work}/${f}`);
    const {spawn}=await import('node:child_process');
    const p=spawn(process.execPath,['src/helder/cli/run.mjs','dev',`${work}/main.ts`],{stdio:['ignore','pipe','pipe'],detached:true});
    let out='';p.stdout.on('data',d=>out+=d);p.stderr.on('data',d=>out+=d);
    const until=async(re,ms)=>{const end=Date.now()+ms;while(Date.now()<end){const m=out.match(re);if(m)return m;await new Promise(r=>setTimeout(r,50));}return null;};
    const before=await until(/tick 3\n/,120000);
    fs.writeFileSync(`${work}/label.ts`,fs.readFileSync(`${work}/label.ts`,'utf8').replace('tick','TOCK'));
    const after=await until(/TOCK (\d+)\n/,60000);
    // (its group: the CLI, its compilation server, the program)
    const stop=sig=>{try{process.kill(-p.pid,sig);}catch{}};
    stop('SIGINT');await new Promise(r=>setTimeout(r,1000));stop('SIGKILL');
    assert.ok(before&&after,`helder dev examples/ts-ticker: no reload seen\n${out}`);
    assert.ok(Number(after[1])>=3,`helder dev examples/ts-ticker: the count started over (TOCK ${after[1]} after tick 3)\n${out}`);
    assert.match(out,/build 1\n[^]*build 2\n/,`helder dev examples/ts-ticker: keep's count of builds not kept\n${out}`);
    console.log(`PASS helder dev examples/ts-ticker (tick 3 ... TOCK ${after[1]}, build 1 ... build 2)`);
}
}
const total=(files.length+programs.length+standards.length)*targets.length;
console.log(shardN>1?`shard ${shardI}/${shardN}: ${passed} of the ${total} compared checks passed`:`${passed}/${total} checks passed (tsc + node; native, wasm32-wasi)`);
