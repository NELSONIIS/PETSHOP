import type { Envelope, FieldError, Meta } from './types'

export const API_BASE = '/api/v1'

export class ApiError extends Error {
  status: number
  code: string
  details: FieldError[]
  extra?: Record<string, unknown>
  requestId?: string
  constructor(status: number, code: string, message: string, details: FieldError[] = [], extra?: Record<string, unknown>, requestId?: string) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.code = code
    this.details = details
    this.extra = extra
    this.requestId = requestId
  }
}

export function isApiError(e: unknown): e is ApiError {
  return e instanceof ApiError
}

export function readCookie(name: string): string {
  if (typeof document === 'undefined') return ''
  const m = document.cookie.split('; ').find((c) => c.startsWith(name + '='))
  return m ? decodeURIComponent(m.slice(name.length + 1)) : ''
}
export const hasSessionHint = () => !!readCookie('petora_csrf')

type Params = Record<string, string | number | boolean | null | undefined>
export interface RequestOpts { params?: Params; body?: unknown; signal?: AbortSignal; noRefresh?: boolean }

let authLostHandler: (() => void) | null = null
export function onAuthLost(fn: (() => void) | null) { authLostHandler = fn }

export function buildQuery(params?: Params): string {
  if (!params) return ''
  const sp = new URLSearchParams()
  for (const [k, v] of Object.entries(params)) {
    if (v === undefined || v === null || v === '' || v === false) continue
    sp.set(k, String(v))
  }
  const s = sp.toString()
  return s ? `?${s}` : ''
}

const NO_REFRESH_PATHS = ['/auth/login', '/auth/register', '/auth/refresh', '/auth/forgot-password', '/auth/reset-password']
let refreshing: Promise<boolean> | null = null

/** Single-flight refresh: concurrent 401s share one /auth/refresh call. */
export function refreshSession(): Promise<boolean> {
  if (!refreshing) {
    refreshing = fetch(`${API_BASE}/auth/refresh`, {
      method: 'POST', credentials: 'include',
      headers: { 'X-CSRF-Token': readCookie('petora_csrf') },
    })
      .then((r) => r.ok)
      .catch(() => false)
      .finally(() => { setTimeout(() => { refreshing = null }, 0) })
  }
  return refreshing
}

async function parse(res: Response): Promise<{ data: unknown; meta?: Meta }> {
  if (res.status === 204) return { data: undefined }
  const text = await res.text()
  let json: unknown = undefined
  if (text) {
    try { json = JSON.parse(text) } catch { json = undefined }
  }
  if (!res.ok) {
    const err = (json as { error?: { code?: string; message?: string; details?: FieldError[]; extra?: Record<string, unknown>; request_id?: string } } | undefined)?.error
    throw new ApiError(res.status, err?.code ?? 'http_error', err?.message ?? `Request failed (${res.status})`, err?.details ?? [], err?.extra, err?.request_id ?? res.headers.get('X-Request-ID') ?? undefined)
  }
  const env = json as Envelope<unknown> | undefined
  return { data: env?.data, meta: env?.meta }
}

export async function request<T>(method: string, path: string, opts: RequestOpts = {}): Promise<Envelope<T>> {
  const doFetch = () => {
    const headers: Record<string, string> = { Accept: 'application/json' }
    const init: RequestInit = { method, credentials: 'include', headers, signal: opts.signal }
    if (method !== 'GET' && method !== 'HEAD') {
      headers['X-CSRF-Token'] = readCookie('petora_csrf')
      if (opts.body !== undefined) {
        headers['Content-Type'] = 'application/json'
        init.body = JSON.stringify(opts.body)
      }
    }
    return fetch(`${API_BASE}${path}${buildQuery(opts.params)}`, init)
  }
  let res: Response
  try {
    res = await doFetch()
  } catch (e) {
    if ((e as Error).name === 'AbortError') throw e
    throw new ApiError(0, 'network_error', 'Network problem. Check your connection and try again.')
  }
  if (res.status === 401 && !opts.noRefresh && !NO_REFRESH_PATHS.includes(path) && hasSessionHint()) {
    const ok = await refreshSession()
    if (ok) {
      res = await doFetch()
    } else {
      authLostHandler?.()
    }
  }
  const { data, meta } = await parse(res)
  return { data: data as T, meta }
}

export const api = {
  get: <T>(path: string, params?: Params, signal?: AbortSignal) => request<T>('GET', path, { params, signal }),
  post: <T>(path: string, body?: unknown, opts?: RequestOpts) => request<T>('POST', path, { ...opts, body }),
  put: <T>(path: string, body?: unknown) => request<T>('PUT', path, { body }),
  patch: <T>(path: string, body?: unknown) => request<T>('PATCH', path, { body }),
  del: <T = void>(path: string, body?: unknown) => request<T>('DELETE', path, { body }),
}

export interface UploadHandle { promise: Promise<unknown>; abort: () => void }

/** Multipart upload with progress + cancel (fetch has no upload progress, so XHR). */
export function upload<T>(path: string, form: FormData, onProgress?: (pct: number) => void): { promise: Promise<T>; abort: () => void } {
  let xhr: XMLHttpRequest | null = null
  let aborted = false
  const send = () =>
    new Promise<{ status: number; body: string }>((resolve, reject) => {
      xhr = new XMLHttpRequest()
      xhr.open('POST', `${API_BASE}${path}`)
      xhr.withCredentials = true
      xhr.setRequestHeader('X-CSRF-Token', readCookie('petora_csrf'))
      xhr.setRequestHeader('Accept', 'application/json')
      xhr.upload.onprogress = (e) => { if (e.lengthComputable) onProgress?.(Math.round((e.loaded / e.total) * 100)) }
      xhr.onload = () => resolve({ status: xhr!.status, body: xhr!.responseText })
      xhr.onerror = () => reject(new ApiError(0, 'network_error', 'Upload failed. Check your connection and retry.'))
      xhr.onabort = () => reject(new ApiError(0, 'aborted', 'Upload cancelled'))
      xhr.send(form)
    })
  const promise = (async () => {
    let r = await send()
    if (r.status === 401 && !aborted && hasSessionHint() && (await refreshSession())) r = await send()
    let json: { data?: T; error?: { code?: string; message?: string; details?: FieldError[]; extra?: Record<string, unknown>; request_id?: string } } = {}
    try { json = JSON.parse(r.body) } catch { /* non-JSON error body */ }
    if (r.status < 200 || r.status >= 300) {
      throw new ApiError(r.status, json.error?.code ?? 'http_error', json.error?.message ?? `Upload failed (${r.status})`, json.error?.details ?? [], json.error?.extra, json.error?.request_id)
    }
    return json.data as T
  })()
  return { promise, abort: () => { aborted = true; xhr?.abort() } }
}

/** Map server validation details onto react-hook-form fields. */
export function applyFieldErrors(
  e: unknown,
  setError: (name: never, err: { type: string; message: string }) => void,
  known?: string[],
): string | null {
  if (!isApiError(e)) return 'Something went wrong. Please try again.'
  let unmapped = false
  for (const d of e.details) {
    if (!known || known.includes(d.field)) setError(d.field as never, { type: 'server', message: d.message })
    else unmapped = true
  }
  if (e.details.length === 0 || unmapped) return e.message
  return null
}
