import { useMemo, useState } from 'react'
import { useAuth } from '../App'
import * as api from '../lib/api'
import { useAsync, Badge, Modal, Field, fmtDate } from '../components/ui'
import { DECISION_COMMITTEES, DECISION_STATUSES, OUTCOMES } from '../lib/constants'

const TABS = ['Open', 'Next SteerCo', 'By committee', 'Deferred / Escalated', 'History']

export default function DecisionLog() {
  const { profile, isPMTT } = useAuth()
  const decisions = useAsync(api.listDecisions)
  const profiles = useAsync(api.listProfiles)
  const [tab, setTab] = useState('Open')
  const [editing, setEditing] = useState(null) // decision object or 'new'

  const list = decisions.data || []
  const view = useMemo(() => {
    switch (tab) {
      case 'Open': return list.filter(d => d.status === 'To Decide' || d.status === 'Blocked')
      case 'Next SteerCo': return list.filter(d => d.next_steerco && d.status !== 'Decided')
      case 'Deferred / Escalated': return list.filter(d => ['Deferred', 'Escalated'].includes(d.status))
      case 'History': return list.filter(d => d.status === 'Decided')
      default: return list
    }
  }, [list, tab])

  const overdue = d => d.due_date && d.status === 'To Decide' && new Date(d.due_date) < new Date()
  const dueSoon = d => d.due_date && d.status === 'To Decide' &&
    (new Date(d.due_date) - Date.now()) / 86400000 <= 7 && !overdue(d)

  const Table = ({ rows }) => (
    <table className="data">
      <thead><tr><th>ID</th><th>Decision</th><th>Related</th><th>Committee</th><th>Owner</th>
        <th>Due</th><th>Reco</th><th>Status</th><th>Outcome</th><th></th></tr></thead>
      <tbody>
        {rows.map(d => (
          <tr key={d.id}>
            <td className="muted small">{d.decision_id}</td>
            <td>{d.title}{d.next_steerco && <> <Badge color="purple">Next SteerCo</Badge></>}</td>
            <td className="small">{d.related_type} · {d.related_id}</td>
            <td className="small">{d.committee_target}</td>
            <td className="small">{d.owner?.name || '—'}</td>
            <td>{fmtDate(d.due_date)} {overdue(d) && <Badge color="red">overdue</Badge>}{dueSoon(d) && <Badge color="amber">≤7d</Badge>}</td>
            <td>{d.recommendation || '—'}</td>
            <td><Badge color={d.status === 'Decided' ? 'green' : d.status === 'Escalated' ? 'red' : d.status === 'To Decide' ? 'amber' : 'gray'}>{d.status}</Badge></td>
            <td>{d.outcome || '—'}</td>
            <td>{isPMTT && <button className="btn secondary small" onClick={() => setEditing(d)}>Edit</button>}</td>
          </tr>
        ))}
        {!rows.length && <tr><td colSpan={10} className="muted">Nothing here.</td></tr>}
      </tbody>
    </table>
  )

  return (
    <div>
      <div className="topbar">
        <h1>Decision Log</h1>
        {isPMTT && <button className="btn" onClick={() => setEditing('new')}>+ New decision</button>}
      </div>
      <div className="tabs">
        {TABS.map(t => <button key={t} className={tab === t ? 'active' : ''} onClick={() => setTab(t)}>{t}</button>)}
      </div>
      {tab === 'By committee' ? (
        DECISION_COMMITTEES.map(c => (
          <div className="card" key={c}>
            <h2>{c}</h2>
            <Table rows={list.filter(d => d.committee_target === c && d.status !== 'Decided')} />
          </div>
        ))
      ) : (
        <div className="card" style={{ overflowX: 'auto' }}><Table rows={view} /></div>
      )}
      {editing && (
        <DecisionModal decision={editing === 'new' ? null : editing} profiles={profiles.data || []}
          me={profile} onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); decisions.reload() }} />
      )}
    </div>
  )
}

