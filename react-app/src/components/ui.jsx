import { useEffect, useState } from 'react'
import { ROADMAP_NOTE } from '../lib/constants'

export function Badge({ color = 'gray', children }) {
  return <span className={`badge ${color}`}>{children}</span>
}

export function StageBadge({ stage }) {
  const colors = {
    'L0 Submitted': 'gray', 'L0 Triage': 'amber', 'L1 Qualified': 'blue',
    'L2 BC/Charter': 'purple', 'G1 Approval': 'amber', 'Converted': 'green',
    'Rejected': 'red', 'Hold': 'gray',
  }
  return <Badge color={colors[stage] || 'gray'}>{stage}</Badge>
}

export function Modal({ title, onClose, children }) {
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={e => e.stopPropagation()}>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
          <h2 className="mb0">{title}</h2>
          <button className="btn secondary small" onClick={onClose}>✕</button>
        </div>
        {children}
      </div>
    </div>
  )
}

export function Field({ label, hint, children }) {
  return (
    <div className="field">
      <label>{label}{hint && <span className="hint">{hint}</span>}</label>
      {children}
    </div>
  )
}

export function MultiCheck({ options, value = [], onChange }) {
  const toggle = (opt) =>
    onChange(value.includes(opt) ? value.filter(v => v !== opt) : [...value, opt])
  return (
    <div className="checks">
      {options.map(o => (
        <label key={o}>
          <input type="checkbox" checked={value.includes(o)} onChange={() => toggle(o)} /> {o}
        </label>
      ))}
    </div>
  )
}

export function Checklist({ items }) {
  return (
    <ul className="checklist">
      {items.map((c, i) => (
        <li key={i}>{c.ok ? '✅' : '⬜'} {c.label}</li>
      ))}
    </ul>
  )
}

export function Progress({ pct }) {
  return <div className="progress"><div style={{ width: `${pct}%`, background: pct >= 80 ? 'var(--green)' : pct >= 40 ? 'var(--amber)' : 'var(--red)' }} /></div>
}

export function RoadmapNote() {
  return <div className="roadmap-note">🔮 <b>Roadmap:</b> {ROADMAP_NOTE}</div>
}

export function useAsync(fn, deps = []) {
  const [state, setState] = useState({ loading: true, data: null, error: null })
  const reload = () => {
    setState(s => ({ ...s, loading: true }))
    fn().then(data => setState({ loading: false, data, error: null }))
      .catch(error => setState({ loading: false, data: null, error }))
  }
  useEffect(reload, deps)
  return { ...state, reload }
}

export function fmtDate(d) {
  if (!d) return '—'
  return new Date(d).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
}
export function fmtDateTime(d) {
  if (!d) return '—'
  return new Date(d).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
}
