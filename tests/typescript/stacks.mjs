import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {take} from '../../src/helder/cli/slots.mjs';
import assert from 'node:assert/strict';
import {SourceMap} from 'node:module';
// Errors' stacks (bun run test typescript, its stacks): each program of
// stacks/ compiled by tsc with source maps and run by node
// (--enable-source-maps, --trace-uncaught: a thrown value's frames), then by
// helder's compiler for this machine and wasm32-wasi; the frames in the
// program's own files (name, file, line, column), the lines that are no
// frames and the exit status the same. WebAssembly has no table of lines: an
// error's frame there is where its `new` ran (node's first), then the async
// functions awaiting. A program calling helder's API (no node's) is checked
// against its output beside it.
const T='tests/typescript/stacks',dir='bin/typescript/stacks';
fs.rmSync(dir,{recursive:true,force:true});fs.mkdirSync(`${dir}/js`,{recursive:true});
fs.writeFileSync(`${dir}/js/package.json`,'{"type":"module"}');
// (under a slot of the machine's job limit)
function run(cmd,args){const release=take();try{const r=spawnSync(cmd,args,{encoding:'utf8',timeout:120000});if(r.error)throw r.error;return r;}finally{release?.();}}
const compiler=run(process.execPath,['src/helder/compiler/build.mjs','--quiet']);
assert.equal(compiler.status,0,compiler.stderr);
const helder=compiler.stdout.trim();
const files=fs.readdirSync(T).filter(f=>f.endsWith('.ts')).sort();
const oracle=files.filter(f=>!fs.existsSync(`${T}/${f.slice(0,-3)}.out`));
const tsc=run(process.execPath,['node_modules/typescript/bin/tsc','--target','esnext','--strict','--skipLibCheck','--module','esnext','--moduleResolution','bundler','--moduleDetection','force','--sourceMap','--outDir',`${dir}/js`,...oracle.map(f=>`${T}/${f}`)]);
assert.equal(tsc.status,0,tsc.stdout);
// (a frame: at name (file:line:column), or at file:line:column; the program's
// own files only, named from here, an unnamed one <anonymous>)
const frame=/^\s+at (?:(.+?) \()?(?:file:\/\/)?([^()]+):(\d+):(\d+)\)?$/;
function parse(text){
    const blocks=[];
    for(const line of text.split('\n')){
        const m=line.match(frame);
        if(!m){if(line.trim()!==''&&!/^\s+at /.test(line))blocks.push({line,frames:[]});continue;}
        let file=path.relative(process.cwd(),m[2]),at=`${m[3]}:${m[4]}`;
        // (node's frames of a thrown value, --trace-uncaught's, are the JavaScript's: mapped here)
        if(file.startsWith(`${dir}/js/`)&&file.endsWith('.js')){
            const e=new SourceMap(JSON.parse(fs.readFileSync(`${file}.map`,'utf8'))).findEntry(m[3]-1,m[4]-1);
            if(!e.originalSource)continue;
            file=path.relative(process.cwd(),path.resolve(path.dirname(file),e.originalSource));
            at=`${e.originalLine+1}:${e.originalColumn+1}`;
        }
        if(!file.startsWith(T+'/'))continue;
        if(blocks.length===0)blocks.push({line:'',frames:[]});
        blocks.at(-1).frames.push(`${m[1]??'<anonymous>'} (${file}:${at})`);
    }
    return blocks;
}
// (stdout's lines as they are; stderr's an uncaught error's, which each writes its own way: their frames)
const lines=b=>b.map(x=>x.line),frames=b=>b.map(x=>x.frames);
// (an uncaught error's: its stack, or a value's, where it was thrown: node's --trace-uncaught after the stack)
const errors=b=>frames(b).filter(f=>f.length>0).slice(0,1);
let passed=0;
for(const file of files){
    const stem=file.slice(0,-3);
    // (a program of helder's API, which node has not: its output beside it, <stem>.out, and WebAssembly's, <stem>.wasm.out)
    if(fs.existsSync(`${T}/${stem}.out`)){
        for(const target of [null,'wasm32-wasi']){
            const out=`${dir}/${stem}${target?'.wasm':''}`;
            const c=run(helder,[`${T}/${file}`,'-o',out,...(target?['--target',target]:[])]);
            assert.equal(c.status,0,`${file} compile ${target??'native'}\n${c.stdout}\n${c.stderr}`);
            const r=target?run(process.execPath,['tests/typescript/run-wasi.cjs',out]):run(out,[]);
            assert.equal(r.stdout+r.stderr,fs.readFileSync(`${T}/${stem}${target?'.wasm':''}.out`,'utf8'),`${file} ${target??'native'}`);
        }
        console.log(`PASS stacks ${stem}`);passed++;
        continue;
    }
    const node=run(process.execPath,['--enable-source-maps','--trace-uncaught',`${dir}/js/${stem}.js`]);
    const want={out:parse(node.stdout),err:parse(node.stderr)};
    // (the functions a program says helder inlines: no frames of their own)
    const inlined=(fs.readFileSync(`${T}/${file}`,'utf8').match(/inlined: (.*?)\)?$/m)?.[1]??'').split(' ').filter(x=>x);
    for(const b of [...want.out,...want.err])b.frames=b.frames.filter(f=>!inlined.includes(f.split(' (')[0]));
    assert.ok(frames(want.out).flat().length+frames(want.err).flat().length>0,`${file}: node wrote no frames of the program\n${node.stdout}\n${node.stderr}`);
    for(const target of [null,'wasm32-wasi']){
        const out=`${dir}/${stem}${target?'.wasm':''}`;
        const c=run(helder,[`${T}/${file}`,'-o',out,...(target?['--target',target]:[])]);
        assert.equal(c.status,0,`${file} compile ${target??'native'}\n${c.stdout}\n${c.stderr}`);
        const r=target?run(process.execPath,['tests/typescript/run-wasi.cjs',out]):run(out,[]);
        const got={out:parse(r.stdout),err:parse(r.stderr)};
        const what=`${file} ${target??'native'}\n--- helder\n${r.stdout}${r.stderr}\n--- node\n${node.stdout}${node.stderr}`;
        assert.equal(r.status,node.status,`exit status: ${what}`);
        assert.deepEqual(lines(got.out),lines(want.out),`lines: ${what}`);
        if(node.status!==0)assert.match(r.stderr,/^Uncaught /,`uncaught: ${what}`);
        if(!target){
            assert.deepEqual(frames(got.out),frames(want.out),`frames: ${what}`);
            assert.deepEqual(errors(got.err),errors(want.err),`uncaught frames: ${what}`);
            continue;
        }
        // (where the `new` ran: node's first frame's place; the async functions awaiting: node's)
        const place=f=>f.replace(/^.* \(/,'(');
        frames(got.out).forEach((f,i)=>{
            const w=frames(want.out)[i],site=f.length>0&&f[0].startsWith('<anonymous> (')?1:0;
            if(site)assert.equal(place(f[0]),place(w[0]),`its place: ${what}`);
            assert.deepEqual(f.slice(site),w.filter(x=>x.startsWith('async ')),`async frames: ${what}`);
        });
    }
    console.log(`PASS stacks ${stem}`);passed++;
}
console.log(`stacks: ${passed} programs`);
