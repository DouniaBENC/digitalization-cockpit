import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import * as api from '../lib/api'
import { useAsync, StageBadge, Badge, RoadmapNote, fmtDate } from '../components/ui'
import { STAGES, ACTIVE_STAGES, PILLARS, COMMITTEES } from '../lib/constants'
import { complexityScore, impactScore, triageOverdue, daysInTriage } from '../lib/logic'

export default function IdeationBoard() {
  const nav = useNavigate()
  const { data: ideas, loading, error } = useAsync(api.listIdeas)
  const [view, setView] = useState('kanban')
  const [flt, setFlt] = useState({ pillar: '', stage: '', owner: '', committee: '', flag: '', q: '' })
  const [tip, setTip] = useState(null)

  const filtered = useMemo(() => (ideas || []).filter(i =>
    (!flt.pillar || i.digital_pillar === flt.pillar) &&
    (!flt.stage || i.stage === flt.stage) &&
    (!flt.committee || i.committee_target === flt.committee) &&
    (!flt.flag || (flt.flag === 'quick_win' && i.quick_win) || (flt.flag === 'priority' && i.priority) ||
      (flt.flag === 'overdue' && triageOverdue(i))) &&
    (!flt.q || (i.title + ' ' + i.idea_id).toLowerCase().includes(flt.q.toLowerCase()))
  ), [ideas, flt])

  if (loading) return <p>Loading…</p>
  if (error) return <p style={{ color: 'var(--red)' }}>{error.message}</p>

  const Card = ({ i }) => (
    <div className="kcard" onClick={() => nav(`/ideas/${i.id}`)}>
      <span className="muted small">{i.idea_id}</span>
      <div className="title">{i.title}</div>
      <div className="meta">
        {i.digital_pillar && <Badge color="blue">{i.digital_pillar}</Badge>}
        {i.quick_win && <Badge color="green">Quick win</Badge>}
        {i.priority && <Badge color="red">Priority</Badge>}
        {triageOverdue(i) && <Badge color="amber">⏰ {daysInTriage(i)}d in triage</Badge>}
      </div>
      <div className="small muted" style={{ marginTop: 6 }}>
        {i.owner?.name ? `Owner: ${i.owner.name}` : 'No owner'} · {fmtDate(i.updated_at)}
      </div>
    </div>
  )

  return (
    <div>
      <div className="topbar">
        <h1>Ideation Board</h1>
        <Link to="/ideas/new" className="btn">+ Submit idea</Link>
      </div>
      <RoadmapNote />
      <div className="filters">
        <input placeholder="Search…" value={flt.q} onChange={e => setFlt({ ...flt, q: e.target.value })} />
        <select value={flt.stage} onChange={e => setFlt({ ...flt, stage: e.target.value })}>
          <option value="">All stages</option>{STAGES.map(s => <option key={s}>{s}</option>)}
        </select>
        <select value={flt.pillar} onChange={e => setFlt({ ...flt, pillar: e.target.value })}>
          <option value="">All pillars</option>{PILLARS.map(p => <option key={p}>{p}</option>)}
        </select>
        <select value={flt.committee} onChange={e => setFlt({ ...flt, committee: e.target.value })}>
          <option value="">All committees</option>{COMMITTEES.map(c => <option key={c}>{c}</option>)}
        </select>
        <select value={flt.flag} onChange={e => setFlt({ ...flt, flag: e.target.value })}>
          <option value="">All flags</option>
          <option value="quick_win">Quick wins</option>
          <option value="priority">Priorities</option>
          <option value="overdue">Triage overdue</option>
        </select>
        <div className="tabs" style={{ border: 'none', marginBottom: 0, marginLeft: 'auto' }}>
          {['kanban', 'table', 'bubble'].map(v => (
            <button key={v} className={view === v ? 'active' : ''} onClick={() => setView(v)}>
              {v[0].toUpperCase() + v.slice(1)}
            </button>
          ))}
        </div>
      </div>

      {view === 'kanban' && (
        <div className="kanban">
          {[...ACTIVE_STAGES, 'Converted'].map(stage => {
            const items = filtered.filter(i => i.stage === stage)
            return (
              <div className="col" key={stage}>
                <h3>{stage} <span>{items.length}</span></h3>
                {items.map(i => <Card key={i.id} i={i} />)}
              </div>
            )
          })}
        </div>
      )}

      {view === 'table' && (
        <div className="card" style={{ overflowX: 'auto' }}>
          <table className="data">
            <thead><tr>
              <th>ID</th><th>Title</th><th>Stage</th><th>Pillar</th><th>Requester</th>
              <th>Owner</th><th>Flags</th><th>Committee</th><th>Updated</th>
            </tr></thead>
            <tbody>
              {filtered.map(i => (
                <tr key={i.id}>
                  <td><Link to={`/ideas/${i.id}`}>{i.idea_id}</Link></td>
                  <td><Link to={`/ideas/${i.id}`}>{i.title}</Link></td>
                  <td><StageBadge stage={i.stage} /></td>
                  <td>{i.digital_pillar || '—'}</td>
                  <td>{i.requester?.name}</td>
                  <td>{i.owner?.name || '—'}</td>
                  <td>
                    {i.quick_win && <Badge color="green">QW</Badge>}{' '}
                    {i.priority && <Badge color="red">P</Badge>}{' '}
                    {triageOverdue(i) && <Badge color="amber">⏰</Badge>}
                  </td>
                  <td>{i.committee_target || '—'}</td>
                  <td>{fmtDate(i.updated_at)}</td>
                </tr>
              ))}
              {!filtered.length && <tr><td colSpan={9} className="muted">No ideas match the filters.</td></tr>}
            </tbody>
          </table>
        </div>
      )}

      {view === 'bubble' && (
        <div className="card bubble-wrap">
          <h2>Impact vs Complexity</h2>
          <p className="muted small">X: complexity (effort assessment) · Y: impact (urgency, value signals) · green = quick win, red = priority</p>
          <BubbleChart ideas={filtered.filter(i => ACTIVE_STAGES.includes(i.stage))} tip={tip} setTip={setTip} nav={nav} />
        </div>
      )}
    </div>
  )
}

