// MathJax configuration for EEMT documentation

window.MathJax = {
  tex: {
    inlineMath: [["\\(", "\\)"], ["$", "$"]],
    displayMath: [["\\[", "\\]"], ["$$", "$$"]],
    processEscapes: true,
    processEnvironments: true,
    packages: {'[+]': ['ams', 'physics', 'mhchem']},
    // Custom macros for EEMT units and symbols
    macros: {
      // SI units
      unit: ["\\text{#1}", 1],
      si: ["\\,\\text{#1}", 1],
      SI: ["#1\\,\\text{#2}", 2],
      // Common EEMT units
      MJm: "\\text{MJ}\\,\\text{m}^{-2}",
      MJmyr: "\\text{MJ}\\,\\text{m}^{-2}\\,\\text{yr}^{-1}",
      kJmol: "\\text{kJ}\\,\\text{mol}^{-1}",
      mmyr: "\\text{mm}\\,\\text{yr}^{-1}",
      degC: "°\\text{C}",
      // EEMT components
      EEMT: "\\text{EEMT}",
      Ebio: "E_{\\text{BIO}}",
      Eppt: "E_{\\text{PPT}}",
      Etopo: "E_{\\text{TOPO}}",
      // Greek letters commonly used
      alpha: "\\alpha",
      beta: "\\beta",
      lambda: "\\lambda"
    }
  },
  options: {
    ignoreHtmlClass: ".*|",
    processHtmlClass: "arithmatex"
  },
  svg: {
    fontCache: 'global'
  }
};

// Custom EEMT equation formatting
document$.subscribe(() => {
  // Add special styling for EEMT equations
  const eemtEquations = document.querySelectorAll('.eemt-equation .MathJax');
  eemtEquations.forEach(eq => {
    eq.style.fontSize = '1.2em';
    eq.style.color = 'var(--md-primary-fg-color)';
  });
  
  // Add copy button to code blocks with equations
  const codeBlocks = document.querySelectorAll('pre code');
  codeBlocks.forEach(block => {
    if (block.textContent.includes('EEMT') || 
        block.textContent.includes('E_BIO') || 
        block.textContent.includes('E_PPT')) {
      
      const copyButton = document.createElement('button');
      copyButton.className = 'md-clipboard md-icon';
      copyButton.title = 'Copy EEMT equation';
      copyButton.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M19,21H8V7H19M19,5H8A2,2 0 0,0 6,7V21A2,2 0 0,0 8,23H19A2,2 0 0,0 21,21V7A2,2 0 0,0 19,5M16,1H4A2,2 0 0,0 2,3V17H4V3H16V1Z"></path></svg>';
      
      copyButton.addEventListener('click', () => {
        navigator.clipboard.writeText(block.textContent);
        copyButton.style.color = 'var(--md-accent-fg-color)';
        setTimeout(() => {
          copyButton.style.color = '';
        }, 1000);
      });
      
      block.parentElement.style.position = 'relative';
      block.parentElement.appendChild(copyButton);
    }
  });
});

// Parameter table enhancements
document$.subscribe(() => {
  const paramTables = document.querySelectorAll('table');
  paramTables.forEach(table => {
    const headers = table.querySelectorAll('th');
    if (headers.length > 0) {
      const firstHeader = headers[0].textContent.toLowerCase();
      if (firstHeader.includes('parameter') || 
          firstHeader.includes('variable') ||
          firstHeader.includes('component')) {
        table.classList.add('parameter-table');
      }
    }
  });
});

// Workflow status indicators
document$.subscribe(() => {
  const statusElements = document.querySelectorAll('.workflow-status');
  statusElements.forEach(element => {
    const status = element.textContent.toLowerCase().trim();
    if (status.includes('complete') || status.includes('✓')) {
      element.classList.add('completed');
    } else if (status.includes('progress') || status.includes('running')) {
      element.classList.add('in-progress');
    } else if (status.includes('pending') || status.includes('todo')) {
      element.classList.add('pending');
    }
  });
});

// Auto-format inline units in .unit-value elements
document$.subscribe(() => {
  const unitElements = document.querySelectorAll('.unit-value');
  unitElements.forEach(element => {
    let text = element.textContent;
    // Format common unit patterns with proper styling
    text = text
      .replace(/MJ\/m²\/yr/g, 'MJ m⁻² yr⁻¹')
      .replace(/MJ m-2 yr-1/g, 'MJ m⁻² yr⁻¹')
      .replace(/mm\/yr/g, 'mm yr⁻¹')
      .replace(/kJ\/mol/g, 'kJ mol⁻¹')
      .replace(/W\/m²/g, 'W m⁻²')
      .replace(/kg\/m²/g, 'kg m⁻²')
      .replace(/m²/g, 'm²')
      .replace(/m³/g, 'm³');
    element.textContent = text;
  });
});

// Auto-detect and style EEMT range values (e.g., "5-15 MJ/m²/yr")
document$.subscribe(() => {
  // Find elements with eemt-range class and format their units
  const rangeElements = document.querySelectorAll('.eemt-range');
  rangeElements.forEach(element => {
    let text = element.innerHTML;
    // Convert ASCII fractions to proper unit notation
    text = text
      .replace(/MJ\/m²\/yr/g, '<span class="unit">MJ m<sup>−2</sup> yr<sup>−1</sup></span>')
      .replace(/MJ m-2 yr-1/g, '<span class="unit">MJ m<sup>−2</sup> yr<sup>−1</sup></span>')
      .replace(/(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)/g, '$1–$2'); // en-dash for ranges
    element.innerHTML = text;
  });

  // Also handle standalone .unit elements
  const unitSpans = document.querySelectorAll('.unit:not(.unit-formatted)');
  unitSpans.forEach(element => {
    element.classList.add('unit-formatted');
  });
});