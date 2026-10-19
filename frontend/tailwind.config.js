/** @type {import('tailwindcss').Config} */
const v = (name) => `rgb(var(--${name}) / <alpha-value>)`
export default {
  darkMode: 'class',
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        primary: { 50: v('p-50'), 100: v('p-100'), 200: v('p-200'), 300: v('p-300'), 400: v('p-400'), 500: v('p-500'), 600: v('p-600'), 700: v('p-700'), 800: v('p-800'), 900: v('p-900'), DEFAULT: v('primary'), fg: v('on-primary') },
        secondary: { 50: v('s-50'), 100: v('s-100'), 500: v('s-500'), 600: v('s-600'), 700: v('s-700'), DEFAULT: v('secondary') },
        accent: { 400: v('a-400'), 500: v('a-500'), 600: v('a-600'), DEFAULT: v('accent') },
        bg: v('bg'),
        warm: v('bg-warm'),
        surface: v('surface'),
        line: v('border'),
        ink: v('text'),
        muted: v('text-muted'),
        success: v('success'),
        warning: v('warning'),
        danger: v('danger'),
        info: v('info'),
      },
      fontFamily: { sans: ['Inter', 'system-ui', '-apple-system', 'Segoe UI', 'Roboto', 'sans-serif'] },
      fontSize: {
        xs: ['12px', '1.4'],
        sm: ['13px', '1.45'],
        base: ['14px', '1.5'],
        lg: ['16px', '1.4'],
        xl: ['18px', '1.35'],
        '2xl': ['22px', '1.3'],
        '3xl': ['28px', '1.2'],
      },
      borderRadius: { chip: '8px', ctl: '10px', card: '14px', sheet: '20px' },
      boxShadow: { card: '0 1px 2px rgba(16,24,20,.06)', raised: '0 4px 14px rgba(16,24,20,.10)' },
      keyframes: {
        shimmer: { '100%': { transform: 'translateX(100%)' } },
        'fade-in': { from: { opacity: 0 }, to: { opacity: 1 } },
        'slide-up': { from: { transform: 'translateY(12px)', opacity: 0 }, to: { transform: 'translateY(0)', opacity: 1 } },
      },
      animation: { shimmer: 'shimmer 1.4s infinite', 'fade-in': 'fade-in .15s ease-out', 'slide-up': 'slide-up .18s ease-out' },
    },
  },
  plugins: [],
}
