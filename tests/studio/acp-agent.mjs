// A scripted ACP agent for the studio's tests (apps/studio/src/studio/AcpAgent.test.hx):
// newline-delimited JSON-RPC on stdin/stdout, as the Agent Client Protocol's
// agents speak it. Prompts: "ask" asks a question of several picks over
// the studio's MCP server (studio.ask, as an MCP agent named claude-code);
// "work" streams a plan, a thought, a Markdown
// reply with chips and five tool calls (the last running), then waits for
// session/cancel; "think" only thinks, until session/cancel; "pulse" calls a tool every
// 600 ms, ten times, then waits for session/cancel; "The user says…" (the inbox's notes) is noted; "markdown" streams a Markdown reply in small
// chunks; "edit" streams text, a thought, a tool call, a
// plan, asks permission, reads and writes app.helder (and a file outside the
// project), then reports what the client answered; "wait" streams a chunk,
// asks permission and waits for session/cancel; "die" logs to stderr and exits.
import {createInterface} from 'node:readline'

let next = 0
const waiting = new Map()
let cwd = '', servers = [], mcp = null, cancelled = null

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
  if (text.startsWith('The user says')) {
    update(s, {sessionUpdate: 'agent_message_chunk', content: {type: 'text', text: 'Noted: ' + text.slice(14)}})
    send({id, result: {stopReason: 'end_turn'}})
    return
  }
  if (text.startsWith('ask') && mcp) {
    // (as an MCP agent of its own, Claude Code's name: studio.ask, several picks; the answer comes later)
    const headers = {'content-type': 'application/json', accept: 'application/json, text/event-stream'}
    const call = async (body, session) => {
      const r = await fetch(mcp, {method: 'POST', headers: session ? {...headers, 'mcp-session-id': session} : headers, body: JSON.stringify({jsonrpc: '2.0', ...body})})
      await r.text()
      return r.headers.get('mcp-session-id')
    }
    const session = await call({id: 1, method: 'initialize', params: {protocolVersion: '2025-06-18', capabilities: {}, clientInfo: {name: 'claude-code', version: '1'}}})
    await call({method: 'notifications/initialized'}, session)
    await call({id: 2, method: 'tools/call', params: {name: 'studio.ask', arguments: {
      question: 'Which rows should glow?',
      options: [{id: 'done', label: 'Done rows'}, {id: 'open', label: 'Open rows'}, {id: 'new', label: 'New rows'}],
      multiple: true
    }}}, session)
    update(s, {sessionUpdate: 'agent_message_chunk', content: {type: 'text', text: 'Asked which rows should glow.'}})
    send({id, result: {stopReason: 'end_turn'}})
    return
  }
  if (text.startsWith('work')) {
    update(s, {sessionUpdate: 'plan', entries: [
      {content: 'the title', priority: 'high', status: 'completed'},
      {content: 'the list', priority: 'high', status: 'in_progress'},
      {content: 'the empty state', priority: 'medium', status: 'pending'}
    ]})
    update(s, {sessionUpdate: 'agent_thought_chunk', content: {type: 'text', text: 'The list first.'}})
    const reply = 'The [Home](studio:screen/Home) frame has its title. Now the list, drawn in `app.helder:4`: three rows, the first one done.\n\n- a **checked** row\n- two open ones'
    for (let i = 0; i < reply.length; i += 9)
      update(s, {sessionUpdate: 'agent_message_chunk', content: {type: 'text', text: reply.slice(i, i + 9)}})
    const tools = ['app.helder · the title', 'app.helder · the input row', 'Read app.helder', 'app.helder · the list', 'app.helder · <view row-gap={1}>']
    tools.forEach((title, k) => {
      update(s, {sessionUpdate: 'tool_call', toolCallId: 'w' + k, title, kind: 'edit', status: k < tools.length - 1 ? 'completed' : 'in_progress'})
    })
    await new Promise(resolve => (cancelled = resolve))
    send({id, result: {stopReason: 'cancelled'}})
    return
  }
  if (text.startsWith('markdown')) {
    const reply = 'Changed the **title**:\n\n- read `app.helder`\n- patched it\n\n```ts\nlet a = 1\n```\n\nSee [app.helder](app.helder#L2) or [helder](https://helder.build).'
    update(s, {sessionUpdate: 'agent_thought_chunk', content: {type: 'text', text: 'The title is in app.helder.'}})
    for (let i = 0; i < reply.length; i += 7)
      update(s, {sessionUpdate: 'agent_message_chunk', content: {type: 'text', text: reply.slice(i, i + 7)}})
    send({id, result: {stopReason: 'end_turn'}})
    return
  }
  if (text.startsWith('pulse')) {
    update(s, {sessionUpdate: 'agent_thought_chunk', content: {type: 'text', text: 'Working.'}})
    for (let k = 0; k < 10; k++) {
      await new Promise(resolve => setTimeout(resolve, 600))
      update(s, {sessionUpdate: 'tool_call', toolCallId: 'p' + k, title: 'step ' + k, kind: 'edit', status: 'completed'})
    }
    await new Promise(resolve => (cancelled = resolve))
    send({id, result: {stopReason: 'cancelled'}})
    return
  }
  if (text.startsWith('think')) {
    update(s, {sessionUpdate: 'agent_thought_chunk', content: {type: 'text', text: 'Thinking about it.'}})
    await new Promise(resolve => (cancelled = resolve))
    send({id, result: {stopReason: 'cancelled'}})
    return
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
    link: link?.name ?? null,
    problems: p.prompt.find(b => b.type === 'text' && b.text.startsWith("The studio's last build failed"))?.text ?? null
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
      mcp = m.params.mcpServers[0]?.url ?? null
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
