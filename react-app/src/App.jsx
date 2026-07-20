import { createContext, useContext, useEffect, useState } from 'react'
import { Routes, Route, NavLink, Navigate } from 'react-router-dom'
import * as api from './lib/api'
import Login from './pages/Login'
import Cockpit from './pages/Cockpit'
import IdeationBoard from './pages/IdeationBoard'
import IdeaForm from './pages/IdeaForm'
import IdeaDetail from './pages/IdeaDetail'
import BusinessCaseEditor from './pages/BusinessCaseEditor'
import CharterEditor from './pages/CharterEditor'
import DecisionLog from './pages/DecisionLog'
import Projects from './pages/Projects'
import ImportExport from './pages/ImportExport'
import Notifications from './pages/Notifications'
import Admin from './pages/Admin'

const AuthCtx = createContext(null)
export const useAuth = () => useContext(AuthCtx)

export default function App() {
  const [session, setSession] = useState(undefined) // undefined = loading
  const [profile, setProfile] = useState(null)
  const [unread, setUnread] = useState(0)

  useEffect(() => {
    api.getSession().then(s => setSession(s ?? null))
    const { data: sub } = api.onAuthChange(s => setSession(s ?? null))
    return () => sub.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (session) {
      api.getMyProfile().then(setProfile).catch(() => setProfile(null))
      api.listNotifications().then(ns => setUnread(ns.filter(n => !n.read).length)).catch(() => {})
    } else setProfile(null)
  }, [session])

  if (session === undefined) return <div style={{ padding: 40 }}>Loading…</div>
  if (!session) return <Login />
  if (!profile) return <div style={{ padding: 40 }}>Loading profile…</div>

  const isPMTT = ['program_manager', 'transformation_team'].includes(profile.role)
  const isPM = profile.role === 'program_manager'

  return (
    <AuthCtx.Provider value={{ session, profile, isPMTT, isPM, refreshUnread: () =>
      api.listNotifications().then(ns => setUnread(ns.filter(n => !n.read).length)).catch(() => {}) }}>
      <div className="app">
        <aside className="sidebar">
          <div className="brand">Digitalization<br />Program Cockpit</div>
          <nav>
            {isPMTT && <NavLink to="/cockpit">📊 Cockpit</NavLink>}
            <NavLink to="/ideas">💡 Ideation Board</NavLink>
            <NavLink to="/ideas/new">➕ Submit Idea</NavLink>
            {isPMTT && <NavLink to="/decisions">⚖️ Decision Log</NavLink>}
            {(isPMTT || profile.role === 'project_lead') && <NavLink to="/projects">📁 Projects</NavLink>}
            {isPMTT && <NavLink to="/import-export">🔄 SmartSheet I/O</NavLink>}
            <NavLink to="/notifications">🔔 Notifications{unread > 0 && <span className="notif-dot">{unread}</span>}</NavLink>
            {isPM && <NavLink to="/admin">⚙️ Users & Roles</NavLink>}
          </nav>
          <div className="foot">
            {profile.name}<br />
            <span style={{ textTransform: 'capitalize' }}>{profile.role.replace(/_/g, ' ')}</span><br />
            <a style={{ color: '#8892ab', cursor: 'pointer' }} onClick={() => api.signOut()}>Sign out</a>
          </div>
        </aside>
        <main className="main">
          <Routes>
            <Route path="/" element={<Navigate to={isPMTT ? '/cockpit' : '/ideas'} />} />
            <Route path="/cockpit" element={<Cockpit />} />
            <Route path="/ideas" element={<IdeationBoard />} />
            <Route path="/ideas/new" element={<IdeaForm />} />
            <Route path="/ideas/:id" element={<IdeaDetail />} />
            <Route path="/ideas/:id/business-case" element={<BusinessCaseEditor />} />
            <Route path="/ideas/:id/charter" element={<CharterEditor />} />
            <Route path="/decisions" element={<DecisionLog />} />
            <Route path="/projects" element={<Projects />} />
            <Route path="/import-export" element={<ImportExport />} />
            <Route path="/notifications" element={<Notifications />} />
            <Route path="/admin" element={<Admin />} />
          </Routes>
        </main>
      </div>
    </AuthCtx.Provider>
  )
}
