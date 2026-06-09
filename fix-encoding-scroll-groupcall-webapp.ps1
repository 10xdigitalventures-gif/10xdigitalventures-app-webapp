# =====================================================================
# Webapp fix script (Part 3):
#  1) Message.js -- ASCII-only rewrite (mojibake fix: SVG ticks, \u escapes)
#  2) globals.css -- duplicate .chat-area rules clean, sahi scroll flex setup
#  3) GroupCallContext.js + GroupCallModal -- mesh (up to ~8 peers)
#  4) chat/[channelId]/page.js -- group call button on header for non-DM
#  5) chat/layout.js -- wrap with GroupCallProvider + listen for gcall:ring
#
# IMPORTANT: All files written as UTF-8 (no BOM) via .NET API so PowerShell's
# default ANSI write cannot corrupt characters. Source code stays ASCII-safe
# (Unicode escapes \uXXXX inside strings) to avoid any encoding round-trip risk.
#
# Run from webapp repo root:
#   powershell -ExecutionPolicy Bypass -File .\fix-encoding-scroll-groupcall-webapp.ps1
# =====================================================================

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Write-FileUtf8NoBom([string]$Path, [string]$Content) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $abs = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
    [System.IO.File]::WriteAllText($abs, $Content, $utf8NoBom)
    Write-Host "  wrote: $Path"
}

function Read-FileUtf8([string]$Path) {
    $abs = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
    return [System.IO.File]::ReadAllText($abs, [System.Text.UTF8Encoding]::new($false))
}

# =====================================================================
# 1) components/Message.js -- ASCII-only rewrite
#    - Ticks rendered as SVG (no Unicode required)
#    - Reaction emojis defined via String.fromCodePoint (ASCII source)
#    - Edit/delete/emoji-picker buttons use SVG instead of emoji characters
# =====================================================================
Write-Host "[1/5] Rewriting components/Message.js (encoding-safe)..."

$messageJs = @'
'use client'
import { useState } from 'react'
import useChatStore from '@/store/chatStore'
import { getSocket } from '@/lib/socket'
import { mediaUrl } from '@/lib/chatFormat'

// Reaction emojis as code points (ASCII source = no encoding risk).
// thumbs_up, red_heart, joy, open_mouth, cry, fire, check, eyes
const EMOJI_CP = [
  [0x1F44D], [0x2764, 0xFE0F], [0x1F602], [0x1F62E],
  [0x1F622], [0x1F525], [0x2705], [0x1F440]
]
const EMOJIS = EMOJI_CP.map(parts => String.fromCodePoint(...parts))

const timeFormatter = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })

function fmtSize(bytes) {
  if (!bytes) return ''
  const kb = bytes / 1024
  return kb < 1024 ? `${Math.round(kb)} KB` : `${(kb / 1024).toFixed(1)} MB`
}

// --- inline SVG ticks (no emoji needed) ---
function TickSingle({ className }) {
  return (
    <svg width="14" height="14" viewBox="0 0 16 11" fill="none" className={className} aria-hidden="true">
      <path d="M1 5.5L5.5 10L15 1" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  )
}
function TickDouble({ className }) {
  return (
    <svg width="18" height="14" viewBox="0 0 20 11" fill="none" className={className} aria-hidden="true">
      <path d="M1 5.5L5 9.5L13 1" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
      <path d="M7 5.5L11 9.5L19 1" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  )
}
function SmileIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <circle cx="12" cy="12" r="10"/><path d="M8 14s1.5 2 4 2 4-2 4-2"/><line x1="9" y1="9" x2="9.01" y2="9"/><line x1="15" y1="9" x2="15.01" y2="9"/>
    </svg>
  )
}
function PencilIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4 12.5-12.5z"/>
    </svg>
  )
}
function TrashIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2"/>
    </svg>
  )
}

