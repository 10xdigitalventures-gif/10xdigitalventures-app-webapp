# ============================================================================
#  10x Chat WEBAPP — files+media, call POPUP, Calls screen, topbar fix
#  Run from the WEBAPP repo root (10xdigitalventures-app-webapp):
#      cd path\to\10xdigitalventures-app-webapp
#      powershell -ExecutionPolicy Bypass -File .\fix-media-call-topbar.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
if (-not (Test-Path ".\package.json")) {
  Write-Host "ERROR: run this from the webapp repo root." -ForegroundColor Red; exit 1
}

function Patch($Path, $Find, $Replace) {
  $full = Join-Path (Get-Location) $Path
  if (-not (Test-Path $full)) { Write-Host "  skip (not found): $Path" -ForegroundColor Yellow; return }
  $c = [System.IO.File]::ReadAllText($full)
  if ($c.Contains($Replace)) { Write-Host "  already patched: $Path" -ForegroundColor DarkGray; return }
  if (-not $c.Contains($Find)) { Write-Host "  pattern NOT found in $Path" -ForegroundColor Yellow; return }
  if (-not (Test-Path "$full.bak5")) { Copy-Item $full "$full.bak5" -Force }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($full, $c.Replace($Find, $Replace), $enc)
  Write-Host "  patched: $Path" -ForegroundColor Green
}
function Write-RepoFile($Path, $Content) {
  $full = Join-Path (Get-Location) $Path
  $dir  = Split-Path $full -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if ((Test-Path $full) -and -not (Test-Path "$full.bak5")) { Copy-Item $full "$full.bak5" -Force }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($full, $Content, $enc)
  Write-Host "  wrote $Path" -ForegroundColor Green
}

Write-Host "`n[1/6] Fix topbar clipping (globals.css .chat-area)..." -ForegroundColor Cyan
$caFind = @'
.chat-area {
  height: calc(100vh - 120px);
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  padding: 20px;
}
'@
$caRepl = @'
.chat-area {
  min-height: 100%;
  display: flex;
  flex-direction: column;
  padding: 20px;
}
'@
Patch "app\globals.css" $caFind $caRepl

Write-Host "`n[2/6] Fix layout height (no page overflow)..." -ForegroundColor Cyan
Patch "app\chat\layout.js" 'className="flex min-h-screen bg-[#0f1117] text-white"' 'className="flex h-screen overflow-hidden bg-[#0f1117] text-white"'

Write-Host "`n[3/6] components/Message.js (image/video/audio/file render + open)..." -ForegroundColor Cyan
$msg = @'
'use client'
import { useState } from 'react'
import useChatStore from '@/store/chatStore'
import { getSocket } from '@/lib/socket'
import { mediaUrl } from '@/lib/chatFormat'

const EMOJIS = ['👍','❤️','😂','😮','😢','🔥','✅','👀']
const timeFormatter = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })

