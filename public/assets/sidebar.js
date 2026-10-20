// Folds the sidebar's sections the way this browser left them. The page sends every section
// open (so without scripts nothing is hidden); the one holding the current page stays open.
(() => {
  const key = (group) => `tally.sidebar.${group.dataset.group}`;
  const store = {
    get: (name) => { try { return localStorage.getItem(name); } catch { return null; } },
    set: (name, value) => { try { localStorage.setItem(name, value); } catch { /* private window */ } }
  };

  document.querySelectorAll("details.nav-group").forEach((group) => {
    if (store.get(key(group)) === "closed" && !group.querySelector("[aria-current]")) group.open = false;
    group.addEventListener("toggle", () => store.set(key(group), group.open ? "open" : "closed"));
  });
})();
