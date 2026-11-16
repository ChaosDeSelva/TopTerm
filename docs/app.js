const drawer = document.querySelector('#drawer');
const expand = document.querySelector('#expand');
const show = document.querySelector('#show');
const examples = {
  shell: "<span class='prompt'>~ ❯</span> printf 'A little more room to think.\\n'\nA little more room to think.\n\n<span class='prompt'>~ ❯</span> <span class='cursor' aria-hidden='true'></span>",
  server: "<span class='prompt'>~/project ❯</span> python3 -m http.server 8000\nServing HTTP on port 8000…\n\n127.0.0.1 — GET /index.html 200",
  logs: "<span class='prompt'>~/project ❯</span> tail -f app.log\n14:32:01  Ready for connections\n14:32:04  Request completed\n14:32:07  Everything is looking good"
};
document.querySelectorAll('[data-tab]').forEach(button => {
  button.addEventListener('click', () => {
    document.querySelectorAll('[data-tab]').forEach(tab => {
      const active = tab === button;
      tab.classList.toggle('active', active);
      tab.setAttribute('aria-pressed', String(active));
    });
    document.querySelector('#terminal').innerHTML = examples[button.dataset.tab];
  });
});
expand.addEventListener('click', () => {
  const expanded = drawer.classList.toggle('expanded');
  expand.setAttribute('aria-pressed', String(expanded));
  expand.setAttribute('aria-label', expanded ? 'Restore terminal to half height' : 'Expand terminal to full height');
  document.querySelector('#height').textContent = expanded ? '100%' : '50%';
});
document.querySelector('#hide').addEventListener('click', () => {
  drawer.classList.add('tucked');
  drawer.inert = true;
  show.hidden = false;
  show.focus({preventScroll: true});
});
show.addEventListener('click', () => {
  drawer.classList.remove('tucked');
  drawer.inert = false;
  show.hidden = true;
  document.querySelector('[data-tab].active').focus({preventScroll: true});
});
document.querySelector('#copy').addEventListener('click', async () => {
  const status = document.querySelector('#copy-status');
  try {
    await navigator.clipboard.writeText(document.querySelector('#commands').textContent);
    status.textContent = 'Copied. Paste into Terminal to build TopTerm.';
  } catch {
    status.textContent = 'Select the commands above to copy them manually.';
  }
});
