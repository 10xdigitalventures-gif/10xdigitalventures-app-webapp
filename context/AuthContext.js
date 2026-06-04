'use client'
import { createContext, useContext, useState, useEffect } from 'react'
import Cookies from 'js-cookie'
import api from '@/lib/api'

const AuthContext = createContext(null)

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const stored = Cookies.get('user')
    if (stored) {
      try { setUser(JSON.parse(stored)) } catch {}
    }
    setLoading(false)
  }, [])

  const login = async (email, password) => {
    const { data } = await api.post('/auth/login', { email, password })
    Cookies.set('token', data.token, { expires: 7 })
    Cookies.set('user', JSON.stringify(data.user), { expires: 7 })
    setUser(data.user)
    return data
  }

  const register = async (name, email, password, invite_code) => {
    const { data } = await api.post('/auth/register', { name, email, password, invite_code })
    Cookies.set('token', data.token, { expires: 7 })
    Cookies.set('user', JSON.stringify(data.user), { expires: 7 })
    setUser(data.user)
    return data
  }

  const logout = () => {
    Cookies.remove('token')
    Cookies.remove('user')
    setUser(null)
    window.location.href = '/login'
  }

  return (
    <AuthContext.Provider value={{ user, loading, login, register, logout, setUser }}>
      {children}
    </AuthContext.Provider>
  )
}

export const useAuth = () => useContext(AuthContext)
