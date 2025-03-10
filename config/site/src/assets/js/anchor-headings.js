// Add anchor links to headings
document.addEventListener('DOMContentLoaded', function() {
  const headings = document.querySelectorAll('article h2, article h3, article h4');

  headings.forEach(heading => {
    // Generate ID from heading text
    if (!heading.id) {
      heading.id = heading.textContent
        .toLowerCase()
        .replace(/[^\w\- ]/g, '') // Remove special characters
        .replace(/\s+/g, '-'); // Replace spaces with hyphens
    }

    // Create anchor link
    const anchor = document.createElement('a');
    anchor.href = `#${heading.id}`;
    anchor.className = 'heading-anchor';
    anchor.setAttribute('aria-hidden', 'true');
    anchor.innerHTML = `<svg class="octicon" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
      <path d="m7.775 3.275 1.25-1.25a3.5 3.5 0 1 1 4.95 4.95l-2.5 2.5a3.5 3.5 0 0 1-4.95 0 .751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018 1.998 1.998 0 0 0 2.83 0l2.5-2.5a2.002 2.002 0 0 0-2.83-2.83l-1.25 1.25a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042Zm-4.69 9.64a1.998 1.998 0 0 0 2.83 0l1.25-1.25a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042l-1.25 1.25a3.5 3.5 0 1 1-4.95-4.95l2.5-2.5a3.5 3.5 0 0 1 4.95 0 .751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018 1.998 1.998 0 0 0-2.83 0l-2.5 2.5a1.998 1.998 0 0 0 0 2.83Z"></path>
    </svg>`;

    // Add anchor link before heading content
    heading.insertBefore(anchor, heading.firstChild);

    // Add hover class to show anchor on heading hover
    heading.classList.add('has-anchor');
  });
});
