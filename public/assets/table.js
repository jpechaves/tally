// The transactions table (issue #83): picking a category in a row's cell saves it at once,
// and the box in the header ticks or unticks every row for a change of many. Served as a
// file so the Content Security Policy (script-src 'self') lets it run.
document.addEventListener("change", (event) => {
  const target = event.target;
  if (target.matches("form.inline-category select") && target.value) target.form.requestSubmit();
  if (target.dataset.checkAll) {
    document.querySelectorAll(`input[name="ids[]"][form="${target.dataset.checkAll}"]`)
      .forEach((box) => { box.checked = target.checked; });
  }
});
