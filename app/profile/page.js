'use client'
import { useState, useEffect } from 'react'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import toast from 'react-hot-toast'
import Link from 'next/link'

export default function ProfilePage() {
  const { user, setUser } = useChatStore()
  const [formData, setFormData] = useState({
    name: '',
    bio: '',
    status: 'Active'
  })
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    if (user) {
      setFormData({
        name: user.name || '',
        bio: user.bio || '',
        status: user.status || 'Active'
      })
    }
  }, [user])

  const handleUpdate = async (e) => {
    e.preventDefault()
    setLoading(true)
    try {
      const { data } = await api.put('/auth/profile', formData)
      setUser(data)
      toast.success('Profile updated successfully')
    } catch (err) {
      toast.error('Failed to update profile')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="flex h-screen bg-[#0f1117] text-white">
      <div className="w-64 border-r border-[#2a2d35] flex flex-col">
        {/* Reuse the sidebar component or just link back */}
        <div className="p-4 border-b border-[#2a2d35]">
          <Link href="/chat" className="text-sm font-bold flex items-center gap-2 hover:text-brand-500 transition-colors">
            ← Back to Chat
          </Link>
        </div>
      </div>
      
      <div className="flex-1 p-8 overflow-y-auto">
        <div className="max-w-2xl mx-auto">
          <h1 className="text-2xl font-bold mb-8">Account Settings</h1>
          
          <div className="bg-[#1a1d24] border border-[#2a2d35] rounded-2xl p-6 space-y-6">
            <div className="flex items-center gap-6 mb-8">
              <div className="w-24 h-24 rounded-full bg-brand-500 flex items-center justify-center text-3xl font-bold">
                {user?.name?.[0]?.toUpperCase() || 'U'}
              </div>
              <div>
                <h2 className="text-xl font-semibold">{user?.name}</h2>
                <p className="text-gray-400 text-sm">{user?.email}</p>
              </div>
            </div>

            <form onSubmit={handleUpdate} className="space-y-4">
              <div>
                <label className="block text-xs font-semibold text-gray-400 uppercase mb-1">Display Name</label>
                <input 
                  type="text"
                  value={formData.name}
                  onChange={e => setFormData({ ...formData, name: e.target.value })}
                  className="w-full bg-[#12141a] border border-[#2a2d35] rounded-lg px-4 py-2 focus:outline-none focus:border-brand-500 transition-colors"
                  placeholder="Your name"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-gray-400 uppercase mb-1">Bio</label>
                <textarea 
                  value={formData.bio}
                  onChange={e => setFormData({ ...formData, bio: e.target.value })}
                  className="w-full bg-[#12141a] border border-[#2a2d35] rounded-lg px-4 py-2 focus:outline-none focus:border-brand-500 transition-colors resize-none"
                  rows={3}
                  placeholder="Tell us about yourself..."
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-gray-400 uppercase mb-1">Status</label>
                <select 
                  value={formData.status}
                  onChange={e => setFormData({ ...formData, status: e.target.value })}
                  className="w-full bg-[#12141a] border border-[#2a2d35] rounded-lg px-4 py-2 focus:outline-none focus:border-brand-500 transition-colors"
                >
                  <option value="Active">Active</option>
                  <option value="Away">Away</option>
                  <option value="Busy">Busy</option>
                  <option value="Do Not Disturb">Do Not Disturb</option>
                </select>
              </div>

              <button 
                type="submit" 
                disabled={loading}
                className="w-full btn-primary py-3 font-semibold rounded-lg transition-all disabled:opacity-50"
              >
                {loading ? 'Saving...' : 'Save Changes'}
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
  )
}
