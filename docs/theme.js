// Dark or light, chosen by the reader and remembered on this device.
//
// The page is dark unless the system asks for light (style.css); this only
// adds an explicit choice on top. It is loaded in <head> without defer so a
// stored choice applies before the first paint, with no flash of the other
// theme. Without JavaScript the page still follows the system setting.
(function () {
  var root = document.documentElement;
  var KEY = "ermod-theme";

  try {
    var stored = localStorage.getItem(KEY);
    if (stored === "dark" || stored === "light") root.dataset.theme = stored;
  } catch (e) {
    // Storage blocked: the system setting decides, as without JavaScript.
  }

  function current() {
    if (root.dataset.theme) return root.dataset.theme;
    return matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
  }

  document.addEventListener("DOMContentLoaded", function () {
    var bar = document.querySelector(".masthead .tools") || document.querySelector(".masthead");
    if (!bar) return;

    var button = document.createElement("button");
    button.type = "button";
    button.className = "theme-toggle";
    button.textContent = "Dark mode";

    function sync() {
      button.setAttribute("aria-pressed", current() === "dark" ? "true" : "false");
    }

    button.addEventListener("click", function () {
      var next = current() === "dark" ? "light" : "dark";
      root.dataset.theme = next;
      try { localStorage.setItem(KEY, next); } catch (e) {}
      sync();
    });

    // Follow the system while the reader has not chosen.
    matchMedia("(prefers-color-scheme: light)").addEventListener("change", sync);

    sync();
    bar.appendChild(button);
  });
})();
