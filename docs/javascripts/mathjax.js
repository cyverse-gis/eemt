// MathJax 3 configuration for EEMT documentation
window.MathJax = {
  tex: {
    inlineMath: [["\\(", "\\)"], ["$", "$"]],
    displayMath: [["\\[", "\\]"], ["$$", "$$"]],
    processEscapes: true,
    processEnvironments: true,
    macros: {
      // EEMT units
      MJm: "\\text{MJ}\\,\\text{m}^{-2}",
      MJmyr: "\\text{MJ}\\,\\text{m}^{-2}\\,\\text{yr}^{-1}",
      kJmol: "\\text{kJ}\\,\\text{mol}^{-1}",
      mmyr: "\\text{mm}\\,\\text{yr}^{-1}",
      degC: "°\\text{C}",
      // EEMT symbols
      EEMT: "\\text{EEMT}",
      Ebio: "E_{\\text{BIO}}",
      Eppt: "E_{\\text{PPT}}",
      Etopo: "E_{\\text{TOPO}}"
    }
  },
  options: {
    ignoreHtmlClass: ".*|",
    processHtmlClass: "arithmatex"
  },
  svg: {
    fontCache: "global"
  }
};

// Auto-classify parameter tables
document$.subscribe(function() {
  document.querySelectorAll("table").forEach(function(table) {
    var headers = table.querySelectorAll("th");
    if (headers.length > 0) {
      var first = headers[0].textContent.toLowerCase();
      if (first.indexOf("parameter") >= 0 || first.indexOf("variable") >= 0 || first.indexOf("component") >= 0) {
        table.classList.add("parameter-table");
      }
    }
  });
});
