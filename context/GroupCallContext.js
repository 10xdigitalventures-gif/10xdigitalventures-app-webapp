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