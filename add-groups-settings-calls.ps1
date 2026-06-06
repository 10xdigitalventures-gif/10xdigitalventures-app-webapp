# ============================================================================
#  10x Chat WEBAPP — groups + settings + call history
#   - NewGroupModal  : create a group and add chosen members
#   - SettingsModal  : edit name/about, notifications, logout
#   - CallsModal     : Recent call history (GET /calls) + start new call
#   - CallContext    : logs each call to POST /calls (popup UI kept)
#   - IconRail       : Groups -> NewGroup, Settings -> Settings, Calls -> Calls
#   - chat/layout    : listens for channel:new (new groups appear live)
#  Run from the WEBAPP repo root:
#      cd path\to\10xdigitalventures-app-webapp
#      powershell -ExecutionPolicy Bypass -File .\add-groups-settings-calls.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
if (-not (Test-Path ".\package.json")) { Write-Host "ERROR: run from the webapp repo root." -ForegroundColor Red; exit 1 }

function Write-RepoFile($Path, $Content) {
  $full = Join-Path (Get-Location) $Path
  $dir  = Split-Path $full -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if ((Test-Path $full) -and -not (Test-Path "$full.bak7")) { Copy-Item $full "$full.bak7" -Force }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($full, $Content, $enc)
  Write-Host "  wrote $Path" -ForegroundColor Green
}

Write-Host "`n[1/6] app/chat/layout.js (listen for channel:new) ..." -ForegroundColor Cyan
$layout = @'
'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import IconRail from '@/components/IconRail'
import Sidebar from '@/components/Sidebar'
import { CallProvider } from '@/context/CallContext'
import useChatStore from '@/store/chatStore'
import { getSocket, disconnectSocket } from '@/lib/socket'
import api from '@/lib/api'

function safeParseUser(value) {
  if (!value || value === 'undefined' || value === 'null') return null
  try { return JSON.parse(value) } catch { if (typeof window !== 'undefined') localStorage.removeItem('user'); return null }
}

export default function ChatLayout({ children }) {
  const router = useRouter()
  const {
    setUser, setChannels, addChannel, addMessage, updateMessage, deleteMessage,
    updateReaction, setUserOnline, setUserOffline, setTyping,
  } = useChatStore()
  const [ready, setReady] = useState(false)

  useEffect(() => {
    const token = localStorage.getItem('token')
    if (!token || token === 'undefined' || token === 'null') {
      localStorage.removeItem('token'); localStorage.removeItem('user'); router.replace('/login'); return
    }
    const savedUser = safeParseUser(localStorage.getItem('user'))
    if (savedUser) setUser(savedUser)

    const init = async () => {
      try {
        const [meRes, chRes] = await Promise.all([api.get('/auth/me'), api.get('/channels')])
        const userData = meRes.data?.data || meRes.data || null
        const channelsData = Array.isArray(chRes.data?.data) ? chRes.data.data : Array.isArray(chRes.data) ? chRes.data : []
        setUser(userData); setChannels(channelsData)
        if (userData) localStorage.setItem('user', JSON.stringify(userData))
        setReady(true)

        const socket = getSocket()
        if (socket) {
          socket.emit('join:channels')
          socket.on('message:new', msg => addMessage(msg.channel_id, msg))
          socket.on('message:edited', ({ message_id, channel_id, content }) => updateMessage(channel_id, message_id, { content, is_edited: 1 }))
          socket.on('message:deleted', ({ message_id, channel_id }) => deleteMessage(channel_id, message_id))
          socket.on('reaction:updated', ({ message_id, channel_id, emoji, user_id, action }) => updateReaction(channel_id, message_id, emoji, user_id, action))
          socket.on('user:online', ({ user_id }) => setUserOnline(user_id))
          socket.on('user:offline', ({ user_id }) => setUserOffline(user_id))
          socket.on('typing:start', ({ user_id, channel_id }) => setTyping(channel_id, user_id, true))
          socket.on('typing:stop', ({ user_id, channel_id }) => setTyping(channel_id, user_id, false))
          socket.on('channel:new', (ch) => { addChannel(ch); socket.emit('join:channels') })
        }
      } catch (error) {
        console.error('Chat init failed:', error)
        localStorage.removeItem('token'); localStorage.removeItem('user'); router.replace('/login')
      }
    }

    init()
    return () => disconnectSocket()
  }, [router, setUser, setChannels, addChannel, addMessage, updateMessage, deleteMessage, updateReaction, setUserOnline, setUserOffline, setTyping])

  if (!ready) {
    return (<div className="h-screen bg-[#0f1117] text-white flex items-center justify-center">Loading chat...</div>)
  }

  return (
    <CallProvider>
      <div className="flex h-screen overflow-hidden bg-[#0f1117] text-white">
        <IconRail />
        <Sidebar />
        <main className="flex-1 overflow-hidden">{children}</main>
      </div>
    </CallProvider>
  )
}
'@
Write-RepoFile "app\chat\layout.js" $layout

