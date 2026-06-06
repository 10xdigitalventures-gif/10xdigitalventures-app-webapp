'use client'

import { createContext, useContext, useEffect, useRef, useState, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import toast from 'react-hot-toast'
import useChatStore from '@/store/chatStore'
import { getSocket } from '@/lib/socket'
import { getInitials } from '@/lib/chatFormat'
import api from '@/lib/api'

const ICE = { iceServers: [{ urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'] }] }
const CallContext = createContext(null)
export const useCall = () => useContext(CallContext)

export function CallProvider({ children }) {
  const { user, channels } = useChatStore()
  const router = useRouter()
  const [state, setState] = useState('idle')
  const [callType, setCallType] = useState('audio')
  const [peer, setPeer] = useState(null)
  const [endReason, setEndReason] = useState(null)
  const [callDuration, setCallDuration] = useState(0)
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
  const endTimerRef = useRef(null)

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
    if (loggedRef.current || !peerRef.current) return null
    loggedRef.current = true
    const answered = answeredRef.current
    const duration = answered && startTsRef.current ? Math.round((Date.now() - startTsRef.current) / 1000) : 0
    const direction = callerRef.current ? 'out' : 'in'
    const status = answered ? 'answered' : (declinedRef.current ? 'declined' : (callerRef.current ? 'no_answer' : 'missed'))
    api.post('/calls', { peer_id: peerRef.current.id, peer_name: peerRef.current.name, type: callTypeRef.current, direction, status, duration }).catch(() => {})
    return { duration, status }
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

  const finish = useCallback(() => {
    const info = logCall()
    cleanup()
    let reason = 'completed'
    if (info) {
      if (info.status === 'declined') reason = 'declined'
      else if (info.status === 'no_answer') reason = 'no_answer'
      else if (info.status === 'missed') reason = 'missed'
    }
    setEndReason(reason)
    setCallDuration(info?.duration || 0)
    setState('ended')
    if (endTimerRef.current) clearTimeout(endTimerRef.current)
    endTimerRef.current = setTimeout(() => { setState('idle'); setPeer(null); setEndReason(null) }, 15000)
  }, [logCall, cleanup])

  const dismissEnded = useCallback(() => {
    if (endTimerRef.current) { clearTimeout(endTimerRef.current); endTimerRef.current = null }
    setState('idle'); setPeer(null); setEndReason(null)
  }, [])

  const endCall = useCallback((notify = true) => {
    if (notify && peerRef.current?.id) getSocket()?.emit('call:end', { to: peerRef.current.id })
    finish()
  }, [finish])

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
    if (!targetId || (state !== 'idle' && state !== 'ended')) return
    if (state === 'ended') dismissEnded()
    callerRef.current = true; answeredRef.current = false; declinedRef.current = false; loggedRef.current = false; startTsRef.current = 0
    setPeer({ id: targetId, name: targetName }); setCallType(type); setState('calling')
    try {
      const stream = await getMedia(type)
      const pc = createPeer(targetId)
      stream.getTracks().forEach(t => pc.addTrack(t, stream))
      const offer = await pc.createOffer(); await pc.setLocalDescription(offer)
      getSocket()?.emit('call:offer', { to: targetId, fromName: user?.name, type, sdp: offer })
    } catch (err) { console.error(err); toast.error('Microphone permission is required to call'); endCall(false) }
  }, [state, user, getMedia, createPeer, endCall, dismissEnded])

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

  const findDMChannelWith = useCallback((peerId) => {
    if (!peerId || !channels) return null
    const dm = channels.find(c => c.type === 'dm' && (c.peer_id === peerId || c.peer === peerId))
    return dm ? dm.id : null
  }, [channels])

  const openChat = useCallback(() => {
    const cid = findDMChannelWith(peerRef.current?.id)
    if (cid) router.push('/chat/' + cid)
    dismissEnded()
  }, [findDMChannelWith, router, dismissEnded])

  const callAgain = useCallback(() => {
    const p = peerRef.current; const t = callTypeRef.current
    if (!p) { dismissEnded(); return }
    dismissEnded()
    setTimeout(() => startCall(p.id, p.name, t), 100)
  }, [startCall, dismissEnded])

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
      if (pcRef.current || (state !== 'idle' && state !== 'ended')) { socket.emit('call:reject', { to: from }); return }
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
    <CallContext.Provider value={{
      state, callType, peer, muted, camOff, hasLocalVideo, remoteVideoOn, endReason, callDuration,
      startCall, acceptCall, rejectCall, endCall, toggleMute, toggleCam,
      openChat, callAgain, dismissEnded,
      localVideoRef, remoteVideoRef, remoteAudioRef
    }}>
      {children}
      <CallModal />
    </CallContext.Provider>
  )
}

// ---------------------------------------------------------------
// WhatsApp Desktop-style call modal
// Reasoning rules applied:
//   - Touch & Interaction: 56x56 control buttons, 16px gaps
//   - Hierarchy: avatar 144 (lg) -> name 2xl -> status sm
//   - Labeling: every action has a visible label under the icon
//   - Press feedback: hover bg + slight scale on press
//   - Color contrast: white-on-#0b141a is 14:1 (AAA)
//   - Animation: pulsing ring while calling (meaningful motion)
// ---------------------------------------------------------------

function LabeledBtn({ title, variant, onClick, children }) {
  // variant: 'mute' | 'accept' | 'decline' | 'end' | 'video' | 'message' | 'callagain' | 'close' | 'neutral'
  const variants = {
    mute:      'bg-white/10 hover:bg-white/15 text-white',
    muted:     'bg-white text-[#0b141a]',
    accept:    'bg-[#1db791] hover:bg-[#17a884] text-white',
    decline:   'bg-[#f15c6d] hover:bg-[#e04658] text-white',
    end:       'bg-[#f15c6d] hover:bg-[#e04658] text-white',
    video:     'bg-white/10 hover:bg-white/15 text-white',
    videooff:  'bg-white text-[#0b141a]',
    message:   'bg-white/10 hover:bg-white/15 text-white',
    callagain: 'bg-[#1db791] hover:bg-[#17a884] text-white',
    close:     'bg-white/10 hover:bg-white/15 text-white',
    neutral:   'bg-white/10 hover:bg-white/15 text-white',
  }
  const cls = variants[variant] || variants.neutral
  return (
    <button
      onClick={onClick}
      aria-label={title}
      className="flex flex-col items-center gap-2 group focus:outline-none"
    >
      <span className={`w-14 h-14 rounded-full flex items-center justify-center transition-all duration-200 active:scale-95 group-focus-visible:ring-2 group-focus-visible:ring-white/40 ${cls}`}>
        {children}
      </span>
      <span className="text-[12px] text-white/70 group-hover:text-white/90 transition-colors">{title}</span>
    </button>
  )
}

function formatDur(s) {
  if (!s) return ''
  const m = Math.floor(s / 60), sec = s % 60
  return m + ':' + String(sec).padStart(2, '0')
}

function CallModal() {
  const c = useCall()
  if (!c || c.state === 'idle') return null
  const {
    state, callType, peer, muted, camOff, hasLocalVideo, remoteVideoOn,
    endReason, callDuration,
    acceptCall, rejectCall, endCall, toggleMute, toggleCam,
    openChat, callAgain, dismissEnded,
    localVideoRef, remoteVideoRef, remoteAudioRef
  } = c

  const isVideo = callType === 'video'

  // ============== ENDED SCREEN ==============
  if (state === 'ended') {
    const label = endReason === 'declined'  ? 'Call declined'
                : endReason === 'no_answer' ? 'No answer'
                : endReason === 'missed'    ? 'Missed call'
                : callDuration > 0          ? 'Call ended  -  ' + formatDur(callDuration)
                : 'Call ended'
    return (
      <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/85 backdrop-blur-md p-4 animate-fade-in">
        <div className="bg-[#0b141a] rounded-2xl border border-white/10 shadow-2xl w-full max-w-[420px] overflow-hidden">
          {/* Header */}
          <div className="flex items-center justify-between px-4 py-3 border-b border-white/5 bg-[#111b21]">
            <div className="flex items-center gap-2 text-[13px] text-white/70">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
              </svg>
              <span>End-to-end encrypted</span>
            </div>
            <button onClick={dismissEnded} title="Close" aria-label="Close"
              className="w-8 h-8 flex items-center justify-center rounded-full text-white/50 hover:text-white hover:bg-white/10 transition-colors">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
              </svg>
            </button>
          </div>

          {/* Body */}
          <div className="flex flex-col items-center pt-14 pb-12 px-6">
            <div className="w-36 h-36 rounded-full bg-gradient-to-br from-[#1db791] to-[#17a884] flex items-center justify-center text-[44px] font-semibold text-white shadow-xl">
              {getInitials(peer?.name)}
            </div>
            <div className="text-center mt-6">
              <div className="text-[22px] font-semibold text-white tracking-tight">{peer?.name || 'Unknown'}</div>
              <div className="text-[14px] text-white/55 mt-1.5">{label}</div>
            </div>
          </div>

          {/* Actions */}
          <div className="flex items-start justify-around pt-3 pb-6 px-4 bg-[#0a1218] border-t border-white/5">
            <LabeledBtn title="Message" variant="message" onClick={openChat}>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
              </svg>
            </LabeledBtn>
            <LabeledBtn title="Call again" variant="callagain" onClick={callAgain}>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/>
              </svg>
            </LabeledBtn>
            <LabeledBtn title="Close" variant="close" onClick={dismissEnded}>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
              </svg>
            </LabeledBtn>
          </div>
        </div>
      </div>
    )
  }

  // ============== ACTIVE / CALLING / RINGING ==============
  const statusText = state === 'calling' ? 'Calling...'
                   : state === 'ringing' ? `Incoming ${isVideo ? 'video' : 'voice'} call`
                   : 'Connected'
  const showStage = remoteVideoOn && state === 'active'
  const localPip  = hasLocalVideo && !camOff
  const isPulsing = state === 'calling' || state === 'ringing'

  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/85 backdrop-blur-md p-4 animate-fade-in">
      <div className={`bg-[#0b141a] rounded-2xl border border-white/10 shadow-2xl w-full overflow-hidden ${showStage ? 'max-w-3xl' : 'max-w-[420px]'}`}>
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-white/5 bg-[#111b21]">
          <div className="flex items-center gap-2 text-[13px] text-white/70">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
            </svg>
            <span>End-to-end encrypted</span>
          </div>
          <span className="text-[12px] text-white/40 uppercase tracking-wider">{isVideo ? 'Video' : 'Voice'}</span>
        </div>

        <audio ref={remoteAudioRef} autoPlay />

        {/* Body */}
        <div className={showStage
          ? 'relative bg-black aspect-video'
          : 'flex flex-col items-center pt-14 pb-12 px-6 relative bg-gradient-to-b from-[#0b141a] to-[#0a1218]'
        }>
          <video ref={remoteVideoRef} autoPlay playsInline className={showStage ? 'absolute inset-0 w-full h-full object-cover' : 'hidden'} />
          <video ref={localVideoRef} autoPlay playsInline muted className={localPip
            ? (showStage
                ? 'absolute bottom-3 right-3 w-32 h-44 object-cover rounded-xl border-2 border-white/20 z-10 shadow-2xl'
                : 'absolute top-3 right-3 w-20 h-28 object-cover rounded-lg border border-white/20 z-10')
            : 'hidden'} />

          {showStage ? (
            <div className="absolute top-3 left-4 z-10">
              <div className="text-[16px] font-semibold text-white drop-shadow">{peer?.name || 'Unknown'}</div>
              <div className="text-[12px] text-white/80 drop-shadow">{statusText}</div>
            </div>
          ) : (
            <>
              {/* Avatar with pulsing ring */}
              <div className="relative">
                {isPulsing && (
                  <>
                    <span className="absolute inset-0 rounded-full bg-[#1db791]/20 animate-ping" />
                    <span className="absolute inset-0 rounded-full bg-[#1db791]/10 animate-ping" style={{ animationDelay: '0.5s' }} />
                  </>
                )}
                <div className="relative w-36 h-36 rounded-full bg-gradient-to-br from-[#1db791] to-[#17a884] flex items-center justify-center text-[44px] font-semibold text-white shadow-xl">
                  {getInitials(peer?.name)}
                </div>
              </div>
              <div className="text-center mt-6">
                <div className="text-[22px] font-semibold text-white tracking-tight">{peer?.name || 'Unknown'}</div>
                <div className="text-[14px] text-white/55 mt-1.5">{statusText}</div>
              </div>
            </>
          )}
        </div>

        {/* Controls */}
        <div className="flex items-start justify-center gap-8 pt-4 pb-6 px-4 bg-[#0a1218] border-t border-white/5">
          {state === 'ringing' ? (
            <>
              <LabeledBtn title="Decline" variant="decline" onClick={rejectCall}>
                <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7 2 2 0 0 1 1.72 2v3a2 2 0 0 1-2.18 2A19.79 19.79 0 0 1 8.63 19.24"/>
                  <line x1="23" y1="1" x2="1" y2="23"/>
                </svg>
              </LabeledBtn>
              <LabeledBtn title="Accept" variant="accept" onClick={acceptCall}>
                <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/>
                </svg>
              </LabeledBtn>
            </>
          ) : (
            <>
              <LabeledBtn title={muted ? 'Unmute' : 'Mute'} variant={muted ? 'muted' : 'mute'} onClick={toggleMute}>
                {muted
                  ? <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="1" y1="1" x2="23" y2="23"/><path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6"/><path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2a7 7 0 0 1-.11 1.23"/><line x1="12" y1="19" x2="12" y2="23"/></svg>
                  : <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/></svg>}
              </LabeledBtn>

              {hasLocalVideo && (
                <LabeledBtn title={camOff ? 'Camera on' : 'Camera off'} variant={camOff ? 'videooff' : 'video'} onClick={toggleCam}>
                  {camOff
                    ? <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="1" y1="1" x2="23" y2="23"/><path d="M16 16H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h2m4 0h6a2 2 0 0 1 2 2v.34m1.66 1.66L23 7v10"/></svg>
                    : <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>}
                </LabeledBtn>
              )}

              <LabeledBtn title="End call" variant="end" onClick={() => endCall(true)}>
                <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7 2 2 0 0 1 1.72 2v3a2 2 0 0 1-2.18 2A19.79 19.79 0 0 1 8.63 19.24"/>
                  <line x1="23" y1="1" x2="1" y2="23"/>
                </svg>
              </LabeledBtn>
            </>
          )}
        </div>
      </div>
    </div>
  )
}