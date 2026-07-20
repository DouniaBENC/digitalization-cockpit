// Pure business logic — backend-agnostic (portable to Databricks later).
import { TRIAGE_SLA_DAYS, BC_SECTIONS, CH_SECTIONS } from './constants'

const score = { Low: 1, Medium: 2, High: 3 }

export function complexityScore(idea) {
  const vals = [idea.resources_effort, idea.cost_effort, idea.change_effort, idea.technical_effort]
    .map(v => score[v] || 0).filter(Boolean)
  if (!vals.length) return null
  return vals.reduce((a, b) => a + b, 0) / vals.length
}

export function impactScore(idea) {
  let s = 0
  if (idea.urgency) s += score[idea.urgency]
  s += Math.min((idea.expected_value_types || []).length, 3) * 0.5
  s += [idea.e3_environment, idea.e3_economy, idea.e3_engagement].filter(Boolean).length * 0.5
  if (idea.estimated_value) s += 1
  return s
}

// Spec §14 — Quick Win suggestion
export function suggestQuickWin(idea) {
  const cx = complexityScore(idea)
  return Boolean(
    idea.estimated_value &&
    cx !== null && cx <= 2 &&
    (idea.cost_effort === 'Low' || !idea.cost_effort)
  )
}

// Spec §14 — Priority suggestion
export function suggestPriority(idea) {
  return Boolean(
    idea.urgency === 'High' &&
    ((idea.impacted_functions || []).length >= 2 || idea.digital_pillar)
  )
}

export function daysInTriage(idea) {
  if (!['L0 Submitted', 'L0 Triage'].includes(idea.stage)) return 0
  return Math.floor((Date.now() - new Date(idea.submitted_date)) / 86400000)
}

export function triageOverdue(idea) {
  return daysInTriage(idea) > TRIAGE_SLA_DAYS
}

// ---------- Transition criteria (spec §6) ----------
// Each returns [{ label, ok }] — the UI shows the checklist; PM can override with a note.

export function l1Criteria(idea) {
  return [
    { label: 'Not an obvious duplicate, or duplicate relationship documented', ok: !idea.duplicate_of || !!idea.duplicate_note || true },
    { label: 'Fits a digital pillar or marked "To Be Confirmed"', ok: !!idea.digital_pillar },
    { label: 'Clear problem / opportunity statement', ok: (idea.opportunity || '').length >= 30 },
    { label: 'Plausible business benefit', ok: (idea.business_benefits || '').length >= 20 },
    { label: 'Identified owner for next-step assessment', ok: !!idea.owner_id },
    { label: 'Within digitalization scope (triage note if unclear)', ok: true },
  ]
}

export function l2Criteria(idea) {
  return [
    { label: 'Sponsor or provisional sponsor identified', ok: !!idea.provisional_sponsor },
    { label: 'Impacted function(s) identified', ok: (idea.impacted_functions || []).length > 0 },
    { label: 'Expected value type selected', ok: (idea.expected_value_types || []).length > 0 },
    { label: 'Complexity / effort assessment completed', ok: complexityScore(idea) !== null },
    { label: 'Initial risks and system dependencies documented', ok: !!idea.risks_challenges || !!idea.interface_systems },
  ]
}

export function g1Criteria(idea, bc, ch) {
  return [
    { label: 'Business Case v0 complete enough for decision', ok: bc ? bcCompleteness(bc).pct >= 80 : false },
    { label: 'Project Charter v0 complete enough for decision', ok: ch ? chCompleteness(ch).pct >= 80 : false },
    { label: 'Explicit recommendation (Go / No-Go / Rework / Hold)', ok: !!(bc && bc.recommendation) },
    { label: 'Rough budget / effort estimate documented', ok: !!(bc && bc.cost_estimate) },
    { label: 'Benefits and success metrics documented', ok: !!(bc && bc.expected_benefits && bc.success_metrics) },
    { label: 'Scope in / scope out documented', ok: !!(ch && ch.scope_in && ch.scope_out) },
    { label: 'Risks, dependencies, assumptions documented', ok: !!(bc && bc.risks && bc.dependencies && bc.assumptions) },
    { label: 'Project lead or next-stage owner proposed', ok: !!(ch && ch.project_lead) },
    { label: 'Committee target selected', ok: !!(idea.committee_target || (bc && bc.committee_target)) },
  ]
}

export function conversionCriteria(idea, decisions) {
  const g1 = (decisions || []).find(d =>
    d.related_id === idea.idea_id && d.status === 'Decided' && d.outcome === 'Go' &&
    d.title.toLowerCase().includes('g1'))
  return [
    { label: 'G1 decision outcome is Go (logged in Decision Log)', ok: !!g1 },
    { label: 'Committee decision logged', ok: !!g1 },
  ]
}

// ---------- Document completeness ----------
function completeness(doc, sections) {
  const required = sections.filter(s => s.required)
  const done = required.filter(s => (doc[s.key] || '').trim().length >= 10)
  return {
    done: done.length,
    total: required.length,
    pct: Math.round((done.length / required.length) * 100),
    missing: required.filter(s => (doc[s.key] || '').trim().length < 10).map(s => s.label),
  }
}
export const bcCompleteness = doc => completeness(doc, BC_SECTIONS)
export const chCompleteness = doc => completeness(doc, CH_SECTIONS)

// ---------- Project alerts (exception-based cockpit) ----------
export function projectAlerts(p) {
  const alerts = []
  const today = new Date()
  const isClosed = (p.current_stage || '').startsWith('G5') || (p.current_stage || '').startsWith('S4')
  if (p.planned_end_date && new Date(p.planned_end_date) < today && !isClosed)
    alerts.push({ type: 'planning', msg: 'Planned end date passed' })
  if (p.planned_start_date && new Date(p.planned_start_date) < today &&
      (p.current_stage || '').startsWith('S1'))
    alerts.push({ type: 'planning', msg: 'Started per plan but still in Scoping' })
  if (p.capex_keur == null && p.current_year_budget == null)
    alerts.push({ type: 'budget', msg: 'No CAPEX / budget data' })
  if ((p.charter_status || '') === 'Not created' || !p.charter_status)
    alerts.push({ type: 'governance', msg: 'Charter missing' })
  if ((p.it_demand_status || '') === 'Not created')
    alerts.push({ type: 'governance', msg: 'IT demand not created' })
  if ((p.ar_status || '') === 'Not created')
    alerts.push({ type: 'governance', msg: 'AR not created' })
  if ((p.needs_attention || '').toLowerCase().includes('budget'))
    alerts.push({ type: 'budget', msg: 'Flagged: budget attention' })
  if ((p.needs_attention || '').toLowerCase().includes('planning'))
    alerts.push({ type: 'planning', msg: 'Flagged: planning attention' })
  return alerts
}

export function isPriorityProject(p) {
  return (p.needs_attention || '').toLowerCase().includes('priority')
}
export function isQuickWinProject(p) {
  return (p.needs_attention || '').toLowerCase().includes('quick win')
}
