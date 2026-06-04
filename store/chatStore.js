import { create } from 'zustand'

const useChatStore = create((set, get) => ({
  user: null,
  channels: [],
  activeChannel: null,
  messages: {},
  onlineUsers: new Set(),
  typingUsers: {},
  members: [],

  setUser: (user) => set({ user }),
  setChannels: (channels) => set({ channels }),
  setActiveChannel: (channel) => set({ activeChannel: channel }),
  setMembers: (members) => set({ members }),

  addChannel: (channel) => set(s => ({ channels: [...s.channels, channel] })),

  setMessages: (channelId, messages) =>
    set(s => ({ messages: { ...s.messages, [channelId]: messages } })),

  addMessage: (channelId, msg) =>
    set(s => ({
      messages: {
        ...s.messages,
        [channelId]: [...(s.messages[channelId] || []), msg],
      },
    })),

  updateMessage: (channelId, messageId, updates) =>
    set(s => ({
      messages: {
        ...s.messages,
        [channelId]: (s.messages[channelId] || []).map(m =>
          m.id === messageId ? { ...m, ...updates } : m
        ),
      },
    })),

  deleteMessage: (channelId, messageId) =>
    set(s => ({
      messages: {
        ...s.messages,
        [channelId]: (s.messages[channelId] || []).map(m =>
          m.id === messageId ? { ...m, is_deleted: 1, content: 'This message was deleted' } : m
        ),
      },
    })),

  updateReaction: (channelId, messageId, emoji, userId, action) =>
    set(s => ({
      messages: {
        ...s.messages,
        [channelId]: (s.messages[channelId] || []).map(m => {
          if (m.id !== messageId) return m
          let reactions = m.reactions ? [...m.reactions] : []
          if (action === 'removed') {
            reactions = reactions.filter(r => !(r.emoji === emoji && r.user_id === userId))
          } else {
            reactions.push({ emoji, user_id: userId })
          }
          return { ...m, reactions }
        }),
      },
    })),

  setUserOnline: (userId) =>
    set(s => { const o = new Set(s.onlineUsers); o.add(userId); return { onlineUsers: o } }),

  setUserOffline: (userId) =>
    set(s => { const o = new Set(s.onlineUsers); o.delete(userId); return { onlineUsers: o } }),

  setTyping: (channelId, userId, isTyping) =>
    set(s => {
      const t = { ...s.typingUsers }
      if (!t[channelId]) t[channelId] = new Set()
      else t[channelId] = new Set(t[channelId])
      isTyping ? t[channelId].add(userId) : t[channelId].delete(userId)
      return { typingUsers: t }
    }),
}))

export default useChatStore
