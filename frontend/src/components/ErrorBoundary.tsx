import { Component, type ReactNode } from 'react'
import { ErrorState } from './ui/Feedback'

export class ErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null }
  static getDerivedStateFromError(error: Error) { return { error } }
  render() {
    if (this.state.error) {
      return <div className="container-page py-10"><ErrorState title="This page hit a problem" error={this.state.error} onRetry={() => { this.setState({ error: null }); window.location.reload() }} /></div>
    }
    return this.props.children
  }
}
