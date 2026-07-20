// Reference data — kept as app-level lists so imports stay tolerant
// and the client can adapt them without schema changes.

export const STAGES = [
  'L0 Submitted', 'L0 Triage', 'L1 Qualified', 'L2 BC/Charter',
  'G1 Approval', 'Converted', 'Rejected', 'Hold',
]

export const ACTIVE_STAGES = STAGES.slice(0, 5)

export const PILLARS = [
  'Smart Planning',
  'AI-enhanced Engineering',
  'Agentic AI for Engineering',
  'CTQ & Digital Twin Innovation',
  'Lean and Automated Support',
  'Digital Thread',
  'To Be Confirmed',
]

export const FUNCTIONS = [
  'Engineering', 'Manufacturing', 'Installation', 'Planning', 'Quality',
  'HR', 'Legal', 'Project', 'Technical Office', 'Other',
]

export const VALUE_TYPES = [
  'Cost reduction', 'Cycle time reduction', 'Quality improvement',
  'Risk reduction', 'Revenue enablement', 'Compliance',
  'User experience', 'Data availability',
]

export const EFFORT = ['Low', 'Medium', 'High']
export const URGENCY = ['Low', 'Medium', 'High']
export const DATA_AVAILABILITY = ['Unknown', 'Low', 'Medium', 'High']

export const COMMITTEES = ['Pillar SteerCo', 'Digitalization SteerCo']
export const DECISION_COMMITTEES = [...COMMITTEES, 'Project Meeting']
export const DECISION_STATUSES = ['To Decide', 'Decided', 'Blocked', 'Deferred', 'Escalated']
export const OUTCOMES = ['Go', 'No-Go', 'Rework', 'Hold']
export const DOC_STATUSES = ['Draft', 'In Review', 'Ready for Gate', 'Approved', 'Rework']

export const PROJECT_STAGES = [
  'S1 (Scoping)', 'G2 (Business Case)', 'S2 (Planning)', 'G3 (Action Plan)',
  'S3 (Execution)', 'G4 (Implementation)', 'S4 (Verification)', 'G5 (Closed)',
]

export const ROLES = [
  { value: 'requester', label: 'Requester' },
  { value: 'program_manager', label: 'Program Manager' },
  { value: 'transformation_team', label: 'Transformation Team' },
  { value: 'project_lead', label: 'Project Lead' },
]

export const TRIAGE_SLA_DAYS = 7

export const ROADMAP_NOTE =
  'AI-guided intake and draft generation are planned for a future release. ' +
  'In the MVP, Business Case v0 and Project Charter v0 are generated from structured ' +
  'fields and enriched manually by the Program Manager / Transformation Team.'

// Business Case structured sections (spec §10)
export const BC_SECTIONS = [
  { key: 'problem_statement', label: '2. Problem / Opportunity', hint: 'What problem are we solving? Who is impacted? Why now?', required: true },
  { key: 'proposed_solution', label: '3. Proposed Concept', hint: 'Proposed digitalization / AI solution, operating model change', required: true },
  { key: 'strategic_alignment', label: '4. Strategic Alignment', hint: 'Digital pillar, link to business objectives', required: true },
  { key: 'e3_impact_summary', label: '4b. E3 Impact', hint: 'Environment, Economy, Engagement', required: false },
  { key: 'expected_benefits', label: '5. Expected Benefits', hint: 'Business benefits, target users / functions', required: true },
  { key: 'assumptions', label: '7. Assumptions', hint: 'Key assumptions and open questions', required: true },
  { key: 'risks', label: '7b. Main Risks', hint: 'Main risks', required: true },
  { key: 'dependencies', label: '7c. Dependencies', hint: 'Systems, data, organization', required: true },
  { key: 'cost_estimate', label: '8. Rough Cost / Effort', hint: 'CAPEX / OPEX, internal and external effort', required: true },
  { key: 'resource_needs', label: '8b. Resource Needs', hint: 'People / skills', required: false },
  { key: 'success_metrics', label: '9. Success Metrics', hint: 'Adoption, efficiency, quality KPIs, first value proof date', required: true },
]

// Charter structured sections (spec §11)
export const CH_SECTIONS = [
  { key: 'objectives', label: '2. Objectives', hint: 'Main objective, expected outcomes', required: true },
  { key: 'scope_in', label: '3. Scope In', hint: 'In scope, target users / processes', required: true },
  { key: 'scope_out', label: '3b. Scope Out', hint: 'Explicitly out of scope', required: true },
  { key: 'deliverables', label: '4. Deliverables', hint: 'MVP / first deliverable, business, technical, change deliverables', required: true },
  { key: 'high_level_timeline', label: '6. Timeline', hint: 'Indicative start / end, key milestones', required: true },
  { key: 'stakeholders', label: '7. Roles & Stakeholders', hint: 'Sponsor, business owner, leads, key stakeholders', required: false },
  { key: 'dependencies', label: '8. Dependencies', hint: 'Data, systems, resources, other projects', required: true },
  { key: 'governance_path', label: '5. Governance & Decision Path', hint: 'Target gate, committee, required decision', required: true },
]