Write-Host "`n[2/6] components/NewGroupModal.js ..." -ForegroundColor Cyan
$newGroup = @'
'use client'
import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import toast from 'react-hot-toast'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import { getInitials, avatarColor } from '@/lib/chatFormat'

export default function NewGroupModal({ onClose }) {
  const router = useRouter()
  const { user, addChannel } = useChatStore()
  const [users, setUsers] = useState([])
  const [selected, setSelected] = useState([])
  const [name, setName] = useState('')
  const [q, setQ] = useState('')
  const [creating, setCreating] = useState(false)

  useEffect(() => {
    api.get('/users').then(({ data }) => {
      const list = Array.isArray(data?.data) ? data.data : Array.isArray(data) ? data : []
      setUsers(list.filter(u => u.id !== user?.id))
    }).catch(() => {})
  }, [user?.id])

  const toggle = (id) => setSelected(s => s.includes(id) ? s.filter(x => x !== id) : [...s, id])

  const create = async () => {
    if (!name.trim()) return toast.error('Enter a group name')
    if (selected.length === 0) return toast.error('Select at least one member')
    setCreating(true)
    try {
      const { data } = await api.post('/channels/group', { name: name.trim(), member_ids: selected })
      const channel = data?.data || data
      if (channel?.id) { addChannel(channel); router.push(`/chat/${channel.id}`) }
      onClose?.()
    } catch (e) { toast.error('Could not create group') } finally { setCreating(false) }
  }

  const filtered = users.filter(u => { const s = q.toLowerCase(); return !s || (u.name || '').toLowerCase().includes(s) })

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-16" onClick={onClose}>
      <div className="w-full max-w-md bg-[#111820] rounded-xl border border-white/10 shadow-2xl overflow-hidden" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between px-4 py-3 border-b border-white/10">
          <span className="text-[15px] font-semibold text-white">New group</span>
          <button onClick={onClose} aria-label="Close" className="text-gray-400 hover:text-white">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
          </button>
        </div>

        <div className="p-3 space-y-2">
          <input value={name} onChange={e => setName(e.target.value)} placeholder="Group name" className="w-full bg-[#202c33] rounded-lg px-3 py-2.5 text-sm text-white placeholder-gray-500 outline-none border-none" />
          <div className="flex items-center gap-2 bg-[#202c33] rounded-lg px-3 py-2">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#8696a0" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
            <input value={q} onChange={e => setQ(e.target.value)} placeholder="Add members" className="bg-transparent border-none outline-none text-sm text-white placeholder-gray-500 w-full" />
          </div>
        </div>

        {selected.length > 0 && <div className="px-4 pb-1 text-[11px] text-brand-500">{selected.length} selected</div>}

        <div className="max-h-[42vh] overflow-y-auto px-2 pb-2">
          {filtered.map(u => {
            const on = selected.includes(u.id)
            return (
              <button key={u.id} onClick={() => toggle(u.id)} className="w-full flex items-center gap-3 p-2 rounded-lg hover:bg-[#202c33] text-left">
                <div className="h-10 w-10 rounded-full flex items-center justify-center text-white font-semibold text-sm flex-shrink-0" style={{ background: avatarColor(u.name) }}>{getInitials(u.name)}</div>
                <div className="min-w-0 flex-1"><div className="text-sm text-white truncate">{u.name}</div></div>
                <span className={`w-5 h-5 rounded-full border flex items-center justify-center flex-shrink-0 ${on ? 'bg-brand-500 border-brand-500' : 'border-gray-500'}`}>
                  {on && <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#06291f" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polyline points="20 6 9 17 4 12"/></svg>}
                </span>
              </button>
            )
          })}
          {filtered.length === 0 && <div className="text-center text-sm text-gray-500 py-6">No people found.</div>}
        </div>

        <div className="p-3 border-t border-white/10">
          <button onClick={create} disabled={creating} className="w-full bg-brand-500 text-[#06291f] font-semibold py-2.5 rounded-lg disabled:opacity-50">{creating ? 'Creating...' : 'Create group'}</button>
        </div>
      </div>
    </div>
  )
}
'@
Write-RepoFile "components\NewGroupModal.js" $newGroup

Write-Host "`n[3/6] components/SettingsModal.js ..." -ForegroundColor Cyan
$settings = @'
'use client'
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import toast from 'react-hot-toast'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import { getInitials } from '@/lib/chatFormat'

