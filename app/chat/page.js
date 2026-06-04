'use client'
export default function ChatHome() {
  return (
    <div className="flex-1 flex items-center justify-center bg-[#0f1117]">
      <div className="text-center">
        <div className="w-16 h-16 bg-brand-500 rounded-2xl flex items-center justify-center text-white font-bold text-2xl mx-auto mb-4">10x</div>
        <h2 className="text-xl font-semibold text-white mb-2">Welcome to 10x Chat</h2>
        <p className="text-gray-400 text-sm">Select a channel from the sidebar to start chatting</p>
      </div>
    </div>
  )
}
