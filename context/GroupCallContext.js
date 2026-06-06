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
  const [state, setState] = useState('idle')              // idle | active
  const [channelId, setChannelId] = useState(null)
  const [callType, setCallType] = useState('audio')
  const [incoming, setIncoming] = useState(null)          // { channel_id, from, fromName, type }
  const [peers, setPeers] = useState([])                  // [{user_id, name, hasVideo, muted, camOff}]
  const [muted, setMuted] = useState(false)
  const [camOff, setCamOff] = useState(false)
  const [hasLocalVideo, setHasLocalVideo] = useState(false)

  const localStreamRef = useRef(null)
  const localVideoRef = useRef(null)
  const peersRef = useRef(new Map())        // userId -> { pc, stream }
  const remoteRefs = useRef(new Map())      // userId -> HTMLVideoElement
  const channelIdRef = useRef(null)
  const callTypeRef = useRef('audio')
  const ringRef = useRef(null)
  const audioCtxRef = useRef(null)

  useEffect(() => { channelIdRef.current = channelId }, [channelId])
  useEffect(() => { callTypeRef.current = callType }, [callType])

  // ---------- Ringtone (same beep loop as 1:1) ----------
  const startRingtone = useCallback(() => {
    try {
      if (!audioCtxRef.current) audioCtxRef.current = new (window.AudioContext || window.webkitAudioContext)()
      const ctx = audioCtxRef.current
      if (ctx.state === 'suspended') ctx.resume()
      const beep = () => {
        const o = ctx.createOscillator(); const g = ctx.createGain()
        o.type = 'sine'; o.frequency.value = 520
        o.connect(g); g.connect(ctx.destination)
        g.gain.setValueAtTime(0.0001, ctx.currentTime)
        g.gain.exponentialRampToValueAtTime(0.08, ctx.currentTime + 0.05)
        g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.5)
        o.start(); o.stop(ctx.currentTime + 0.55)
      }
      beep(); ringRef.current = setInterval(beep, 1800)
    } catch (e) {}
  }, [])
  const stopRingtone = useCallback(() => { if (ringRef.current) { clearInterval(ringRef.current); ringRef.current = null } }, [])

  // ---------- Peer helpers ----------
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
    if (entry) { try { entry.pc.close() } catch (e) {}; peersRef.current.delete(uid) }
    remoteRefs.current.delete(uid)
  }, [])

  const getMedia = useCallback(async (type) => {
    let stream
    try {
      if (type === 'video') stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: true })
      else                  stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false })
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

  // ---------- Lifecycle ----------
  const cleanup = useCallback(() => {
    peersRef.current.forEach((entry) => { try { entry.pc.close() } catch (e) {} })
    peersRef.current.clear()
    remoteRefs.current.clear()
    if (localStreamRef.current) { localStreamRef.current.getTracks().forEach(t => t.stop()); localStreamRef.current = null }
    setPeers([]); setMuted(false); setCamOff(false); setHasLocalVideo(false)
    stopRingtone()
  }, [stopRingtone])

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
    const cid = incoming.channel_id; const type = incoming.type
    setIncoming(null); setChannelId(cid); setCallType(type); setState('active')
    stopRingtone()
    try {
      await getMedia(type)
      const sock = getSocket()
      if (sock) sock.emit('gcall:join', { channel_id: cid, name: user?.name || 'User', type })
    } catch (e) { toast.error('Microphone permission is required'); leaveCall() }
  }, [incoming, user, getMedia, leaveCall, stopRingtone])

  const declineIncoming = useCallback(() => { stopRingtone(); setIncoming(null) }, [stopRingtone])

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

  // ---------- Ringtone for incoming ----------
  useEffect(() => { if (incoming) startRingtone(); else stopRingtone() }, [incoming, startRingtone, stopRingtone])

  // Browser notification on incoming
  useEffect(() => {
    if (incoming && typeof Notification !== 'undefined' && Notification.permission === 'granted') {
      try {
        const n = new Notification('Group ' + (incoming.type === 'video' ? 'video' : 'voice') + ' call', { body: incoming.fromName || 'Someone is calling', tag: 'incoming-gcall', requireInteraction: true })
        n.onclick = () => { window.focus(); n.close() }
        return () => { try { n.close() } catch (e) {} }
      } catch (e) {}
    }
  }, [incoming])

  // ---------- Socket wiring ----------
  useEffect(() => {
    const sock = getSocket(); if (!sock) return

    const onRing = ({ channel_id, from, fromName, type }) => {
      if (state === 'active' && channelIdRef.current === channel_id) return
      if (from === user?.id) return
      if (incoming) return
      setIncoming({ channel_id, from, fromName, type })
    }

    const onPeers = async ({ channel_id, peers: list }) => {
      if (channel_id !== channelIdRef.current) return
      for (const p of list.slice(0, MAX_PEERS)) {
        if (peersRef.current.has(p.user_id)) continue
        const pc = makePeer(p.user_id, p.name)
        try {
          const offer = await pc.createOffer(); await pc.setLocalDescription(offer)
          sock.emit('gcall:offer', { channel_id, to: p.user_id, sdp: offer })
        } catch (e) { console.error('offer error', e) }
      }
    }

    const onJoined = ({ channel_id, user_id, name }) => {
      if (channel_id !== channelIdRef.current) return
      upsertPeer(user_id, { name })
    }
    const onLeft = ({ channel_id, user_id }) => {
      if (channel_id !== channelIdRef.current) return
      removePeerUI(user_id)
    }
    const onOffer = async ({ channel_id, from, sdp }) => {
      if (channel_id !== channelIdRef.current) return
      let entry = peersRef.current.get(from); let pc
      if (entry) pc = entry.pc; else pc = makePeer(from, 'User')
      try {
        await pc.setRemoteDescription(new RTCSessionDescription(sdp))
        const ans = await pc.createAnswer(); await pc.setLocalDescription(ans)
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

    sock.on('gcall:ring',   onRing)
    sock.on('gcall:peers',  onPeers)
    sock.on('gcall:joined', onJoined)
    sock.on('gcall:left',   onLeft)
    sock.on('gcall:offer',  onOffer)
    sock.on('gcall:answer', onAnswer)
    sock.on('gcall:ice',    onIce)
    sock.on('gcall:state',  onState)
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
      localVideoRef, setRemoteRef, channelName, incoming, acceptIncoming, declineIncoming
    }}>
      {children}
      <GroupCallRingModal />
      <GroupCallModal />
    </GroupCallContext.Provider>
  )
}

