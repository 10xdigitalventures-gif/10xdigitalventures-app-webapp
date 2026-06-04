'use client'
import useChatStore from '@/store/chatStore'

export default function MembersList() {
  const { members, onlineUsers } = useChatStore()

  const online = members.filter(m => onlineUsers.has(m.id) || m.is_online)
  const offline = members.filter(m => !onlineUsers.has(m.id) && !m.is_online)

  return (
    <div className="w-52 bg-[#12141a] border-l border-[#2a2d35] flex flex-col h-screen flex-shrink-0">
      <div className="p-4 border-b border-[#2a2d35]">
        <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wider">Members</h3>
      </div>
      <div className="flex-1 overflow-y-auto p-2">
        {online.length > 0 && (
          <>
            <p className="text-xs text-gray-500 px-2 py-1">Online — {online.length}</p>
            {online.map(m => (
              <div key={m.id} className="flex items-center gap-2 px-2 py-1.5 rounded-md hover:bg-white/5 cursor-pointer">
                <div className="relative">
                  <div className="w-7 h-7 rounded-full bg-brand-500 flex items-center justify-center text-white text-xs font-medium">
                    {m.name?.[0]?.toUpperCase()}
                  </div>
                  <div className="absolute bottom-0 right-0 w-2.5 h-2.5 bg-green-400 rounded-full border-2 border-[#12141a]" />
                </div>
                <div className="min-w-0">
                  <p className="text-sm text-gray-200 truncate">{m.name}</p>
                  {m.status && <p className="text-xs text-gray-500 truncate">{m.status}</p>}
                </div>
              </div>
            ))}
          </>
        )}
        {offline.length > 0 && (
          <>
            <p className="text-xs text-gray-500 px-2 py-1 mt-2">Offline — {offline.length}</p>
            {offline.map(m => (
              <div key={m.id} className="flex items-center gap-2 px-2 py-1.5 rounded-md hover:bg-white/5 cursor-pointer opacity-50">
                <div className="relative">
                  <div className="w-7 h-7 rounded-full bg-gray-600 flex items-center justify-center text-white text-xs font-medium">
                    {m.name?.[0]?.toUpperCase()}
                  </div>
                  <div className="absolute bottom-0 right-0 w-2.5 h-2.5 bg-gray-500 rounded-full border-2 border-[#12141a]" />
                </div>
                <p className="text-sm text-gray-400 truncate">{m.name}</p>
              </div>
            ))}
          </>
        )}
      </div>
    </div>
  )
}
