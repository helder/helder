// A scripted ACP agent for the studio's tests (apps/studio/src/studio/AcpAgent.test.hx):
// newline-delimited JSON-RPC on stdin/stdout, as the Agent Client Protocol's
// agents speak it. Prompts: "edit" streams text, a thought, a tool call, a
// plan, asks permission, reads and writes app.helder (and a file outside the
// project), then reports what the client answered; "wait" streams a chunk,
// asks permission and waits for session/cancel; "die" logs to stderr and exits.
import {createInterface} from 'node:readline'

let next = 0
const waiting = new Map()
let cwd = '', servers = [], cancelled = null

function send(m) {
  process.stdout.write(JSON.stringify({jsonrpc: '2.0', ...m}) + '\n')
}

function request(method, params) {
  const id = ++next
  send({id, method, params})
  return new Promise(resolve => waiting.set(id, resolve))
}

function update(sessionId, update) {
  send({method: 'session/update', params: {sessionId, update}})
}

async function prompt(id, p) {
  const s = p.sessionId
  const text = p.prompt.filter(b => b.type === 'text').map(b => b.text).join('\n')
  const link = p.prompt.find(b => b.type === 'resource_link')
  if (text.startsWith('die')) {
    process.stderr.write('fake: about to die\n')
    process.exit(3)
  }
  if (text.startsWith('wait')) {
    update(s, {sessionUpdate: 'agent_message_chunk', content: {type: 'text', text: 'waiting '}})
    const asked = request('session/request_permission', {
      sessionId: s,
      toolCall: {toolCallId: 't2', title: 'Run it'},
      options: [{optionId: 'yes', name: 'Allow', kind: 'allow_once'}]
    })
    await new Promise(resolve => (cancelled = resolve))
    const a = await asked
    update(s, {sessionUpdate: 'agent_message_chunk', content: {type: 'text', text: a.result.outcome.outcome}})
    send({id, result: {stopReason: 'cancelled'}})
    return
  }
  update(s, {sessionUpdate: 'agent_message_chunk', content: {type: 'text', text: 'Hello '}})
  update(s, {sessionUpdate: 'agent_thought_chunk', content: {type: 'text', text: 'hmm'}})
  update(s, {sessionUpdate: 'agent_message_chunk', content: {type: 'text', text: 'world. '}})
  update(s, {sessionUpdate: 'unknown_kind', what: 1})
  update(s, {sessionUpdate: 'plan', entries: [
    {content: 'read', priority: 'high', status: 'completed'},
    {content: 'write', priority: 'high', status: 'pending'}
  ]})
  update(s, {sessionUpdate: 'tool_call', toolCallId: 't1', title: 'Edit app.helder', kind: 'edit', status: 'pending'})
  const asked = await request('session/request_permission', {
    sessionId: s,
    toolCall: {toolCallId: 't1', title: 'Edit app.helder'},
    options: [
      {optionId: 'yes', name: 'Allow', kind: 'allow_once'},
      {optionId: 'no', name: 'Reject', kind: 'reject_once'}
    ]
  })
  update(s, {sessionUpdate: 'tool_call_update', toolCallId: 't1', status: 'in_progress'})
  const file = cwd + '/app.helder'
  const read = await request('fs/read_text_file', {sessionId: s, path: file, line: 2, limit: 1})
  const whole = await request('fs/read_text_file', {sessionId: s, path: file})
  const wrote = await request('fs/write_text_file', {sessionId: s, path: file, content: whole.result.content.replace('Hello', 'Hi')})
  const outside = await request('fs/write_text_file', {sessionId: s, path: cwd + '/../outside.txt', content: 'no'})
  const missing = await request('nope/nothing', {})
  update(s, {sessionUpdate: 'tool_call_update', toolCallId: 't1', status: 'completed'})
  const report = {
    permission: asked.result?.outcome,
    line: read.result?.content,
    wrote: wrote.error ? 'error' : 'ok',
    outside: outside.error ? 'error' : 'ok',
    missing: missing.error?.code,
    servers,
    link: link?.name ?? null
  }
  update(s, {sessionUpdate: 'agent_message_chunk', content: {type: 'text', text: JSON.stringify(report)}})
  send({id, result: {stopReason: 'end_turn'}})
}

const lines = createInterface({input: process.stdin})
lines.on('line', line => {
  if (!line.trim()) return
  const m = JSON.parse(line)
  if (m.method === undefined) {
    const resolve = waiting.get(m.id)
    waiting.delete(m.id)
    resolve?.(m)
    return
  }
  switch (m.method) {
    case 'initialize':
      return send({id: m.id, result: {
        protocolVersion: 1,
        agentCapabilities: {mcpCapabilities: {http: true}, promptCapabilities: {image: true}},
        authMethods: []
      }})
    case 'session/new':
      cwd = m.params.cwd
      servers = m.params.mcpServers.map(s => s.type + ' ' + s.name + ' ' + s.url)
      return send({id: m.id, result: {sessionId: 's1'}})
    case 'session/prompt':
      return void prompt(m.id, m.params)
    case 'session/cancel':
      return void cancelled?.()
    default:
      if (m.id !== undefined) send({id: m.id, error: {code: -32601, message: 'no ' + m.method}})
  }
})
lines.on('close', () => process.exit(0))
