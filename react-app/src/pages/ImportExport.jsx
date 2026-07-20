import { useState } from 'react'
import * as api from '../lib/api'
import { useAsync, Badge, fmtDateTime } from '../components/ui'
import { parseSmartsheetFile, exportInitiativesToSmartsheet, validateForExport } from '../lib/smartsheet'

export default function ImportExport() {
  const projects = useAsync(api.listProjects)
  const ideas = useAsync(api.listIdeas)
  const [preview, setPreview] = useState(null) // { rows, warnings, dupes, fileName }
  const [busy, setBusy] = useState(false)
  const [done, setDone] = useState(null)
  const [err, setErr] = useState(null)

  const onFile = async (e) => {
    const file = e.target.files[0]
    if (!file) return
    setErr(null); setDone(null); setBusy(true)
    try {
      const { rows, warnings } = await parseSmartsheetFile(file)
      const existing = await api.existingProjectIds()
      const dupes = rows.filter(r => existing.has(r.project_id)).map(r => r.project_id)
      setPreview({ rows, warnings, dupes, fileName: file.name })
    } catch (ex) { setErr(ex.message) }
    setBusy(false)
    e.target.value = ''
  }

  const confirmImport = async () => {
    setBusy(true); setErr(null)
    try {
      const stamped = preview.rows.map(r => ({
        ...r, source_file: preview.fileName, imported_at: new Date().toISOString(),
      }))
      await api.upsertProjects(stamped)
      setDone(`Imported ${stamped.length} projects from ${preview.fileName} (${preview.dupes.length} updated, ${stamped.length - preview.dupes.length} new).`)
      setPreview(null); projects.reload()
    } catch (ex) { setErr(ex.message) }
    setBusy(false)
  }

  const converted = (ideas.data || []).filter(i => i.stage === 'Converted')
  const exportConverted = async () => {
    setBusy(true); setErr(null)
    try {
      const items = []
      const problems = []
      for (const idea of converted) {
        const charter = await api.getCharterByIdea(idea.id)
        const bc = await api.getBusinessCaseByIdea(idea.id)
        const errors = validateForExport(idea, charter)
        if (errors.length) problems.push(`${idea.idea_id}: ${errors.join(', ')}`)
        items.push({ idea, charter, bc })
      }
      if (problems.length && !window.confirm(`Some initiatives have gaps:\n${problems.join('\n')}\n\nExport anyway?`)) {
        setBusy(false); return
      }
      exportInitiativesToSmartsheet(items, `smartsheet_import_${new Date().toISOString().slice(0, 10)}.xlsx`)
      setDone(`Exported ${items.length} converted initiatives to a SmartSheet-ready file.`)
    } catch (ex) { setErr(ex.message) }
    setBusy(false)
  }

  const lastImport = (projects.data || []).filter(p => p.imported_at)
    .sort((a, b) => new Date(b.imported_at) - new Date(a.imported_at))[0]

  return (
    <div style={{ maxWidth: 900 }}>
      <div className="topbar"><h1>SmartSheet Import / Export</h1></div>
      <p className="muted small">SmartSheet remains the official source of truth. Phase 1 uses file exchange; a direct connector is on the roadmap (Phase 2).</p>

      <div className="card">
        <h2>Import projects (SmartSheet XLSX/CSV export)</h2>
        {lastImport && <p className="small muted">Last import: {fmtDateTime(lastImport.imported_at)} — {lastImport.source_file}</p>}
        <input type="file" accept=".xlsx,.csv" onChange={onFile} disabled={busy} />
        {preview && (
          <div style={{ marginTop: 14 }}>
            <p><b>{preview.rows.length}</b> projects found in <b>{preview.fileName}</b>.</p>
            {preview.dupes.length > 0 && (
              <p className="small" style={{ color: 'var(--amber)' }}>
                ⚠ {preview.dupes.length} existing project IDs will be updated: {preview.dupes.join(', ')}
              </p>
            )}
            {preview.warnings.map((w, i) => <p key={i} className="small" style={{ color: 'var(--amber)' }}>⚠ {w}</p>)}
            <div style={{ maxHeight: 260, overflow: 'auto', border: '1px solid var(--border)', borderRadius: 8, marginBottom: 10 }}>
              <table className="data">
                <thead><tr><th>Id</th><th>Name</th><th>Stage</th><th>Pillar</th><th>Lead</th><th>Initiative</th></tr></thead>
                <tbody>{preview.rows.map((r, i) => (
                  <tr key={i}><td>{r.project_id}{preview.dupes.includes(r.project_id) && <> <Badge color="amber">update</Badge></>}</td>
                    <td>{r.project_name}</td><td className="small">{r.current_stage}</td>
                    <td className="small">{r.digital_pillar}</td><td className="small">{r.project_lead}</td>
                    <td className="small">{r.linked_initiative_id}</td></tr>
                ))}</tbody>
              </table>
            </div>
            <button className="btn" onClick={confirmImport} disabled={busy}>Confirm import</button>{' '}
            <button className="btn secondary" onClick={() => setPreview(null)}>Cancel</button>
          </div>
        )}
      </div>

      <div className="card">
        <h2>Export converted initiatives (SmartSheet-ready)</h2>
        <p className="small muted">Generates an XLSX matching the SmartSheet column structure for the {converted.length} converted initiative(s). Required fields are validated before export.</p>
        <button className="btn" onClick={exportConverted} disabled={busy || !converted.length}>
          Export {converted.length} initiative(s)
        </button>
      </div>

      {done && <p style={{ color: 'var(--green)' }}>{done}</p>}
      {err && <p style={{ color: 'var(--red)' }}>{err}</p>}
    </div>
  )
}
