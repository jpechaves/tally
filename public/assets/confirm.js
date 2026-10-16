// Asks before sending a form marked data-confirm="question" (deleting a plan, removing
// budgets). Served as a file so the Content Security Policy (script-src 'self') lets it run.
document.addEventListener("submit", (event) => {
  const question = event.target.dataset.confirm;
  if (question && !window.confirm(question)) event.preventDefault();
});
