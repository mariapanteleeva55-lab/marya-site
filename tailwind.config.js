/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./*.html'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        cream:   { DEFAULT: '#FDF8F3', dark: '#1A1612' },
        sand:    { DEFAULT: '#E8DDD0', dark: '#2A2420' },
        warm:    { DEFAULT: '#C4A882', dark: '#8B7355' },
        accent:  { DEFAULT: '#D4956A', dark: '#E8A87A' },
        sage:    { DEFAULT: '#8BA888', dark: '#6B8A68' },
        ink:     { DEFAULT: '#2C2018', dark: '#F5EDE4' },
        muted:   { DEFAULT: '#7A6A5A', dark: '#A89880' },
      },
      fontFamily: {
        serif:  ['Georgia', 'Cambria', 'serif'],
        sans:   ['Inter', 'system-ui', 'sans-serif'],
      },
      animation: {
        'pulse-soft': 'pulseSoft 2s ease-in-out infinite',
        'fade-up':    'fadeUp 0.6s ease-out forwards',
        'float':      'float 6s ease-in-out infinite',
        'marquee':    'marquee 30s linear infinite',
      },
      keyframes: {
        pulseSoft: {
          '0%, 100%': { transform: 'scale(1)' },
          '50%':      { transform: 'scale(1.03)' },
        },
        fadeUp: {
          from: { opacity: '0', transform: 'translateY(24px)' },
          to:   { opacity: '1', transform: 'translateY(0)' },
        },
        float: {
          '0%, 100%': { transform: 'translateY(0px)' },
          '50%':      { transform: 'translateY(-12px)' },
        },
        marquee: {
          from: { transform: 'translateX(0)' },
          to:   { transform: 'translateX(-50%)' },
        },
      },
    },
  },
}
