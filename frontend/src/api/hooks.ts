import { useMutation, useQuery, useQueryClient, keepPreviousData, type QueryKey, type UseQueryOptions } from '@tanstack/react-query'
import { api, type RequestOpts } from './client'
import type { Category, Envelope, ListingCard, Meta, Plan, PublicConfig, SubscriptionStatus } from './types'

type Params = Record<string, string | number | boolean | null | undefined>

/** Generic GET hook. Returns the unwrapped data + pagination meta. Pass `null` as path to disable. */
export function useGet<T>(path: string | null, params?: Params, opts: Partial<UseQueryOptions<Envelope<T>>> & { keepPrevious?: boolean } = {}) {
  const { keepPrevious, ...rest } = opts
  const q = useQuery<Envelope<T>>({
    queryKey: [path, params ?? {}] as QueryKey,
    queryFn: ({ signal }) => api.get<T>(path as string, params, signal),
    enabled: path !== null,
    placeholderData: keepPrevious ? keepPreviousData : undefined,
    ...rest,
  })
  return { ...q, items: q.data?.data as T | undefined, meta: q.data?.meta as Meta | undefined }
}

/** Generic mutation. Invalidates the given path prefixes on success. */
export function useSend<TIn = void, TOut = unknown>(
  fn: (input: TIn) => Promise<Envelope<TOut>>,
  opts: { invalidate?: (string | null)[]; onSuccess?: (data: TOut, input: TIn) => void } = {},
) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: TIn) => (await fn(input)).data,
    onSuccess: (data, input) => {
      for (const p of opts.invalidate ?? []) qc.invalidateQueries({ predicate: (q) => typeof q.queryKey[0] === 'string' && (q.queryKey[0] as string).startsWith(p as string) })
      opts.onSuccess?.(data, input)
    },
  })
}

export const post = <T,>(path: string, body?: unknown, o?: RequestOpts) => api.post<T>(path, body, o)

export const useConfig = () => useGet<PublicConfig>('/config', undefined, { staleTime: 5 * 60_000 })
export const useCategories = () => useGet<Category[]>('/categories', undefined, { staleTime: 5 * 60_000 })
export const usePlans = (audience?: 'buyer' | 'seller') => useGet<Plan[]>('/subscription-plans', { audience }, { staleTime: 60_000 })
export const useSubscription = (enabled = true) => useGet<SubscriptionStatus>(enabled ? '/subscriptions/current' : null)
export const usePets = (params: Params, opts?: { keepPrevious?: boolean; enabled?: boolean }) =>
  useGet<ListingCard[]>(opts?.enabled === false ? null : '/pets', params, { keepPrevious: opts?.keepPrevious ?? true, staleTime: 30_000 })

export function useToggleFavourite() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, on }: { id: string; on: boolean }) => {
      if (on) await api.post('/favourites', { listing_id: id })
      else await api.del(`/favourites/${id}`)
    },
    onMutate: async ({ id, on }) => {
      // Optimistic: patch every cached list/detail that contains this listing.
      const snapshots = qc.getQueriesData<Envelope<unknown>>({ predicate: (q) => typeof q.queryKey[0] === 'string' && (q.queryKey[0] as string).startsWith('/') })
      const patch = (v: unknown): unknown => {
        if (Array.isArray(v)) return v.map(patch)
        if (v && typeof v === 'object') {
          const o = v as Record<string, unknown>
          if (o.id === id && 'is_favourite' in o) return { ...o, is_favourite: on }
          return o
        }
        return v
      }
      for (const [key, snap] of snapshots) {
        if (snap?.data !== undefined) qc.setQueryData(key, { ...snap, data: patch(snap.data) })
      }
      return { snapshots }
    },
    onError: (_e, _v, ctx) => { ctx?.snapshots.forEach(([key, snap]) => qc.setQueryData(key, snap)) },
    onSettled: () => { qc.invalidateQueries({ predicate: (q) => q.queryKey[0] === '/favourites' }) },
  })
}
