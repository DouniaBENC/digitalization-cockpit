import { useParams, Link } from 'react-router-dom'
import * as api from '../lib/api'
import { useAsync } from '../components/ui'
import DocEditor, { GovernanceHeaderFields } from '../components/DocEditor'
import { BC_SECTIONS } from '../lib/constants'
import { bcCompleteness } from '../lib/logic'

export default function BusinessCaseEditor() {
  const { id } = useParams()
  const idea = useAsync(() => api.getIdea(id), [id])
  const bc = useAsync(() => api.getBusinessCaseByIdea(id), [id])

  if (idea.loading || bc.loading) return <p>Loading…</p>
  if (!bc.data) return <p className="muted">No business case yet — it is created automatically when the idea is qualified (L1). <Link to={`/ideas/${id}`}>← Back to idea</Link></p>

  return (
    <div>
      <p className="no-print"><Link to={`/ideas/${id}`}>← Back to {idea.data.idea_id}</Link></p>
      <DocEditor
        key={bc.data.id + bc.data.version}
        docType="business_case"
        doc={bc.data}
        idea={idea.data}
        title={`Business Case — ${idea.data.title}`}
        sections={BC_SECTIONS}
        completeness={bcCompleteness}
        extraFields={['recommendation', 'committee_target', 'estimated_value']}
        extraHeader={GovernanceHeaderFields}
        onSaved={() => bc.reload()}
      />
    </div>
  )
}