export default function SettingsModal({ onClose }) {
  const router = useRouter()
  const { user, setUser } = useChatStore()
  const [name, setName] = useState(user?.name || '')
  const [about, setAbout] = useState(user?.status || '')
  const [saving, setSaving] = useState(false)

  const save = async () => {
    if (!name.trim()) return toast.error('Name cannot be empty')
    setSaving(true)
    try {
      await api.put('/auth/profile', { name: name.trim(), status: about })
      const updated = { ...user, name: name.trim(), status: about }
      setUser(updated)
      localStorage.setItem('user', JSON.stringify(updated))
      toast.success('Saved')
    } catch (e) { toast.error('Could not save') } finally { setSaving(false) }
  }

  const enableNotifications = async () => {
    if (typeof Notification === 'undefined') return toast('Not supported')
    const p = await Notification.requestPermission()
    toast(p === 'granted' ? 'Notifications enabled' : 'Notifications blocked')
  }

  const logout = () => { localStorage.removeItem('token'); localStorage.removeItem('user'); router.replace('/login') }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-16" onClick={onClose}>
      <div className="w-full max-w-md bg-[#111820] rounded-xl border border-white/10 shadow-2xl overflow-hidden" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between px-4 py-3 border-b border-white/10">
          <span className="text-[15px] font-semibold text-white">Settings</span>
          <button onClick={onClose} aria-label="Close" className="text-gray-400 hover:text-white">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
          </button>
        </div>

        <div className="p-4 flex items-center gap-3 border-b border-white/10">
          <div className="h-14 w-14 rounded-full bg-brand-500 text-[#06291f] font-bold flex items-center justify-center text-lg">{getInitials(name)}</div>
          <div className="min-w-0">
            <div className="text-base font-semibold text-white truncate">{name || 'You'}</div>
            <div className="text-xs text-gray-500 truncate">{user?.email}</div>
          </div>
        </div>

        <div className="p-4 space-y-3">
          <div>
            <label className="block text-[11px] uppercase tracking-wide text-gray-500 mb-1">Name</label>
            <input value={name} onChange={e => setName(e.target.value)} className="w-full bg-[#202c33] rounded-lg px-3 py-2.5 text-sm text-white outline-none border-none" />
          </div>
          <div>
            <label className="block text-[11px] uppercase tracking-wide text-gray-500 mb-1">About</label>
            <input value={about} onChange={e => setAbout(e.target.value)} placeholder="Hey there! I am using 10x Chat" className="w-full bg-[#202c33] rounded-lg px-3 py-2.5 text-sm text-white placeholder-gray-500 outline-none border-none" />
          </div>
          <button onClick={save} disabled={saving} className="w-full bg-brand-500 text-[#06291f] font-semibold py-2.5 rounded-lg disabled:opacity-50">{saving ? 'Saving...' : 'Save changes'}</button>
        </div>

        <div className="border-t border-white/10 py-2">
          <button onClick={enableNotifications} className="w-full flex items-center gap-3 px-4 py-3 text-sm text-white hover:bg-white/5 text-left">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#1db791" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>
            Enable notifications
          </button>
          <button onClick={logout} className="w-full flex items-center gap-3 px-4 py-3 text-sm text-red-400 hover:bg-white/5 text-left">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>
            Log out
          </button>
        </div>
      </div>
    </div>
  )
}
'@
Write-RepoFile "components\SettingsModal.js" $settings

Write-Host "`n[4/6] components/CallsModal.js (recent history + start call) ..." -ForegroundColor Cyan
$callsModal = @'
'use client'

import { useEffect, useState } from 'react'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import { getInitials, avatarColor } from '@/lib/chatFormat'
import { useCall } from '@/context/CallContext'

const tf = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })
function whenLabel(d) {
  if (!d) return ''
  const dt = new Date(d); const now = new Date()
  const sameDay = dt.toDateString() === now.toDateString()
  const yest = new Date(now); yest.setDate(now.getDate() - 1)
  if (sameDay) return tf.format(dt)
  if (dt.toDateString() === yest.toDateString()) return 'Yesterday'
  return dt.toLocaleDateString()
}
function PhoneIcon() { return (<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/></svg>) }
function VideoIcon() { return (<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>) }
function ArrowIcon({ dir, missed }) {
  const color = missed ? '#f87171' : '#1db791'
  return dir === 'out'
    ? (<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="7" y1="17" x2="17" y2="7"/><polyline points="7 7 17 7 17 17"/></svg>)
    : (<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="17" y1="7" x2="7" y2="17"/><polyline points="17 17 7 17 7 7"/></svg>)
}

