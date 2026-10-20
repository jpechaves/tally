// The transactions table (issues #83 and #85): picking a category in a row's cell saves it
// at once, and the box in the header ticks or unticks every row for a change of many.
// Before a change of many, it asks, naming how many rows (every result, with "select
// all") and the category. Served as a file so the Content Security Policy
// (script-src 'self') lets it run.
document.addEventListener("change", (event) => {
  const target = event.target;
  if (target.matches("form.inline-category select") && target.value) target.form.requestSubmit();
  if (target.dataset.checkAll) {
    document.querySelectorAll(`input[name="ids[]"][form="${target.dataset.checkAll}"]`)
      .forEach((box) => { box.checked = target.checked; });
  }
});

document.addEventListener("submit", (event) => {
  const form = event.target;
  if (!form.dataset.ask) return;
  const count = form.querySelector('input[name="all"]')?.checked ? Number(form.dataset.total)
    : document.querySelectorAll(`input[name="ids[]"][form="${form.id}"]:checked`).length;
  if (!count) return;
  const rows = count === 1 ? form.dataset.one : form.dataset.other.replace("%{count}", count);
  const question = form.dataset.ask.replace("%{rows}", rows)
    .replace("%{category}", form.querySelector("select").selectedOptions[0].text);
  if (!window.confirm(question)) event.preventDefault();
});
