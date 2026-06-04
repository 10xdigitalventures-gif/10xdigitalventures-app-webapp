'use client'
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import toast from 'react-hot-toast'
import api from '@/lib/api'

export default function RegisterPage() {
  const router = useRouter()
  const [form, setForm] = useState({ name: '', email: '', password: '', invite_code: '' })
  const [loading, setLoading] = useState(false)

  const handle = e => setForm({ ...form, [e.target.name]: e.target.value })

  const submit = async e => {
    e.preventDefault()
    setLoading(true)
    try {
      const { data } = await api.post('/auth/register', form)
      localStorage.setItem('token', data.token)
      localStorage.setItem('user', JSON.stringify(data.user))
      router.replace('/chat')
    } catch (err) {
      toast.error(err.response?.data?.message || 'Registration failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="flex items-center justify-center h-screen bg-[#0f1117]">
      <div className="w-full max-w-sm p-8 bg-[#1a1d24] rounded-2xl border border-[#3a3d45]">
        <div className="text-center mb-8">
          <div className="w-12 h-12 bg-brand-500 rounded-xl flex items-center justify-center text-white font-bold text-xl mx-auto mb-4">10x</div>
          <h1 className="text-xl font-semibold text-white">Create account</h1>
          <p className="text-sm text-gray-400 mt-1">You need an invite code to join</p>
        </div>
        <form onSubmit={submit} className="space-y-4">
          <div>
            <label className="text-xs text-gray-400 mb-1 block">Full Name</label>
            <input name="name" placeholder="Your name" value={form.name} onChange={handle} required />
          </div>
          <div>
            <label className="text-xs text-gray-400 mb-1 block">Email</label>
            <input name="email" type="email" placeholder="you@example.com" value={form.email} onChange={handle} required />
          </div>
          <div>
            <label className="text-xs text-gray-400 mb-1 block">Password</label>
            <input name="password" type="password" placeholder="Min 8 characters" value={form.password} onChange={handle} required />
          </div>
          <div>
            <label className="text-xs text-gray-400 mb-1 block">Invite Code</label>
            <input name="invite_code" placeholder="Enter workspace invite code" value={form.invite_code} onChange={handle} required />
          </div>
          <button type="submit" className="btn-primary mt-2" disabled={loading}>
            {loading ? 'Creating account...' : 'Create Account'}
          </button>
        </form>
        <p className="text-center text-sm text-gray-400 mt-6">
          Already have an account?{' '}
          <Link href="/login" className="text-brand-100 hover:underline">Sign in</Link>
        </p>
      </div>
    </div>
  )
}
