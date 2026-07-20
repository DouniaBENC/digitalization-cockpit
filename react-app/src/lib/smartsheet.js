// SmartSheet import/export mapping (spec §12, Phase 1).
// Column headers match the official SmartSheet export structure.
import * as XLSX from 'xlsx'

export const SMARTSHEET_COLUMNS = [
  'Id', 'Needs attention', 'Project Category', 'Project Name', 'Current Stage',
  'Digital Pillar', 'Key Benefiting Functions', 'Project Execution phase',
  'Pillar Sponsor', 'Project Description', 'Project Lead', 'PWR-T IT lead',
  'Integrator/Consultants', 'Charter Status', 'Charter file', 'IT Demand Status',
  'AR Status', 'AR file', 'CAPEX k€', 'Current Y Budget',
  'Cost Center/Internal Order', 'Planned Start Date', 'Planned End Date',
  'Linked Initiatives #',
]

const FIELD_MAP = {
  'Id': 'project_id',
  'Needs attention': 'needs_attention',
  'Project Category': 'project_category',
  'Project Name': 'project_name',
  'Current Stage': 'current_stage',
  'Digital Pillar': 'digital_pillar',
  'Key Benefiting Functions': 'key_benefiting_functions',
  'Project Execution phase': 'execution_phase',
  'Pillar Sponsor': 'pillar_sponsor',
  'Project Description': 'project_description',
  'Project Lead': 'project_lead',
  'PWR-T IT lead': 'pwt_it_lead',
  'Integrator/Consultants': 'integrator_consultants',
  'Charter Status': 'charter_status',
  'Charter file': 'charter_file',
  'IT Demand Status': 'it_demand_status',
  'AR Status': 'ar_status',
  'AR file': 'ar_file',
  'CAPEX k€': 'capex_keur',
  'Current Y Budget': 'current_year_budget',
  'Cost Center/Internal Order': 'cost_center_internal_order',
  'Planned Start Date': 'planned_start_date',
  'Planned End Date': 'planned_end_date',
  'Linked Initiatives #': 'linked_initiative_id',
}

function toDate(v) {
  if (v == null || v === '') return null
  if (v instanceof Date) return v.toISOString().slice(0, 10)
  if (typeof v === 'number') { // Excel serial
    const d = XLSX.SSF.parse_date_code(v)
    if (!d) return null
    return `${d.y}-${String(d.m).padStart(2, '0')}-${String(d.d).padStart(2, '0')}`
  }
  const d = new Date(v)
  return isNaN(d) ? null : d.toISOString().slice(0, 10)
}

function toNum(v) {
  if (v == null || v === '') return null
  const n = Number(String(v).replace(',', '.'))
  return isNaN(n) ? null : n
}

// Parse an uploaded SmartSheet XLSX/CSV export -> { rows, warnings }
export async function parseSmartsheetFile(file) {
  const buf = await file.arrayBuffer()
  const wb = XLSX.read(buf, { cellDates: true })
  // Pick the sheet whose header contains 'Id' and 'Project Name'
  let sheet = null
  for (const name of wb.SheetNames) {
    const ws = wb.Sheets[name]
    const head = XLSX.utils.sheet_to_json(ws, { header: 1, range: 0 })[0] || []
    if (head.includes('Id') && head.includes('Project Name')) { sheet = ws; break }
  }
  if (!sheet) throw new Error('No sheet with SmartSheet columns (Id, Project Name) found')

  const raw = XLSX.utils.sheet_to_json(sheet, { defval: null })
  const warnings = []
  const known = new Set(SMARTSHEET_COLUMNS)
  const headers = Object.keys(raw[0] || {})
  headers.filter(h => !known.has(h)).forEach(h => warnings.push(`Unknown column ignored: "${h}"`))
  SMARTSHEET_COLUMNS.filter(c => !headers.includes(c)).forEach(c => warnings.push(`Missing column: "${c}"`))

  const rows = raw
    .filter(r => r['Id'])
    .map(r => {
      const out = {}
      for (const [col, field] of Object.entries(FIELD_MAP)) {
        let v = r[col]
        if (field === 'planned_start_date' || field === 'planned_end_date') v = toDate(v)
        else if (field === 'capex_keur' || field === 'current_year_budget') v = toNum(v)
        else if (typeof v === 'string') v = v.trim() || null
        out[field] = v ?? null
      }
      return out
    })

  // in-file duplicate detection
  const seen = new Set()
  rows.forEach(r => {
    if (seen.has(r.project_id)) warnings.push(`Duplicate project Id in file: ${r.project_id}`)
    seen.add(r.project_id)
  })
  return { rows, warnings }
}

// Export converted initiatives as a SmartSheet-ready workbook
export function exportInitiativesToSmartsheet(items, filename = 'smartsheet_import.xlsx') {
  const data = items.map(({ idea, charter, bc }) => ({
    'Id': idea.linked_project_id || '',
    'Needs attention': [idea.priority && 'Priority', idea.quick_win && 'Quick Win'].filter(Boolean).join(', '),
    'Project Category': 'Digitalization',
    'Project Name': idea.title,
    'Current Stage': 'S1 (Scoping)',
    'Digital Pillar': idea.digital_pillar || '',
    'Key Benefiting Functions': (idea.impacted_functions || []).join(', '),
    'Project Execution phase': 'Discovery',
    'Pillar Sponsor': (charter && charter.sponsor) || idea.provisional_sponsor || '',
    'Project Description': idea.opportunity || '',
    'Project Lead': (charter && charter.project_lead) || '',
    'PWR-T IT lead': '',
    'Integrator/Consultants': '',
    'Charter Status': charter ? (charter.status === 'Approved' ? 'Approved' : 'Created & not approved') : 'Not created',
    'Charter file': '',
    'IT Demand Status': 'Not created',
    'AR Status': 'Not created',
    'AR file': '',
    'CAPEX k€': (bc && bc.cost_estimate) || '',
    'Current Y Budget': '',
    'Cost Center/Internal Order': '',
    'Planned Start Date': '',
    'Planned End Date': '',
    'Linked Initiatives #': idea.idea_id,
  }))
  const ws = XLSX.utils.json_to_sheet(data, { header: SMARTSHEET_COLUMNS })
  const wb = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(wb, ws, 'Projects')
  XLSX.writeFile(wb, filename)
}

// Validation before export (spec: validate required fields)
export function validateForExport(idea, charter) {
  const errors = []
  if (!idea.linked_project_id) errors.push('Missing project ID')
  if (!idea.title) errors.push('Missing project name')
  if (!idea.digital_pillar) errors.push('Missing digital pillar')
  if (!charter || !charter.project_lead) errors.push('Missing project lead in charter')
  return errors
}
