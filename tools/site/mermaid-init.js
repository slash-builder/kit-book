// Turns mermaid code blocks in the book into diagrams. Included on every page by mdBook (additional-js).
//
// mdBook renders a mermaid code fence as <pre><code class="language-mermaid">source</code></pre>. This script
// replaces each one with a <div class="mermaid"> and draws it with the vendored copy of mermaid
// (tools/site/vendor/mermaid.min.js, served from the site root as mermaid.min.js). Nothing is loaded from another host.
// The big file is only requested on pages that actually have a diagram.
//
// The diagram theme follows the book theme: mdBook puts the theme name (light, rust, coal, navy, ayu) on <html> as a
// class; coal, navy and ayu are dark. When the reader changes the theme the diagrams are drawn again.
(function () {
  "use strict";

  var DARK = ["coal", "navy", "ayu"];
  var blocks = Array.prototype.slice.call(document.querySelectorAll("pre > code.language-mermaid"));
  if (blocks.length === 0) { return; }

  function isDark() {
    var cls = document.documentElement.classList;
    for (var i = 0; i < DARK.length; i++) { if (cls.contains(DARK[i])) { return true; } }
    return false;
  }

  // Swap the code blocks for placeholders that remember their source, so a theme change can redraw them.
  var nodes = blocks.map(function (code) {
    var pre = code.parentNode;
    var div = document.createElement("div");
    div.className = "mermaid";
    div.setAttribute("data-mermaid-source", code.textContent);
    div.textContent = code.textContent; // shown as plain text until the diagram is drawn (or if it cannot be)
    div.style.whiteSpace = "pre-wrap";
    pre.parentNode.replaceChild(div, pre);
    return div;
  });

  var drawn = null; // "dark" or "light": the theme the diagrams are drawn in right now
  var drawing = false;
  var again = false;

  var counter = 0;

  // Draw every diagram in the given theme, one after the other. Each gets its own id so the styles of one diagram can
  // never apply to another.
  function drawAll(want) {
    window.mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme: want === "dark" ? "dark" : "default"
    });
    return nodes.reduce(function (previous, div) {
      return previous.then(function () {
        counter += 1;
        return window.mermaid.render("kit-book-diagram-" + counter, div.getAttribute("data-mermaid-source")).then(function (out) {
          div.innerHTML = out.svg;
          div.setAttribute("data-processed", "true");
          div.style.whiteSpace = "";
        }, function (err) {
          // mermaid may leave its own error drawing in the page body; the source stays visible in place of the diagram.
          var junk = document.getElementById("dkit-book-diagram-" + counter);
          if (junk && junk.parentNode) { junk.parentNode.removeChild(junk); }
          div.removeAttribute("data-processed");
          div.textContent = div.getAttribute("data-mermaid-source");
          div.className = "mermaid mermaid-failed";
          div.style.whiteSpace = "pre-wrap";
          if (window.console) { console.error("mermaid: a diagram could not be drawn", err); }
        });
      });
    }, Promise.resolve());
  }

  function draw() {
    if (drawing) { again = true; return; }
    var want = isDark() ? "dark" : "light";
    if (drawn === want) { return; }
    drawing = true;
    drawAll(want).then(function () {
      drawn = want;
      drawing = false;
      if (again) { again = false; draw(); }
    });
  }

  function start() {
    draw();
    // mdBook changes the class of <html> when the reader picks a theme.
    new MutationObserver(draw).observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });
  }

  var root = (typeof path_to_root === "string") ? path_to_root : "";
  var script = document.createElement("script");
  script.src = root + "mermaid.min.js";
  script.onload = start;
  script.onerror = function () {
    if (window.console) { console.error("mermaid: could not load " + script.src + "; the diagrams stay as source"); }
  };
  document.head.appendChild(script);
})();
