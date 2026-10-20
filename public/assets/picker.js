// Searchable pickers (issue #84): every <select data-picker> gets a text box that narrows
// its options as you type, ignoring accents and case. An option also matches on its group's
// name (typing "Alimentação" lists all its children) and, with data-picker="values", on its
// value ("2026-08"). The <select> stays in the form, so it is still what gets submitted, and
// without JS it is all there is. Served as a file so the Content Security Policy
// (script-src 'self') lets it run.
(() => {
  const fold = (text) => text.normalize("NFD").replace(/\p{Mn}/gu, "").toLowerCase();
  let count = 0;

  const enhance = (select) => {
    const id = `picker-${++count}`;
    const box = document.createElement("span");
    const input = document.createElement("input");
    const list = document.createElement("ul");
    box.className = "picker";
    input.type = "text";
    input.autocomplete = "off";
    input.setAttribute("role", "combobox");
    input.setAttribute("aria-autocomplete", "list");
    input.setAttribute("aria-expanded", "false");
    input.setAttribute("aria-controls", id);
    input.setAttribute("aria-label", select.getAttribute("aria-label") || select.options[0]?.text || "");
    list.id = id;
    list.setAttribute("role", "listbox");
    list.hidden = true;

    // One entry per option you can pick, under a heading per group.
    const entries = [];
    let group = null;
    let heading = null;
    [...select.options].forEach((option, index) => {
      if (option.disabled) return;
      const label = option.parentElement.tagName === "OPTGROUP" ? option.parentElement.label : "";
      if (label && label !== group) {
        heading = document.createElement("li");
        heading.setAttribute("role", "presentation");
        heading.className = "picker-group";
        heading.textContent = label;
        list.append(heading);
      }
      if (!label) heading = null;
      group = label;
      const item = document.createElement("li");
      item.id = `${id}-${index}`;
      item.setAttribute("role", "option");
      item.textContent = option.text;
      list.append(item);
      const values = select.dataset.picker === "values" ? option.value : "";
      entries.push({option, item, heading, text: fold(`${option.text} ${label} ${values}`)});
    });

    const shown = () => entries.filter((entry) => !entry.item.hidden);
    let active = null;
    const activate = (entry) => {
      if (active) active.item.removeAttribute("aria-selected");
      active = entry;
      if (!entry) return input.removeAttribute("aria-activedescendant");
      entry.item.setAttribute("aria-selected", "true");
      input.setAttribute("aria-activedescendant", entry.item.id);
      entry.item.scrollIntoView({block: "nearest"});
    };
    const filter = (query) => {
      const words = fold(query).split(/\s+/).filter(Boolean);
      entries.forEach((entry) => { entry.item.hidden = !words.every((word) => entry.text.includes(word)); });
      list.querySelectorAll(".picker-group").forEach((group) => {
        group.hidden = !entries.some((entry) => entry.heading === group && !entry.item.hidden);
      });
      empty.hidden = shown().length > 0;
      place();
      activate(shown()[0] || null);
    };
    // The list floats over the page (position: fixed), so a table's rounded, scrolling box
    // can't clip it. It drops below the box, or opens upward when there's more room there.
    const place = () => {
      if (list.hidden) return;
      const rect = input.getBoundingClientRect();
      const below = window.innerHeight - rect.bottom - 8;
      const above = rect.top - 8;
      list.style.maxHeight = "";
      const wanted = Math.min(list.scrollHeight, parseFloat(getComputedStyle(list).maxHeight));
      const up = below < wanted && above > below;
      list.style.minWidth = `${rect.width}px`;
      list.style.left = `${Math.max(Math.min(rect.left, window.innerWidth - list.offsetWidth - 8), 8)}px`;
      list.style.top = up ? "" : `${rect.bottom + 4}px`;
      list.style.bottom = up ? `${window.innerHeight - rect.top + 4}px` : "";
      list.style.maxHeight = `${Math.min(wanted, up ? above : below)}px`;
    };
    const open = () => {
      list.hidden = false;
      input.setAttribute("aria-expanded", "true");
      input.select();
      filter("");
    };
    const close = () => {
      list.hidden = true;
      input.setAttribute("aria-expanded", "false");
      activate(null);
      input.value = select.selectedOptions[0]?.disabled ? "" : select.selectedOptions[0]?.text || "";
    };
    const pick = (entry) => {
      const changed = select.value !== entry.option.value;
      select.value = entry.option.value;
      close();
      if (changed) select.dispatchEvent(new Event("change", {bubbles: true}));
    };

    const empty = document.createElement("li");
    empty.className = "picker-empty";
    empty.textContent = document.body.dataset.pickerEmpty || "";
    empty.hidden = true;
    list.append(empty);

    input.addEventListener("focus", open);
    input.addEventListener("click", () => { if (list.hidden) open(); });
    input.addEventListener("input", () => { list.hidden = false; filter(input.value); });
    input.addEventListener("blur", close);
    input.addEventListener("keydown", (event) => {
      const items = shown();
      const at = items.indexOf(active);
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        if (list.hidden) open();
        const step = event.key === "ArrowDown" ? 1 : -1;
        activate(items[Math.min(Math.max(at + step, 0), items.length - 1)] || null);
      } else if (event.key === "Enter" && !list.hidden) {
        event.preventDefault();
        if (active) pick(active);
      } else if (event.key === "Escape" && !list.hidden) {
        event.preventDefault();
        close();
      }
    });
    // mousedown, not click, so the box doesn't lose focus (and close) first.
    list.addEventListener("mousedown", (event) => {
      event.preventDefault();
      const entry = entries.find((candidate) => candidate.item === event.target);
      if (entry) pick(entry);
    });

    // Scrolling (the page or a table's box) or resizing moves the box; the list follows.
    window.addEventListener("scroll", (event) => { if (event.target !== list) place(); }, true);
    window.addEventListener("resize", place);

    // A required picker with nothing picked: the browser can't point at the hidden
    // <select>, so the box takes the focus instead.
    select.addEventListener("invalid", (event) => {
      event.preventDefault();
      input.focus();
    });
    const placeholder = [...select.options].find((option) => option.disabled);
    if (placeholder) input.placeholder = placeholder.text;

    select.classList.add("picker-native");
    select.tabIndex = -1;
    select.setAttribute("aria-hidden", "true");
    select.after(box);
    box.append(input, list);
    close();
  };

  document.querySelectorAll("select[data-picker]").forEach(enhance);
})();
