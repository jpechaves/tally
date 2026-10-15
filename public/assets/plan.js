// Live recalculation on a draft savings plan: as a "New limit" changes, update its cut,
// what the plan would save and whether that reaches the target, and ask before accepting
// limits that miss it. Served as a file so the Content Security Policy (script-src 'self')
// lets it run.
(() => {
  const form = document.getElementById("plan");
  if (!form) return;
  const inputs = form.querySelectorAll("input[data-baseline]");
  if (!inputs.length) return;
  const {today, target, decimal, locale, currency, reaches, short, confirmShort} = form.dataset;
  const thousands = decimal === "," ? "." : ",";
  const cents = (text) => {
    const plain = text.trim().replace(/^R\$\s*/, "").split(thousands).join("").replace(decimal, ".");
    return /^-?\d+(\.\d{1,2})?$/.test(plain) ? Math.round(Number(plain) * 100) : NaN;
  };
  const money = (c) => (c < 0 ? "-" : "") + currency + " " +
    (Math.abs(c) / 100).toLocaleString(locale, {minimumFractionDigits: 2, maximumFractionDigits: 2});
  const saved = () => Number(today) + [...inputs].reduce((sum, input) => {
    const value = cents(input.value);
    return sum + (isNaN(value) ? 0 : Number(input.dataset.baseline) - value);
  }, 0);
  const update = () => {
    inputs.forEach((input) => {
      const value = cents(input.value);
      const cut = isNaN(value) ? 0 : Number(input.dataset.baseline) - value;
      input.closest("tr").querySelector("[data-cut]").textContent = money(cut);
    });
    const total = saved();
    document.getElementById("new-saved").textContent = money(total);
    document.getElementById("verdict").textContent = total >= Number(target) ? reaches : short;
  };
  inputs.forEach((input) => input.addEventListener("input", update));
  // Accepting limits that miss the target is allowed, but only on purpose.
  form.addEventListener("submit", (event) => {
    if (saved() < Number(target) && !window.confirm(confirmShort)) event.preventDefault();
  });
})();
