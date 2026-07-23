// Tailwind CSS v4 - Minimal config for content paths only
// Theme configuration has been moved to app/assets/tailwind/pallastrade/admin/application.css
module.exports = {
  content: [
    // Host app admin customizations
    './app/helpers/pallastrade/admin/**/*.rb',
    './app/javascript/pallastrade/admin/**/*.js',
    './app/views/pallastrade/admin/**/*.erb',
    // PallasTrade Admin engine paths (set by engine initializer)
    process.env.pallastrade_ADMIN_PATH + '/app/helpers/**/*.rb',
    process.env.pallastrade_ADMIN_PATH + '/app/javascript/**/*.js',
    process.env.pallastrade_ADMIN_PATH + '/app/views/pallastrade/admin/**/*.erb'
  ].filter(Boolean)
}
