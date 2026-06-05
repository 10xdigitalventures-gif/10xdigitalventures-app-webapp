'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import toast from 'react-hot-toast'
import api from '@/lib/api'

export default function LoginPage() {
  const router = useRouter()
  const [form, setForm] = useState({ email: '', password: '' })
  const [loading, setLoading] = useState(false)

  const handle = e => setForm({ ...form, [e.target.name]: e.target.value })

  const submit = async e => {
    e.preventDefault()
    setLoading(true)

    try {
      const { data } = await api.post('/auth/login', form)
      const payload = data?.data || data

      if (!payload?.token || !payload?.user) {
        throw new Error('Invalid login response')
      }

      localStorage.setItem('token', payload.token)
      localStorage.setItem('user', JSON.stringify(payload.user))
      router.replace('/chat')
    } catch (err) {
      toast.error(err.response?.data?.message || err.message || 'Login failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen bg-[#0f1117] flex items-center justify-center p-4">
      <form onSubmit={submit} className="w-full max-w-md bg-[#1a1d24] border border-gray-700 rounded-2xl p-8 space-y-5">
        <div className="text-center">
          <div className="mx-auto mb-6 h-14 w-14 rounded-xl bg-brand-500 flex items-center justify-center font-bold text-xl text-white">10x</div>
          <h1 className="text-2xl font-bold text-white">Welcome back</h1>
          <p className="text-gray-400 mt-2">Sign in to 10x Chat</p>
        </div>

        <div>
          <label className="block text-sm text-gray-400 mb-2">Email</label>
          <input name="email" type="email" value={form.email} onChange={handle} className="w-full px-4 py-3 rounded-lg bg-gray-100 text-black" required />
        </div>

        <div>
          <label className="block text-sm text-gray-400 mb-2">Password</label>
          <input name="password" type="password" value={form.password} onChange={handle} className="w-full px-4 py-3 rounded-lg bg-gray-100 text-black" required />
        </div>

        <button disabled={loading} className="w-full py-3 rounded-lg bg-brand-500 text-white font-semibold disabled:opacity-70">
          {loading ? 'Signing in...' : 'Sign In'}
        </button>

        <p className="text-center text-gray-400">
          No account? <Link href="/register" className="text-white font-semibold">Register with invite code</Link>
        </p>
      </form>
    </div>
  )
}