export default function CallsModal({ onClose }) {
  const { user, onlineUsers } = useChatStore()
  const call = useCall()
  const [users, setUsers] = useState([])
  const [recent, setRecent] = useState([])
  const [q, setQ] = useState('')

  useEffect(() => {
    api.get('/users').then(({ data }) => {
      const list = Array.isArray(data?.data) ? data.data : Array.isArray(data) ? data : []
      setUsers(list.filter(u => u.id !== user?.id))
    }).catch(() => {})
    api.get('/calls').then(({ data }) => {
      setRecent(Array.isArray(data?.data) ? data.data : [])
    }).catch(() => {})
  }, [user?.id])

  const placeCall = (u, type) => { if (!call?.startCall) return; call.startCall(u.id, u.name, type); onClose?.() }
  const filtered = users.filter(u => { const s = q.toLowerCase(); return !s || (u.name || '').toLowerCase().includes(s) })

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-16" onClick={onClose}>
      <div className="w-full max-w-md bg-[#111820] rounded-xl border border-white/10 shadow-2xl overflow-hidden" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between px-4 py-3 border-b border-white/10">
          <span className="text-[16px] font-semibold text-white">Calls</span>
          <button onClick={onClose} aria-label="Close" className="text-gray-400 hover:text-white">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
          </button>
        </div>

        <div className="p-3">
          <div className="flex items-center gap-2 bg-[#202c33] rounded-lg px-3 py-2">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#8696a0" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
            <input autoFocus value={q} onChange={e => setQ(e.target.value)} placeholder="Search name" className="bg-transparent border-none outline-none text-sm text-white placeholder-gray-500 w-full" />
          </div>
        </div>

        <div className="max-h-[60vh] overflow-y-auto px-2 pb-3">
          {!q && recent.length > 0 && (
            <>
              <div className="px-2 pt-1 pb-2 text-[11px] uppercase tracking-wide text-gray-500">Recent</div>
              {recent.map(c => {
                const missed = c.status === 'missed' || c.status === 'no_answer' || c.status === 'declined'
                return (
                  <div key={c.id} className="flex items-center gap-3 p-2 rounded-lg hover:bg-[#202c33]">
                    <div className="h-11 w-11 rounded-full flex items-center justify-center text-white font-semibold text-sm flex-shrink-0" style={{ background: avatarColor(c.peer_name) }}>{getInitials(c.peer_name)}</div>
                    <div className="min-w-0 flex-1">
                      <div className={`text-sm truncate ${missed ? 'text-red-400' : 'text-white'}`}>{c.peer_name || 'Unknown'}</div>
                      <div className="text-xs text-gray-500 flex items-center gap-1">
                        <ArrowIcon dir={c.direction} missed={missed} />
                        {c.status === 'answered' ? (c.direction === 'out' ? 'Outgoing' : 'Incoming') : (c.status === 'declined' ? 'Declined' : 'Missed')}
                      </div>
                    </div>
                    <span className="text-[11px] text-gray-500">{whenLabel(c.created_at)}</span>
                    {c.type === 'video' ? <span className="text-gray-500"><VideoIcon /></span> : <span className="text-gray-500"><PhoneIcon /></span>}
                  </div>
                )
              })}
            </>
          )}

          <div className="px-2 pt-2 pb-2 text-[11px] uppercase tracking-wide text-gray-500">Start a new call</div>
          {filtered.length === 0 ? (
            <div className="text-center text-sm text-gray-500 py-6">No people found.</div>
          ) : filtered.map(u => (
            <div key={u.id} className="flex items-center gap-3 p-2 rounded-lg hover:bg-[#202c33]">
              <div className="relative flex-shrink-0">
                <div className="h-11 w-11 rounded-full flex items-center justify-center text-white font-semibold text-sm" style={{ background: avatarColor(u.name) }}>{getInitials(u.name)}</div>
                {onlineUsers?.has?.(u.id) && <span className="absolute bottom-0 right-0 w-3 h-3 rounded-full bg-brand-500 border-2 border-[#111820]" />}
              </div>
              <div className="min-w-0 flex-1">
                <div className="text-sm text-white truncate">{u.name}</div>
                <div className="text-xs text-gray-500 truncate">{onlineUsers?.has?.(u.id) ? 'online' : 'offline'}</div>
              </div>
              <button onClick={() => placeCall(u, 'audio')} title="Voice call" aria-label="Voice call" className="w-9 h-9 flex items-center justify-center rounded-full text-brand-500 hover:bg-white/5"><PhoneIcon /></button>
              <button onClick={() => placeCall(u, 'video')} title="Video call" aria-label="Video call" className="w-9 h-9 flex items-center justify-center rounded-full text-brand-500 hover:bg-white/5"><VideoIcon /></button>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
'@
Write-RepoFile "components\CallsModal.js" $callsModal

Write-Host "`n[5/6] components/IconRail.js (wire Groups + Settings + Calls) ..." -ForegroundColor Cyan
$iconRail = @'
'use client'

import { useState } from 'react'
import { useRouter, usePathname } from 'next/navigation'
import useChatStore from '@/store/chatStore'
import { getInitials } from '@/lib/chatFormat'
import CallsModal from '@/components/CallsModal'
import NewGroupModal from '@/components/NewGroupModal'
import SettingsModal from '@/components/SettingsModal'

function RailButton({ title, active, onClick, children }) {
  return (
    <button onClick={onClick} title={title} aria-label={title}
      className={`w-10 h-10 flex items-center justify-center rounded-xl transition-colors ${active ? 'bg-brand-500/15 text-brand-500' : 'text-gray-400 hover:bg-white/5 hover:text-white'}`}>
      {children}
    </button>
  )
}

export default function IconRail() {
  const router = useRouter()
  const pathname = usePathname() || ''
  const { user } = useChatStore()
  const [modal, setModal] = useState(null) // 'calls' | 'group' | 'settings'

  return (
    <>
      <nav className="w-[60px] bg-[#0c1016] border-r border-white/10 flex flex-col items-center py-3 gap-2 flex-shrink-0">
        <button onClick={() => setModal('settings')} title="Profile" aria-label="Profile" className="w-9 h-9 rounded-full bg-brand-500 text-[#06291f] font-bold flex items-center justify-center mb-2 text-sm">
          {getInitials(user?.name)}
        </button>

        <RailButton title="Chats" active={pathname.startsWith('/chat')} onClick={() => router.push('/chat')}>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/></svg>
        </RailButton>

        <RailButton title="Calls" active={modal === 'calls'} onClick={() => setModal('calls')}>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
        </RailButton>

        <RailButton title="New group" active={modal === 'group'} onClick={() => setModal('group')}>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
        </RailButton>

        <div className="mt-auto flex flex-col items-center gap-2">
          <RailButton title="Settings" active={modal === 'settings'} onClick={() => setModal('settings')}>
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
          </RailButton>
        </div>
      </nav>

      {modal === 'calls' && <CallsModal onClose={() => setModal(null)} />}
      {modal === 'group' && <NewGroupModal onClose={() => setModal(null)} />}
      {modal === 'settings' && <SettingsModal onClose={() => setModal(null)} />}
    </>
  )
}
'@
Write-RepoFile "components\IconRail.js" $iconRail

Write-Host "`n[6/6] context/CallContext.js (popup + logs each call) ..." -ForegroundColor Cyan
$callCtx = @'
'use client'

import { createContext, useContext, useEffect, useRef, useState, useCallback } from 'react'
import toast from 'react-hot-toast'
import useChatStore from '@/store/chatStore'
import { getSocket } from '@/lib/socket'
import { getInitials } from '@/lib/chatFormat'
import api from '@/lib/api'

const ICE = { iceServers: [{ urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'] }] }
const CallContext = createContext(null)
export const useCall = () => useContext(CallContext)

export function CallProvider({ children }) {
  const { user } = useChatStore()
  const [state, setState] = useState('idle')
  const [callType, setCallType] = useState('audio')
  const [peer, setPeer] = useState(null)
  const [muted, setMuted] = useState(false)
  const [camOff, setCamOff] = useState(false)
  const [hasLocalVideo, setHasLocalVideo] = useState(false)
  const [remoteVideoOn, setRemoteVideoOn] = useState(false)

  const pcRef = useRef(null)
  const localStreamRef = useRef(null)
  const localVideoRef = useRef(null)
  const remoteVideoRef = useRef(null)
  const remoteAudioRef = useRef(null)
  const pendingOfferRef = useRef(null)
  const pendingCandidatesRef = useRef([])
  const audioCtxRef = useRef(null)
  const ringRef = useRef(null)

  // for call logging
  const peerRef = useRef(null)
  const callTypeRef = useRef('audio')
  const callerRef = useRef(false)
  const answeredRef = useRef(false)
  const declinedRef = useRef(false)
  const startTsRef = useRef(0)
  const loggedRef = useRef(false)

  useEffect(() => { peerRef.current = peer }, [peer])
  useEffect(() => { callTypeRef.current = callType }, [callType])

  useEffect(() => {
    if (typeof Notification !== 'undefined' && Notification.permission === 'default') {
      Notification.requestPermission().catch(() => {})
    }
  }, [])

  const startRingtone = useCallback(() => {
    try {
      if (!audioCtxRef.current) audioCtxRef.current = new (window.AudioContext || window.webkitAudioContext)()
      const ctx = audioCtxRef.current
      if (ctx.state === 'suspended') ctx.resume()
      const beep = () => {
        const o = ctx.createOscillator(); const g = ctx.createGain()
        o.type = 'sine'; o.frequency.value = 480
        o.connect(g); g.connect(ctx.destination)
        g.gain.setValueAtTime(0.0001, ctx.currentTime)
        g.gain.exponentialRampToValueAtTime(0.08, ctx.currentTime + 0.05)
        g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.5)
        o.start(); o.stop(ctx.currentTime + 0.55)
      }
      beep(); ringRef.current = setInterval(beep, 1600)
    } catch (e) {}
  }, [])
  const stopRingtone = useCallback(() => { if (ringRef.current) { clearInterval(ringRef.current); ringRef.current = null } }, [])

  const logCall = useCallback(() => {
    if (loggedRef.current || !peerRef.current) return
    loggedRef.current = true
    const answered = answeredRef.current
    const duration = answered && startTsRef.current ? Math.round((Date.now() - startTsRef.current) / 1000) : 0
    const direction = callerRef.current ? 'out' : 'in'
    const status = answered ? 'answered' : (declinedRef.current ? 'declined' : (callerRef.current ? 'no_answer' : 'missed'))
    api.post('/calls', { peer_id: peerRef.current.id, peer_name: peerRef.current.name, type: callTypeRef.current, direction, status, duration }).catch(() => {})
  }, [])

  const cleanup = useCallback(() => {
    stopRingtone()
    try { pcRef.current?.close() } catch (e) {}
    pcRef.current = null
    localStreamRef.current?.getTracks().forEach(t => t.stop())
    localStreamRef.current = null
    pendingOfferRef.current = null
    pendingCandidatesRef.current = []
    setMuted(false); setCamOff(false); setHasLocalVideo(false); setRemoteVideoOn(false)
  }, [stopRingtone])

  const finish = useCallback(() => { logCall(); cleanup(); setState('idle'); setPeer(null) }, [logCall, cleanup])
  const endCall = useCallback((notify = true) => { if (notify && peerRef.current?.id) getSocket()?.emit('call:end', { to: peerRef.current.id }); finish() }, [finish])

  const attachRemote = (stream) => {
    if (remoteVideoRef.current) remoteVideoRef.current.srcObject = stream
    if (remoteAudioRef.current) remoteAudioRef.current.srcObject = stream
  }
  const createPeer = useCallback((targetId) => {
    const pc = new RTCPeerConnection(ICE)
    pc.onicecandidate = (e) => { if (e.candidate) getSocket()?.emit('call:ice', { to: targetId, candidate: e.candidate }) }
    pc.ontrack = (e) => {
      const stream = e.streams[0]; attachRemote(stream)
      const vt = stream.getVideoTracks()[0]
      if (vt) { const upd = () => setRemoteVideoOn(!!vt.enabled && !vt.muted); vt.onmute = upd; vt.onunmute = upd; vt.onended = () => setRemoteVideoOn(false); upd() }
      else setRemoteVideoOn(false)
    }
    pc.onconnectionstatechange = () => { if (['disconnected','failed','closed'].includes(pc.connectionState)) finish() }
    pcRef.current = pc
    return pc
  }, [finish])

  const getMedia = useCallback(async (type) => {
    let stream
    if (type === 'video') {
      try { stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: true }) }
      catch (e) { toast('No camera - joining with audio only'); stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false }) }
    } else { stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false }) }
    localStreamRef.current = stream
    setHasLocalVideo(stream.getVideoTracks().length > 0)
    if (localVideoRef.current) localVideoRef.current.srcObject = stream
    return stream
  }, [])

  const startCall = useCallback(async (targetId, targetName, type = 'audio') => {
    if (!targetId || state !== 'idle') return
    callerRef.current = true; answeredRef.current = false; declinedRef.current = false; loggedRef.current = false; startTsRef.current = 0
    setPeer({ id: targetId, name: targetName }); setCallType(type); setState('calling')
    try {
      const stream = await getMedia(type)
      const pc = createPeer(targetId)
      stream.getTracks().forEach(t => pc.addTrack(t, stream))
      const offer = await pc.createOffer(); await pc.setLocalDescription(offer)
      getSocket()?.emit('call:offer', { to: targetId, fromName: user?.name, type, sdp: offer })
    } catch (err) { console.error(err); toast.error('Microphone permission is required to call'); endCall(false) }
  }, [state, user, getMedia, createPeer, endCall])

  const acceptCall = useCallback(async () => {
    const offer = pendingOfferRef.current
    if (!offer || !peer?.id) return
    stopRingtone(); answeredRef.current = true; startTsRef.current = Date.now(); setState('active')
    try {
      const stream = await getMedia(callType)
      const pc = createPeer(peer.id)
      stream.getTracks().forEach(t => pc.addTrack(t, stream))
      await pc.setRemoteDescription(new RTCSessionDescription(offer))
      for (const c of pendingCandidatesRef.current) { try { await pc.addIceCandidate(c) } catch (e) {} }
      pendingCandidatesRef.current = []
      const answer = await pc.createAnswer(); await pc.setLocalDescription(answer)
      getSocket()?.emit('call:answer', { to: peer.id, sdp: answer })
    } catch (err) { console.error(err); toast.error('Microphone permission is required to answer'); endCall() }
  }, [peer, callType, getMedia, createPeer, endCall, stopRingtone])

  const rejectCall = useCallback(() => { declinedRef.current = true; if (peer?.id) getSocket()?.emit('call:reject', { to: peer.id }); finish() }, [peer, finish])
  const toggleMute = () => { const s = localStreamRef.current; if (!s) return; s.getAudioTracks().forEach(t => { t.enabled = !t.enabled }); setMuted(m => !m) }
  const toggleCam = () => { const s = localStreamRef.current; if (!s) return; const tr = s.getVideoTracks(); if (!tr.length) return; tr.forEach(t => { t.enabled = !t.enabled }); setCamOff(c => !c) }

  useEffect(() => { if (state === 'ringing' || state === 'calling') startRingtone(); else stopRingtone() }, [state, startRingtone, stopRingtone])

  useEffect(() => {
    if (state === 'ringing' && peer && typeof Notification !== 'undefined' && Notification.permission === 'granted') {
      try {
        const n = new Notification(`Incoming ${callType === 'video' ? 'video' : 'voice'} call`, { body: peer.name || 'Unknown', tag: 'incoming-call', requireInteraction: true })
        n.onclick = () => { window.focus(); n.close() }
        return () => { try { n.close() } catch (e) {} }
      } catch (e) {}
    }
  }, [state, peer, callType])

  useEffect(() => {
    const socket = getSocket(); if (!socket) return
    const onOffer = ({ from, fromName, type, sdp }) => {
      if (pcRef.current || state !== 'idle') { socket.emit('call:reject', { to: from }); return }
      callerRef.current = false; answeredRef.current = false; declinedRef.current = false; loggedRef.current = false; startTsRef.current = 0
      pendingOfferRef.current = sdp; setPeer({ id: from, name: fromName || 'Unknown' }); setCallType(type || 'audio'); setState('ringing')
    }
    const onAnswer = async ({ sdp }) => { try { await pcRef.current?.setRemoteDescription(new RTCSessionDescription(sdp)); answeredRef.current = true; startTsRef.current = Date.now(); setState('active') } catch (e) {} }
    const onIce = async ({ candidate }) => {
      if (!candidate) return
      if (pcRef.current && pcRef.current.remoteDescription) { try { await pcRef.current.addIceCandidate(candidate) } catch (e) {} }
      else pendingCandidatesRef.current.push(candidate)
    }
    socket.on('call:offer', onOffer); socket.on('call:answer', onAnswer); socket.on('call:ice', onIce)
    socket.on('call:reject', finish); socket.on('call:end', finish)
    return () => { socket.off('call:offer', onOffer); socket.off('call:answer', onAnswer); socket.off('call:ice', onIce); socket.off('call:reject', finish); socket.off('call:end', finish) }
  }, [state, finish])

  return (
    <CallContext.Provider value={{ state, callType, peer, muted, camOff, hasLocalVideo, remoteVideoOn, startCall, acceptCall, rejectCall, endCall, toggleMute, toggleCam, localVideoRef, remoteVideoRef, remoteAudioRef }}>
      {children}
      <CallModal />
    </CallContext.Provider>
  )
}

