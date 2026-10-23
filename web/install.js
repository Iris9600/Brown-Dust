let installation;
const installButton = document.getElementById('install');
window.addEventListener('beforeinstallprompt', (event) => {
  event.preventDefault();
  installation = event;
  installButton.hidden = false;
});
installButton.addEventListener('click', async () => {
  if (!installation) return;
  installButton.hidden = true;
  try {
    await installation.prompt();
    await installation.userChoice;
  } finally {
    installation = undefined;
  }
});
window.addEventListener('appinstalled', () => {
  installation = undefined;
  installButton.hidden = true;
});
window.addEventListener('flutter-first-frame', () => {
  document.getElementById('loading')?.remove();
});
// sw.js is generated for release builds by tool/prepare_web.mjs.
if ('serviceWorker' in navigator && window.isSecureContext) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('sw.js').catch((error) => {
      console.warn('Offline support unavailable:', error);
    });
  });
}
