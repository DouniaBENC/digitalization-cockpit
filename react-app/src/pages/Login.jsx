import { useState } from 'react'
import * as api from '../lib/api'

export default function Login() {
  const [mode, setMode] = useState('signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [name, setName] = useState('')
  const [error, setError] = useState(null)
  const [info, setInfo] = useState(null)
  const [busy, setBusy] = useState(false)

  const submit = async (e) => {
    e.preventDefault()
    setBusy(true); setError(null); setInfo(null)
    try {
      if (mode === 'signin') await api.signIn(email, password)
      else {
        await api.signUp(email, password, name)
        setInfo('Account created. If email confirmation is enabled, check your inbox; otherwise sign in.')
        setMode('signin')
      }
    } catch (err) { setError(err.message) }
    setBusy(false)
  }

  return (
    <div className="login-wrap">
      <div className="login-card">
        <h1 style={{ marginBottom: 4 }}>Digitalization Program Cockpit</h1>
        <p className="muted small" style={{ marginTop: 0 }}>Governance preparation & portfolio steering</p>
        <form onSubmit={submit}>
          {mode === 'signup' && (
            <div className="field"><label>Name</label>
              <input type="text" value={name} onChange={e => setName(e.target.value)} required /></div>
          )}
          <div className="field"><label>Email</label>
            <input type="email" value={email} onChange={e => setEmail(e.target.value)} required /></div>
          <div className="field"><label>Password</label>
            <input type="password" value={password} onChange={e => setPassword(e.target.value)} required /></div>
          {error && <p style={{ color: 'var(--red)', fontSize: 13 }}>{error}</p>}
          {info && <p style={{ color: 'var(--green)', fontSize: 13 }}>{info}</p>}
          <button className="btn" disabled={busy} style={{ width: '100%' }}>
            {mode === 'signin' ? 'Sign in' : 'Create account'}
          </button>
        </form>
        <p className="small" style={{ textAlign: 'center' }}>
          {mode === 'signin'
            ? <>No account? <a onClick={() => setMode('signup')} style={{ cursor: 'pointer' }}>Sign up</a></>
            : <>Have an account? <a onClick={() => setMode('signin')} style={{ cursor: 'pointer' }}>Sign in</a></>}
        </p>
      </div>
    </div>
  )
}