function CtrlBtn({ title, danger, active, onClick, children }) {
  return (
    <button onClick={onClick} title={title} aria-label={title}
      className={`w-14 h-14 rounded-full flex items-center justify-center transition-colors ${danger ? 'bg-red-600 hover:bg-red-700 text-white' : active ? 'bg-white text-[#111820]' : 'bg-white/10 hover:bg-white/20 text-white'}`}>
      {children}
    </button>
  )
}

function CallModal() {
  const c = useCall()
  if (!c || c.state === 'idle') return null
  const { state, callType, peer, muted, camOff, hasLocalVideo, remoteVideoOn, acceptCall, rejectCall, endCall, toggleMute, toggleCam, localVideoRef, remoteVideoRef, remoteAudioRef } = c
  const isVideo = callType === 'video'
  const statusText = state === 'calling' ? 'Calling...' : state === 'ringing' ? `Incoming ${isVideo ? 'video' : 'voice'} call` : 'Connected'
  const showStage = remoteVideoOn && state === 'active'
  const localPip = hasLocalVideo && !camOff

  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/70 backdrop-blur-sm p-4">
      <div className={`bg-[#0b141a] rounded-2xl border border-white/10 shadow-2xl w-full overflow-hidden ${showStage ? 'max-w-2xl' : 'max-w-sm'}`}>
        <audio ref={remoteAudioRef} autoPlay />
        <div className={showStage ? 'relative bg-black aspect-video' : 'flex flex-col items-center gap-4 pt-10 pb-6 px-6 relative'}>
          <video ref={remoteVideoRef} autoPlay playsInline className={showStage ? 'absolute inset-0 w-full h-full object-cover' : 'hidden'} />
          <video ref={localVideoRef} autoPlay playsInline muted className={localPip ? (showStage ? 'absolute bottom-3 right-3 w-24 h-32 object-cover rounded-lg border border-white/20 z-10' : 'absolute top-3 right-3 w-16 h-24 object-cover rounded-lg border border-white/20 z-10') : 'hidden'} />
          {showStage ? (
            <div className="absolute top-3 left-4 z-10">
              <div className="text-base font-semibold text-white drop-shadow">{peer?.name || 'Unknown'}</div>
              <div className="text-[11px] text-gray-200 drop-shadow">{statusText}</div>
            </div>
          ) : (
            <>
              <div className="w-24 h-24 rounded-full bg-brand-500 flex items-center justify-center text-3xl font-semibold text-[#06291f]">{getInitials(peer?.name)}</div>
              <div className="text-center">
                <div className="text-xl font-semibold text-white">{peer?.name || 'Unknown'}</div>
                <div className="text-sm text-gray-400 mt-1 animate-pulse">{statusText}</div>
              </div>
            </>
          )}
        </div>
        <div className="flex items-center justify-center gap-4 py-5 bg-[#111820] border-t border-white/5">
          {state === 'ringing' ? (
            <>
              <CtrlBtn title="Decline" danger onClick={rejectCall}>
                <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7 2 2 0 0 1 1.72 2v3a2 2 0 0 1-2.18 2A19.79 19.79 0 0 1 8.63 19.24"/><line x1="23" y1="1" x2="1" y2="23"/></svg>
              </CtrlBtn>
              <CtrlBtn title="Accept" onClick={acceptCall}>
                <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#1db791" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
              </CtrlBtn>
            </>
          ) : (
            <>
              <CtrlBtn title={muted ? 'Unmute' : 'Mute'} active={muted} onClick={toggleMute}>
                {muted
                  ? <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="1" y1="1" x2="23" y2="23"/><path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6"/><path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2a7 7 0 0 1-.11 1.23"/><line x1="12" y1="19" x2="12" y2="23"/></svg>
                  : <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/></svg>}
              </CtrlBtn>
              {hasLocalVideo && (
                <CtrlBtn title={camOff ? 'Camera on' : 'Camera off'} active={camOff} onClick={toggleCam}>
                  <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>
                </CtrlBtn>
              )}
              <CtrlBtn title="End call" danger onClick={() => endCall(true)}>
                <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7 2 2 0 0 1 1.72 2v3a2 2 0 0 1-2.18 2A19.79 19.79 0 0 1 8.63 19.24"/><line x1="23" y1="1" x2="1" y2="23"/></svg>
              </CtrlBtn>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
'@
Write-RepoFile "context\CallContext.js" $callCtx

Write-Host "`nDone (webapp)." -ForegroundColor Cyan
$doGit = Read-Host "Commit and push? (y/n)"
if ($doGit -eq 'y') {
  git add "app/chat/layout.js" "components/NewGroupModal.js" "components/SettingsModal.js" "components/CallsModal.js" "components/IconRail.js" "context/CallContext.js"
  git commit -m "feat(web): create-group + settings modals; call history in Calls screen; log calls"
  $push = Read-Host "Push now? (y/n)"
  if ($push -eq 'y') { git push; Write-Host "`nPushed." -ForegroundColor Green }
  else { Write-Host "`nCommitted locally. Push later with: git push" -ForegroundColor Yellow }
} else { Write-Host "`nSkipped git. Review with: git diff" -ForegroundColor Yellow }
Write-Host "`nRun the BACKEND script (add-groups-calls-backend.ps1) + import migration_p2.sql first, then restart the API." -ForegroundColor Yellow