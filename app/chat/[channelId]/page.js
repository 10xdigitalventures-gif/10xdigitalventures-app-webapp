'use client'
import { useEffect, useRef, useState } from 'react'
import { useParams } from 'next/navigation'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import Message from '@/components/Message'
import MessageInput from '@/components/MessageInput'
import MembersList from '@/components/MembersList'
import { getSocket } from '@/lib/socket'

export default function ChannelPage() {
  const { channelId } = useParams()
  const { channels, messages, setMessages, setMembers, setActiveChannel, typingUsers, user, updateMessage } = useChatStore()
  const [loading, setLoading] = useState(true)
  const bottomRef = useRef(null)
  const scrollRef = useRef(null)

  const channel = channels.find(c => c.id === channelId)
  const channelMessages = messages[channelId] || []

  const typingInChannel = typingUsers[channelId]
    ? [...typingUsers[channelId]].filter(id => id !== user?.id)
    : []

  useEffect(() => {
    if (!channelId) return
    setActiveChannel(channel)
    setLoading(true)

    Promise.all([
      api.get(\`/messages/\${channelId}\`),
      api.get(\`/channels/\${channelId}/members\`),
    ]).then(([msgRes, memRes]) => {
      setMessages(channelId, msgRes.data.data)
      setMembers(memRes.data.data)
      setLoading(false)

      // Emit read status for all unread messages
      const unreadIds = msgRes.data.data
        .filter(m => m.sender_id !== user?.id && (!m.status || !m.status.some(s => s.user_id === user?.id && s.read_at)))
        .map(m => m.id);

      if (unreadIds.length > 0) {
        const socket = getSocket();
        socket.emit('message:read', { channel_id: channelId, message_ids: unreadIds });
      }
    }).catch(() => setLoading(false))
  }, [channelId, user?.id])

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'auto' })
  }, [channelMessages.length])

  // Mark incoming messages as read if we are in the channel
  useEffect(() => {
    const socket = getSocket();
    const handleNewMessage = (msg) => {
       if (msg.channel_id === channelId && msg.sender_id !== user?.id) {
         socket.emit('message:read', { channel_id: channelId, message_ids: [msg.id] });
       }
    };
    socket.on('message:new', handleNewMessage);
    return () => socket.off('message:new', handleNewMessage);
  }, [channelId, user?.id]);

  return (
    <div className="flex flex-1 overflow-hidden">
      <div className="flex flex-col flex-1 overflow-hidden relative">
        {/* Channel Header */}
        <div className="flex items-center justify-between px-6 py-3 border-b border-[#2a2d35] bg-[#12141a] flex-shrink-0 z-10 shadow-sm">
          <div className="flex items-center gap-4">
            <div className="w-10 h-10 rounded-full bg-brand-500/10 flex items-center justify-center text-brand-500 font-bold text-lg">
              {channel?.type === 'dm' ? '👤' : '#'}
            </div>
            <div>
              <h2 className="font-bold text-[16px] text-white leading-tight">{channel?.name || 'loading...'}</h2>
              <div className="flex items-center gap-2 mt-0.5">
                {typingInChannel.length > 0 ? (
                  <p className="text-[12px] text-brand-500 animate-pulse font-medium">typing...</p>
                ) : (
                  <p className="text-[12px] text-gray-500">
                    {channel?.type === 'dm' ? 'Online' : \`\${channel?.topic || 'Digital Workspace'}\`}
                  </p>
                )}
              </div>
            </div>
          </div>

          <div className="flex items-center gap-4 text-gray-400">
            <button className="hover:text-white transition-colors">🔍</button>
            <button className="hover:text-white transition-colors">📞</button>
            <button className="hover:text-white transition-colors">📹</button>
          </div>
        </div>

        {/* Messages */}
        <div
          ref={scrollRef}
          className="flex-1 overflow-y-auto bg-[#0b0d11] scroll-smooth"
          style={{ backgroundImage: 'radial-gradient(circle, #1a1d24 0.5px, transparent 0.5px)', backgroundSize: '24px 24px' }}
        >
          <div className="chat-area">
            {loading ? (
              <div className="flex flex-col items-center justify-center h-full gap-4">
                <div className="w-8 h-8 border-2 border-brand-500 border-t-transparent rounded-full animate-spin" />
                <p className="text-sm text-gray-500 animate-pulse">Loading conversation...</p>
              </div>
            ) : channelMessages.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-full text-center px-12">
                <div className="w-20 h-20 rounded-full bg-brand-500/5 flex items-center justify-center text-4xl mb-6">
                   {channel?.type === 'dm' ? '👋' : '🏢'}
                </div>
                <h3 className="text-xl font-bold text-white mb-2">Welcome to #{channel?.name}</h3>
                <p className="text-gray-400 text-sm max-w-xs">Start the conversation by sending a message below.</p>
              </div>
            ) : (
              <>
                 <div className="flex justify-center my-6">
                   <span className="px-3 py-1 rounded bg-[#1e2229] text-[11px] font-bold text-gray-500 uppercase tracking-wider">Messages are end-to-end encrypted</span>
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

      {/* Members sidebar */}
      <MembersList />
    </div>
  )
}