// ============================================================
// WhatsApp Desktop-style modal helpers
// ============================================================

function GLabeledBtn({ title, variant, onClick, children }) {
  const variants = {
    mute:      'bg-white/10 hover:bg-white/15 text-white',
    muted:     'bg-white text-[#0b141a]',
    accept:    'bg-[#1db791] hover:bg-[#17a884] text-white',
    decline:   'bg-[#f15c6d] hover:bg-[#e04658] text-white',
    end:       'bg-[#f15c6d] hover:bg-[#e04658] text-white',
    video:     'bg-white/10 hover:bg-white/15 text-white',
    videooff:  'bg-white text-[#0b141a]',
    neutral:   'bg-white/10 hover:bg-white/15 text-white',
  }
  const cls = variants[variant] || variants.neutral
  return (
    <button onClick={onClick} aria-label={title} className="flex flex-col items-center gap-2 group focus:outline-none">
      <span className={`w-14 h-14 rounded-full flex items-center justify-center transition-all duration-200 active:scale-95 group-focus-visible:ring-2 group-focus-visible:ring-white/40 ${cls}`}>{children}</span>
      <span className="text-[12px] text-white/70 group-hover:text-white/90 transition-colors">{title}</span>
    </button>
  )
}

function GroupCallRingModal() {
  const c = useGroupCall(); if (!c || !c.incoming) return null
  const { incoming, acceptIncoming, declineIncoming, channels } = c
  // Try to look up channel name from store
  const { channels: storeChannels } = useChatStore.getState ? { channels: useChatStore.getState().channels } : { channels: null }
  const chName = (storeChannels || []).find(x => x.id === incoming.channel_id)?.name

  return (
    <div className="fixed inset-0 z-[80] flex items-center justify-center bg-black/85 backdrop-blur-md p-4 animate-fade-in">
      <div className="bg-[#0b141a] rounded-2xl border border-white/10 shadow-2xl w-full max-w-[420px] overflow-hidden">
        <div className="flex items-center justify-between px-4 py-3 border-b border-white/5 bg-[#111b21]">
          <div className="flex items-center gap-2 text-[13px] text-white/70">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
            <span>End-to-end encrypted</span>
          </div>
          <span className="text-[12px] text-white/40 uppercase tracking-wider">{incoming.type === 'video' ? 'Group video' : 'Group voice'}</span>
        </div>

        <div className="flex flex-col items-center pt-14 pb-12 px-6 relative bg-gradient-to-b from-[#0b141a] to-[#0a1218]">
          <div className="relative">
            <span className="absolute inset-0 rounded-full bg-[#1db791]/20 animate-ping" />
            <span className="absolute inset-0 rounded-full bg-[#1db791]/10 animate-ping" style={{ animationDelay: '0.5s' }} />
            <div className="relative w-36 h-36 rounded-full bg-gradient-to-br from-[#1db791] to-[#17a884] flex items-center justify-center text-[44px] font-semibold text-white shadow-xl">
              {getInitials(chName || incoming.fromName)}
            </div>
          </div>
          <div className="text-center mt-6">
            <div className="text-[22px] font-semibold text-white tracking-tight">{chName || 'Group call'}</div>
            <div className="text-[14px] text-white/55 mt-1.5">{incoming.fromName} is calling...</div>
          </div>
        </div>

        <div className="flex items-start justify-center gap-10 pt-4 pb-6 px-4 bg-[#0a1218] border-t border-white/5">
          <GLabeledBtn title="Decline" variant="decline" onClick={declineIncoming}>
            <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7 2 2 0 0 1 1.72 2v3a2 2 0 0 1-2.18 2A19.79 19.79 0 0 1 8.63 19.24"/><line x1="23" y1="1" x2="1" y2="23"/></svg>
          </GLabeledBtn>
          <GLabeledBtn title="Accept" variant="accept" onClick={acceptIncoming}>
            <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
          </GLabeledBtn>
        </div>
      </div>
    </div>
  )
}

