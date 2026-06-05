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