function fmtSize(bytes) {
  if (!bytes) return ''
  const kb = bytes / 1024
  return kb < 1024 ? `${Math.round(kb)} KB` : `${(kb / 1024).toFixed(1)} MB`
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
    if (read) return <span className="text-[#34b7f1]" title="Read">✓✓</span>
    if (delivered) return <span className="text-gray-400" title="Delivered">✓✓</span>
    return <span className="text-gray-400" title="Sent">✓</span>
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
          <button onClick={() => setShowEmoji(!showEmoji)} className="w-7 h-7 flex items-center justify-center hover:bg-white/5 rounded-full text-sm">😊</button>
          {isOwn && (<button onClick={() => setEditing(true)} className="w-7 h-7 flex items-center justify-center hover:bg-white/5 rounded-full text-xs text-gray-500 hover:text-white">✏️</button>)}
          {isOwn && (<button onClick={deleteMsg} className="w-7 h-7 flex items-center justify-center hover:bg-white/5 rounded-full text-xs text-gray-500 hover:text-red-400">🗑️</button>)}
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
Write-RepoFile "components\Message.js" $msg

Write-Host "`n[4/6] components/MessageInput.js (attach menu, no double-send)..." -ForegroundColor Cyan
$input = @'
'use client'
import { useState, useRef } from 'react'
import toast from 'react-hot-toast'
import { getSocket } from '@/lib/socket'
import api from '@/lib/api'

export default function MessageInput({ channelId }) {
  const [content, setContent] = useState('')
  const [uploading, setUploading] = useState(false)
  const [isTyping, setIsTyping] = useState(false)
  const [menuOpen, setMenuOpen] = useState(false)
  const mediaInputRef = useRef(null)
  const docInputRef = useRef(null)
  const typingTimeoutRef = useRef(null)

  const handleSend = () => {
    if (!content.trim()) return
    getSocket()?.emit('message:send', { channel_id: channelId, content: content.trim(), type: 'text' })
    setContent('')
    stopTyping()
  }

  const startTyping = () => {
    if (!isTyping) { setIsTyping(true); getSocket()?.emit('typing:start', { channel_id: channelId }) }
    if (typingTimeoutRef.current) clearTimeout(typingTimeoutRef.current)
    typingTimeoutRef.current = setTimeout(stopTyping, 3000)
  }
  const stopTyping = () => {
    setIsTyping(false); getSocket()?.emit('typing:stop', { channel_id: channelId })
    if (typingTimeoutRef.current) clearTimeout(typingTimeoutRef.current)
  }

  const uploadFile = async (file) => {
    if (!file) return
    setMenuOpen(false)
    setUploading(true)
    const formData = new FormData()
    formData.append('file', file)
    try {
      // The upload endpoint creates the message AND broadcasts it over the
      // socket (message:new). So we do NOT emit message:send here (doing both
      // caused duplicate + broken-image messages).
      await api.post(`/files/upload/${channelId}`, formData)
    } catch (err) {
      console.error('upload failed', err)
      toast.error('Upload failed')
    } finally {
      setUploading(false)
      if (mediaInputRef.current) mediaInputRef.current.value = ''
      if (docInputRef.current) docInputRef.current.value = ''
    }
  }

  return (
    <div className="px-4 py-3 bg-[#12141a] border-t border-[#2a2d35] flex items-center gap-3">
      <input type="file" accept="image/*,video/*" className="hidden" ref={mediaInputRef} onChange={e => uploadFile(e.target.files?.[0])} />
      <input type="file" className="hidden" ref={docInputRef} onChange={e => uploadFile(e.target.files?.[0])} />

      <div className="relative">
        <button onClick={() => setMenuOpen(o => !o)} disabled={uploading} title="Attach" aria-label="Attach"
          className="w-10 h-10 flex items-center justify-center rounded-full text-gray-400 hover:bg-white/5 transition-colors disabled:opacity-50">
          {uploading
            ? <span className="w-5 h-5 border-2 border-brand-500 border-t-transparent rounded-full animate-spin" />
            : <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48"/></svg>}
        </button>
        {menuOpen && (
          <div className="absolute bottom-12 left-0 w-52 bg-[#1e2229] border border-white/10 rounded-xl shadow-2xl overflow-hidden z-20">
            <button onClick={() => mediaInputRef.current?.click()} className="w-full flex items-center gap-3 px-4 py-3 text-sm text-white hover:bg-white/5 text-left">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#1db791" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/></svg>
              Photos & Videos
            </button>
            <button onClick={() => docInputRef.current?.click()} className="w-full flex items-center gap-3 px-4 py-3 text-sm text-white hover:bg-white/5 text-left">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#1db791" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
              Document
            </button>
          </div>
        )}
      </div>

      <div className="flex-1">
        <textarea
          value={content}
          onChange={e => { setContent(e.target.value); startTyping() }}
          onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSend() } }}
          placeholder="Type a message..."
          rows={1}
          className="w-full resize-none py-3 px-4 bg-[#1e2028] rounded-2xl border-none focus:ring-0 text-[15px] text-white placeholder-gray-500 max-h-32"
        />
      </div>

      <button onClick={handleSend} disabled={!content.trim() || uploading} title="Send" aria-label="Send"
        className="w-10 h-10 flex items-center justify-center rounded-full bg-brand-500 text-[#06291f] transition-all hover:scale-105 active:scale-95 disabled:bg-gray-700 disabled:opacity-50 disabled:scale-100">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/></svg>
      </button>
    </div>
  )
}
'@
Write-RepoFile "components\MessageInput.js" $input

