// ============================================================
// Data access layer — the ONLY module that talks to Supabase.
// To migrate to the client's stack (e.g. Databricks Lakebase +
// their SSO), reimplement this module; screens stay untouched.
// ============================================================
import { supabase } from './supabase'

const one = ({ data, error }) => { if (error) throw error; return data }

// ---------- Auth / profile ----------
export async function getSession() {
  return (await supabase.auth.getSession()).data.session
}
export function onAuthChange(cb) {
  return supabase.auth.onAuthStateChange((_e, s) => cb(s))
}
export async function signIn(email, password) {
  return one(await supabase.auth.signInWithPassword({ email, password }))
}
export async function signUp(email, password, name) {
  return one(await supabase.auth.signUp({ email, password, options: { data: { name } } }))
}
export async function signOut() { await supabase.auth.signOut() }

export async function getMyProfile() {
  const s = await getSession()
  if (!s) return null
  return one(await supabase.from('profiles').select('*').eq('id', s.user.id).single())
}
export async function listProfiles() {
  return one(await supabase.from('profiles').select('*').order('name'))
}
export async function updateProfileRole(id, role) {
  return one(await supabase.from('profiles').update({ role }).eq('id', id).select())
}

// ---------- Ideas ----------
export async function listIdeas() {
  return one(await supabase.from('ideas')
    .select('*, requester:requester_id(name), owner:owner_id(name)')
    .order('created_at', { ascending: false }))
}
export async function getIdea(id) {
  return one(await supabase.from('ideas')
    .select('*, requester:requester_id(name,email), owner:owner_id(name)')
    .eq('id', id).single())
}
export async function createIdea(fields) {
  return one(await supabase.from('ideas').insert(fields).select().single())
}
export async function updateIdea(id, fields) {
  return one(await supabase.from('ideas').update(fields).eq('id', id).select().single())
}
export async function qualifyIdea(id) {
  return one(await supabase.rpc('qualify_idea', { p_idea: id }))
}
export async function convertToProject(ideaId, projectId, projectLead) {
  return one(await supabase.rpc('convert_to_project',
    { p_idea: ideaId, p_project_id: projectId, p_project_lead: projectLead }))
}

// ---------- Business cases / charters ----------
export async function getBusinessCaseByIdea(ideaId) {
  const rows = one(await supabase.from('business_cases').select('*').eq('idea_id', ideaId)
    .order('created_at', { ascending: false }).limit(1))
  return rows[0] || null
}
export async function updateBusinessCase(id, fields) {
  return one(await supabase.from('business_cases').update(fields).eq('id', id).select().single())
}
export async function getCharterByIdea(ideaId) {
  const rows = one(await supabase.from('project_charters').select('*').eq('idea_id', ideaId)
    .order('created_at', { ascending: false }).limit(1))
  return rows[0] || null
}
export async function updateCharter(id, fields) {
  return one(await supabase.from('project_charters').update(fields).eq('id', id).select().single())
}
export async function saveVersion(docType, docId, label, snapshot, userId) {
  return one(await supabase.from('document_versions')
    .insert({ doc_type: docType, doc_id: docId, version_label: label, snapshot, saved_by: userId }).select())
}
export async function listVersions(docType, docId) {
  return one(await supabase.from('document_versions').select('*, saver:saved_by(name)')
    .eq('doc_type', docType).eq('doc_id', docId).order('created_at', { ascending: false }))
}

// ---------- Decisions ----------
export async function listDecisions() {
  return one(await supabase.from('decisions')
    .select('*, owner:owner_id(name), action_owner:action_owner_id(name)')
    .order('due_date', { ascending: true, nullsFirst: false }))
}
export async function createDecision(fields) {
  return one(await supabase.from('decisions').insert(fields).select().single())
}
export async function updateDecision(id, fields) {
  return one(await supabase.from('decisions').update(fields).eq('id', id).select().single())
}

// ---------- Projects ----------
export async function listProjects() {
  return one(await supabase.from('projects').select('*').order('project_id'))
}
export async function upsertProjects(rows) {
  return one(await supabase.from('projects').upsert(rows, { onConflict: 'project_id' }).select())
}
export async function existingProjectIds() {
  const rows = one(await supabase.from('projects').select('project_id'))
  return new Set(rows.map(r => r.project_id))
}

// ---------- Activity / comments ----------
export async function listActivity(relatedType, relatedId) {
  return one(await supabase.from('activity').select('*, user:user_id(name)')
    .eq('related_type', relatedType).eq('related_id', relatedId)
    .order('created_at', { ascending: false }))
}
export async function addComment(relatedType, relatedId, userId, message) {
  return one(await supabase.from('activity')
    .insert({ related_type: relatedType, related_id: relatedId, user_id: userId, kind: 'comment', message })
    .select())
}

// ---------- Notifications ----------
export async function listNotifications() {
  const s = await getSession()
  return one(await supabase.from('notifications').select('*')
    .eq('recipient_id', s.user.id).order('created_at', { ascending: false }).limit(100))
}
export async function markNotificationRead(id) {
  return one(await supabase.from('notifications').update({ read: true }).eq('id', id).select())
}
export async function markAllNotificationsRead() {
  const s = await getSession()
  return one(await supabase.from('notifications').update({ read: true })
    .eq('recipient_id', s.user.id).eq('read', false).select())
}