function PeerTile({ peer, setRemoteRef }) {
  const showVideo = peer.hasVideo && !peer.camOff
  return (
    <div className="relative bg-[#0a1218] rounded-xl overflow-hidden aspect-video flex items-center justify-center border border-white/5">
      <video ref={(el) => setRemoteRef(peer.user_id, el)} autoPlay playsInline className={showVideo ? 'absolute inset-0 w-full h-full object-cover' : 'hidden'} />
      {!showVideo && (
        <div className="w-20 h-20 rounded-full bg-gradient-to-br from-[#1db791] to-[#17a884] flex items-center justify-center text-2xl font-semibold text-white shadow-lg">
          {getInitials(peer.name)}
        </div>
      )}
      <div className="absolute bottom-2 left-2 right-2 flex items-center justify-between text-[12px] text-white drop-shadow">
        <span className="bg-black/40 backdrop-blur px-2 py-0.5 rounded">{peer.name}</span>
        {peer.muted && (
          <span className="bg-black/40 backdrop-blur w-6 h-6 rounded-full flex items-center justify-center">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#f87171" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="1" y1="1" x2="23" y2="23"/><path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6"/><path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2a7 7 0 0 1-.11 1.23"/><line x1="12" y1="19" x2="12" y2="23"/></svg>
          </span>
        )}
      </div>
    </div>
  )
}

