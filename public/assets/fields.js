// Amounts and days typed the way the page's language writes them. Without scripts the
// fields work as plain inputs and the browser's own date picker.
//
// - An amount field (inputmode="decimal") fills in as you type digits, cents first:
//   "216102" reads "2.161,02" in Portuguese and "2,161.02" in English; a "-" anywhere
//   makes it negative. The server reads both separators (Tally::Money.parse).
// - A date field gets a text box in dd/mm/aaaa (Portuguese) or mm/dd/yyyy (English) and a
//   button that opens the calendar. The browser's own date input stays in the form,
//   hidden, and is what gets sent, as YYYY-MM-DD.
(() => {
  const pt = document.documentElement.lang.startsWith("pt");
  const [thousands, decimal] = pt ? [".", ","] : [",", "."];

  const money = (text) => {
    const digits = text.replace(/\D/g, "").replace(/^0+(?=\d)/, "");
    if (digits === "") return text.includes("-") ? "-" : "";
    const padded = digits.padStart(3, "0");
    const whole = padded.slice(0, -2).replace(/\B(?=(\d{3})+(?!\d))/g, thousands);
    return `${text.includes("-") ? "-" : ""}${whole}${decimal}${padded.slice(-2)}`;
  };

  document.querySelectorAll('input[inputmode="decimal"]').forEach((input) => {
    // A value the page wrote ("182.40") is in the page's own format already.
    if (input.value) input.value = money(input.value.includes(decimal) ? input.value : `${input.value}${decimal}00`);
    input.addEventListener("input", () => { input.value = money(input.value); });
  });

  const order = pt ? ["d", "m", "y"] : ["m", "d", "y"];
  const placeholder = pt ? "dd/mm/aaaa" : "mm/dd/yyyy";
  const masked = (text) => text.replace(/\D/g, "").slice(0, 8).replace(/^(\d{2})(\d)/, "$1/$2").replace(/^(\d{2}\/\d{2})(\d)/, "$1/$2");
  const shown = (iso) => {
    const [y, m, d] = iso.split("-");
    return iso ? order.map((part) => ({d, m, y})[part]).join("/") : "";
  };
  const iso = (text) => {
    const parts = text.split("/");
    if (parts.length !== 3 || parts[2].length !== 4) return null;
    const {d, m, y} = Object.fromEntries(order.map((part, index) => [part, parts[index]]));
    const date = new Date(Date.UTC(+y, +m - 1, +d));
    const value = `${y}-${m}-${d}`;
    return date.toISOString().slice(0, 10) === value ? value : null;
  };

  document.querySelectorAll('input[type="date"]').forEach((native) => {
    const box = document.createElement("span");
    box.className = "date-field";
    const text = document.createElement("input");
    text.type = "text";
    text.inputMode = "numeric";
    text.placeholder = placeholder;
    text.size = 10;
    text.required = native.required;
    text.value = shown(native.value);
    if (native.hasAttribute("aria-label")) text.setAttribute("aria-label", native.getAttribute("aria-label"));
    native.required = false;
    native.tabIndex = -1;
    native.setAttribute("aria-hidden", "true");
    native.before(box);
    box.append(text, native);

    if (typeof native.showPicker === "function") {
      const open = document.createElement("button");
      open.type = "button";
      open.className = "date-open";
      open.setAttribute("aria-label", pt ? "Abrir calendário" : "Open calendar");
      open.innerHTML = '<svg class="icon" viewBox="0 0 16 16" aria-hidden="true"><rect x="2.5" y="3.5" width="11" height="10" rx="1.5"/><path d="M2.5 6.5h11M5.5 2v3M10.5 2v3"/></svg>';
      open.addEventListener("click", () => native.showPicker());
      box.append(open);
    }

    const sync = () => {
      const value = text.value === "" ? "" : iso(text.value);
      native.value = value || "";
      text.setCustomValidity(value === null ? `Use ${placeholder}` : "");
    };
    text.addEventListener("input", () => { text.value = masked(text.value); sync(); });
    native.addEventListener("change", () => { text.value = shown(native.value); sync(); });
  });
})();
