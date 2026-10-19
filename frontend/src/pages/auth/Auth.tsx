import { useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { api, applyFieldErrors, isApiError } from '@/api/client'
import { useAuth, homeFor } from '@/auth/AuthContext'
import { Logo } from '@/components/Brand'
import { Button } from '@/components/ui/Button'
import { Alert } from '@/components/ui/Feedback'
import { Checkbox, Field, Input } from '@/components/ui/Form'
import { useToast } from '@/components/ui/Toast'
import { codeSchema, forgotSchema, loginSchema, registerSchema, resetSchema, type LoginForm, type RegisterForm } from '@/lib/schemas'

export const safeNext = (n: string | null): string | null => (n && n.startsWith('/') && !n.startsWith('//') ? n : null)

function Frame({ title, subtitle, children, footer }: { title: string; subtitle?: string; children: React.ReactNode; footer?: React.ReactNode }) {
  return (
    <div className="grid min-h-[calc(100dvh-56px)] place-items-start bg-warm px-4 py-8 sm:place-items-center">
      <div className="w-full max-w-md space-y-4">
        <div className="flex justify-center"><Logo /></div>
        <div className="card space-y-4 p-5">
          <div><h1 className="text-2xl">{title}</h1>{subtitle && <p className="mt-0.5 text-sm text-muted">{subtitle}</p>}</div>
          {children}
        </div>
        {footer && <p className="text-center text-sm text-muted">{footer}</p>}
      </div>
    </div>
  )
}

export function LoginPage() {
  const { login } = useAuth()
  const nav = useNavigate()
  const [sp] = useSearchParams()
  const [needOtp, setNeedOtp] = useState(false)
  const [formErr, setFormErr] = useState<string | null>(null)
  const { register, handleSubmit, formState: { errors, isSubmitting } } = useForm<LoginForm>({ resolver: zodResolver(loginSchema), defaultValues: { email: '', password: '', otp: '' } })
  const next = safeNext(sp.get('next'))
  const onSubmit = handleSubmit(async (v) => {
    setFormErr(null)
    try {
      const u = await login(v.email, v.password, v.otp || undefined)
      nav(next && (u.account_type !== 'staff' || next.startsWith('/admin')) ? next : homeFor(u), { replace: true })
    } catch (e) {
      if (isApiError(e) && e.code === 'mfa_required') { setNeedOtp(true); setFormErr(null); return }
      setFormErr(isApiError(e) ? e.message : 'Could not sign in. Try again.')
    }
  })
  return (
    <Frame title="Welcome back" subtitle="Log in to your PETORA account." footer={<>New here? <Link className="font-semibold text-primary-600 underline" to={`/register${next ? `?next=${encodeURIComponent(next)}` : ''}`}>Create an account</Link></>}>
      <form onSubmit={onSubmit} className="space-y-3" noValidate>
        {formErr && <Alert tone="danger">{formErr}</Alert>}
        <Field label="Email" error={errors.email?.message} required><Input type="email" autoComplete="username" inputMode="email" {...register('email')} /></Field>
        <Field label="Password" error={errors.password?.message} required><Input type="password" autoComplete="current-password" {...register('password')} /></Field>
        {needOtp && <Field label="Authenticator code" hint="Enter the 6-digit code from your authenticator app." required><Input inputMode="numeric" autoComplete="one-time-code" maxLength={6} autoFocus {...register('otp')} /></Field>}
        <Button type="submit" className="w-full" size="lg" loading={isSubmitting}>{needOtp ? 'Verify and log in' : 'Log in'}</Button>
        <p className="text-center text-sm"><Link to="/forgot-password" className="text-primary-600 underline">Forgot your password?</Link></p>
      </form>
    </Frame>
  )
}

export function RegisterPage({ role }: { role: 'buyer' | 'seller' }) {
  const { register: signUp } = useAuth()
  const nav = useNavigate()
  const [sp] = useSearchParams()
  const [formErr, setFormErr] = useState<string | null>(null)
  const { register, handleSubmit, setError, formState: { errors, isSubmitting } } = useForm<RegisterForm>({
    resolver: zodResolver(registerSchema), defaultValues: { name: '', email: '', phone: '', password: '', confirm: '', accept_terms: false },
  })
  const next = safeNext(sp.get('next'))
  const onSubmit = handleSubmit(async (v) => {
    setFormErr(null)
    try {
      await signUp({ name: v.name, email: v.email, phone: v.phone?.replace(/\s/g, '') || undefined, password: v.password, role, accept_terms: v.accept_terms })
      nav(`/verify-email${next ? `?next=${encodeURIComponent(next)}` : ''}`, { replace: true })
    } catch (e) {
      setFormErr(applyFieldErrors(e, setError as never, ['name', 'email', 'phone', 'password', 'accept_terms']))
    }
  })
  return (
    <Frame title={role === 'seller' ? 'Become a seller' : 'Create your account'} subtitle={role === 'seller' ? 'List pets responsibly. You’ll verify your identity before publishing.' : 'Browse for free. Unlock seller contacts when you’re ready.'}
      footer={<>{role === 'buyer' ? <>Selling pets? <Link className="font-semibold text-primary-600 underline" to="/register/seller">Register as a seller</Link></> : <>Looking to buy? <Link className="font-semibold text-primary-600 underline" to="/register">Register as a buyer</Link></>} · <Link className="font-semibold text-primary-600 underline" to="/login">Log in</Link></>}>
      <form onSubmit={onSubmit} className="space-y-3" noValidate>
        {formErr && <Alert tone="danger">{formErr}</Alert>}
        <Field label="Full name" error={errors.name?.message} required><Input autoComplete="name" {...register('name')} /></Field>
        <Field label="Email" error={errors.email?.message} required><Input type="email" inputMode="email" autoComplete="email" {...register('email')} /></Field>
        <Field label="Mobile number" error={errors.phone?.message} hint="Optional. Used for account security, not shown to others."><Input type="tel" inputMode="tel" autoComplete="tel" {...register('phone')} /></Field>
        <Field label="Password" error={errors.password?.message} hint="At least 10 characters, with a letter and a number." required><Input type="password" autoComplete="new-password" {...register('password')} /></Field>
        <Field label="Confirm password" error={errors.confirm?.message} required><Input type="password" autoComplete="new-password" {...register('confirm')} /></Field>
        <div>
          <Checkbox label={<>I agree to the <Link to="/terms" className="underline" target="_blank">Terms</Link> and <Link to="/privacy" className="underline" target="_blank">Privacy Policy</Link></>} {...register('accept_terms')} />
          {errors.accept_terms && <p role="alert" className="text-xs font-medium text-danger">{errors.accept_terms.message}</p>}
        </div>
        <Button type="submit" className="w-full" size="lg" loading={isSubmitting}>Create account</Button>
      </form>
    </Frame>
  )
}

export function VerifyEmailPage() {
  const { user, loading, refreshUser } = useAuth()
  const nav = useNavigate()
  const toast = useToast()
  const [sp] = useSearchParams()
  const [err, setErr] = useState<string | null>(null)
  const { register, handleSubmit, formState: { errors, isSubmitting } } = useForm<{ code: string }>({ resolver: zodResolver(codeSchema), defaultValues: { code: '' } })
  const [sending, setSending] = useState(false)
  if (!loading && !user) return <Frame title="Verify your email"><Alert tone="info">Please <Link className="underline" to="/login?next=/verify-email">log in</Link> to verify your email.</Alert></Frame>
  const done = async () => { const u = await refreshUser(); nav(safeNext(sp.get('next')) ?? (u ? homeFor(u) : '/'), { replace: true }) }
  const onSubmit = handleSubmit(async ({ code }) => {
    setErr(null)
    try { await api.post('/auth/verify-email', { code }); toast.success('Email verified'); await done() } catch (e) { setErr(isApiError(e) ? e.message : 'Could not verify the code') }
  })
  const resend = async () => {
    setSending(true)
    try { await api.post('/auth/resend-verification'); toast.success('A new code is on its way') } catch (e) { toast.error(isApiError(e) ? e.message : 'Could not resend') } finally { setSending(false) }
  }
  if (user?.email_verified) return <Frame title="Email verified"><Alert tone="success">Your email is already verified.</Alert><Button className="w-full" onClick={done}>Continue</Button></Frame>
  return (
    <Frame title="Verify your email" subtitle={`We sent a 6-digit code to ${user?.email ?? 'your email'}. It expires in 15 minutes.`}>
      <form onSubmit={onSubmit} className="space-y-3" noValidate>
        {err && <Alert tone="danger">{err}</Alert>}
        <Field label="Verification code" error={errors.code?.message} required><Input inputMode="numeric" autoComplete="one-time-code" maxLength={6} className="text-center text-xl tracking-[0.4em]" autoFocus {...register('code')} /></Field>
        <Button type="submit" className="w-full" size="lg" loading={isSubmitting}>Verify</Button>
        <div className="flex items-center justify-between text-sm"><button type="button" onClick={resend} disabled={sending} className="min-h-[44px] text-primary-600 underline disabled:opacity-60">Resend code</button>
          <button type="button" onClick={() => nav(user ? homeFor(user) : '/')} className="min-h-[44px] text-muted underline">Skip for now</button></div>
      </form>
    </Frame>
  )
}

export function ForgotPasswordPage() {
  const nav = useNavigate()
  const [err, setErr] = useState<string | null>(null)
  const { register, handleSubmit, formState: { errors, isSubmitting } } = useForm<{ email: string }>({ resolver: zodResolver(forgotSchema), defaultValues: { email: '' } })
  const onSubmit = handleSubmit(async ({ email }) => {
    setErr(null)
    try { await api.post('/auth/forgot-password', { email }); nav(`/reset-password?email=${encodeURIComponent(email)}`) } catch (e) { setErr(isApiError(e) ? e.message : 'Something went wrong') }
  })
  return (
    <Frame title="Forgot your password?" subtitle="Enter your email and we’ll send a reset code." footer={<Link to="/login" className="underline">Back to log in</Link>}>
      <form onSubmit={onSubmit} className="space-y-3" noValidate>
        {err && <Alert tone="danger">{err}</Alert>}
        <Field label="Email" error={errors.email?.message} required><Input type="email" inputMode="email" autoComplete="email" {...register('email')} /></Field>
        <Button type="submit" className="w-full" size="lg" loading={isSubmitting}>Send reset code</Button>
      </form>
    </Frame>
  )
}

export function ResetPasswordPage() {
  const nav = useNavigate()
  const toast = useToast()
  const [sp] = useSearchParams()
  const [err, setErr] = useState<string | null>(null)
  const { register, handleSubmit, setError, formState: { errors, isSubmitting } } = useForm<{ email: string; code: string; password: string }>({
    resolver: zodResolver(resetSchema), defaultValues: { email: sp.get('email') ?? '', code: '', password: '' },
  })
  const onSubmit = handleSubmit(async (v) => {
    setErr(null)
    try { await api.post('/auth/reset-password', v); toast.success('Password changed. Please log in.'); nav('/login', { replace: true }) } catch (e) { setErr(applyFieldErrors(e, setError as never, ['email', 'code', 'password'])) }
  })
  return (
    <Frame title="Reset your password" subtitle="Enter the code we emailed you and choose a new password." footer={<Link to="/forgot-password" className="underline">Send a new code</Link>}>
      <form onSubmit={onSubmit} className="space-y-3" noValidate>
        {err && <Alert tone="danger">{err}</Alert>}
        <Field label="Email" error={errors.email?.message} required><Input type="email" autoComplete="email" {...register('email')} /></Field>
        <Field label="6-digit code" error={errors.code?.message} required><Input inputMode="numeric" autoComplete="one-time-code" maxLength={6} {...register('code')} /></Field>
        <Field label="New password" error={errors.password?.message} hint="At least 10 characters, with a letter and a number." required><Input type="password" autoComplete="new-password" {...register('password')} /></Field>
        <Button type="submit" className="w-full" size="lg" loading={isSubmitting}>Change password</Button>
      </form>
    </Frame>
  )
}