function GroupCallModal() {
  const g = useGroupCall()
  if (!g || g.state !== 'active') return null
  const { peers, channelName, muted, camOff, hasLocalVideo, toggleMute, toggleCam, leaveCall, localVideoRef, setRemoteRef, callType } = g

  const totalTiles = peers.length + 1
  const cols = totalTiles <= 1 ? 1 : totalTiles <= 4 ? 2 : 3

  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/90 backdrop-blur-md p-4 animate-fade-in">
      <div className="bg-[#0b141a] rounded-2xl border border-white/10 shadow-2xl w-full max-w-5xl overflow-hidden flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-3 bg-[#111b21] border-b border-white/5">
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-2 text-[13px] text-white/70">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
              <span>End-to-end encrypted</span>
            </div>
          </div>
          <div className="text-right">
            <div className="text-[14px] font-semibold text-white truncate max-w-[280px]">{channelName}</div>
            <div className="text-[11px] text-white/40 uppercase tracking-wider">{callType === 'video' ? 'Group video' : 'Group voice'}  -  {totalTiles} participant{totalTiles === 1 ? '' : 's'}</div>
          </div>
        </div>

        {/* Grid */}
        <div className="bg-black p-3 max-h-[70vh] overflow-y-auto">
          <div className="grid gap-2" style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))` }}>
            {/* Self tile */}
            <div className="relative bg-[#0a1218] rounded-xl overflow-hidden aspect-video flex items-center justify-center border border-white/10">
              <video ref={localVideoRef} autoPlay playsInline muted className={hasLocalVideo && !camOff ? 'absolute inset-0 w-full h-full object-cover' : 'hidden'} />
              {!(hasLocalVideo && !camOff) && (
                <div className="w-20 h-20 rounded-full bg-gradient-to-br from-[#1db791] to-[#17a884] flex items-center justify-center text-2xl font-semibold text-white shadow-lg">You</div>
              )}
              <div className="absolute bottom-2 left-2 right-2 flex items-center justify-between text-[12px] text-white drop-shadow">
                <span className="bg-black/40 backdrop-blur px-2 py-0.5 rounded">You</span>
                {muted && (
                  <span className="bg-black/40 backdrop-blur w-6 h-6 rounded-full flex items-center justify-center">
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#f87171" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="1" y1="1" x2="23" y2="23"/><path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6"/><path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2a7 7 0 0 1-.11 1.23"/><line x1="12" y1="19" x2="12" y2="23"/></svg>
                  </span>
                )}
              </div>
            </div>

            {peers.map(p => <PeerTile key={p.user_id} peer={p} setRemoteRef={setRemoteRef} />)}
          </div>

          {peers.length === 0 && (
            <div className="text-center text-white/50 text-sm mt-4">Waiting for others to join...</div>
          )}
        </div>

        {/* Controls */}
        <div className="flex items-start justify-center gap-8 pt-4 pb-6 px-4 bg-[#0a1218] border-t border-white/5">
          <GLabeledBtn title={muted ? 'Unmute' : 'Mute'} variant={muted ? 'muted' : 'mute'} onClick={toggleMute}>
            {muted
              ? <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="1" y1="1" x2="23" y2="23"/><path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6"/><path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2a7 7 0 0 1-.11 1.23"/><line x1="12" y1="19" x2="12" y2="23"/></svg>
              : <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/></svg>}
          </GLabeledBtn>

          {hasLocalVideo && (
            <GLabeledBtn title={camOff ? 'Camera on' : 'Camera off'} variant={camOff ? 'videooff' : 'video'} onClick={toggleCam}>
              {camOff
                ? <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="1" y1="1" x2="23" y2="23"/><path d="M16 16H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h2m4 0h6a2 2 0 0 1 2 2v.34m1.66 1.66L23 7v10"/></svg>
                : <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>}
            </GLabeledBtn>
          )}

          <GLabeledBtn title="Leave" variant="end" onClick={leaveCall}>
            <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7 2 2 0 0 1 1.72 2v3a2 2 0 0 1-2.18 2A19.79 19.79 0 0 1 8.63 19.24"/><line x1="23" y1="1" x2="1" y2="23"/></svg>
          </GLabeledBtn>
        </div>
      </div>
    </div>
  )
}