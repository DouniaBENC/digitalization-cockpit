import { useMemo, useState } from 'react'
import * as api from '../lib/api'
import { useAsync, Badge, fmtDate, fmtDateTime } from '../components/ui'
import { PILLARS, PROJECT_STAGES } from '../lib/constants'
import { projectAlerts, isPriorityProject, isQuickWinProject } from '../lib/logic'

export default function Projects() {
  const projects = useAsync(api.listProjects)
  const [flt, setFlt] = useState({ stage: '', pillar: '', flag: '', q: '' })
  const [selected, setSelected] = useState(null)

  const list = useMemo(() => (projects.data || []).filter(p =>
    (!flt.stage || (p.current_stage || '').startsWith(flt.stage.slice(0, 2))) &&
    (!flt.pillar || p.digital_pillar === flt.pillar) &&
    (!flt.flag ||
      (flt.flag === 'priority' && isPriorityProject(p)) ||
      (flt.flag === 'quick_win' && isQuickWinProject(p)) ||
      (flt.flag === 'alerts' && projectAlerts(p).length > 0)) &&
    (!flt.q || (p.project_name + ' ' + p.project_id + ' ' + (p.linked_initiative_id || '')).toLowerCase().includes(flt.q.toLowerCase()))
  ), [projects.data, flt])

  if (projects.loading) return <p>Loading…</p>

  return (
    <div>
      <div className="topbar">
        <div>
          <h1>Projects</h1>
          <p className="muted small mb0">Mirror of SmartSheet (official source of truth). Read-only here — update via import, push changes via export.</p>
        </div>
      </div>
      <div className="filters">
        <input placeholder="Search…" value={flt.q} onChange={e => setFlt({ ...flt, q: e.target.value })} />
        <select value={flt.stage} onChange={e => setFlt({ ...flt, stage: e.target.value })}>
          <option value="">All stages</option>{PROJECT_STAGES.map(s => <option key={s}>{s}</option>)}
        </select>
        <select value={flt.pillar} onChange={e => setFlt({ ...flt, pillar: e.target.value })}>
          <option value="">All pillars</option>{PILLARS.map(p => <option key={p}>{p}</option>)}
        </select>
        <select value={flt.flag} onChange={e => setFlt({ ...flt, flag: e.target.value })}>
          <option value="">All</option>
          <option value="priority">Priority</option>
          <option value="quick_win">Quick win</option>
          <option value="alerts">With alerts</option>
        </select>
      </div>
      <div className="card" style={{ overflowX: 'auto' }}>
        <table className="data">
          <thead><tr>
            <th>ID</th><th>Name</th><th>Stage</th><th>Pillar</th><th>Lead</th><th>Sponsor</th>
            <th>Charter</th><th>IT Demand</th><th>AR</th><th>CAPEX k€</th><th>Budget</th>
            <th>Start</th><th>End</th><th>Initiative</th><th>Alerts</th>
          </tr></thead>
          <tbody>
            {list.map(p => {
              const alerts = projectAlerts(p)
              return (
                <tr key={p.id} onClick={() => setSelected(p)} style={{ cursor: 'pointer' }}>
                  <td>{p.project_id}</td>
                  <td>{p.project_name}
                    {isPriorityProject(p) && <> <Badge color="red">P</Badge></>}
                    {isQuickWinProject(p) && <> <Badge color="green">QW</Badge></>}
                  </td>
                  <td className="small">{p.current_stage || '—'}</td>
                  <td className="small">{p.digital_pillar || '—'}</td>
                  <td className="small">{p.project_lead || '—'}</td>
                  <td className="small">{p.pillar_sponsor || '—'}</td>
                  <td><StatusBadge v={p.charter_status} /></td>
                  <td><StatusBadge v={p.it_demand_status} /></td>
                  <td><StatusBadge v={p.ar_status} /></td>
                  <td>{p.capex_keur ?? '—'}</td>
                  <td>{p.current_year_budget ?? '—'}</td>
                  <td className="small">{fmtDate(p.planned_start_date)}</td>
                  <td className="small">{fmtDate(p.planned_end_date)}</td>
                  <td className="small">{p.linked_initiative_id || '—'}</td>
                  <td>{alerts.length > 0 && <Badge color="red">{alerts.length} ⚠</Badge>}</td>
                </tr>
              )
            })}
            {!list.length && <tr><td colSpan={15} className="muted">No projects. Import a SmartSheet export from the SmartSheet I/O screen.</td></tr>}
          </tbody>
        </table>
      </div>
      {selected && <ProjectPanel p={selected} onClose={() => setSelected(null)} />}
    </div>
  )
}

function StatusBadge({ v }) {
  if (!v) return <span className="muted">—</span>
  const color = v === 'Approved' ? 'green' : v === 'N/A' ? 'gray' : v === 'Not created' ? 'red' : 'amber'
  return <Badge color={color}>{v}</Badge>
}

function ProjectPanel({ p, onClose }) {
  const alerts = projectAlerts(p)
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={e => e.stopPropagation()}>
        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
          <h2>{p.project_id} — {p.project_name}</h2>
          <button className="btn secondary small" onClick={onClose}>✕</button>
        </div>
        <p className="small" style={{ whiteSpace: 'pre-wrap' }}>{p.project_description || 'No description.'}</p>
        {alerts.length > 0 && (
          <div className="card" style={{ background: 'var(--red-soft)', border: 'none' }}>
            {alerts.map((a, i) => <div key={i} className="small">⚠ [{a.type}] {a.msg}</div>)}
          </div>
        )}
        <table className="data">
          <tbody>
            {[
              ['Stage', p.current_stage], ['Execution phase', p.execution_phase],
              ['Pillar', p.digital_pillar], ['Benefiting functions', p.key_benefiting_functions],
              ['Sponsor', p.pillar_sponsor], ['Lead', p.project_lead], ['IT lead', p.pwt_it_lead],
              ['Integrator', p.integrator_consultants], ['Charter', p.charter_status],
              ['IT demand', p.it_demand_status], ['AR', p.ar_status],
              ['CAPEX k€', p.capex_keur], ['Current Y budget', p.current_year_budget],
              ['Cost center', p.cost_center_internal_order],
              ['Planned', `${fmtDate(p.planned_start_date)} → ${fmtDate(p.planned_end_date)}`],
              ['Linked initiative', p.linked_initiative_id],
              ['Imported', p.imported_at ? `${fmtDateTime(p.imported_at)} (${p.source_file || 'unknown file'})` : 'Created in app'],
            ].map(([k, v]) => (
              <tr key={k}><td className="muted small" style={{ width: 150 }}>{k}</td><td>{v ?? '—'}</td></tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
