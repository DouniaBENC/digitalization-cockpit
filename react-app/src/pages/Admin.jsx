import * as api from '../lib/api'
import { useAsync, Badge } from '../components/ui'
import { ROLES } from '../lib/constants'

export default function Admin() {
  const profiles = useAsync(api.listProfiles)
  if (profiles.loading) return <p>Loading…</p>

  const setRole = async (id, role) => { await api.updateProfileRole(id, role); profiles.reload() }

  return (
    <div style={{ maxWidth: 700 }}>
      <div className="topbar"><h1>Users & Roles</h1></div>
      <p className="muted small">Roles drive permissions (enforced server-side). New signups start as Requester.</p>
      <div className="card">
        <table className="data">
          <thead><tr><th>Name</th><th>Email</th><th>Role</th><th>Active</th></tr></thead>
          <tbody>
            {(profiles.data || []).map(p => (
              <tr key={p.id}>
                <td>{p.name}</td>
                <td className="small">{p.email}</td>
                <td>
                  <select value={p.role} onChange={e => setRole(p.id, e.target.value)}
                    style={{ padding: '5px 8px', border: '1px solid var(--border)', borderRadius: 6 }}>
                    {ROLES.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}
                  </select>
                </td>
                <td>{p.active ? <Badge color="green">active</Badge> : <Badge color="gray">inactive</Badge>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
