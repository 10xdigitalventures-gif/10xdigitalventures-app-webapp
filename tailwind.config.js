/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './app/**/*.{js,jsx}',
    './components/**/*.{js,jsx}',
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          50:  '#e6fcf5',
          100: '#c3fae8',
          500: '#1db791', // 10x Green
          600: '#12b886',
          700: '#0ca678',
        },
        surface: {
          50:  '#ffffff',
          100: '#f8f9fa',
          200: '#e9ecef',
          800: '#12141a', // Dark theme background
          900: '#0f1117',
        }
      },
    },
  },
  plugins: [],
}
