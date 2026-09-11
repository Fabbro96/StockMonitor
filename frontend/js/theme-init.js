/* Anti-FOUC: applica il tema prima del primo paint. Caricato in <head> senza defer. */
(() => {
  try {
    const saved = localStorage.getItem('app_theme');
    const theme = (saved === 'light' || saved === 'dark')
      ? saved
      : (matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');
    document.documentElement.setAttribute('data-theme', theme);
  } catch {
    document.documentElement.setAttribute('data-theme', 'dark');
  }
})();
