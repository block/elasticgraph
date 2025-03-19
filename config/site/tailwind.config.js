/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./src/**/*.{html,md}"],
  darkMode: 'class',
  theme: {
    extend: {
      spacing: {
        '1.25': '0.3125rem',
      },
    },
  },
  plugins: [
    require('@tailwindcss/typography'),
  ],
}