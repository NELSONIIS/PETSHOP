import { LinkButton } from '@/components/ui/Button'
import { EmptyState } from '@/components/ui/Feedback'

export default function NotFound() {
  return <div className="container-page py-12"><EmptyState title="Page not found" body="The page you’re looking for doesn’t exist or has moved." action={<LinkButton to="/">Go home</LinkButton>} /></div>
}
