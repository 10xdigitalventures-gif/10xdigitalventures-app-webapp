# ============================================================================
#  10x Chat WEBAPP — calling upgrades + Calls tab
#   - context/CallContext.js : incoming-call notify (ringtone + browser
#       notification), ask permissions early, camera-optional (audio still
#       connects if no camera), show video only for whoever's camera is on.
#   - components/CallsModal.js : the "Calls" tab — pick a contact to call.
#   - components/IconRail.js   : wire the phone (Calls) button to open it.
#
#  Run from the WEBAPP repo root (10xdigitalventures-app-webapp):
#      cd path\to\10xdigitalventures-app-webapp
#      powershell -ExecutionPolicy Bypass -File .\upgrade-calling.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
if (-not (Test-Path ".\package.json")) {
  Write-Host "ERROR: run this from the webapp repo root (package.json not found)." -ForegroundColor Red
  exit 1
}

function Write-RepoFile($Path, $Content) {
  $full = Join-Path (Get-Location) $Path
  $dir  = Split-Path $full -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if ((Test-Path $full) -and -not (Test-Path "$full.bak4")) { Copy-Item $full "$full.bak4" -Force; Write-Host "  backed up -> $Path.bak4" -ForegroundColor DarkGray }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($full, $Content, $enc)
  Write-Host "  wrote $Path" -ForegroundColor Green
}

Write-Host "`n[1/3] context/CallContext.js ..." -ForegroundColor Cyan
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
  const [state, setState] = useState('idle')        // idle | calling | ringing | active
  const [callType, setCallType] = useState('audio') // audio | video
  const [peer, setPeer] = useState(null)            // { id, name }
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

  // Ask for notification permission up front so incoming calls can alert.
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
      beep()
      ringRef.current = setInterval(beep, 1600)
    } catch (e) {}
  }, [])

  const stopRingtone = useCallback(() => {
    if (ringRef.current) { clearInterval(ringRef.current); ringRef.current = null }
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
    pc.ontrack = (e) => {
      const stream = e.streams[0]
      attachRemote(stream)
      const vt = stream.getVideoTracks()[0]
      if (vt) {
        const upd = () => setRemoteVideoOn(!!vt.enabled && !vt.muted)
        vt.onmute = upd; vt.onunmute = upd; vt.onended = () => setRemoteVideoOn(false)
        upd()
      } else {
        setRemoteVideoOn(false)
      }
    }
    pc.onconnectionstatechange = () => {
      if (['disconnected', 'failed', 'closed'].includes(pc.connectionState)) finish()
    }
    pcRef.current = pc
    return pc
  }, [finish])

  // Camera-optional: if video is wanted but no camera / denied, fall back to
  // audio-only so the call still connects.
  const getMedia = useCallback(async (type) => {
    let stream
    if (type === 'video') {
      try {
        stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: true })
      } catch (e) {
        toast('No camera available - joining with audio only')
        stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false })
      }
    } else {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false })
    }
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
      const offer = await pc.createOffer()
      await pc.setLocalDescription(offer)
      getSocket()?.emit('call:offer', { to: targetId, fromName: user?.name, type, sdp: offer })
    } catch (err) {
      console.error('startCall', err)
      toast.error('Microphone permission is required to call')
      endCall(false)
    }
  }, [state, user, getMedia, createPeer, endCall])

  const acceptCall = useCallback(async () => {
    const offer = pendingOfferRef.current
    if (!offer || !peer?.id) return
    stopRingtone()
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
    } catch (err) {
      console.error('acceptCall', err)
      toast.error('Microphone permission is required to answer')
      endCall()
    }
  }, [peer, callType, getMedia, createPeer, endCall, stopRingtone])

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
    const tracks = s.getVideoTracks(); if (!tracks.length) return
    tracks.forEach(t => { t.enabled = !t.enabled })
    setCamOff(c => !c)
  }

  // ring while incoming/outgoing
  useEffect(() => {
    if (state === 'ringing' || state === 'calling') startRingtone()
    else stopRingtone()
  }, [state, startRingtone, stopRingtone])

  // browser notification for an incoming call (esp. when tab is in background)
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
  const localPipVisible = hasLocalVideo && !camOff

  return (
    <div className="fixed inset-0 z-[60] bg-[#0b141a] flex flex-col items-center justify-between py-10">
      <audio ref={remoteAudioRef} autoPlay />

      {/* remote video fills the screen only when the other side's camera is on */}
      <video ref={remoteVideoRef} autoPlay playsInline className={remoteVideoOn ? 'absolute inset-0 w-full h-full object-cover bg-black' : 'hidden'} />
      {/* local preview (only if we actually have a camera and it's on) */}
      <video ref={localVideoRef} autoPlay playsInline muted className={localPipVisible ? 'absolute bottom-28 right-6 w-32 h-44 object-cover rounded-xl border border-white/20 bg-black z-10' : 'hidden'} />

      {/* avatar shown whenever there is no remote video (audio call, or their camera off) */}
      {!remoteVideoOn && (
        <div className="relative z-10 flex flex-col items-center gap-4 mt-10">
          <div className="w-28 h-28 rounded-full bg-brand-500 flex items-center justify-center text-3xl font-semibold text-[#06291f]">
            {getInitials(peer?.name)}
          </div>
          <div className="text-center">
            <div className="text-2xl font-semibold text-white">{peer?.name || 'Unknown'}</div>
            <div className="text-sm text-gray-400 mt-1 animate-pulse">{statusText}</div>
          </div>
        </div>
      )}

      {remoteVideoOn && (
        <div className="absolute top-6 left-0 right-0 text-center z-10">
          <div className="text-lg font-semibold text-white drop-shadow">{peer?.name || 'Unknown'}</div>
          <div className="text-xs text-gray-200 drop-shadow">{statusText}</div>
        </div>
      )}

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
  )
}
'@
Write-RepoFile "context\CallContext.js" $callCtx

