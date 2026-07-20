// Shared editor used by Business Case and Charter screens:
// structured sections, completeness, versions, status, print/PDF export.
import { useState } from 'react'
import { useAuth } from '../App'
import * as api from '../lib/api'
import { Field, Badge, Progress, Checklist, RoadmapNote, Modal, fmtDateTime, useAsync } from './ui'
import { DOC_STATUSES, OUTCOMES, COMMITTEES } from '../lib/constants'

export default function DocEditor({
  docType, doc, idea, sections, completeness, extraHeader, extraFields, onSaved, title,
}) {
  const { profile, isPMTT } = useAuth()
  const [f, setF] = useState(() => {
    const init = {}
    sections.forEach(s => { init[s.key] = doc[s.key] || '' })
    ;(extraFields || []).forEach(k => { init[k] = doc[k] || '' })
    init.status = doc.status
    return init
  })
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState(null)
  const [showVersions, setShowVersions] = useState(false)
  const versions = useAsync(() => api.listVersions(docType, doc.id), [doc.id])
  const set = (k, v) => setF(s => ({ ...s, [k]: v }))
  const comp = completeness({ ...doc, ...f })

  const save = async (newVersion = false) => {
    setBusy(true); setErr(null)
    try {
      const fields = { ...f }
      if (newVersion) {
        // snapshot current DB state before bumping
        await api.saveVersion(docType, doc.id, doc.version, doc, profile.id)
        const n = parseInt((doc.version || 'v0').replace('v', ''), 10) + 1
        fields.version = `v${n}`
      }
      const update = docType === 'business_case'
        ? await api.updateBusinessCase(doc.id, fields)
        : await api.updateCharter(doc.id, fields)
      onSaved(update)
    } catch (e) { setErr(e.message) }
    setBusy(false)
  }

  const readiness = comp.pct >= 80
  return (
    <div>
      <div className="topbar">
        <div>
          <span className="muted small">{idea.idea_id} · {doc.business_case_id || doc.charter_id} · {doc.version}</span>
          <h1>{title}</h1>
        </div>
        <div style={{ display: 'flex', gap: 8 }} className="no-print">
          <button className="btn secondary" onClick={() => setShowVersions(true)}>Versions ({(versions.data || []).length})</button>
          <button className="btn secondary" onClick={() => window.print()}>Export PDF</button>
          {isPMTT && <button className="btn secondary" onClick={() => save(true)} disabled={busy}>Save as new version</button>}
          {isPMTT && <button className="btn" onClick={() => save(false)} disabled={busy}>Save</button>}
        </div>
      </div>
      <RoadmapNote />
      <div className="card no-print">
        <div style={{ display: 'flex', gap: 16, alignItems: 'center', flexWrap: 'wrap' }}>
          <div style={{ flex: 1, minWidth: 220 }}>
            <div className="small muted" style={{ marginBottom: 4 }}>
              Completeness: {comp.done}/{comp.total} required sections
              {' '}<Badge color={readiness ? 'green' : 'amber'}>{readiness ? 'Gate ready' : 'Not gate ready'}</Badge>
            </div>
            <Progress pct={comp.pct} />
          </div>
          <Field label="Status">
            <select value={f.status} onChange={e => set('status', e.target.value)} disabled={!isPMTT}>
              {DOC_STATUSES.map(s => <option key={s}>{s}</option>)}
            </select>
          </Field>
          {extraHeader && extraHeader(f, set, isPMTT)}
        </div>
        {!readiness && comp.missing.length > 0 && (
          <p className="small" style={{ color: 'var(--amber)', marginBottom: 0 }}>
            Missing: {comp.missing.join(' · ')}
          </p>
        )}
      </div>

      {err && <p style={{ color: 'var(--red)' }}>{err}</p>}

      {/* Print header */}
      <div className="card" style={{ display: 'none' }} media="print">
        <h1>{title}</h1>
      </div>

      {sections.map(s => (
        <div className="card" key={s.key}>
          <Field label={`${s.label}${s.required ? ' *' : ''}`} hint={s.hint}>
            <textarea value={f[s.key]} onChange={e => set(s.key, e.target.value)}
              disabled={!isPMTT} style={{ minHeight: 90 }} />
          </Field>
        </div>
      ))}

      {showVersions && (
        <Modal title="Version history" onClose={() => setShowVersions(false)}>
          <p className="small muted">Current: {doc.version} (live). Snapshots below were saved when a new version was created.</p>
          {(versions.data || []).length === 0 && <p className="muted">No previous versions.</p>}
          {(versions.data || []).map(v => (
            <div key={v.id} className="alert-line">
              <Badge color="blue">{v.version_label}</Badge>
              <span className="small">saved by {v.saver?.name || '—'} · {fmtDateTime(v.created_at)}</span>
            </div>
          ))}
        </Modal>
      )}
    </div>
  )
}

export function GovernanceHeaderFields(f, set, isPMTT) {
  return (
    <>
      <div className="field">
        <label>Recommendation</label>
        <select value={f.recommendation || ''} onChange={e => set('recommendation', e.target.value)} disabled={!isPMTT}>
          <option value="">—</option>{OUTCOMES.map(o => <option key={o}>{o}</option>)}
        </select>
      </div>
      <div className="field">
        <label>Committee Target</label>
        <select value={f.committee_target || ''} onChange={e => set('committee_target', e.target.value)} disabled={!isPMTT}>
          <option value="">—</option>{COMMITTEES.map(c => <option key={c}>{c}</option>)}
        </select>
      </div>
    </>
  )
}
