'use client'
import { useState, useEffect } from 'react'
import api from '@/lib/api'
import toast from 'react-hot-toast'

export default function AdminPage() {
  const [users, setUsers] = useState([])
  const [loading, setLoading] = useState(true)
  const [searchQuery, setSearchQuery] = useState('')

  const fetchUsers = async () => {
    try {
      const { data } = await api.get('/admin/users')
      setUsers(data.data)
    } catch (err) {
      toast.error('Failed to fetch users')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchUsers()
  }, [])

  const updateUser = async (userId, updates) => {
    try {
      await api.put(`/admin/users/${userId}`, updates)
      toast.success('User updated')
      fetchUsers()
    } catch (err) {
      toast.error('Update failed')
    }
  }

  const deleteUser = async (userId) => {
    if (!confirm('Are you sure you want to delete this user?')) return
    try {
      await api.delete(`/admin/users/${userId}`)
      toast.success('User deleted')
      fetchUsers()
    } catch (err) {
      toast.error('Deletion failed')
    }
  }

  const filteredUsers = users.filter(u => 
    u.name.toLowerCase().includes(searchQuery.toLowerCase()) || 
    u.email.toLowerCase().includes(searchQuery.toLowerCase())
  )

  if (loading) return <div className="flex items-center justify-center h-screen bg-[#0f1117] text-white">Loading admin panel...</div>

  return (
    <div className="p-8 bg-[#0f1117] min-h-screen text-white">
      <div className="max-w-6xl mx-auto">
        <div className="flex items-center justify-between mb-8">
          <h1 className="text-2xl font-bold">Admin Dashboard</h1>
          <div className="relative">
            <input 
              type="text"
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              placeholder="Search users..."
              className="bg-[#1a1d24] border border-[#2a2d35] rounded-lg px-4 py-2 text-sm focus:outline-none focus:border-brand-500"
            />
          </div>
        </div>

        <div className="bg-[#1a1d24] border border-[#2a2d35] rounded-xl overflow-hidden">
          <table className="w-full text-left text-sm">
            <thead className="bg-[#242731] text-gray-400 uppercase text-xs font-semibold">
              <tr>
                <th className="px-6 py-3">User</th>
                <th className="px-6 py-3">Email</th>
                <th className="px-6 py-3">Role</th>
                <th className="px-6 py-3">Status</th>
                <th className="px-6 py-3 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[#2a2d35]">
              {filteredUsers.map(u => (
                <tr key={u.id} className="hover:bg-white/[0.02] transition-colors">
                  <td className="px-6 py-4 font-medium">{u.name}</td>
                  <td className="px-6 py-4 text-gray-400">{u.email}</td>
                  <td className="px-6 py-4">
                    <select 
                      value={u.role || 'user'} 
                      onChange={e => updateUser(u.id, { role: e.target.value })}
                      className="bg-transparent border border-[#3a3d45] rounded px-1 py-0.5 text-xs focus:outline-none"
                    >
                      <option value="user">User</option>
                      <option value="admin">Admin</option>
                    </select>
                  </td>
                  <td className="px-6 py-4">
                    <select 
                      value={u.status || 'active'} 
                      onChange={e => updateUser(u.id, { status: e.target.value })}
                      className="bg-transparent border border-[#3a3d45] rounded px-1 py-0.5 text-xs focus:outline-none"
                    >
                      <option value="active">Active</option>
                      <option value="banned">Banned</option>
                    </select>
                  </td>
                  <td className="px-6 py-4 text-right">
                    <button 
                      onClick={() => deleteUser(u.id)}
                      className="text-red-400 hover:text-red-300 text-xs font-medium"
                    >
                      Delete
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {filteredUsers.length === 0 && (
            <div className="p-8 text-center text-gray-500">No users found.</div>
          )}
        </div>
      </div>
    </div>
  )
}
