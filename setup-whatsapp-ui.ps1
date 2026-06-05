# ============================================================================
#  10x Chat — WhatsApp-style UI setup
#  Run this from the ROOT of the 10xdigitalventures-app-webapp repo:
#      cd path\to\10xdigitalventures-app-webapp
#      powershell -ExecutionPolicy Bypass -File .\setup-whatsapp-ui.ps1
#  It writes 4 files (backs up existing ones), makes a branch, commits,
#  and asks before pushing.
# ============================================================================

$ErrorActionPreference = "Stop"

# --- Guard: make sure we're in the right repo ----------------------------------
if (-not (Test-Path ".\package.json")) {
  Write-Host "ERROR: package.json not found. Run this from the repo root." -ForegroundColor Red
  exit 1
}
$pkg = Get-Content ".\package.json" -Raw
if ($pkg -notmatch '10x-chat-web') {
  Write-Host "WARNING: this doesn't look like the 10x-chat-web repo. Continue anyway? (y/n)" -ForegroundColor Yellow
  if ((Read-Host) -ne 'y') { exit 1 }
}

# --- Helper: write a UTF-8 (no BOM) file, creating folders as needed -----------
function Write-RepoFile($Path, $Content) {
  $full = Join-Path (Get-Location) $Path
  $dir  = Split-Path $full -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if (Test-Path $full) { Copy-Item $full "$full.bak" -Force; Write-Host "  backed up $Path -> $Path.bak" -ForegroundColor DarkGray }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($full, $Content, $enc)
  Write-Host "  wrote $Path" -ForegroundColor Green
}

Write-Host "`nWriting WhatsApp-style UI files..." -ForegroundColor Cyan

# ============================================================================
# 1) lib/chatFormat.js  — formatting + sorting helpers (no external deps)
# ============================================================================
$libChatFormat = @'
// Chat-list formatting helpers (WhatsApp-style). Pure JS, no external deps.

export function formatChatTime(value) {
  if (!value) return ''
  const d = new Date(value)
  if (isNaN(d.getTime())) return ''
  const now = new Date()
  if (d.toDateString() === now.toDateString()) {
    let h = d.getHours()
    const m = d.getMinutes().toString().padStart(2, '0')
    const ap = h < 12 ? 'am' : 'pm'
    h = h % 12 || 12
    return `${h}:${m} ${ap}`
  }
  const yest = new Date(now)
  yest.setDate(now.getDate() - 1)
  if (d.toDateString() === yest.toDateString()) return 'Yesterday'
  const diffDays = (now.getTime() - d.getTime()) / 86400000
  if (diffDays < 7) return d.toLocaleDateString(undefined, { weekday: 'short' })
  return d.toLocaleDateString(undefined, { day: '2-digit', month: '2-digit', year: '2-digit' })
}

export function getInitials(name = '') {
  const parts = String(name || '').trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return 'U'
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase()
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
}

const AVATAR_COLORS = ['#2a3942', '#3a2f5c', '#1f3d5c', '#5c4a1f', '#14564a', '#5c2f3a', '#2f5c3a', '#3a3a5c']
export function avatarColor(name = '') {
  let hash = 0
  const s = String(name || '')
  for (let i = 0; i < s.length; i++) hash = (hash * 31 + s.charCodeAt(i)) >>> 0
  return AVATAR_COLORS[hash % AVATAR_COLORS.length]
}

export function lastMsgTime(channel) {
  return channel?.last_message_at || channel?.last_message?.created_at || channel?.created_at || null
}

export function sortChannels(channels) {
  const arr = Array.isArray(channels) ? [...channels] : []
  return arr.sort((a, b) => {
    const pa = a?.is_pinned ? 1 : 0
    const pb = b?.is_pinned ? 1 : 0
    if (pa !== pb) return pb - pa
    const ta = new Date(lastMsgTime(a) || 0).getTime()
    const tb = new Date(lastMsgTime(b) || 0).getTime()
    return tb - ta
  })
}