Write-Host "`n[2/3] components/CallsModal.js ..." -ForegroundColor Cyan
$callsModal = @'
'use client'

import { useEffect, useState } from 'react'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import { getInitials, avatarColor } from '@/lib/chatFormat'
import { useCall } from '@/context/CallContext'

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

  const placeCall = (u, type) => {
    if (!call?.startCall) return
    call.startCall(u.id, u.name, type)
    onClose?.()
  }

  const filtered = users.filter(u => {
    const s = q.toLowerCase()
    return !s || (u.name || '').toLowerCase().includes(s) || (u.email || '').toLowerCase().includes(s)
  })

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-16" onClick={onClose}>
      <div className="w-full max-w-md bg-[#111820] rounded-xl border border-white/10 shadow-2xl overflow-hidden" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between px-4 py-3 border-b border-white/10">
          <span className="text-[15px] font-semibold text-white">Start a call</span>
          <button onClick={onClose} aria-label="Close" className="text-gray-400 hover:text-white">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
          </button>
        </div>

        <div className="p-3">
          <div className="flex items-center gap-2 bg-[#202c33] rounded-lg px-3 py-2">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#8696a0" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
            <input autoFocus value={q} onChange={e => setQ(e.target.value)} placeholder="Search people" className="bg-transparent border-none outline-none text-sm text-white placeholder-gray-500 w-full" />
          </div>
        </div>

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
              <button onClick={() => placeCall(u, 'audio')} title="Voice call" aria-label="Voice call" className="w-9 h-9 flex items-center justify-center rounded-full text-brand-500 hover:bg-white/5">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
              </button>
              <button onClick={() => placeCall(u, 'video')} title="Video call" aria-label="Video call" className="w-9 h-9 flex items-center justify-center rounded-full text-brand-500 hover:bg-white/5">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
'@
Write-RepoFile "components\CallsModal.js" $callsModal

Write-Host "`n[3/3] components/IconRail.js (wire Calls button) ..." -ForegroundColor Cyan
$iconRail = @'
'use client'

import { useState } from 'react'
import { useRouter, usePathname } from 'next/navigation'
import useChatStore from '@/store/chatStore'
import { getInitials } from '@/lib/chatFormat'
import CallsModal from '@/components/CallsModal'

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
  const [showCalls, setShowCalls] = useState(false)

  const logout = () => {
    localStorage.removeItem('token')
    localStorage.removeItem('user')
    router.replace('/login')
  }

  return (
    <>
      <nav className="w-[60px] bg-[#0c1016] border-r border-white/10 flex flex-col items-center py-3 gap-2 flex-shrink-0">
        <button onClick={() => router.push('/profile')} title="Profile" aria-label="Profile" className="w-9 h-9 rounded-full bg-brand-500 text-[#06291f] font-bold flex items-center justify-center mb-2 text-sm">
          {getInitials(user?.name)}
        </button>

        <RailButton title="Chats" active={pathname.startsWith('/chat')} onClick={() => router.push('/chat')}>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/></svg>
        </RailButton>

        <RailButton title="Calls" active={showCalls} onClick={() => setShowCalls(true)}>
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

      {showCalls && <CallsModal onClose={() => setShowCalls(false)} />}
    </>
  )
}
'@
Write-RepoFile "components\IconRail.js" $iconRail

Write-Host "`nDone (webapp)." -ForegroundColor Cyan
$doGit = Read-Host "Commit and push the webapp changes? (y/n)"
if ($doGit -eq 'y') {
  git add "context/CallContext.js" "components/CallsModal.js" "components/IconRail.js"
  git commit -m "feat(web): calls tab + incoming-call notify/ringtone, early permissions, camera-optional video"
  $push = Read-Host "Push now? (y/n)"
  if ($push -eq 'y') { git push; Write-Host "`nPushed." -ForegroundColor Green }
  else { Write-Host "`nCommitted locally. Push later with: git push" -ForegroundColor Yellow }
} else {
  Write-Host "`nSkipped git. Review with: git diff" -ForegroundColor Yellow
}
Write-Host "`nNotes: needs HTTPS (you have it). STUN-only works on most networks;" -ForegroundColor Yellow
Write-Host "for strict/corporate NAT add a TURN server later." -ForegroundColor Yellow