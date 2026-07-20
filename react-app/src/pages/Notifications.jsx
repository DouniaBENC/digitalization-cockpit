import * as api from '../lib/api'
import { useAuth } from '../App'
import { useAsync, Badge, fmtDateTime } from '../components/ui'

export default function Notifications() {
  const { refreshUnread } = useAuth()
  const notifs = useAsync(api.listNotifications)

  const markAll = async () => { await api.markAllNotificationsRead(); notifs.reload(); refreshUnread() }
  const markOne = async (id) => { await api.markNotificationRead(id); notifs.reload(); refreshUnread() }

  if (notifs.loading) return <p>Loading…</p>
  const list = notifs.data || []

  return (
    <div style={{ maxWidth: 800 }}>
      <div className="topbar">
        <h1>Notifications</h1>
        {list.some(n => !n.read) && <button className="btn secondary" onClick={markAll}>Mark all read</button>}
      </div>
      <div className="card">
        {list.map(n => (
          <div key={n.id} className="alert-line" style={{ opacity: n.read ? 0.55 : 1 }}>
            <Badge color={n.read ? 'gray' : 'blue'}>{n.type}</Badge>
            <span>{n.message}</span>
            <span className="muted small">{fmtDateTime(n.created_at)}</span>
            {!n.read && <button className="btn secondary small" onClick={() => markOne(n.id)}>✓</button>}
          </div>
        ))}
        {!list.length && <p className="muted">No notifications.</p>}
      </div>
    </div>
  )
}
