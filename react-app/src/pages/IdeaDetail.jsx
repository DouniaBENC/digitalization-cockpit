import { useState } from 'react'
import { useParams, Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../App'
import * as api from '../lib/api'
import { useAsync, StageBadge, Badge, Modal, Field, MultiCheck, Checklist, fmtDate, fmtDateTime } from '../components/ui'
import { PILLARS, FUNCTIONS, VALUE_TYPES, EFFORT, URGENCY, DATA_AVAILABILITY, COMMITTEES } from '../lib/constants'
import { l1Criteria, l2Criteria, g1Criteria, conversionCriteria, suggestQuickWin, suggestPriority } from '../lib/logic'

export default function IdeaDetail() {
  const { id } = useParams()
  const nav = useNavigate()
  const { profile, isPMTT, isPM } = useAuth()
  const idea = useAsync(() => api.getIdea(id), [id])
  const bc = useAsync(() => api.getBusinessCaseByIdea(id), [id])
  const ch = useAsync(() => api.getCharterByIdea(id), [id])
  const activity = useAsync(() => api.listActivity('Idea', id), [id])
  const decisions = useAsync(api.listDecisions, [id])
  const [modal, setModal] = useState(null) // 'qualify' | 'l2' | 'g1' | 'convert' | 'reject' | 'hold'
  const [comment, setComment] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState(null)

  if (idea.loading) return <p>Loading…</p>
  if (idea.error) return <p style={{ color: 'var(--red)' }}>{idea.error.message}</p>
  const i = idea.data

  const canEditIdea = isPMTT || (i.requester_id === profile.id && i.stage === 'L0 Submitted')
  const ideaDecisions = (decisions.data || []).filter(d => d.related_id === i.idea_id)

  const save = async (fields) => {
    setBusy(true); setErr(null)
    try { await api.updateIdea(i.id, fields); idea.reload() }
    catch (e) { setErr(e.message) }
    setBusy(false)
  }

  const doQualify = async () => {
    setBusy(true); setErr(null)
    try {
      await api.qualifyIdea(i.id)
      setModal(null); idea.reload(); bc.reload(); ch.reload(); activity.reload(); decisions.reload()
    } catch (e) { setErr(e.message) }
    setBusy(false)
  }

  const moveStage = async (stage) => {
    await save({ stage }); setModal(null); activity.reload()
  }

  const postComment = async () => {
    if (!comment.trim()) return
    await api.addComment('Idea', i.id, profile.id, comment.trim())
    setComment(''); activity.reload()
  }

  return (
    <div>
      <div className="topbar">
        <div>
          <span className="muted small">{i.idea_id} · submitted {fmtDate(i.submitted_date)} by {i.requester?.name}</span>
          <h1>{i.title}</h1>
          <div style={{ display: 'flex', gap: 6, marginTop: 4 }}>
            <StageBadge stage={i.stage} />
            {i.digital_pillar && <Badge color="blue">{i.digital_pillar}</Badge>}
            {i.quick_win && <Badge color="green">Quick win</Badge>}
            {i.priority && <Badge color="red">Priority</Badge>}
            {i.committee_target && <Badge color="purple">{i.committee_target}</Badge>}
            {i.linked_project_id && <Badge color="green">→ {i.linked_project_id}</Badge>}
          </div>
        </div>
        {isPMTT && (
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {i.stage === 'L0 Submitted' && (
              <button className="btn" onClick={() => moveStage('L0 Triage')}>Start triage</button>)}
            {i.stage === 'L0 Triage' && (
              <button className="btn" onClick={() => setModal('qualify')}>Qualify → L1</button>)}
            {i.stage === 'L1 Qualified' && (
              <button className="btn" onClick={() => setModal('l2')}>Move → L2 Preparation</button>)}
            {i.stage === 'L2 BC/Charter' && (
              <button className="btn" onClick={() => setModal('g1')}>Ready → G1 Approval</button>)}
            {i.stage === 'G1 Approval' && isPM && (
              <button className="btn" onClick={() => setModal('convert')}>Convert → Project</button>)}
            {!['Rejected', 'Converted'].includes(i.stage) && (<>
              <button className="btn secondary" onClick={() => moveStage('Hold')}>Hold</button>
              <button className="btn danger" onClick={() => moveStage('Rejected')}>Reject</button>
            </>)}
            {i.stage === 'Hold' && (
              <button className="btn secondary" onClick={() => moveStage('L0 Triage')}>Reopen</button>)}
          </div>
        )}
      </div>
      {err && <p style={{ color: 'var(--red)' }}>{err}</p>}

      <div className="grid cols-2">
        <div>
          <div className="card">
            <h2>Original Submission</h2>
            <Info label="Problem / Opportunity" value={i.opportunity} multiline />
            <Info label="Business Benefits" value={i.business_benefits} multiline />
            <Info label="E3 Impact" value={[i.e3_environment && 'Environment', i.e3_economy && 'Economy', i.e3_engagement && 'Engagement'].filter(Boolean).join(', ') || '—'} />
            <Info label="Value Types" value={(i.expected_value_types || []).join(', ') || '—'} />
            <Info label="Impacted Functions" value={(i.impacted_functions || []).join(', ') || '—'} />
            <Info label="Estimated Value" value={i.estimated_value || '—'} />
            <Info label="Systems Involved" value={i.interface_systems || '—'} />
            <Info label="Risks / Constraints" value={i.risks_challenges || '—'} multiline />
          </div>

          <div className="card">
            <h2>Governance Documents</h2>
            {bc.data ? (
              <p>📄 <Link to={`/ideas/${i.id}/business-case`}>Business Case {bc.data.business_case_id} ({bc.data.version})</Link> — <Badge color={bc.data.status === 'Ready for Gate' ? 'green' : 'gray'}>{bc.data.status}</Badge></p>
            ) : <p className="muted">Business Case v0 will be created automatically at L1 qualification.</p>}
            {ch.data ? (
              <p>📄 <Link to={`/ideas/${i.id}/charter`}>Project Charter {ch.data.charter_id} ({ch.data.version})</Link> — <Badge color={ch.data.status === 'Ready for Gate' ? 'green' : 'gray'}>{ch.data.status}</Badge></p>
            ) : <p className="muted">Project Charter v0 will be created automatically at L1 qualification.</p>}
          </div>

          <div className="card">
            <h2>Decisions</h2>
            {ideaDecisions.length ? ideaDecisions.map(d => (
              <div key={d.id} className="alert-line">
                <Badge color={d.status === 'Decided' ? 'green' : d.status === 'Escalated' ? 'red' : 'amber'}>{d.status}</Badge>
                <span>{d.title}</span>
                <span className="muted small">{d.committee_target}{d.due_date ? ` · due ${fmtDate(d.due_date)}` : ''}{d.outcome ? ` · ${d.outcome}` : ''}</span>
              </div>
            )) : <p className="muted">No decisions linked yet.</p>}
            {isPMTT && <p><Link to="/decisions" className="small">Manage in Decision Log →</Link></p>}
          </div>
        </div>

        <div>
          {isPMTT && <TriagePanel i={i} save={save} busy={busy} />}

          <div className="card">
            <h2>Comments & Activity</h2>
            <div style={{ display: 'flex', gap: 8, marginBottom: 10 }}>
              <input type="text" style={{ flex: 1, padding: '8px 10px', border: '1px solid var(--border)', borderRadius: 7 }}
                placeholder="Add a comment…" value={comment} onChange={e => setComment(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && postComment()} />
              <button className="btn small" onClick={postComment}>Post</button>
            </div>
            {(activity.data || []).map(a => (
              <div key={a.id} className="activity-item">
                <span className="who">{a.user?.name || 'System'}</span>{' '}
                {a.kind === 'comment' ? '💬' : '⚙️'} {a.message}
                <div className="when">{fmtDateTime(a.created_at)}</div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {modal === 'qualify' && (
        <Modal title="Qualify idea → L1" onClose={() => setModal(null)}>
          <p className="small muted">L0 → L1 criteria (spec §6). Qualifying automatically creates Business Case v0, Project Charter v0 and the initial decision record.</p>
          <Checklist items={l1Criteria(i)} />
          {!i.owner_id && <p className="small" style={{ color: 'var(--amber)' }}>Tip: assign an owner in the triage panel first.</p>}
          {err && <p style={{ color: 'var(--red)' }}>{err}</p>}
          <button className="btn" onClick={doQualify} disabled={busy}>Confirm qualification</button>
        </Modal>
      )}
      {modal === 'l2' && (
        <Modal title="Move to L2 — BC / Charter preparation" onClose={() => setModal(null)}>
          <Checklist items={l2Criteria(i)} />
          <p className="small muted">The Transformation Team confirms there is enough substance to prepare governance materials.</p>
          <button className="btn" onClick={() => moveStage('L2 BC/Charter')} disabled={busy}>Confirm move to L2</button>
        </Modal>
      )}
      {modal === 'g1' && (
        <Modal title="Ready for G1 Approval" onClose={() => setModal(null)}>
          <Checklist items={g1Criteria(i, bc.data, ch.data)} />
          <p className="small muted">Log the G1 decision in the Decision Log for the target committee.</p>
          <button className="btn" onClick={() => moveStage('G1 Approval')} disabled={busy}>Confirm — send to G1</button>
        </Modal>
      )}
      {modal === 'convert' && (
        <ConvertModal i={i} decisions={decisions.data || []} onClose={() => setModal(null)}
          onDone={() => { setModal(null); idea.reload(); activity.reload() }} />
      )}
    </div>
  )
}

function Info({ label, value, multiline }) {
  return (
    <div style={{ marginBottom: 10 }}>
      <div className="small muted" style={{ fontWeight: 600 }}>{label}</div>
      <div style={multiline ? { whiteSpace: 'pre-wrap' } : {}}>{value}</div>
    </div>
  )
}

function TriagePanel({ i, save, busy }) {
  const [f, setF] = useState({
    digital_pillar: i.digital_pillar || '', urgency: i.urgency || '',
    data_availability: i.data_availability || '', resources_effort: i.resources_effort || '',
    cost_effort: i.cost_effort || '', change_effort: i.change_effort || '', technical_effort: i.technical_effort || '',
    provisional_sponsor: i.provisional_sponsor || '', committee_target: i.committee_target || '',
    quick_win: i.quick_win, priority: i.priority, triage_notes: i.triage_notes || '',
    impacted_functions: i.impacted_functions || [], expected_value_types: i.expected_value_types || [],
    owner_id: i.owner_id || '',
  })
  const { data: profiles } = useAsync(api.listProfiles)
  const set = (k, v) => setF(s => ({ ...s, [k]: v }))
  const sel = (label, key, opts) => (
    <Field label={label}>
      <select value={f[key]} onChange={e => set(key, e.target.value)}>
        <option value="">—</option>{opts.map(o => <option key={o}>{o}</option>)}
      </select>
    </Field>
  )
  const qwSuggest = suggestQuickWin({ ...i, ...f })
  const prSuggest = suggestPriority({ ...i, ...f })

  return (
    <div className="card">
      <h2>Triage & Assessment</h2>
      <div className="grid cols-2">
        {sel('Digital Pillar', 'digital_pillar', PILLARS)}
        <Field label="Owner (next-step assessment)">
          <select value={f.owner_id} onChange={e => set('owner_id', e.target.value)}>
            <option value="">—</option>
            {(profiles || []).filter(p => p.role !== 'requester').map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </Field>
        {sel('Urgency', 'urgency', URGENCY)}
        {sel('Data Availability', 'data_availability', DATA_AVAILABILITY)}
        {sel('Resources Effort', 'resources_effort', EFFORT)}
        {sel('Cost Effort', 'cost_effort', EFFORT)}
        {sel('Change Effort', 'change_effort', EFFORT)}
        {sel('Technical Effort', 'technical_effort', EFFORT)}
        {sel('Committee Target', 'committee_target', COMMITTEES)}
        <Field label="Provisional Sponsor">
          <input type="text" value={f.provisional_sponsor} onChange={e => set('provisional_sponsor', e.target.value)} />
        </Field>
      </div>
      <Field label="Impacted Functions"><MultiCheck options={FUNCTIONS} value={f.impacted_functions} onChange={v => set('impacted_functions', v)} /></Field>
      <Field label="Value Types"><MultiCheck options={VALUE_TYPES} value={f.expected_value_types} onChange={v => set('expected_value_types', v)} /></Field>
      <div className="checks" style={{ marginBottom: 10 }}>
        <label><input type="checkbox" checked={f.quick_win} onChange={e => set('quick_win', e.target.checked)} /> Quick win {qwSuggest && !f.quick_win && <Badge color="green">suggested</Badge>}</label>
        <label><input type="checkbox" checked={f.priority} onChange={e => set('priority', e.target.checked)} /> Priority {prSuggest && !f.priority && <Badge color="red">suggested</Badge>}</label>
      </div>
      <Field label="Triage Notes" hint="duplicate check, scope fit, pillar rationale">
        <textarea value={f.triage_notes} onChange={e => set('triage_notes', e.target.value)} />
      </Field>
      <button className="btn" disabled={busy} onClick={() => save({
        ...f,
        digital_pillar: f.digital_pillar || null, urgency: f.urgency || null,
        data_availability: f.data_availability || null, resources_effort: f.resources_effort || null,
        cost_effort: f.cost_effort || null, change_effort: f.change_effort || null,
        technical_effort: f.technical_effort || null, committee_target: f.committee_target || null,
        owner_id: f.owner_id || null,
      })}>Save assessment</button>
    </div>
  )
}

function ConvertModal({ i, decisions, onClose, onDone }) {
  const [projectId, setProjectId] = useState('')
  const [lead, setLead] = useState('')
  const [err, setErr] = useState(null)
  const [busy, setBusy] = useState(false)
  const criteria = conversionCriteria(i, decisions)

  const convert = async () => {
    setBusy(true); setErr(null)
    try { await api.convertToProject(i.id, projectId.trim(), lead.trim()); onDone() }
    catch (e) { setErr(e.message); setBusy(false) }
  }
  return (
    <Modal title="Convert initiative to project (G1 → S1)" onClose={onClose}>
      <Checklist items={criteria} />
      <Field label="SmartSheet Project ID *" hint="e.g. PRJ-026 — duplicates are rejected">
        <input type="text" value={projectId} onChange={e => setProjectId(e.target.value)} />
      </Field>
      <Field label="Project Lead *">
        <input type="text" value={lead} onChange={e => setLead(e.target.value)} />
      </Field>
      <p className="small muted">Creates the project record (stage S1 Scoping), links the initiative ID, and keeps the idea traceable. Export it to SmartSheet from the SmartSheet I/O screen.</p>
      {err && <p style={{ color: 'var(--red)' }}>{err}</p>}
      <button className="btn" disabled={busy || !projectId.trim() || !lead.trim()} onClick={convert}>Convert</button>
    </Modal>
  )
}
