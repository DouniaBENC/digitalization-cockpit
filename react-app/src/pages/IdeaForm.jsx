// Simple submission form — deliberately light (spec: idea submission must stay simple).
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../App'
import * as api from '../lib/api'
import { Field, MultiCheck, RoadmapNote } from '../components/ui'
import { PILLARS, FUNCTIONS, VALUE_TYPES, URGENCY } from '../lib/constants'

export default function IdeaForm() {
  const { profile } = useAuth()
  const nav = useNavigate()
  const [f, setF] = useState({
    title: '', opportunity: '', business_benefits: '', digital_pillar: '',
    impacted_functions: [], expected_value_types: [], estimated_value: '',
    urgency: '', risks_challenges: '', interface_systems: '',
    e3_environment: false, e3_economy: false, e3_engagement: false,
  })
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)
  const set = (k, v) => setF(s => ({ ...s, [k]: v }))

  const submit = async (e) => {
    e.preventDefault()
    if (!f.e3_environment && !f.e3_economy && !f.e3_engagement && !f.expected_value_types.length) {
      setError('Please select at least one expected impact area (E3) or value type.')
      return
    }
    setBusy(true); setError(null)
    try {
      const idea = await api.createIdea({
        ...f,
        digital_pillar: f.digital_pillar || null,
        urgency: f.urgency || null,
        requester_id: profile.id,
        stage: 'L0 Submitted', // manual move to triage by PM/TT (validated design change)
      })
      nav(`/ideas/${idea.id}`)
    } catch (err) { setError(err.message); setBusy(false) }
  }

  return (
    <div style={{ maxWidth: 760 }}>
      <div className="topbar"><h1>Submit a Digitalization Idea</h1></div>
      <RoadmapNote />
      <form onSubmit={submit} className="card">
        <Field label="Title *"><input type="text" required value={f.title} onChange={e => set('title', e.target.value)} placeholder="Short, descriptive title" /></Field>
        <Field label="Problem / Opportunity *" hint="What problem are you trying to address? How is the work done today?">
          <textarea required value={f.opportunity} onChange={e => set('opportunity', e.target.value)} /></Field>
        <Field label="Expected Business Benefits *" hint="What would a better future state look like?">
          <textarea required value={f.business_benefits} onChange={e => set('business_benefits', e.target.value)} /></Field>
        <Field label="E3 Impact Areas" hint="At least one impact area or value type required">
          <div className="checks">
            <label><input type="checkbox" checked={f.e3_environment} onChange={e => set('e3_environment', e.target.checked)} /> Environment</label>
            <label><input type="checkbox" checked={f.e3_economy} onChange={e => set('e3_economy', e.target.checked)} /> Economy</label>
            <label><input type="checkbox" checked={f.e3_engagement} onChange={e => set('e3_engagement', e.target.checked)} /> Engagement</label>
          </div>
        </Field>
        <Field label="Expected Value Types"><MultiCheck options={VALUE_TYPES} value={f.expected_value_types} onChange={v => set('expected_value_types', v)} /></Field>
        <div className="grid cols-2">
          <Field label="Digital Pillar" hint="Leave empty if unsure">
            <select value={f.digital_pillar} onChange={e => set('digital_pillar', e.target.value)}>
              <option value="">— Not sure —</option>
              {PILLARS.map(p => <option key={p}>{p}</option>)}
            </select></Field>
          <Field label="Urgency">
            <select value={f.urgency} onChange={e => set('urgency', e.target.value)}>
              <option value="">—</option>{URGENCY.map(u => <option key={u}>{u}</option>)}
            </select></Field>
        </div>
        <Field label="Which functions / teams would benefit?"><MultiCheck options={FUNCTIONS} value={f.impacted_functions} onChange={v => set('impacted_functions', v)} /></Field>
        <Field label="Estimated Value" hint="Rough estimate, free text"><input type="text" value={f.estimated_value} onChange={e => set('estimated_value', e.target.value)} placeholder="e.g. 50 hours/month saved, 20 k€/year" /></Field>
        <Field label="Systems / Data / Tools Involved"><input type="text" value={f.interface_systems} onChange={e => set('interface_systems', e.target.value)} placeholder="SAP, Teamcenter, MES, BEDM, Synergy…" /></Field>
        <Field label="Known Risks, Blockers or Constraints"><textarea value={f.risks_challenges} onChange={e => set('risks_challenges', e.target.value)} /></Field>
        {error && <p style={{ color: 'var(--red)' }}>{error}</p>}
        <button className="btn" disabled={busy}>Submit idea</button>
      </form>
    </div>
  )
}
