# ============================================================================
#  10x Chat — MERGED: WhatsApp New Chat + WebRTC Calling
#  Applies BOTH fixes/features in one run:
#    1) WhatsApp-style "New chat" modal in components/Sidebar.js
#    2) WebRTC audio/video calling for direct messages
#
#  Run from web repo root:
#    cd E:\Downloads\10xdigitalventures-main\10xdigitalventures-main\web
#    powershell -ExecutionPolicy Bypass -File .\apply-new-chat-and-calling.ps1
# ============================================================================

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\package.json")) {
  Write-Host "ERROR: run this from the web repo root (package.json not found)." -ForegroundColor Red
  exit 1
}

function Write-RepoFile($Path, $Content) {
  $full = Join-Path (Get-Location) $Path
  $dir  = Split-Path $full -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

  $backup = "$full.bak-merged"
  if ((Test-Path $full) -and -not (Test-Path $backup)) {
    Copy-Item $full $backup -Force
    Write-Host "  backed up -> $Path.bak-merged" -ForegroundColor DarkGray
  }

  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($full, $Content, $enc)
  Write-Host "  wrote $Path" -ForegroundColor Green
}

Write-Host "`n[1/4] Writing WhatsApp-style New Chat sidebar..." -ForegroundColor Cyan

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
  const [showNewChat, setShowNewChat] = useState(false)
  const [newChatSearch, setNewChatSearch] = useState('')
  const [starting, setStarting] = useState(null)

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
    setStarting(userId)
    try {
      const { data } = await api.post(`/channels/dm/${userId}`)
      const channel = data?.data || data
      if (!channel?.id) throw new Error('Invalid channel response')
      const exists = (Array.isArray(channels) ? channels : []).some(c => c.id === channel.id)
      if (!exists) addChannel(channel)
      setShowNewChat(false)
      setNewChatSearch('')
      setSearchQuery('')
      router.push(`/chat/${channel.id}`)
    } catch (err) {
      toast.error('Could not start direct message')
    } finally {
      setStarting(null)
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

  const inlineSuggestions = users.filter(u => {
    const name = (u?.name || '').toLowerCase()
    const email = (u?.email || '').toLowerCase()
    return name.includes(q) || email.includes(q)
  })

  const nq = newChatSearch.toLowerCase()
  const newChatUsers = users.filter(u => {
    const name = (u?.name || '').toLowerCase()
    const email = (u?.email || '').toLowerCase()
    return !nq || name.includes(nq) || email.includes(nq)
  })

  return (
    <>
      <aside className="w-80 bg-[#111820] border-r border-white/10 flex flex-col h-screen">
        <div className="px-4 py-3 flex items-center justify-between">
          <span className="text-[17px] font-semibold text-white">Chats</span>
          <button onClick={() => setShowNewChat(true)} title="New chat" aria-label="New chat" className="text-gray-400 hover:text-white">
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 5v14"/><path d="M5 12h14"/></svg>
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
          {q && inlineSuggestions.length > 0 && (
            <div className="mb-2">
              <div className="text-[11px] uppercase tracking-wide text-gray-500 px-3 py-2">Start new chat</div>
              {inlineSuggestions.map(u => (
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
            <div className="text-center text-sm text-gray-500 py-10">
              No chats yet.
              <button onClick={() => setShowNewChat(true)} className="block mx-auto mt-2 text-brand-500 hover:underline">Start a new chat</button>
            </div>
          )}
        </div>
      </aside>

      {showNewChat && (
        <div className="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-16" onClick={() => setShowNewChat(false)}>
          <div className="w-full max-w-md bg-[#111820] rounded-xl border border-white/10 shadow-2xl overflow-hidden" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between px-4 py-3 border-b border-white/10">
              <span className="text-[15px] font-semibold text-white">New chat</span>
              <button onClick={() => setShowNewChat(false)} aria-label="Close" className="text-gray-400 hover:text-white">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
              </button>
            </div>

            <div className="p-3">
              <div className="flex items-center gap-2 bg-[#202c33] rounded-lg px-3 py-2">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#8696a0" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
                <input
                  autoFocus
                  value={newChatSearch}
                  onChange={e => setNewChatSearch(e.target.value)}
                  placeholder="Search people"
                  className="bg-transparent border-none outline-none text-sm text-white placeholder-gray-500 w-full"
                />
              </div>
            </div>

            <div className="max-h-[50vh] overflow-y-auto px-2 pb-3">
              {newChatUsers.length === 0 ? (
                <div className="text-center text-sm text-gray-500 py-8">No people found.</div>
              ) : newChatUsers.map(u => (
                <button
                  key={u.id}
                  onClick={() => startDM(u.id)}
                  disabled={starting === u.id}
                  className="w-full flex items-center gap-3 p-2 rounded-lg hover:bg-[#202c33] text-left disabled:opacity-50"
                >
                  <div className="relative flex-shrink-0">
                    <div className="h-11 w-11 rounded-full flex items-center justify-center text-white font-semibold text-sm" style={{ background: avatarColor(u.name) }}>{getInitials(u.name)}</div>
                    {onlineUsers?.has?.(u.id) && <span className="absolute bottom-0 right-0 w-3 h-3 rounded-full bg-brand-500 border-2 border-[#111820]" />}
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="text-sm text-white truncate">{u.name}</div>
                    <div className="text-xs text-gray-500 truncate">{u.email || (onlineUsers?.has?.(u.id) ? 'online' : 'tap to chat')}</div>
                  </div>
                  {starting === u.id && <span className="w-4 h-4 border-2 border-brand-500 border-t-transparent rounded-full animate-spin flex-shrink-0" />}
                </button>
              ))}
            </div>
          </div>
        </div>
      )}
    </>
  )
}
'@

Write-RepoFile "components\Sidebar.js" $sidebar

Write-Host "`n[2/4] Writing WebRTC CallContext..." -ForegroundColor Cyan

$callCtx = @'
'use client'

import { createContext, useContext, useEffect, useRef, useState, useCallback } from 'react'
import useChatStore from '@/store/chatStore'
import { getSocket } from '@/lib/socket'
import { getInitials } from '@/lib/chatFormat'

const ICE = { iceServers: [{ urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'] }] }

const CallContext = createContext(null)
export const useCall = () => useContext(CallContext)

export function CallProvider({ children }) {
  const { user } = useChatStore()
  const [state, setState] = useState('idle')        // idle | calling | ringing | active
  const [callType, setCallType] = useState('audio') // audio | video
  const [peer, setPeer] = useState(null)            // { id, name }
  const [muted, setMuted] = useState(false)
  const [camOff, setCamOff] = useState(false)

  const pcRef = useRef(null)
  const localStreamRef = useRef(null)
  const localVideoRef = useRef(null)
  const remoteVideoRef = useRef(null)
  const remoteAudioRef = useRef(null)
  const pendingOfferRef = useRef(null)
  const pendingCandidatesRef = useRef([])

  const cleanup = useCallback(() => {
    try { pcRef.current?.close() } catch (e) {}
    pcRef.current = null
    localStreamRef.current?.getTracks().forEach(t => t.stop())
    localStreamRef.current = null
    pendingOfferRef.current = null
    pendingCandidatesRef.current = []
    setMuted(false); setCamOff(false)
  }, [])

  const finish = useCallback(() => { cleanup(); setState('idle'); setPeer(null) }, [cleanup])

  const endCall = useCallback((notify = true) => {
    if (notify && peer?.id) getSocket()?.emit('call:end', { to: peer.id })
    finish()
  }, [peer, finish])

  const attachRemote = (stream) => {
    if (remoteVideoRef.current) remoteVideoRef.current.srcObject = stream
    if (remoteAudioRef.current) remoteAudioRef.current.srcObject = stream
  }

  const createPeer = useCallback((targetId) => {
    const pc = new RTCPeerConnection(ICE)
    pc.onicecandidate = (e) => { if (e.candidate) getSocket()?.emit('call:ice', { to: targetId, candidate: e.candidate }) }
    pc.ontrack = (e) => attachRemote(e.streams[0])
    pc.onconnectionstatechange = () => {
      if (['disconnected', 'failed', 'closed'].includes(pc.connectionState)) finish()
    }
    pcRef.current = pc
    return pc
  }, [finish])

  const getMedia = async (type) => {
    const stream = await navigator.mediaDevices.getUserMedia(
      type === 'video' ? { audio: true, video: true } : { audio: true, video: false }
    )
    localStreamRef.current = stream
    if (localVideoRef.current) localVideoRef.current.srcObject = stream
    return stream
  }

  const startCall = useCallback(async (targetId, targetName, type = 'audio') => {
    if (!targetId || state !== 'idle') return
    setPeer({ id: targetId, name: targetName }); setCallType(type); setState('calling')
    try {
      const stream = await getMedia(type)
      const pc = createPeer(targetId)
      stream.getTracks().forEach(t => pc.addTrack(t, stream))
      const offer = await pc.createOffer()
      await pc.setLocalDescription(offer)
      getSocket()?.emit('call:offer', { to: targetId, fromName: user?.name, type, sdp: offer })
    } catch (err) { console.error('startCall', err); endCall(false) }
  }, [state, user, createPeer, endCall])

  const acceptCall = useCallback(async () => {
    const offer = pendingOfferRef.current
    if (!offer || !peer?.id) return
    setState('active')
    try {
      const stream = await getMedia(callType)
      const pc = createPeer(peer.id)
      stream.getTracks().forEach(t => pc.addTrack(t, stream))
      await pc.setRemoteDescription(new RTCSessionDescription(offer))
      for (const c of pendingCandidatesRef.current) { try { await pc.addIceCandidate(c) } catch (e) {} }
      pendingCandidatesRef.current = []
      const answer = await pc.createAnswer()
      await pc.setLocalDescription(answer)
      getSocket()?.emit('call:answer', { to: peer.id, sdp: answer })
    } catch (err) { console.error('acceptCall', err); endCall() }
  }, [peer, callType, createPeer, endCall])

  const rejectCall = useCallback(() => {
    if (peer?.id) getSocket()?.emit('call:reject', { to: peer.id })
    finish()
  }, [peer, finish])

  const toggleMute = () => {
    const s = localStreamRef.current; if (!s) return
    s.getAudioTracks().forEach(t => { t.enabled = !t.enabled })
    setMuted(m => !m)
  }
  const toggleCam = () => {
    const s = localStreamRef.current; if (!s) return
    s.getVideoTracks().forEach(t => { t.enabled = !t.enabled })
    setCamOff(c => !c)
  }

  useEffect(() => {
    const socket = getSocket()
    if (!socket) return
    const onOffer = ({ from, fromName, type, sdp }) => {
      if (pcRef.current || state !== 'idle') { socket.emit('call:reject', { to: from }); return }
      pendingOfferRef.current = sdp
      setPeer({ id: from, name: fromName || 'Unknown' }); setCallType(type || 'audio'); setState('ringing')
    }
    const onAnswer = async ({ sdp }) => {
      try { await pcRef.current?.setRemoteDescription(new RTCSessionDescription(sdp)); setState('active') } catch (e) { console.error(e) }
    }
    const onIce = async ({ candidate }) => {
      if (!candidate) return
      if (pcRef.current && pcRef.current.remoteDescription) { try { await pcRef.current.addIceCandidate(candidate) } catch (e) {} }
      else pendingCandidatesRef.current.push(candidate)
    }
    socket.on('call:offer', onOffer)
    socket.on('call:answer', onAnswer)
    socket.on('call:ice', onIce)
    socket.on('call:reject', finish)
    socket.on('call:end', finish)
    return () => {
      socket.off('call:offer', onOffer); socket.off('call:answer', onAnswer)
      socket.off('call:ice', onIce); socket.off('call:reject', finish); socket.off('call:end', finish)
    }
  }, [state, finish])

  return (
    <CallContext.Provider value={{ state, callType, peer, muted, camOff, startCall, acceptCall, rejectCall, endCall, toggleMute, toggleCam, localVideoRef, remoteVideoRef, remoteAudioRef }}>
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
  const { state, callType, peer, muted, camOff, acceptCall, rejectCall, endCall, toggleMute, toggleCam, localVideoRef, remoteVideoRef, remoteAudioRef } = c
  const isVideo = callType === 'video'
  const statusText = state === 'calling' ? 'Calling...' : state === 'ringing' ? `Incoming ${isVideo ? 'video' : 'voice'} call` : 'In call'

  return (
    <div className="fixed inset-0 z-[60] bg-[#0b141a] flex flex-col items-center justify-between py-10">
      <audio ref={remoteAudioRef} autoPlay />

      {isVideo && state === 'active' ? (
        <>
          <video ref={remoteVideoRef} autoPlay playsInline className="absolute inset-0 w-full h-full object-cover bg-black" />
          <video ref={localVideoRef} autoPlay playsInline muted className="absolute bottom-28 right-6 w-32 h-44 object-cover rounded-xl border border-white/20 bg-black z-10" />
        </>
      ) : (
        <>
          <video ref={remoteVideoRef} autoPlay playsInline className="hidden" />
          <video ref={localVideoRef} autoPlay playsInline muted className="hidden" />
        </>
      )}

      <div className="relative z-10 flex flex-col items-center gap-4 mt-10">
        <div className="w-28 h-28 rounded-full bg-brand-500 flex items-center justify-center text-3xl font-semibold text-[#06291f]">
          {getInitials(peer?.name)}
        </div>
        <div className="text-center">
          <div className="text-2xl font-semibold text-white">{peer?.name || 'Unknown'}</div>
          <div className="text-sm text-gray-400 mt-1 animate-pulse">{statusText}</div>
        </div>
      </div>

      <div className="relative z-10 flex items-center gap-5">
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
              {muted ? (
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="1" y1="1" x2="23" y2="23"/><path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6"/><path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2a7 7 0 0 1-.11 1.23"/><line x1="12" y1="19" x2="12" y2="23"/></svg>
              ) : (
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/></svg>
              )}
            </CtrlBtn>

            {isVideo && (
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
  )
}
'@

Write-RepoFile "context\CallContext.js" $callCtx

Write-Host "`n[3/4] Writing chat layout with CallProvider..." -ForegroundColor Cyan

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
    <CallProvider>
      <div className="flex min-h-screen bg-[#0f1117] text-white">
        <IconRail />
        <Sidebar />
        <main className="flex-1 overflow-hidden">{children}</main>
      </div>
    </CallProvider>
  )
}
'@

Write-RepoFile "app\chat\layout.js" $layout

Write-Host "`n[4/4] Writing channel page with call buttons..." -ForegroundColor Cyan

$channelPage = @'
'use client'
import { useEffect, useRef, useState } from 'react'
import { useParams } from 'next/navigation'
import toast from 'react-hot-toast'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import Message from '@/components/Message'
import MessageInput from '@/components/MessageInput'
import MembersList from '@/components/MembersList'
import { getSocket } from '@/lib/socket'
import { useCall } from '@/context/CallContext'

const ICO = { width: 20, height: 20, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round', 'aria-hidden': true }
function HashIcon() { return (<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="4" y1="9" x2="20" y2="9"/><line x1="4" y1="15" x2="20" y2="15"/><line x1="10" y1="3" x2="8" y2="21"/><line x1="16" y1="3" x2="14" y2="21"/></svg>) }
function UserIcon() { return (<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>) }
function PhoneIcon() { return (<svg {...ICO}><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/></svg>) }
function VideoIcon() { return (<svg {...ICO}><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>) }
function SearchIcon() { return (<svg {...ICO}><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>) }
function InfoIcon() { return (<svg {...ICO}><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>) }

function IconBtn({ title, onClick, children }) {
  return (<button onClick={onClick} title={title} aria-label={title} className="w-9 h-9 flex items-center justify-center rounded-full text-gray-400 hover:bg-white/5 hover:text-white transition-colors">{children}</button>)
}

export default function ChannelPage() {
  const { channelId } = useParams()
  const { channels, messages, members, setMessages, setMembers, setActiveChannel, typingUsers, user } = useChatStore()
  const call = useCall()
  const [loading, setLoading] = useState(true)
  const [showMembers, setShowMembers] = useState(true)
  const bottomRef = useRef(null)
  const scrollRef = useRef(null)

  const channel = channels.find(c => c.id === channelId)
  const isDM = channel?.type === 'dm'
  const channelMessages = messages[channelId] || []
  const dmPeer = isDM ? (members || []).find(m => String(m.id) !== String(user?.id)) : null

  const typingInChannel = typingUsers[channelId]
    ? [...typingUsers[channelId]].filter(id => id !== user?.id)
    : []

  useEffect(() => {
    if (!channelId) return
    setActiveChannel(channel)
    setLoading(true)
    Promise.all([
      api.get(`/messages/${channelId}`),
      api.get(`/channels/${channelId}/members`),
    ]).then(([msgRes, memRes]) => {
      const list = Array.isArray(msgRes.data?.data) ? msgRes.data.data : (Array.isArray(msgRes.data) ? msgRes.data : [])
      const mem = Array.isArray(memRes.data?.data) ? memRes.data.data : (Array.isArray(memRes.data) ? memRes.data : [])
      setMessages(channelId, list)
      setMembers(mem)
      setLoading(false)
      const unreadIds = list
        .filter(m => m.sender_id !== user?.id && (!Array.isArray(m.status) || !m.status.some(s => s.user_id === user?.id && s.read_at)))
        .map(m => m.id)
      if (unreadIds.length > 0) {
        getSocket()?.emit('message:read', { channel_id: channelId, message_ids: unreadIds })
      }
    }).catch(() => setLoading(false))
  }, [channelId, user?.id])

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'auto' })
  }, [channelMessages.length])

  useEffect(() => {
    const socket = getSocket()
    if (!socket) return
    const handleNewMessage = (msg) => {
      if (msg.channel_id === channelId && msg.sender_id !== user?.id) {
        socket.emit('message:read', { channel_id: channelId, message_ids: [msg.id] })
      }
    }
    socket.on('message:new', handleNewMessage)
    return () => socket.off('message:new', handleNewMessage)
  }, [channelId, user?.id])

  const handleCall = (type) => {
    if (!isDM || !dmPeer) { toast('Calls are available in direct messages'); return }
    if (!call?.startCall) { toast('Calling is not ready'); return }
    call.startCall(dmPeer.id, dmPeer.name, type)
  }

  const subtitle = typingInChannel.length > 0
    ? 'typing...'
    : isDM ? 'online' : `${members?.length || 0} members`

  return (
    <div className="flex flex-1 overflow-hidden">
      <div className="flex flex-col flex-1 overflow-hidden relative">
        {/* Topbar */}
        <div className="flex items-center justify-between px-4 py-2 border-b border-[#2a2d35] bg-[#111820] flex-shrink-0 z-10">
          <div className="flex items-center gap-3 min-w-0">
            <div className="w-10 h-10 rounded-full bg-[#2a3942] flex items-center justify-center text-brand-500 flex-shrink-0">
              {isDM ? <UserIcon /> : <HashIcon />}
            </div>
            <div className="min-w-0">
              <h2 className="font-semibold text-[15px] text-white truncate leading-tight">{channel?.name || 'loading...'}</h2>
              <p className={`text-[12px] truncate leading-tight ${typingInChannel.length > 0 ? 'text-brand-500' : 'text-gray-500'}`}>{subtitle}</p>
            </div>
          </div>
          <div className="flex items-center gap-1">
            <IconBtn title="Voice call" onClick={() => handleCall('audio')}><PhoneIcon /></IconBtn>
            <IconBtn title="Video call" onClick={() => handleCall('video')}><VideoIcon /></IconBtn>
            <IconBtn title="Search"><SearchIcon /></IconBtn>
            <IconBtn title="Info & members" onClick={() => setShowMembers(v => !v)}><InfoIcon /></IconBtn>
          </div>
        </div>

        {/* Messages */}
        <div ref={scrollRef} className="flex-1 overflow-y-auto bg-[#0b0d11] scroll-smooth" style={{ backgroundImage: 'radial-gradient(circle, #1a1d24 0.5px, transparent 0.5px)', backgroundSize: '24px 24px' }}>
          <div className="chat-area">
            {loading ? (
              <div className="flex flex-col items-center justify-center h-full gap-4">
                <div className="w-8 h-8 border-2 border-brand-500 border-t-transparent rounded-full animate-spin" />
                <p className="text-sm text-gray-500 animate-pulse">Loading conversation...</p>
              </div>
            ) : channelMessages.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-full text-center px-12">
                <div className="w-20 h-20 rounded-full bg-brand-500/5 flex items-center justify-center mb-6 text-brand-500">
                  {isDM ? <UserIcon /> : <HashIcon />}
                </div>
                <h3 className="text-xl font-bold text-white mb-2">{isDM ? channel?.name : `#${channel?.name || ''}`}</h3>
                <p className="text-gray-400 text-sm max-w-xs">Start the conversation by sending a message below.</p>
              </div>
            ) : (
              <>
                <div className="flex justify-center my-6">
                  <span className="px-3 py-1 rounded bg-[#1e2229] text-[11px] font-medium text-gray-500 uppercase tracking-wider">Messages are end-to-end encrypted</span>
                </div>
                {channelMessages.map(msg => (
                  <Message key={msg.id} msg={msg} channelId={channelId} />
                ))}
              </>
            )}
            <div ref={bottomRef} className="h-4" />
          </div>
        </div>

        {/* Input */}
        <div className="bg-[#12141a] p-1">
          <MessageInput channelId={channelId} />
        </div>
      </div>

      {showMembers && <MembersList />}
    </div>
  )
}
'@

Write-RepoFile "app\chat\[channelId]\page.js" $channelPage

Write-Host "`nFrontend files written successfully." -ForegroundColor Green

$runBuild = Read-Host "Run npm build now? (y/n)"
if ($runBuild -eq 'y') {
  npm run build
}

$doGit = Read-Host "Commit and push these web changes to main? (y/n)"
if ($doGit -eq 'y') {
  git add "components/Sidebar.js" "context/CallContext.js" "app/chat/layout.js" "app/chat/[channelId]/page.js"
  git commit -m "feat(web): add new chat modal and WebRTC calling"
  git push -u origin main
  Write-Host "`nPushed to main. Redeploy/rebuild on Hostinger." -ForegroundColor Green
} else {
  Write-Host "`nSkipped git. Review with: git diff" -ForegroundColor Yellow
}

Write-Host "`n================ BACKEND REQUIRED FOR CALLING ================" -ForegroundColor Magenta
Write-Host "Add this to backend/socket/index.js INSIDE io.on('connection', (socket) => { ... }):" -ForegroundColor Yellow
Write-Host @"
  socket.join('user:' + userId);

  socket.on('call:offer',  (d) => io.to('user:' + d.to).emit('call:offer',  { from: userId, fromName: d.fromName, type: d.type, sdp: d.sdp }));
  socket.on('call:answer', (d) => io.to('user:' + d.to).emit('call:answer', { from: userId, sdp: d.sdp }));
  socket.on('call:ice',    (d) => io.to('user:' + d.to).emit('call:ice',    { from: userId, candidate: d.candidate }));
  socket.on('call:reject', (d) => io.to('user:' + d.to).emit('call:reject', { from: userId }));
  socket.on('call:end',    (d) => io.to('user:' + d.to).emit('call:end',    { from: userId }));
"@ -ForegroundColor White

Write-Host "`nNotes:" -ForegroundColor Cyan
Write-Host "- New chat modal works with existing POST /channels/dm/:userId endpoint." -ForegroundColor Yellow
Write-Host "- Calling UI needs the backend socket signalling above to connect calls." -ForegroundColor Yellow
Write-Host "- HTTPS is required for mic/camera; your https domain is OK." -ForegroundColor Yellow
Write-Host "- After deploy, clear browser storage: localStorage.clear(); location.href='/login'" -ForegroundColor Yellow