// Returns { sender, kind, text } for the chat-list preview line.
export function previewOf(channel, currentUserId) {
  const lm = channel?.last_message
  if (!lm) return { sender: null, kind: 'text', text: channel?.topic || '' }
  const isGroup = channel?.type !== 'dm'
  let sender = null
  if (lm.sender_id && currentUserId && lm.sender_id === currentUserId) sender = 'You'
  else if (isGroup) sender = lm.sender_name || null
  const type = lm.type || 'text'
  if (type === 'image') return { sender, kind: 'image', text: 'Photo' }
  if (type === 'video') return { sender, kind: 'video', text: 'Video' }
  if (type === 'voice' || type === 'audio') return { sender, kind: 'voice', text: 'Voice message' }
  if (type === 'file') return { sender, kind: 'file', text: lm.content || 'Document' }
  return { sender, kind: 'text', text: lm.content || '' }
}

// 'read' | 'delivered' | 'sent' | null  (only when last message is from current user)
export function lastMsgStatus(channel, currentUserId) {
  const lm = channel?.last_message
  if (!lm || !currentUserId || lm.sender_id !== currentUserId) return null
  const stats = Array.isArray(lm.status) ? lm.status : null
  if (stats && stats.length > 0) {
    if (stats.every(s => s.read_at)) return 'read'
    if (stats.every(s => s.delivered_at)) return 'delivered'
    return 'sent'
  }
  if (lm.read_at || lm.is_read) return 'read'
  if (lm.delivered_at || lm.is_delivered) return 'delivered'
  return 'sent'
}

export function peerId(channel) {
  return channel?.peer_id || channel?.other_user_id || channel?.dm_user_id || null
}
'@
Write-RepoFile "lib\chatFormat.js" $libChatFormat

# ============================================================================
# 2) components/IconRail.js  — WhatsApp-style left vertical nav
# ============================================================================
$iconRail = @'
'use client'

import { useRouter, usePathname } from 'next/navigation'
import useChatStore from '@/store/chatStore'
import { getInitials } from '@/lib/chatFormat'

function RailButton({ title, active, onClick, children }) {
  return (
    <button
      onClick={onClick}
      title={title}
      aria-label={title}
      className={`w-10 h-10 flex items-center justify-center rounded-xl transition-colors ${
        active ? 'bg-brand-500/15 text-brand-500' : 'text-gray-400 hover:bg-white/5 hover:text-white'
      }`}
    >
      {children}
    </button>
  )
}

export default function IconRail() {
  const router = useRouter()
  const pathname = usePathname() || ''
  const { user } = useChatStore()

  const logout = () => {
    localStorage.removeItem('token')
    localStorage.removeItem('user')
    router.replace('/login')
  }

  return (
    <nav className="w-[60px] bg-[#0c1016] border-r border-white/10 flex flex-col items-center py-3 gap-2 flex-shrink-0">
      <button
        onClick={() => router.push('/profile')}
        title="Profile"
        aria-label="Profile"
        className="w-9 h-9 rounded-full bg-brand-500 text-[#06291f] font-bold flex items-center justify-center mb-2 text-sm"
      >
        {getInitials(user?.name)}
      </button>

      <RailButton title="Chats" active={pathname.startsWith('/chat')} onClick={() => router.push('/chat')}>
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/></svg>
      </RailButton>

      <RailButton title="Calls (coming soon)">
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
      </RailButton>

      <RailButton title="Status (coming soon)">
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" strokeDasharray="3 3" aria-hidden="true"><circle cx="12" cy="12" r="9"/></svg>
      </RailButton>

      <RailButton title="Groups (coming soon)">
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
      </RailButton>

      <div className="mt-auto flex flex-col items-center gap-2">
        <RailButton title="Settings" onClick={() => router.push('/profile')}>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
        </RailButton>
        <RailButton title="Logout" onClick={logout}>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>
        </RailButton>
      </div>
    </nav>
  )
}
'@
Write-RepoFile "components\IconRail.js" $iconRail

# ============================================================================
# 3) components/Sidebar.js  — WhatsApp-style chat list (graceful fallbacks)
# ============================================================================
$sidebar = @'
'use client'

import { useState, useEffect } from 'react'
import { useRouter, usePathname } from 'next/navigation'
import Link from 'next/link'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import toast from 'react-hot-toast'
import {
  formatChatTime, getInitials, avatarColor, sortChannels,
  previewOf, lastMsgStatus, lastMsgTime, peerId,
} from '@/lib/chatFormat'

