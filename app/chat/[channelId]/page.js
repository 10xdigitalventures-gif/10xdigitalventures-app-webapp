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
import { useGroupCall } from '@/context/GroupCallContext'

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
  const [showScrollBtn, setShowScrollBtn] = useState(false)
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
    {
      const el = scrollRef.current
      if (el) {
        const threshold = 200
        const distance = el.scrollHeight - el.scrollTop - el.clientHeight
        if (distance < threshold) el.scrollTop = el.scrollHeight
      }
    }
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

  const subtitle = typingInChannel.length > 0
    ? 'typing...'
    : isDM ? 'online' : `${members?.length || 0} members`

  return (
    <div className="flex flex-1 overflow-hidden h-full min-h-0">
      <div className="flex flex-col flex-1 overflow-hidden relative h-full min-h-0 min-w-0">
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
        <div ref={scrollRef} className="flex-1 min-h-0 overflow-y-auto bg-[#0b0d11] scroll-smooth" style={{ backgroundImage: 'radial-gradient(circle, #1a1d24 0.5px, transparent 0.5px)', backgroundSize: '24px 24px' }}>
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

        
        {showScrollBtn && (
          <button
            onClick={() => { const el = scrollRef.current; if (el) el.scrollTop = el.scrollHeight }}
            title="Scroll to bottom"
            aria-label="Scroll to bottom"
            className="absolute right-5 bottom-20 z-20 w-10 h-10 rounded-full bg-[#202c33] hover:bg-[#2a3942] text-white shadow-lg border border-white/10 flex items-center justify-center"
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polyline points="6 9 12 15 18 9"/></svg>
          </button>
        )}
        {/* Input */}
        <div className="bg-[#12141a] p-1 flex-shrink-0 z-10 border-t border-[#2a2d35]">
          <MessageInput channelId={channelId} />
        </div>
      </div>

      {showMembers && <MembersList />}
    </div>
  )
}