// Match the top page's dark mode (battery plugged in) before first paint.
try { if (/(?:^|; )pos_battery=[^;]/.test(document.cookie)) document.documentElement.classList.add('dark'); } catch (e) {}
