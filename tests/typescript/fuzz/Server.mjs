import net from 'node:net'
import path from 'node:path'
import {spawn} from 'node:child_process'

// helder's compiler as a compilation server (`--server-connect`, the
// protocol of src/helder/compiler/service/Resident.hx: a request's words one
// per line after their length, a 32-bit little-endian integer; the answer
// after its length too, its lines \x01 output, \x02 failure, else a message).
// tsgo stays up and Haxe's side stays typed between builds.
export class Server {
  #process
  #socket
  #buffer = Buffer.alloc(0)
  #waiting = null
  #queue = Promise.resolve()
  output = ''

  static async start(compiler, root) {
    const listener = net.createServer()
    await new Promise(resolve => listener.listen(0, '127.0.0.1', resolve))
    const {port} = listener.address()
    // (a resident compiler keeps what it makes: a large nursery and old
    // space spare it collections, as Resident's)
    const env = {RT_OLD_MB: '4096', RT_MINOR_KB: '32768', ...process.env}
    const child = spawn(compiler, ['--server-connect', `127.0.0.1:${port}`],
      {stdio: ['ignore', 'pipe', 'pipe'], env})
    const server = new Server(root)
    server.#process = child
    for (const pipe of [child.stdout, child.stderr])
      pipe.on('data', d => server.output = (server.output + d).slice(-8192))
    const socket = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('no connection')), 60000)
      listener.once('connection', s => {clearTimeout(timer); resolve(s)})
      child.once('exit', code => reject(new Error(`exited with ${code}`)))
    }).finally(() => listener.close())
    server.#socket = socket
    socket.on('data', d => {
      server.#buffer = Buffer.concat([server.#buffer, d])
      server.#pump()
    })
    socket.on('close', () => server.#fail(new Error('connection closed')))
    child.once('exit', () => server.#fail(new Error('the server stopped')))
    return server
  }

  constructor(root) {
    this.root = root
    this.std = path.resolve(root, 'node_modules/@hxmc/cli/hxmc/bootstrap/hxmc-std')
  }

  get pid() {
    return this.#process.pid
  }

  // the short form's words (helder.typescript.Frontend.direct), built
  build(entry, out, target) {
    const words = ['-cp', path.resolve(this.root, 'src'),
      '-main', 'helder.typescript.js.Seed', '--custom-target', `hxmc=${out}`,
      '-D', `helder.typescript=${path.resolve(entry)}`, '-D', 'hxmc.markup-braces']
    if (target) words.push('-D', `hxmc.target=${target}`)
    return this.request(words)
  }

  request(words) {
    const run = () => new Promise((resolve, reject) => {
      const body = Buffer.from(['--cwd', this.root, ...words, '-cp', this.std].join('\n'))
      const head = Buffer.alloc(4)
      head.writeInt32LE(body.length)
      this.#waiting = {resolve, reject, start: Date.now()}
      this.#socket.write(Buffer.concat([head, body]))
      this.#pump()
    })
    const next = this.#queue.then(run, run)
    this.#queue = next.catch(() => {})
    return next
  }

  stop() {
    this.#socket?.destroy()
    this.#process.kill('SIGTERM')
    const child = this.#process
    setTimeout(() => {if (child.exitCode == null) child.kill('SIGKILL')}, 2000).unref()
  }

  #pump() {
    if (!this.#waiting || this.#buffer.length < 4) return
    const n = this.#buffer.readInt32LE(0)
    if (this.#buffer.length < 4 + n) return
    const answer = this.#buffer.subarray(4, 4 + n).toString()
    this.#buffer = this.#buffer.subarray(4 + n)
    const {resolve, start} = this.#waiting
    this.#waiting = null
    let ok = true
    const messages = [], printed = []
    for (const line of answer.split('\n')) {
      if (line.startsWith('\x01')) printed.push(line.slice(1).split('\x01').join('\n'))
      else if (line.startsWith('\x02')) ok = false
      else if (line !== '') messages.push(line)
    }
    resolve({ok, messages: messages.join('\n'), printed: printed.join(''), ms: Date.now() - start})
  }

  #fail(error) {
    if (!this.#waiting) return
    const {reject} = this.#waiting
    this.#waiting = null
    error.message += '\n' + this.output.slice(-2000)
    reject(error)
  }
}
