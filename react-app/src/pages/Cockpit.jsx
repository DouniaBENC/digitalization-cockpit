// Exception-based cockpit (spec §8.7): decisions, alerts, priorities,
// quick wins, escalations, highlights. Goal: SteerCo prep < 30 min.
import { Link } from 'react-router-dom'
import * as api from '../lib/api'
import { useAsync, Badge, fmtDate } from '../components/ui'
import { projectAlerts, isPriorityProject, isQuickWinProject, triageOverdue } from '../lib/logic'
import { COMMITTEES } from '../lib/constants'

export default function Cockpit() {
  const ideas = useAsync(api.listIdeas)
  const projects = useAsync(api.listProjects)
  const decisions = useAsync(api.listDecisions)

  if (ideas.loading || projects.loading || decisions.loading) return <p>Loading…</p>
  const I = ideas.data || [], P = projects.data || [], D = decisions.data || []

  const funnel = [
    ['Submitted', I.filter(i => i.stage === 'L0 Submitted').length],
    ['In triage', I.filter(i => i.stage === 'L0 Triage').length],
    ['Qualified (L1/L2)', I.filter(i => ['L1 Qualified', 'L2 BC/Charter'].includes(i.stage)).length],
    ['At G1', I.filter(i => i.stage === 'G1 Approval').length],
    ['Converted', I.filter(i => i.stage === 'Converted').length],
  ]
  const activeProjects = P.filter(p => !(p.current_stage || '').startsWith('G5'))
  const completed = P.filter(p => (p.current_stage || '').startsWith('G5'))
  const withAlerts = P.map(p => ({ p, alerts: projectAlerts(p) })).filter(x => x.alerts.length)
  const budgetAlerts = withAlerts.filter(x => x.alerts.some(a => a.type === 'budget'))
  const planningAlerts = withAlerts.filter(x => x.alerts.some(a => a.type === 'planning'))
  const openDecisions = D.filter(d => ['To Decide', 'Blocked'].includes(d.status))
  const nextSteerco = D.filter(d => d.next_steerco && d.status !== 'Decided')
  const escalations = D.filter(d => d.status === 'Escalated')
  const overdueTriage = I.filter(triageOverdue)
  const highlights = [
    ...D.filter(d => d.status === 'Decided' && d.outcome === 'Go')
      .slice(0, 4).map(d => `✅ Go decision: ${d.title}`),
    ...I.filter(i => i.stage === 'Converted').slice(0, 3)
      .map(i => `🚀 ${i.idea_id} converted to project ${i.linked_project_id}`),
    ...completed.slice(0, 3).map(p => `🏁 ${p.project_name} closed`),
  ]

  return (
    <div>
      <div className="topbar">
        <div>
          <h1>Cockpit</h1>
          <p className="muted small mb0">Exception-based view — decisions, alerts, priorities. Target: SteerCo pack in &lt; 30 min.</p>
        </div>
        <button className="btn secondary no-print" onClick={() => window.print()}>🖨 Print SteerCo pack</button>
      </div>

      <div className="grid cols-4">
        {funnel.map(([l, n]) => (
          <div className="card kpi" key={l}><div className="num">{n}</div><div className="lbl">{l}</div></div>
        ))}
        <div className="card kpi"><div className="num">{activeProjects.length}</div><div className="lbl">Active projects</div></div>
        <div className="card kpi"><div className="num">{completed.length}</div><div className="lbl">Completed</div></div>
        <div className="card kpi"><div className="num" style={{ color: 'var(--green)' }}>{I.filter(i => i.quick_win).length + P.filter(isQuickWinProject).length}</div><div className="lbl">Quick wins</div></div>
        <div className="card kpi"><div className="num" style={{ color: 'var(--red)' }}>{I.filter(i => i.priority).length + P.filter(isPriorityProject).length}</div><div className="lbl">Priorities</div></div>
      </div>

      <div className="grid cols-2">
        <div className="card">
          <h2>⚖️ Open decisions for next committees</h2>
          {COMMITTEES.map(c => {
            const rows = openDecisions.filter(d => d.committee_target === c)
            return (
              <div key={c} style={{ marginBottom: 10 }}>
                <h3 className="muted small">{c} ({rows.length})</h3>
                {rows.slice(0, 6).map(d => (
                  <div key={d.id} className="alert-line">
                    <Badge color={d.status === 'Blocked' ? 'red' : 'amber'}>{d.status}</Badge>
                    <span>{d.title}</span>
                    <span className="muted small">{d.due_date ? `due ${fmtDate(d.due_date)}` : ''} {d.recommendation ? `· reco: ${d.recommendation}` : ''}</span>
                  </div>
                ))}
                {!rows.length && <p className="muted small">None.</p>}
              </div>
            )
          })}
          {nextSteerco.length > 0 && (
            <p className="small"><Badge color="purple">Next SteerCo agenda</Badge> {nextSteerco.length} item(s) flagged — <Link to="/decisions">view</Link></p>
          )}
        </div>

        <div>
          <div className="card">
            <h2>⚠️ Alerts</h2>
            {budgetAlerts.map(({ p, alerts }) => (
              <div key={p.id} className="alert-line"><Badge color="red">Budget</Badge>
                <span>{p.project_id} {p.project_name}</span>
                <span className="muted small">{alerts.filter(a => a.type === 'budget').map(a => a.msg).join('; ')}</span></div>
            ))}
            {planningAlerts.map(({ p, alerts }) => (
              <div key={p.id + 'p'} className="alert-line"><Badge color="amber">Planning</Badge>
                <span>{p.project_id} {p.project_name}</span>
                <span className="muted small">{alerts.filter(a => a.type === 'planning').map(a => a.msg).join('; ')}</span></div>
            ))}
            {overdueTriage.map(i => (
              <div key={i.id} className="alert-line"><Badge color="amber">Triage</Badge>
                <span><Link to={`/ideas/${i.id}`}>{i.idea_id} {i.title}</Link></span>
                <span className="muted small">waiting too long in triage</span></div>
            ))}
            {withAlerts.filter(x => x.alerts.some(a => a.type === 'governance')).map(({ p, alerts }) => (
              <div key={p.id + 'g'} className="alert-line"><Badge color="gray">Governance</Badge>
                <span>{p.project_id} {p.project_name}</span>
                <span className="muted small">{alerts.filter(a => a.type === 'governance').map(a => a.msg).join('; ')}</span></div>
            ))}
            {!withAlerts.length && !overdueTriage.length && <p className="muted">No alerts. 🎉</p>}
          </div>

          <div className="card">
            <h2>🚨 Escalations</h2>
            {escalations.map(d => (
              <div key={d.id} className="alert-line"><Badge color="red">Escalated</Badge><span>{d.title}</span></div>
            ))}
            {!escalations.length && <p className="muted">None.</p>}
          </div>

          <div className="card">
            <h2>🌟 Positive highlights</h2>
            {highlights.length ? highlights.map((h, i) => <div key={i} className="alert-line"><span>{h}</span></div>)
              : <p className="muted">Nothing yet — they will appear as decisions are taken and initiatives convert.</p>}
          </div>
        </div>
      </div>
    </div>
  )
}
