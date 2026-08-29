const navToggle = document.querySelector('.menu-toggle');
const siteNav = document.querySelector('.site-nav');

if (navToggle && siteNav) {
  navToggle.addEventListener('click', () => {
    const isOpen = navToggle.getAttribute('aria-expanded') === 'true';
    navToggle.setAttribute('aria-expanded', String(!isOpen));
    siteNav.classList.toggle('is-open', !isOpen);
  });

  siteNav.querySelectorAll('a').forEach((link) => {
    link.addEventListener('click', () => {
      navToggle.setAttribute('aria-expanded', 'false');
      siteNav.classList.remove('is-open');
    });
  });
}

const reveals = document.querySelectorAll('.reveal');

if ('IntersectionObserver' in window) {
  const revealObserver = new IntersectionObserver(
    (entries, observer) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    },
    { rootMargin: '0px 0px -8% 0px', threshold: 0.08 },
  );

  reveals.forEach((element) => revealObserver.observe(element));
} else {
  reveals.forEach((element) => element.classList.add('is-visible'));
}

const snippets = [
  'The distinction between Time and any of the three dimensions of Space is only this…',
  'We can move about in all three dimensions, but not freely in Time.',
  'The scientific people, however, know very well that Time is only a kind of Space.',
  'There are really four dimensions, three of which we call the three planes of Space…',
];

const nextSnippet = document.querySelector('#next-snippet');
const snippetText = document.querySelector('#snippet-text');
const snippetCount = document.querySelector('#snippet-count');
const progressLine = document.querySelector('.reader-progress-line span');
const progressLabel = document.querySelector('.reader-progress > span');
const currentSnippet = document.querySelector('.snippet-current');

if (nextSnippet && snippetText && snippetCount && progressLine && progressLabel && currentSnippet) {
  let snippetIndex = 0;

  nextSnippet.addEventListener('click', () => {
    currentSnippet.classList.add('is-changing');

    window.setTimeout(() => {
      snippetIndex = (snippetIndex + 1) % snippets.length;
      const percentage = 12 + snippetIndex * 6;
      snippetText.textContent = snippets[snippetIndex];
      snippetCount.textContent = `${String(snippetIndex + 1).padStart(2, '0')} / 04`;
      progressLine.style.width = `${percentage}%`;
      progressLabel.textContent = `${percentage}%`;
      currentSnippet.classList.remove('is-changing');
    }, 170);
  });
}

const year = document.querySelector('#year');

if (year) {
  year.textContent = new Date().getFullYear();
}