export default function Message({ msg, channelId }) {
  const { user, updateMessage, deleteMessage } = useChatStore()
  const [showActions, setShowActions] = useState(false)
  const [editing, setEditing] = useState(false)
  const [editContent, setEditContent] = useState(msg.content)
  const [showEmoji, setShowEmoji] = useState(false)

  const isOwn = msg.sender_id === user?.id
  const isDeleted = msg.is_deleted === 1
  const createdAt = msg.created_at ? timeFormatter.format(new Date(msg.created_at)) : ''
  const url = mediaUrl(msg.file_url || msg.content)

  const renderStatus = () => {
    if (!isOwn) return null
    const stats = Array.isArray(msg.status) ? msg.status : []
    const read = stats.length > 0 && stats.every(s => s.read_at)
    const delivered = stats.length > 0 && stats.every(s => s.delivered_at)
    if (read) return <span className="inline-flex items-center text-[#34b7f1]" title="Read"><TickDouble /></span>
    if (delivered) return <span className="inline-flex items-center text-gray-400" title="Delivered"><TickDouble /></span>
    return <span className="inline-flex items-center text-gray-400" title="Sent"><TickSingle /></span>
  }

  const saveEdit = () => {
    if (!editContent.trim()) return
    getSocket()?.emit('message:edit', { message_id: msg.id, channel_id: channelId, content: editContent })
    updateMessage(channelId, msg.id, { content: editContent, is_edited: 1 })
    setEditing(false)
  }
  const deleteMsg = () => {
    if (!confirm('Delete this message?')) return
    getSocket()?.emit('message:delete', { message_id: msg.id, channel_id: channelId })
    deleteMessage(channelId, msg.id)
  }
  const toggleReaction = (emoji) => {
    getSocket()?.emit('reaction:toggle', { message_id: msg.id, channel_id: channelId, emoji })
    setShowEmoji(false)
  }
  const groupedReactions = () => {
    const rx = Array.isArray(msg.reactions) ? msg.reactions : []
    if (!rx.length) return {}
    return rx.reduce((acc, r) => { acc[r.emoji] = acc[r.emoji] || []; acc[r.emoji].push(r.user_id); return acc }, {})
  }

  if (isDeleted) {
    return (
      <div className={`flex w-full mb-2 ${isOwn ? 'justify-end' : 'justify-start'}`}>
        <div className={`message-bubble ${isOwn ? 'message-sent' : 'message-received'} opacity-60`}>
          <div className="text-xs italic text-white/70">This message was deleted</div>
        </div>
      </div>
    )
  }

  const renderMedia = () => {
    if (msg.type === 'image') {
      return <img src={url} onClick={() => window.open(url, '_blank')} alt={msg.file_name || 'Image'} className="max-w-[280px] max-h-[340px] object-cover rounded-lg mb-1 cursor-pointer hover:brightness-95" />
    }
    if (msg.type === 'video') {
      return <video src={url} controls className="max-w-[280px] rounded-lg mb-1" />
    }
    if (msg.type === 'audio' || msg.type === 'voice') {
      return <audio src={url} controls className="mb-1 max-w-[240px] h-10" />
    }
    if (msg.type === 'file') {
      return (
        <a href={url} target="_blank" rel="noreferrer" download className="flex items-center gap-3 mb-1 px-3 py-2 bg-black/20 rounded-lg border border-white/5 hover:bg-black/30 max-w-[260px]">
          <span className="w-9 h-9 rounded-lg bg-brand-500/15 flex items-center justify-center text-brand-500 flex-shrink-0">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
          </span>
          <span className="min-w-0">
            <span className="block text-sm text-white truncate">{msg.file_name || msg.content}</span>
            <span className="block text-[11px] text-white/50">{fmtSize(msg.file_size) || 'Open file'}</span>
          </span>
        </a>
      )
    }
    return <p className="text-[14.5px] text-gray-100 whitespace-pre-wrap break-words leading-relaxed mr-12">{msg.content}</p>
  }

  return (
    <div className={`flex w-full mb-1 ${isOwn ? 'justify-end' : 'justify-start'} group animate-fade-in`}
      onMouseEnter={() => setShowActions(true)} onMouseLeave={() => { setShowActions(false); setShowEmoji(false) }}>
      <div className={`message-bubble relative ${isOwn ? 'message-sent' : 'message-received'}`}>
        {!isOwn && (<div className="text-[11px] font-bold text-brand-500 mb-1 leading-none">{msg.sender_name}</div>)}
        {editing ? (
          <div className="min-w-[200px]">
            <textarea value={editContent} onChange={e => setEditContent(e.target.value)} className="text-sm resize-none bg-black/20 border-none p-1 w-full text-white" rows={2} autoFocus />
            <div className="flex justify-end gap-2 mt-1">
              <button onClick={() => setEditing(false)} className="text-[10px] uppercase font-bold text-white/60">Cancel</button>
              <button onClick={saveEdit} className="text-[10px] uppercase font-bold text-brand-100">Save</button>
            </div>
          </div>
        ) : (
          <div className="relative">
            {renderMedia()}
            <div className="flex items-center gap-1 absolute bottom-[-4px] right-[-4px] select-none">
              <span className="text-[10px] text-white/50 uppercase">{createdAt}</span>
              {renderStatus()}
            </div>
          </div>
        )}
        {Object.keys(groupedReactions()).length > 0 && (
          <div className="flex flex-wrap gap-1 mt-2 -mb-1">
            {Object.entries(groupedReactions()).map(([emoji, users]) => (
              <button key={emoji} onClick={() => toggleReaction(emoji)} className={`flex items-center gap-0.5 px-1.5 py-0.5 rounded-full text-[10px] border transition-colors ${users.includes(user?.id) ? 'bg-brand-500/20 border-brand-500' : 'bg-black/10 border-white/5 hover:border-white/20'}`}>
                {emoji} <span>{users.length}</span>
              </button>
            ))}
          </div>
        )}
      </div>

      {showActions && !editing && (
        <div className={`flex items-center gap-1 mx-2 ${isOwn ? 'flex-row-reverse' : 'flex-row'}`}>
          <button onClick={() => setShowEmoji(!showEmoji)} title="React" className="w-7 h-7 flex items-center justify-center hover:bg-white/5 rounded-full text-gray-400 hover:text-white"><SmileIcon /></button>
          {isOwn && (<button onClick={() => setEditing(true)} title="Edit" className="w-7 h-7 flex items-center justify-center hover:bg-white/5 rounded-full text-gray-500 hover:text-white"><PencilIcon /></button>)}
          {isOwn && (<button onClick={deleteMsg} title="Delete" className="w-7 h-7 flex items-center justify-center hover:bg-white/5 rounded-full text-gray-500 hover:text-red-400"><TrashIcon /></button>)}
          {showEmoji && (
            <div className={`absolute bottom-full mb-2 bg-[#1a1d24] border border-[#3a3d45] rounded-full p-1.5 flex gap-1 shadow-xl z-50 animate-fade-in ${isOwn ? 'right-0' : 'left-0'}`}>
              {EMOJIS.map(e => (<button key={e} onClick={() => toggleReaction(e)} className="w-8 h-8 flex items-center justify-center hover:scale-125 transition-transform text-lg">{e}</button>))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
'@
Write-FileUtf8NoBom -Path "components/Message.js" -Content $messageJs

# =====================================================================
# 2) app/globals.css -- clean .chat-area rules, sahi scroll flex setup
# =====================================================================
Write-Host "[2/5] Rewriting app/globals.css (scroll fix)..."

$globalsCss = @'
@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  --brand-color: #1db791;
  --bg-dark: #0f1117;
  --surface-dark: #12141a;
  --text-primary: #e8eaed;
  --text-secondary: #9ca3af;
  --radius: 8px;
}

* { box-sizing: border-box; margin: 0; padding: 0; }

html, body, #__next { height: 100%; }

body {
  background: var(--bg-dark);
  color: var(--text-primary);
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
  height: 100vh;
  overflow: hidden;
}

::-webkit-scrollbar { width: 6px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: #3a3d45; border-radius: 10px; }
::-webkit-scrollbar-thumb:hover { background: #4a4d55; }

/* Message bubbles (WhatsApp style) */
.message-bubble {
  max-width: 70%;
  padding: 8px 12px;
  border-radius: var(--radius);
  position: relative;
  margin-bottom: 2px;
}
.message-sent {
  background: #056162;
  align-self: flex-end;
  border-bottom-right-radius: 2px;
}
.message-received {
  background: #262d31;
  align-self: flex-start;
  border-bottom-left-radius: 2px;
}

/* Chat scroll area:
   The parent <div ref={scrollRef}> already has `flex-1 overflow-y-auto`.
   So `.chat-area` just needs to be a vertical flex column with padding,
   and it must NOT impose a fixed height (that was the old bug). */
.chat-area {
  display: flex;
  flex-direction: column;
  padding: 20px;
  min-height: 100%;
}

.sidebar-item { transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1); }
.sidebar-item:hover { background: rgba(255,255,255,0.06); }
.sidebar-item.active { background: rgba(29, 183, 145, 0.15); border-left: 3px solid var(--brand-color); }

input, textarea {
  outline: none;
  background: #1e2028;
  border: 1px solid #3a3d45;
  color: #e8eaed;
  border-radius: var(--radius);
  padding: 10px 14px;
  width: 100%;
  transition: border-color 0.15s;
}
input:focus, textarea:focus { border-color: var(--brand-color); }

.btn-primary {
  background: var(--brand-color);
  color: white;
  padding: 10px 20px;
  border-radius: var(--radius);
  border: none;
  cursor: pointer;
  font-weight: 600;
  transition: filter 0.15s;
  width: 100%;
}
.btn-primary:hover { filter: brightness(1.1); }
.btn-primary:active { transform: scale(0.98); }

@keyframes fadeIn { from { opacity: 0; transform: translateY(5px); } to { opacity: 1; transform: translateY(0); } }
.animate-fade-in { animation: fadeIn 0.2s ease-out forwards; }

@media (prefers-reduced-motion: reduce) {
  * { animation-duration: 0.01ms !important; animation-iteration-count: 1 !important; transition-duration: 0.01ms !important; scroll-behavior: auto !important; }
}
'@
Write-FileUtf8NoBom -Path "app/globals.css" -Content $globalsCss

# =====================================================================
# 3) context/GroupCallContext.js -- mesh peer manager + modal
# =====================================================================
Write-Host "[3/5] Writing context/GroupCallContext.js (mesh + modal)..."

$groupCall = @'
'use client'

import { createContext, useContext, useEffect, useRef, useState, useCallback } from 'react'
import toast from 'react-hot-toast'
import useChatStore from '@/store/chatStore'
import { getSocket } from '@/lib/socket'
import { getInitials } from '@/lib/chatFormat'

const ICE = { iceServers: [{ urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'] }] }
const MAX_PEERS = 8

const GroupCallContext = createContext(null)
export const useGroupCall = () => useContext(GroupCallContext)

export function GroupCallProvider({ children }) {
  const { user, channels } = useChatStore()
  const [state, setState] = useState('idle') // idle | ringing | active
  const [channelId, setChannelId] = useState(null)
  const [callType, setCallType] = useState('audio')
  const [incoming, setIncoming] = useState(null) // { channel_id, from, fromName, type }
  const [peers, setPeers] = useState([]) // [{user_id, name, hasVideo, muted, camOff}]
  const [muted, setMuted] = useState(false)
  const [camOff, setCamOff] = useState(false)
  const [hasLocalVideo, setHasLocalVideo] = useState(false)

  const localStreamRef = useRef(null)
  const localVideoRef = useRef(null)
  const peersRef = useRef(new Map()) // userId -> { pc, stream, videoRef }
  const remoteRefs = useRef(new Map()) // userId -> HTMLVideoElement
  const channelIdRef = useRef(null)
  const callTypeRef = useRef('audio')

  useEffect(() => { channelIdRef.current = channelId }, [channelId])
  useEffect(() => { callTypeRef.current = callType }, [callType])

  const attachRemote = (uid, stream) => {
    const el = remoteRefs.current.get(uid)
    if (el) el.srcObject = stream
  }

  const upsertPeer = useCallback((uid, patch) => {
    setPeers(prev => {
      const i = prev.findIndex(p => p.user_id === uid)
      if (i === -1) return [...prev, { user_id: uid, name: 'User', hasVideo: false, muted: false, camOff: false, ...patch }]
      const copy = [...prev]; copy[i] = { ...copy[i], ...patch }; return copy
    })
  }, [])

  const removePeerUI = useCallback((uid) => {
    setPeers(prev => prev.filter(p => p.user_id !== uid))
    const entry = peersRef.current.get(uid)
    if (entry) { try { entry.pc.close() } catch (e) {} ; peersRef.current.delete(uid) }
    remoteRefs.current.delete(uid)
  }, [])

  const getMedia = useCallback(async (type) => {
    let stream
    try {
      if (type === 'video') stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: true })
      else stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false })
    } catch (e) {
      if (type === 'video') {
        try { stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false }); toast('Camera not available - joined with audio only') }
        catch (e2) { throw e2 }
      } else { throw e }
    }
    localStreamRef.current = stream
    setHasLocalVideo(stream.getVideoTracks().length > 0)
    if (localVideoRef.current) localVideoRef.current.srcObject = stream
    return stream
  }, [])

  const makePeer = useCallback((uid, name) => {
    const pc = new RTCPeerConnection(ICE)
    const sock = getSocket()
    const cid = channelIdRef.current

    // Push local tracks
    const local = localStreamRef.current
    if (local) local.getTracks().forEach(t => pc.addTrack(t, local))

    pc.onicecandidate = (e) => { if (e.candidate && sock) sock.emit('gcall:ice', { channel_id: cid, to: uid, candidate: e.candidate }) }
    pc.ontrack = (e) => {
      const stream = e.streams[0]
      const entry = peersRef.current.get(uid)
      if (entry) entry.stream = stream
      attachRemote(uid, stream)
      upsertPeer(uid, { hasVideo: stream.getVideoTracks().length > 0, name })
    }
    pc.onconnectionstatechange = () => {
      if (['failed', 'closed'].includes(pc.connectionState)) removePeerUI(uid)
    }

    peersRef.current.set(uid, { pc, stream: null })
    upsertPeer(uid, { name })
    return pc
  }, [removePeerUI, upsertPeer])

  const cleanup = useCallback(() => {
    peersRef.current.forEach((entry) => { try { entry.pc.close() } catch (e) {} })
    peersRef.current.clear()
    remoteRefs.current.clear()
    if (localStreamRef.current) { localStreamRef.current.getTracks().forEach(t => t.stop()); localStreamRef.current = null }
    setPeers([]); setMuted(false); setCamOff(false); setHasLocalVideo(false)
  }, [])

  const leaveCall = useCallback(() => {
    const sock = getSocket()
    if (sock && channelIdRef.current) sock.emit('gcall:leave', { channel_id: channelIdRef.current })
    cleanup()
    setState('idle'); setChannelId(null); setIncoming(null)
  }, [cleanup])

  const startCall = useCallback(async (cid, type = 'audio') => {
    if (!cid) return
    if (state !== 'idle') { toast('You are already in a call'); return }
    setChannelId(cid); setCallType(type); setState('active')
    try {
      await getMedia(type)
      const sock = getSocket()
      if (sock) sock.emit('gcall:join', { channel_id: cid, name: user?.name || 'User', type })
    } catch (e) {
      console.error(e); toast.error('Microphone permission is required')
      leaveCall()
    }
  }, [state, user, getMedia, leaveCall])

  const acceptIncoming = useCallback(async () => {
    if (!incoming) return
    const cid = incoming.channel_id
    setIncoming(null); setChannelId(cid); setCallType(incoming.type); setState('active')
    try {
      await getMedia(incoming.type)
      const sock = getSocket()
      if (sock) sock.emit('gcall:join', { channel_id: cid, name: user?.name || 'User', type: incoming.type })
    } catch (e) { toast.error('Microphone permission is required'); leaveCall() }
  }, [incoming, user, getMedia, leaveCall])

  const declineIncoming = () => { setIncoming(null) }

  const toggleMute = () => {
    const s = localStreamRef.current; if (!s) return
    s.getAudioTracks().forEach(t => { t.enabled = !t.enabled })
    const m = !muted; setMuted(m)
    getSocket()?.emit('gcall:state', { channel_id: channelIdRef.current, muted: m, camOff })
  }
  const toggleCam = () => {
    const s = localStreamRef.current; if (!s) return
    const tr = s.getVideoTracks(); if (!tr.length) return
    tr.forEach(t => { t.enabled = !t.enabled })
    const c = !camOff; setCamOff(c)
    getSocket()?.emit('gcall:state', { channel_id: channelIdRef.current, muted, camOff: c })
  }

  const setRemoteRef = useCallback((uid, el) => {
    if (el) {
      remoteRefs.current.set(uid, el)
      const entry = peersRef.current.get(uid)
      if (entry && entry.stream) el.srcObject = entry.stream
    } else { remoteRefs.current.delete(uid) }
  }, [])

  // ---------- Socket wiring ----------
  useEffect(() => {
    const sock = getSocket(); if (!sock) return

    const onRing = ({ channel_id, from, fromName, type }) => {
      // Only show ring if not already in this call / not the originator
      if (state === 'active' && channelIdRef.current === channel_id) return
      if (from === user?.id) return
      if (incoming) return
      setIncoming({ channel_id, from, fromName, type })
    }

    const onPeers = async ({ channel_id, peers: list }) => {
      if (channel_id !== channelIdRef.current) return
      // For each existing peer, create offer (we are the new joiner)
      for (const p of list.slice(0, MAX_PEERS)) {
        if (peersRef.current.has(p.user_id)) continue
        const pc = makePeer(p.user_id, p.name)
        try {
          const offer = await pc.createOffer()
          await pc.setLocalDescription(offer)
          sock.emit('gcall:offer', { channel_id, to: p.user_id, sdp: offer })
        } catch (e) { console.error('offer error', e) }
      }
    }

    const onJoined = ({ channel_id, user_id, name }) => {
      if (channel_id !== channelIdRef.current) return
      // Existing peers wait for the new joiner's offer (no action needed here,
      // but we pre-register their name so UI shows them).
      upsertPeer(user_id, { name })
    }

    const onLeft = ({ channel_id, user_id }) => {
      if (channel_id !== channelIdRef.current) return
      removePeerUI(user_id)
    }

    const onOffer = async ({ channel_id, from, sdp }) => {
      if (channel_id !== channelIdRef.current) return
      let entry = peersRef.current.get(from)
      let pc
      if (entry) { pc = entry.pc } else { pc = makePeer(from, 'User') }
      try {
        await pc.setRemoteDescription(new RTCSessionDescription(sdp))
        const ans = await pc.createAnswer()
        await pc.setLocalDescription(ans)
        sock.emit('gcall:answer', { channel_id, to: from, sdp: ans })
      } catch (e) { console.error('answer error', e) }
    }

    const onAnswer = async ({ channel_id, from, sdp }) => {
      if (channel_id !== channelIdRef.current) return
      const entry = peersRef.current.get(from); if (!entry) return
      try { await entry.pc.setRemoteDescription(new RTCSessionDescription(sdp)) } catch (e) { console.error('setRemote error', e) }
    }

    const onIce = async ({ channel_id, from, candidate }) => {
      if (channel_id !== channelIdRef.current) return
      const entry = peersRef.current.get(from); if (!entry || !candidate) return
      try { await entry.pc.addIceCandidate(candidate) } catch (e) {}
    }

    const onState = ({ channel_id, user_id, muted: m, camOff: c }) => {
      if (channel_id !== channelIdRef.current) return
      upsertPeer(user_id, { muted: !!m, camOff: !!c })
    }

    sock.on('gcall:ring', onRing)
    sock.on('gcall:peers', onPeers)
    sock.on('gcall:joined', onJoined)
    sock.on('gcall:left', onLeft)
    sock.on('gcall:offer', onOffer)
    sock.on('gcall:answer', onAnswer)
    sock.on('gcall:ice', onIce)
    sock.on('gcall:state', onState)
    return () => {
      sock.off('gcall:ring', onRing); sock.off('gcall:peers', onPeers)
      sock.off('gcall:joined', onJoined); sock.off('gcall:left', onLeft)
      sock.off('gcall:offer', onOffer); sock.off('gcall:answer', onAnswer)
      sock.off('gcall:ice', onIce); sock.off('gcall:state', onState)
    }
  }, [state, incoming, user, makePeer, upsertPeer, removePeerUI])

  const channelName = channels?.find(c => c.id === channelId)?.name || 'Group call'

  return (
    <GroupCallContext.Provider value={{
      state, channelId, callType, peers, muted, camOff, hasLocalVideo,
      startCall, leaveCall, toggleMute, toggleCam,
      localVideoRef, setRemoteRef, channelName, incoming
    }}>
      {children}
      <GroupCallRingModal incoming={incoming} onAccept={acceptIncoming} onDecline={declineIncoming} />
      <GroupCallModal />
    </GroupCallContext.Provider>
  )
}

function GroupCallRingModal({ incoming, onAccept, onDecline }) {
  if (!incoming) return null
  return (
    <div className="fixed inset-0 z-[80] flex items-center justify-center bg-black/70 backdrop-blur-sm p-4">
      <div className="bg-[#0b141a] rounded-2xl border border-white/10 shadow-2xl w-full max-w-sm overflow-hidden">
        <div className="flex flex-col items-center gap-3 pt-8 pb-5 px-6">
          <div className="w-20 h-20 rounded-full bg-brand-500 flex items-center justify-center text-2xl font-semibold text-[#06291f]">{getInitials(incoming.fromName)}</div>
          <div className="text-center">
            <div className="text-lg font-semibold text-white">{incoming.fromName}</div>
            <div className="text-sm text-gray-400 mt-1">Incoming group {incoming.type === 'video' ? 'video' : 'voice'} call</div>
          </div>
        </div>
        <div className="flex items-center justify-center gap-4 py-4 bg-[#111820] border-t border-white/5">
          <button onClick={onDecline} title="Decline" className="w-14 h-14 rounded-full bg-red-600 hover:bg-red-700 text-white flex items-center justify-center">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7 2 2 0 0 1 1.72 2v3a2 2 0 0 1-2.18 2A19.79 19.79 0 0 1 8.63 19.24"/><line x1="23" y1="1" x2="1" y2="23"/></svg>
          </button>
          <button onClick={onAccept} title="Accept" className="w-14 h-14 rounded-full bg-green-600 hover:bg-green-700 text-white flex items-center justify-center">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
          </button>
        </div>
      </div>
    </div>
  )
}

function PeerTile({ peer, setRemoteRef }) {
  return (
    <div className="relative bg-[#0a0f14] rounded-xl overflow-hidden aspect-video flex items-center justify-center">
      <video ref={(el) => setRemoteRef(peer.user_id, el)} autoPlay playsInline className={peer.hasVideo && !peer.camOff ? 'absolute inset-0 w-full h-full object-cover' : 'hidden'} />
      {!(peer.hasVideo && !peer.camOff) && (
        <div className="w-16 h-16 rounded-full bg-brand-500 flex items-center justify-center text-xl font-semibold text-[#06291f]">{getInitials(peer.name)}</div>
      )}
      <div className="absolute bottom-1 left-2 text-[12px] text-white drop-shadow flex items-center gap-1">
        <span>{peer.name}</span>
        {peer.muted && <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#f87171" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="1" y1="1" x2="23" y2="23"/><path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6"/><path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2a7 7 0 0 1-.11 1.23"/><line x1="12" y1="19" x2="12" y2="23"/></svg>}
      </div>
    </div>
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

function GroupCallModal() {
  const g = useGroupCall()
  if (!g || g.state !== 'active') return null
  const { peers, channelName, muted, camOff, hasLocalVideo, toggleMute, toggleCam, leaveCall, localVideoRef, setRemoteRef, callType } = g
  const totalTiles = peers.length + 1
  const cols = totalTiles <= 1 ? 1 : totalTiles <= 4 ? 2 : 3

  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/80 backdrop-blur-sm p-4">
      <div className="bg-[#0b141a] rounded-2xl border border-white/10 shadow-2xl w-full max-w-4xl overflow-hidden flex flex-col">
        <div className="flex items-center justify-between px-5 py-3 bg-[#111820] border-b border-white/5">
          <div>
            <div className="text-sm text-gray-400">Group {callType === 'video' ? 'video' : 'voice'} call</div>
            <div className="text-base font-semibold text-white truncate">{channelName}</div>
          </div>
          <div className="text-xs text-gray-400">{totalTiles} participant{totalTiles === 1 ? '' : 's'}</div>
        </div>

        <div className={`grid gap-2 p-3 bg-black`} style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))` }}>
          {/* self */}
          <div className="relative bg-[#0a0f14] rounded-xl overflow-hidden aspect-video flex items-center justify-center">
            <video ref={localVideoRef} autoPlay playsInline muted className={hasLocalVideo && !camOff ? 'absolute inset-0 w-full h-full object-cover' : 'hidden'} />
            {!(hasLocalVideo && !camOff) && (
              <div className="w-16 h-16 rounded-full bg-brand-500 flex items-center justify-center text-xl font-semibold text-[#06291f]">You</div>
            )}
            <div className="absolute bottom-1 left-2 text-[12px] text-white drop-shadow">You</div>
          </div>
          {peers.map(p => <PeerTile key={p.user_id} peer={p} setRemoteRef={setRemoteRef} />)}
        </div>

        <div className="flex items-center justify-center gap-4 py-5 bg-[#111820] border-t border-white/5">
          <CtrlBtn title={muted ? 'Unmute' : 'Mute'} active={muted} onClick={toggleMute}>
            {muted
              ? <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="1" y1="1" x2="23" y2="23"/><path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6"/><path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2a7 7 0 0 1-.11 1.23"/><line x1="12" y1="19" x2="12" y2="23"/></svg>
              : <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/></svg>}
          </CtrlBtn>
          {hasLocalVideo && (
            <CtrlBtn title={camOff ? 'Camera on' : 'Camera off'} active={camOff} onClick={toggleCam}>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>
            </CtrlBtn>
          )}
          <CtrlBtn title="Leave call" danger onClick={leaveCall}>
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7 2 2 0 0 1 1.72 2v3a2 2 0 0 1-2.18 2A19.79 19.79 0 0 1 8.63 19.24"/><line x1="23" y1="1" x2="1" y2="23"/></svg>
          </CtrlBtn>
        </div>
      </div>
    </div>
  )
}
'@
Write-FileUtf8NoBom -Path "context/GroupCallContext.js" -Content $groupCall

# =====================================================================
# 4) app/chat/[channelId]/page.js -- add "Group call" buttons for non-DM
#    + ensure smooth scroll behavior
# =====================================================================
Write-Host "[4/5] Patching app/chat/[channelId]/page.js (group call buttons + scroll)..."

$pagePath = "app/chat/[channelId]/page.js"
$page = Read-FileUtf8 $pagePath

# 4a) Import useGroupCall (idempotent)
if ($page -notmatch "useGroupCall") {
    $page = $page -replace "import \{ useCall \} from '@/context/CallContext'", "import { useCall } from '@/context/CallContext'`r`nimport { useGroupCall } from '@/context/GroupCallContext'"
}

# 4b) Use the hook + replace handleCall to dispatch group vs 1:1
$oldHandle = @"
  const handleCall = (type) => {
    if (!isDM || !dmPeer) { toast('Calls are available in direct messages'); return }
    if (!call?.startCall) { toast('Calling is not ready'); return }
    call.startCall(dmPeer.id, dmPeer.name, type)
  }
"@
$newHandle = @"
  const groupCall = useGroupCall()
  const handleCall = (type) => {
    if (isDM) {
      if (!dmPeer) { toast('No peer to call'); return }
      if (!call?.startCall) { toast('Calling is not ready'); return }
      call.startCall(dmPeer.id, dmPeer.name, type)
    } else {
      if (!groupCall?.startCall) { toast('Group calling is not ready'); return }
      groupCall.startCall(channelId, type)
    }
  }
"@
if ($page.Contains("groupCall?.startCall") -eq $false) {
    $page = $page.Replace($oldHandle.Trim(), $newHandle.Trim())
}

# 4c) Smooth scroll on new messages
$page = $page.Replace("bottomRef.current?.scrollIntoView({ behavior: 'auto' })",
                      "bottomRef.current?.scrollIntoView({ behavior: 'smooth', block: 'end' })")

Write-FileUtf8NoBom -Path $pagePath -Content $page

# =====================================================================
# 5) app/chat/layout.js -- wrap children with GroupCallProvider
# =====================================================================
Write-Host "[5/5] Patching app/chat/layout.js (GroupCallProvider)..."

$layPath = "app/chat/layout.js"
$lay = Read-FileUtf8 $layPath

if ($lay -notmatch "GroupCallProvider") {
    $lay = $lay -replace "import \{ CallProvider \} from '@/context/CallContext'", "import { CallProvider } from '@/context/CallContext'`r`nimport { GroupCallProvider } from '@/context/GroupCallContext'"
    $lay = $lay.Replace("<CallProvider>", "<CallProvider>`r`n      <GroupCallProvider>")
    $lay = $lay.Replace("</CallProvider>", "      </GroupCallProvider>`r`n    </CallProvider>")
}

Write-FileUtf8NoBom -Path $layPath -Content $lay

Write-Host ""
Write-Host "================================================================="
Write-Host "WEBAPP DONE."
Write-Host "Next steps:"
Write-Host "  1) cd to webapp folder, run: npm run build  (or restart dev server)"
Write-Host "  2) Hard-refresh browser (Ctrl+F5) to clear cached JS/CSS"
Write-Host "  3) Test:"
Write-Host "     - Messages no longer show mojibake (broken chars)"
Write-Host "     - Scroll inside chat works and auto-scrolls to bottom"
Write-Host "     - On a GROUP channel, click voice/video icon -> group call popup"
Write-Host "     - Other members see incoming ring popup, can accept/decline"
Write-Host "================================================================="