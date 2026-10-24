// Shows the overlay inside a form marked data-busy once it is sent, and disables its buttons
// so a slow request (an import) isn't sent twice. The next page load clears it; a page
// restored by the back button is reset by hand.
document.addEventListener("submit", (event) => {
  const form = event.target;
  if (form.dataset.busy === undefined || event.defaultPrevented) return;
  form.querySelector(".busy").hidden = false;
  form.querySelectorAll("button").forEach((button) => { button.disabled = true; });
});

window.addEventListener("pageshow", () => {
  document.querySelectorAll("form[data-busy] .busy").forEach((busy) => { busy.hidden = true; });
  document.querySelectorAll("form[data-busy] button").forEach((button) => { button.disabled = false; });
});