const FILTERS = [
  { key: 'all', label: 'All' },
  { key: 'unread', label: 'Unread' },
  { key: 'groups', label: 'Groups' },
]

function PreviewIcon({ kind }) {
  const p = { width: 13, height: 13, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round', 'aria-hidden': true }
  if (kind === 'image') return (<svg {...p}><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/></svg>)
  if (kind === 'video') return (<svg {...p}><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>)
  if (kind === 'voice') return (<svg {...p}><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/></svg>)
  if (kind === 'file') return (<svg {...p}><path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48"/></svg>)
  return null
}

function Ticks({ status }) {
  if (!status) return null
  const c = status === 'read' ? '#34b7f1' : '#8696a0'
  if (status === 'sent') {
    return (<svg width="15" height="11" viewBox="0 0 16 12" fill="none" stroke={c} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M2 6.5 5.5 10 13 2"/></svg>)
  }
  return (<svg width="17" height="11" viewBox="0 0 20 12" fill="none" stroke={c} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M1 6.5 4.5 10 11.5 2"/><path d="M8 10 15 2"/></svg>)
}

export default function Sidebar() {
  const router = useRouter()
  const pathname = usePathname() || ''
  const activeChannelId = pathname.startsWith('/chat/') ? pathname.split('/chat/')[1]?.split('/')[0] : null

  const { user, channels, addChannel, onlineUsers } = useChatStore()
  const [searchQuery, setSearchQuery] = useState('')
  const [users, setUsers] = useState([])
  const [filter, setFilter] = useState('all')

  useEffect(() => {
    const fetchUsers = async () => {
      try {
        const { data } = await api.get('/users')
        const list = Array.isArray(data?.data) ? data.data : Array.isArray(data) ? data : []
        setUsers(list.filter(u => u.id !== user?.id))
      } catch (err) {
        console.error('Failed to fetch users', err)
      }
    }
    if (user?.id) fetchUsers()
  }, [user?.id])

  const startDM = async (userId) => {
    try {
      const { data } = await api.post(`/channels/dm/${userId}`)
      const channel = data?.data || data
      if (!channel?.id) throw new Error('Invalid channel response')
      addChannel(channel)
      router.push(`/chat/${channel.id}`)
    } catch (err) {
      toast.error('Could not start direct message')
    }
  }

  const safeChannels = Array.isArray(channels) ? channels : []
  const q = searchQuery.toLowerCase()

  const visibleChannels = sortChannels(
    safeChannels.filter(ch => {
      const name = (ch?.name || '').toLowerCase()
      if (q && !name.includes(q)) return false
      if (filter === 'unread') return (ch.unread_count || 0) > 0
      if (filter === 'groups') return ch.type === 'public' || ch.type === 'private'
      return true
    })
  )

  const suggestedUsers = users.filter(u => {
    const name = (u?.name || '').toLowerCase()
    const email = (u?.email || '').toLowerCase()
    return name.includes(q) || email.includes(q)
  })

  return (
    <aside className="w-80 bg-[#111820] border-r border-white/10 flex flex-col h-screen">
      <div className="px-4 py-3 flex items-center justify-between">
        <span className="text-[17px] font-semibold text-white">Chats</span>
        <button title="New chat" aria-label="New chat" className="text-gray-400 hover:text-white">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4z"/></svg>
        </button>
      </div>

      <div className="px-3 pb-2">
        <div className="flex items-center gap-2 bg-[#202c33] rounded-lg px-3 py-2">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#8696a0" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
          <input
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
            placeholder="Search or start new chat"
            className="bg-transparent border-none outline-none text-sm text-white placeholder-gray-500 w-full"
          />
        </div>
      </div>

      <div className="flex gap-2 px-3 pb-2">
        {FILTERS.map(f => (
          <button
            key={f.key}
            onClick={() => setFilter(f.key)}
            className={`px-3 py-1 rounded-full text-xs font-medium transition-colors ${
              filter === f.key ? 'bg-brand-500 text-[#06291f]' : 'bg-[#202c33] text-gray-400 hover:bg-[#2a2d35]'
            }`}
          >
            {f.label}
          </button>
        ))}
      </div>

      <div className="flex-1 overflow-y-auto px-2 pb-3">
        {q && suggestedUsers.length > 0 && (
          <div className="mb-2">
            <div className="text-[11px] uppercase tracking-wide text-gray-500 px-3 py-2">Start new chat</div>
            {suggestedUsers.map(u => (
              <button key={u.id} onClick={() => startDM(u.id)} className="w-full flex items-center gap-3 p-2 rounded-lg hover:bg-[#202c33] text-left">
                <div className="h-11 w-11 rounded-full flex items-center justify-center text-white font-semibold text-sm flex-shrink-0" style={{ background: avatarColor(u.name) }}>{getInitials(u.name)}</div>
                <div className="min-w-0">
                  <div className="text-sm text-white truncate">{u.name}</div>
                  <div className="text-xs text-gray-500 truncate">{u.email || 'Start a conversation'}</div>
                </div>
              </button>
            ))}
          </div>
        )}

        {visibleChannels.map(ch => {
          const isActive = activeChannelId === ch.id
          const isGroup = ch.type !== 'dm'
          const preview = previewOf(ch, user?.id)
          const status = lastMsgStatus(ch, user?.id)
          const unread = ch.unread_count || 0
          const time = formatChatTime(lastMsgTime(ch))
          const pid = peerId(ch)
          const online = !isGroup && pid && onlineUsers?.has?.(pid)

          return (
            <Link key={ch.id} href={`/chat/${ch.id}`} className={`flex items-center gap-3 px-2 py-1.5 rounded-lg transition-colors ${isActive ? 'bg-[#202c33]' : 'hover:bg-[#202c33]/60'}`}>
              <div className="relative flex-shrink-0">
                <div className="h-12 w-12 rounded-full flex items-center justify-center text-white font-semibold" style={{ background: isGroup ? '#2a3942' : avatarColor(ch.name) }}>
                  {isGroup ? (
                    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#1db791" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="4" y1="9" x2="20" y2="9"/><line x1="4" y1="15" x2="20" y2="15"/><line x1="10" y1="3" x2="8" y2="21"/><line x1="16" y1="3" x2="14" y2="21"/></svg>
                  ) : getInitials(ch.name)}
                </div>
                {online && <span className="absolute bottom-0 right-0 w-3 h-3 rounded-full bg-brand-500 border-2 border-[#111820]" />}
              </div>

              <div className="min-w-0 flex-1 border-b border-white/5 pb-2">
                <div className="flex items-center justify-between gap-2">
                  <span className={`text-[15px] truncate ${unread ? 'text-white font-semibold' : 'text-gray-200'}`}>{ch.name}</span>
                  <span className={`text-[11px] flex-shrink-0 ${unread ? 'text-brand-500' : 'text-gray-500'}`}>{time}</span>
                </div>
                <div className="flex items-center justify-between gap-2 mt-0.5">
                  <span className="text-[12.5px] text-gray-500 truncate flex items-center min-w-0">
                    {status && <span className="mr-1 inline-flex flex-shrink-0"><Ticks status={status} /></span>}
                    {preview.sender && <span className="mr-1 flex-shrink-0">{preview.sender}:</span>}
                    {preview.kind !== 'text' && <span className="mr-1 inline-flex text-gray-400 flex-shrink-0"><PreviewIcon kind={preview.kind} /></span>}
                    <span className="truncate">{preview.text}</span>
                  </span>
                  <span className="flex items-center gap-1.5 flex-shrink-0">
                    {ch.is_muted && (
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#8696a0" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M13.73 21a2 2 0 0 1-3.46 0"/><path d="M18.63 13A17.89 17.89 0 0 1 18 8"/><path d="M6.26 6.26A5.86 5.86 0 0 0 6 8c0 7-3 9-3 9h14"/><path d="M18 8a6 6 0 0 0-9.33-5"/><line x1="1" y1="1" x2="23" y2="23"/></svg>
                    )}
                    {ch.is_pinned && (
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#8696a0" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="12" y1="17" x2="12" y2="22"/><path d="M5 17h14l-1.5-3V8a2 2 0 0 0-2-2h-7a2 2 0 0 0-2 2v6z"/></svg>
                    )}
                    {unread > 0 && (
                      <span className="bg-brand-500 text-[#06291f] text-[11px] font-semibold rounded-full min-w-[20px] h-5 flex items-center justify-center px-1.5">{unread > 99 ? '99+' : unread}</span>
                    )}
                  </span>
                </div>
              </div>
            </Link>
          )
        })}

        {visibleChannels.length === 0 && !q && (
          <div className="text-center text-sm text-gray-500 py-10">No chats yet. Search a name to start one.</div>
        )}
      </div>
    </aside>
  )
}
'@
Write-RepoFile "components\Sidebar.js" $sidebar

# ============================================================================
# 4) app/chat/layout.js  — same logic as before, now renders <IconRail/>
# ============================================================================
$chatLayout = @'
'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import IconRail from '@/components/IconRail'
import Sidebar from '@/components/Sidebar'
import useChatStore from '@/store/chatStore'
import { getSocket, disconnectSocket } from '@/lib/socket'
import api from '@/lib/api'

function safeParseUser(value) {
  if (!value || value === 'undefined' || value === 'null') return null
  try {
    return JSON.parse(value)
  } catch {
    if (typeof window !== 'undefined') localStorage.removeItem('user')
    return null
  }
}

export default function ChatLayout({ children }) {
  const router = useRouter()

  const {
    setUser, setChannels, addMessage, updateMessage, deleteMessage,
    updateReaction, setUserOnline, setUserOffline, setTyping,
  } = useChatStore()

  const [ready, setReady] = useState(false)

  useEffect(() => {
    const token = localStorage.getItem('token')
    if (!token || token === 'undefined' || token === 'null') {
      localStorage.removeItem('token')
      localStorage.removeItem('user')
      router.replace('/login')
      return
    }

    const savedUser = safeParseUser(localStorage.getItem('user'))
    if (savedUser) setUser(savedUser)

    const init = async () => {
      try {
        const [meRes, chRes] = await Promise.all([
          api.get('/auth/me'),
          api.get('/channels'),
        ])

        const userData = meRes.data?.data || meRes.data || null
        const channelsData = Array.isArray(chRes.data?.data)
          ? chRes.data.data
          : Array.isArray(chRes.data) ? chRes.data : []

        setUser(userData)
        setChannels(channelsData)
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
        }
      } catch (error) {
        console.error('Chat init failed:', error)
        localStorage.removeItem('token')
        localStorage.removeItem('user')
        router.replace('/login')
      }
    }

    init()
    return () => disconnectSocket()
  }, [router, setUser, setChannels, addMessage, updateMessage, deleteMessage, updateReaction, setUserOnline, setUserOffline, setTyping])

  if (!ready) {
    return (
      <div className="min-h-screen bg-[#0f1117] text-white flex items-center justify-center">
        Loading chat...
      </div>
    )
  }

  return (
    <div className="flex min-h-screen bg-[#0f1117] text-white">
      <IconRail />
      <Sidebar />
      <main className="flex-1 overflow-hidden">{children}</main>
    </div>
  )
}
'@
Write-RepoFile "app\chat\layout.js" $chatLayout

# ============================================================================
#  Git: branch + commit + (optional) push
# ============================================================================
Write-Host "`nFiles written." -ForegroundColor Cyan
$doGit = Read-Host "Create branch 'feat/whatsapp-ui', commit, and push? (y/n)"
if ($doGit -eq 'y') {
  git rev-parse --verify feat/whatsapp-ui *> $null
  if ($LASTEXITCODE -eq 0) { git checkout feat/whatsapp-ui } else { git checkout -b feat/whatsapp-ui }
  git add lib/chatFormat.js components/IconRail.js components/Sidebar.js app/chat/layout.js
  git commit -m "feat(web): WhatsApp-style chat list, icon rail, and conversation polish"
  $push = Read-Host "Push to origin/feat/whatsapp-ui now? (y/n)"
  if ($push -eq 'y') {
    git push -u origin feat/whatsapp-ui
    Write-Host "`nDone. Open a PR from feat/whatsapp-ui when ready." -ForegroundColor Green
  } else {
    Write-Host "`nCommitted locally. Push later with: git push -u origin feat/whatsapp-ui" -ForegroundColor Yellow
  }
} else {
  Write-Host "`nSkipped git. Files (and .bak backups) are written. Review with: git diff" -ForegroundColor Yellow
}

Write-Host "`nNext: run 'npm run dev' and open /chat to see the new UI." -ForegroundColor Cyan