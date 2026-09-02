/**
 * Add a copy button to every `[data-command]` element.
 *
 * Progressive enhancement in both directions. Without JavaScript the command
 * is still there to select and copy by hand; and the button is only created
 * when `navigator.clipboard` exists — it is undefined on an insecure origin,
 * and a Copy button that silently fails is worse than no button at all. That
 * is the same rule the hero follows for its own controls.
 */
export function attachCopy(root: ParentNode): void {
  if (!navigator.clipboard) return;

  for (const host of root.querySelectorAll<HTMLElement>('[data-command]')) {
    const value = host.dataset.command;
    // `attachCopy` runs once per Command instance on the page (Astro hoists
    // and dedupes the module, but the call site is per-component), so without
    // this every host would collect one button per instance.
    if (!value || host.querySelector('.copy')) continue;

    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'copy';
    button.textContent = 'Copy';

    // The label is the feedback, so it has to be announced, not just seen.
    const live = document.createElement('span');
    live.className = 'visually-hidden';
    live.setAttribute('role', 'status');
    live.setAttribute('aria-live', 'polite');

    let reset = 0;
    button.addEventListener('click', () => {
      navigator.clipboard.writeText(value).then(
        () => {
          button.textContent = 'Copied';
          live.textContent = 'Command copied to the clipboard.';
        },
        () => {
          // A rejected write is the one case where saying nothing would leave
          // the user believing they hold a command they do not.
          button.textContent = 'Press ⌘C';
          live.textContent = 'Copying failed. Select the command and press Command-C.';
        },
      );
      clearTimeout(reset);
      reset = window.setTimeout(() => {
        button.textContent = 'Copy';
        live.textContent = '';
      }, 2000);
    });

    // appendChild rather than append: this project's tsconfig also pulls in
    // @cloudflare/workers-types for the Worker, whose globals shadow
    // ParentNode.append with a Response-flavoured overload.
    host.appendChild(button);
    host.appendChild(live);
  }
}
