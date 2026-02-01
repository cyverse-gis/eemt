// MathJax configuration for EEMT documentation

window.MathJax = {
  tex: {
    inlineMath: [["\\(", "\\)"], ["$", "$"]],
    displayMath: [["\\[", "\\]"], ["$$", "$$"]],
    processEscapes: true,
    processEnvironments: true,
    packages: {'[+]': ['ams', 'physics', 'mhchem']}
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