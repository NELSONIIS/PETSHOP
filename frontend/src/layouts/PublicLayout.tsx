import { Outlet, useLocation } from 'react-router-dom'
import { useEffect } from 'react'
import { Footer } from '@/components/Footer'
import { Header } from '@/components/Header'

export function PublicLayout() {
  const { pathname } = useLocation()
  useEffect(() => { window.scrollTo(0, 0) }, [pathname])
  return (
    <div className="flex min-h-dvh flex-col">
      <a href="#main" className="sr-only focus:not-sr-only focus:absolute focus:left-2 focus:top-2 focus:z-[70] focus:rounded-ctl focus:bg-surface focus:px-3 focus:py-2">Skip to content</a>
      <Header />
      <main id="main" className="flex-1"><Outlet /></main>
      <Footer />
    </div>
  )
}
