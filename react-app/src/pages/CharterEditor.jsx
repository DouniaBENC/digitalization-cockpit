import { useParams, Link } from 'react-router-dom'
import * as api from '../lib/api'
import { useAsync, Field } from '../components/ui'
import DocEditor from '../components/DocEditor'
import { CH_SECTIONS } from '../lib/constants'
import { chCompleteness } from '../lib/logic'

export default function CharterEditor() {
  const { id } = useParams()
  const idea = useAsync(() => api.getIdea(id), [id])
  const ch = useAsync(() => api.getCharterByIdea(id), [id])

  if (idea.loading || ch.loading) return <p>Loading…</p>
  if (!ch.data) return <p className="muted">No charter yet — it is created automatically when the idea is qualified (L1). <Link to={`/ideas/${id}`}>← Back to idea</Link></p>

  const rolesHeader = (f, set, isPMTT) => (
    <>
      <div className="field"><label>Sponsor</label>
        <input type="text" value={f.sponsor || ''} onChange={e => set('sponsor', e.target.value)} disabled={!isPMTT} /></div>
      <div className="field"><label>Business Owner</label>
        <input type="text" value={f.business_owner || ''} onChange={e => set('business_owner', e.target.value)} disabled={!isPMTT} /></div>
      <div className="field"><label>Proposed Project Lead</label>
        <input type="text" value={f.project_lead || ''} onChange={e => set('project_lead', e.target.value)} disabled={!isPMTT} /></div>
    </>
  )

  return (
    <div>
      <p className="no-print"><Link to={`/ideas/${id}`}>← Back to {idea.data.idea_id}</Link></p>
      <DocEditor
        key={ch.data.id + ch.data.version}
        docType="charter"
        doc={ch.data}
        idea={idea.data}
        title={`Project Charter — ${idea.data.title}`}
        sections={CH_SECTIONS}
        completeness={chCompleteness}
        extraFields={['sponsor', 'business_owner', 'project_lead']}
        extraHeader={rolesHeader}
        onSaved={() => ch.reload()}
      />
    </div>
  )
}