function DecisionModal({ decision, profiles, me, onClose, onSaved }) {
  const [f, setF] = useState(decision ? { ...decision } : {
    title: '', related_type: 'Idea', related_id: '', committee_target: 'Pillar SteerCo',
    due_date: '', recommendation: '', impact: '', status: 'To Decide', outcome: '',
    decision_date: '', decision_notes: '', next_action: '', next_steerco: false,
    owner_id: me.id, action_owner_id: '',
  })
  const [err, setErr] = useState(null)
  const [busy, setBusy] = useState(false)
  const set = (k, v) => setF(s => ({ ...s, [k]: v }))

  const save = async () => {
    setBusy(true); setErr(null)
    const payload = {
      title: f.title, related_type: f.related_type, related_id: f.related_id,
      committee_target: f.committee_target, due_date: f.due_date || null,
      recommendation: f.recommendation || null, impact: f.impact || null,
      status: f.status, outcome: f.outcome || null,
      decision_date: f.decision_date || (f.status === 'Decided' ? new Date().toISOString().slice(0, 10) : null),
      decision_notes: f.decision_notes || null, next_action: f.next_action || null,
      next_steerco: !!f.next_steerco, owner_id: f.owner_id || null,
      action_owner_id: f.action_owner_id || null,
    }
    try {
      if (decision) await api.updateDecision(decision.id, payload)
      else await api.createDecision(payload)
      onSaved()
    } catch (e) { setErr(e.message); setBusy(false) }
  }

  return (
    <Modal title={decision ? `Edit ${decision.decision_id}` : 'New decision'} onClose={onClose}>
      <Field label="Decision question *"><input type="text" value={f.title} onChange={e => set('title', e.target.value)} /></Field>
      <div className="grid cols-2">
        <Field label="Related type">
          <select value={f.related_type} onChange={e => set('related_type', e.target.value)}>
            {['Idea', 'Business Case', 'Charter', 'Project'].map(t => <option key={t}>{t}</option>)}
          </select></Field>
        <Field label="Related ID *" hint="e.g. IDEA-0001 / PRJ-003">
          <input type="text" value={f.related_id} onChange={e => set('related_id', e.target.value)} /></Field>
        <Field label="Committee">
          <select value={f.committee_target} onChange={e => set('committee_target', e.target.value)}>
            {DECISION_COMMITTEES.map(c => <option key={c}>{c}</option>)}
          </select></Field>
        <Field label="Due date"><input type="date" value={f.due_date || ''} onChange={e => set('due_date', e.target.value)} /></Field>
        <Field label="Owner">
          <select value={f.owner_id || ''} onChange={e => set('owner_id', e.target.value)}>
            <option value="">—</option>
            {profiles.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select></Field>
        <Field label="Action owner (follow-up)">
          <select value={f.action_owner_id || ''} onChange={e => set('action_owner_id', e.target.value)}>
            <option value="">—</option>
            {profiles.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select></Field>
        <Field label="Recommendation">
          <select value={f.recommendation || ''} onChange={e => set('recommendation', e.target.value)}>
            <option value="">—</option>{OUTCOMES.map(o => <option key={o}>{o}</option>)}
          </select></Field>
        <Field label="Status">
          <select value={f.status} onChange={e => set('status', e.target.value)}>
            {DECISION_STATUSES.map(s => <option key={s}>{s}</option>)}
          </select></Field>
        {f.status === 'Decided' && (
          <Field label="Outcome">
            <select value={f.outcome || ''} onChange={e => set('outcome', e.target.value)}>
              <option value="">—</option>{OUTCOMES.map(o => <option key={o}>{o}</option>)}
            </select></Field>
        )}
      </div>
      <Field label="Impact"><textarea value={f.impact || ''} onChange={e => set('impact', e.target.value)} /></Field>
      <Field label="Decision notes / rationale"><textarea value={f.decision_notes || ''} onChange={e => set('decision_notes', e.target.value)} /></Field>
      <Field label="Next action"><input type="text" value={f.next_action || ''} onChange={e => set('next_action', e.target.value)} /></Field>
      <div className="checks" style={{ marginBottom: 12 }}>
        <label><input type="checkbox" checked={!!f.next_steerco} onChange={e => set('next_steerco', e.target.checked)} /> Put on next SteerCo agenda</label>
      </div>
      {err && <p style={{ color: 'var(--red)' }}>{err}</p>}
      <button className="btn" disabled={busy || !f.title || !f.related_id} onClick={save}>Save</button>
    </Modal>
  )
}