Write-Host "`n[5/6] context/CallContext.js (call as centered POPUP)..." -ForegroundColor Cyan
$callCtx = @'
'use client'

import { createContext, useContext, useEffect, useRef, useState, useCallback } from 'react'
import toast from 'react-hot-toast'
import useChatStore from '@/store/chatStore'
import { getSocket } from '@/lib/socket'
import { getInitials } from '@/lib/chatFormat'

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
  const finish = useCallback(() => { cleanup(); setState('idle'); setPeer(null) }, [cleanup])
  const endCall = useCallback((notify = true) => { if (notify && peer?.id) getSocket()?.emit('call:end', { to: peer.id }); finish() }, [peer, finish])

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
    stopRingtone(); setState('active')
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

  const rejectCall = useCallback(() => { if (peer?.id) getSocket()?.emit('call:reject', { to: peer.id }); finish() }, [peer, finish])
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
      pendingOfferRef.current = sdp; setPeer({ id: from, name: fromName || 'Unknown' }); setCallType(type || 'audio'); setState('ringing')
    }
    const onAnswer = async ({ sdp }) => { try { await pcRef.current?.setRemoteDescription(new RTCSessionDescription(sdp)); setState('active') } catch (e) {} }
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
          <video ref={localVideoRef} autoPlay playsInline muted className={localPip ? (showStage ? 'absolute bottom-3 right-3 w-24 h-32 object-cover rounded-lg border border-white/20 z-10' : 'absolute top-3 right-3 w-16 h-22 object-cover rounded-lg border border-white/20 z-10') : 'hidden'} />

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

Write-Host "`n[6/6] components/CallsModal.js (WhatsApp-style Calls screen)..." -ForegroundColor Cyan
$callsModal = @'
'use client'

import { useEffect, useState } from 'react'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import { getInitials, avatarColor } from '@/lib/chatFormat'
import { useCall } from '@/context/CallContext'

function PhoneIcon() { return (<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/></svg>) }
function VideoIcon() { return (<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>) }

export default function CallsModal({ onClose }) {
  const { user, onlineUsers } = useChatStore()
  const call = useCall()
  const [users, setUsers] = useState([])
  const [q, setQ] = useState('')

  useEffect(() => {
    api.get('/users').then(({ data }) => {
      const list = Array.isArray(data?.data) ? data.data : Array.isArray(data) ? data : []
      setUsers(list.filter(u => u.id !== user?.id))
    }).catch(() => {})
  }, [user?.id])

  const placeCall = (u, type) => { if (!call?.startCall) return; call.startCall(u.id, u.name, type); onClose?.() }
  const filtered = users.filter(u => { const s = q.toLowerCase(); return !s || (u.name || '').toLowerCase().includes(s) || (u.email || '').toLowerCase().includes(s) })

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

        <div className="px-4 pb-1 text-[11px] uppercase tracking-wide text-gray-500">Start a new call</div>
        <div className="max-h-[55vh] overflow-y-auto px-2 pb-3">
          {filtered.length === 0 ? (
            <div className="text-center text-sm text-gray-500 py-8">No people found.</div>
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

Write-Host "`nDone." -ForegroundColor Cyan
$doGit = Read-Host "Commit and push? (y/n)"
if ($doGit -eq 'y') {
  git add "app/globals.css" "app/chat/layout.js" "components/Message.js" "components/MessageInput.js" "context/CallContext.js" "components/CallsModal.js"
  git commit -m "feat(web): media messages (image/video/audio/file) + attach menu; call popup modal; Calls screen; fix topbar clipping"
  $push = Read-Host "Push now? (y/n)"
  if ($push -eq 'y') { git push; Write-Host "`nPushed." -ForegroundColor Green }
  else { Write-Host "`nCommitted locally. Push later with: git push" -ForegroundColor Yellow }
} else { Write-Host "`nSkipped git. Review with: git diff" -ForegroundColor Yellow }
Write-Host "`nReminder: run the BACKEND script (fix-files-backend.ps1) too, so file_url is returned and uploads broadcast." -ForegroundColor Yellow