function BubbleChart({ ideas, tip, setTip, nav }) {
  const W = 800, H = 420, pad = 45
  const pts = ideas.map(i => ({
    i,
    x: complexityScore(i) ?? 1.5 + Math.random() * 0.01,
    y: impactScore(i),
  }))
  const maxY = Math.max(5, ...pts.map(p => p.y))
  const sx = v => pad + ((v - 1) / 2) * (W - 2 * pad)
  const sy = v => H - pad - (v / maxY) * (H - 2 * pad)
  return (
    <>
      {tip && <div className="bubble-tip" style={{ left: tip.px + 12, top: tip.py - 10 }}>{tip.label}</div>}
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', maxHeight: 460 }}
        onMouseLeave={() => setTip(null)}>
        <line x1={pad} y1={H - pad} x2={W - pad} y2={H - pad} stroke="#c8cdd8" />
        <line x1={pad} y1={pad} x2={pad} y2={H - pad} stroke="#c8cdd8" />
        <text x={W / 2} y={H - 10} textAnchor="middle" fontSize="12" fill="#66708a">Complexity →</text>
        <text x={14} y={H / 2} textAnchor="middle" fontSize="12" fill="#66708a" transform={`rotate(-90 14 ${H / 2})`}>Impact →</text>
        {['Low', 'Medium', 'High'].map((l, k) => (
          <text key={l} x={sx(k + 1)} y={H - pad + 16} textAnchor="middle" fontSize="11" fill="#8892ab">{l}</text>
        ))}
        {/* quick-win quadrant hint */}
        <rect x={pad} y={pad} width={(W - 2 * pad) / 2} height={(H - 2 * pad) / 2} fill="#1a8f4d" opacity="0.05" />
        <text x={pad + 8} y={pad + 16} fontSize="11" fill="#1a8f4d">Quick-win zone</text>
        {pts.map(({ i, x, y }, k) => (
          <circle key={k} cx={sx(x)} cy={sy(y)} r={i.priority ? 14 : 10}
            fill={i.quick_win ? 'var(--green)' : i.priority ? 'var(--red)' : 'var(--accent)'}
            opacity="0.75" style={{ cursor: 'pointer' }}
            onClick={() => nav(`/ideas/${i.id}`)}
            onMouseEnter={e => setTip({ px: e.nativeEvent.offsetX, py: e.nativeEvent.offsetY, label: `${i.idea_id} — ${i.title}` })}
          />
        ))}
      </svg>
    </>
  )
}
