import './globals.css'
import { Toaster } from 'react-hot-toast'

export const metadata = {
  title: '10x Chat | 10xDigitalVentures',
  description: 'Team Chat by 10x Digital Ventures',
}

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>
        {children}
        <Toaster
          position="top-right"
          toastOptions={{
            style: {
              background: '#1e2028',
              color: '#e8eaed',
              border: '1px solid #3a3d45',
            },
          }}
        />
      </body>
    </html>
  )
}
