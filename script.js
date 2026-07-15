// Scroll to top button
const scrollTopBtn = document.getElementById('scrollTop');
if (scrollTopBtn) {
    window.addEventListener('scroll', () => {
        const scrollY = window.scrollY;
        const maxScroll = document.body.scrollHeight - window.innerHeight;

        if (scrollY > 300) {
            scrollTopBtn.classList.add('visible');
            // Starts very transparent, gets more solid the further you scroll
            const scrollProgress = (scrollY - 300) / (maxScroll - 300);
            const opacity = Math.min(0.85, 0.1 + scrollProgress * 0.75);
            scrollTopBtn.style.opacity = opacity;
        } else {
            scrollTopBtn.classList.remove('visible');
            scrollTopBtn.style.opacity = 0;
        }
    });

    scrollTopBtn.addEventListener('click', () => {
        window.scrollTo({ top: 0, behavior: 'smooth' });
    });
}

// Match About Rica divider width to just the text
window.addEventListener('load', () => {
    const aboutTitle = document.querySelector('.about-text .section-title');
    const aboutDivider = document.querySelector('.about-text .section-divider');
    if (aboutTitle && aboutDivider) {
        const range = document.createRange();
        range.selectNodeContents(aboutTitle);
        const textWidth = range.getBoundingClientRect().width;
        aboutDivider.style.width = textWidth + 'px';
    }
});

// Sparkle effect on hero logo
const heroLogo = document.querySelector('.hero-logo');
if (heroLogo) {
    let sparkleInterval = null;

    function createLogoSparkle() {
        const rect = heroLogo.getBoundingClientRect();
        const symbols = ['✦', '✧', '⋆', '★', '✵'];
        const sparkle = document.createElement('span');
        sparkle.classList.add('sparkle-particle');
        sparkle.textContent = symbols[Math.floor(Math.random() * symbols.length)];

        // random position around the logo border
        const x = rect.left + Math.random() * rect.width;
        const y = rect.top + Math.random() * rect.height;

        const angle = Math.random() * Math.PI * 2;
        const distance = 30 + Math.random() * 40;
        const tx = Math.cos(angle) * distance + 'px';
        const ty = Math.sin(angle) * distance + 'px';

        sparkle.style.setProperty('--tx', tx);
        sparkle.style.setProperty('--ty', ty);
        sparkle.style.left = x + 'px';
        sparkle.style.top = y + 'px';
        sparkle.style.fontSize = (Math.random() * 10 + 8) + 'px';

        document.body.appendChild(sparkle);
        setTimeout(() => sparkle.remove(), 800);
    }

    if (window.matchMedia('(hover: hover)').matches) {
        heroLogo.addEventListener('mouseenter', () => {
            sparkleInterval = setInterval(createLogoSparkle, 80);
        });

        heroLogo.addEventListener('mouseleave', () => {
            clearInterval(sparkleInterval);
        });
    } else {
        // Touch devices have no hover — sparkle automatically while the logo is on screen
        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    if (!sparkleInterval) {
                        sparkleInterval = setInterval(createLogoSparkle, 300);
                    }
                } else if (sparkleInterval) {
                    clearInterval(sparkleInterval);
                    sparkleInterval = null;
                }
            });
        }, { threshold: 0.3 });

        observer.observe(heroLogo);
    }
}

// Services dropdown toggle
const servicesDropdown = document.querySelector('.has-dropdown');
if (servicesDropdown) {
    servicesDropdown.querySelector('a').addEventListener('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        servicesDropdown.classList.toggle('open');
    });

    // Close dropdown when clicking outside
    document.addEventListener('click', (e) => {
        if (!servicesDropdown.contains(e.target)) {
            servicesDropdown.classList.remove('open');
        }
    });
}

// Hamburger menu toggle
const hamburger = document.getElementById('hamburger');
const navMenu = document.getElementById('nav-menu');

if (hamburger && navMenu) {
    hamburger.addEventListener('click', () => {
        hamburger.classList.toggle('open');
        navMenu.classList.toggle('open');
    });

    // Close menu when a link is clicked (but not the services dropdown toggle)
    navMenu.querySelectorAll('a').forEach(link => {
        link.addEventListener('click', () => {
            const parentLi = link.closest('li');
            if (parentLi && parentLi.classList.contains('has-dropdown')) return;
            hamburger.classList.remove('open');
            navMenu.classList.remove('open');
        });
    });
}

// Clean URL hash on page load and scroll to section
window.addEventListener('load', () => {
    if (window.location.hash) {
        const target = document.querySelector(window.location.hash);
        if (target) target.scrollIntoView({ behavior: 'instant', block: 'start' });
        history.replaceState(null, null, window.location.pathname);
    }
});

// Custom select dropdowns
document.querySelectorAll('.custom-select').forEach(select => {
    const trigger = select.querySelector('.custom-select-trigger');
    const options = select.querySelectorAll('.custom-select-options li');
    const hiddenInput = select.parentElement.querySelector('input[type="hidden"]');

    trigger.addEventListener('click', (e) => {
        e.stopPropagation();
        document.querySelectorAll('.custom-select.open').forEach(s => { if (s !== select) s.classList.remove('open'); });
        select.classList.toggle('open');
    });

    options.forEach(option => {
        option.addEventListener('click', () => {
            trigger.textContent = option.dataset.value;
            hiddenInput.value = option.dataset.value;
            select.classList.add('selected');
            select.classList.remove('open');
        });
    });
});

document.addEventListener('click', () => {
    document.querySelectorAll('.custom-select.open').forEach(s => s.classList.remove('open'));
});

// Book a Consultation buttons — scroll without hash
document.querySelectorAll('[data-scroll]').forEach(btn => {
    btn.addEventListener('click', function(e) {
        e.preventDefault();
        e.stopImmediatePropagation();
        const target = document.getElementById(this.dataset.scroll);
        if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
});

// Smooth scrolling for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        // Skip dropdown toggle links
        if (this.closest('.has-dropdown') && !this.closest('.dropdown-menu')) {
            e.preventDefault();
            return;
        }
        const targetId = this.getAttribute('href');
        if (targetId === '#') {
            e.preventDefault();
            window.scrollTo({ top: 0, behavior: 'smooth' });
            return;
        }
        const targetElement = document.querySelector(targetId);
        if (targetElement) {
            e.preventDefault();
            targetElement.scrollIntoView({ behavior: 'smooth', block: 'start' });
            setTimeout(() => history.replaceState(null, null, window.location.pathname), 10);
        }
    });
});

// Fade-in sections on scroll
const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.style.opacity = '1';
            entry.target.style.transform = 'translateY(0)';
            observer.unobserve(entry.target);
        }
    });
}, { threshold: 0.1, rootMargin: '0px 0px -80px 0px' });

document.querySelectorAll('section').forEach(section => {
    section.style.opacity = '0';
    section.style.transform = 'translateY(20px)';
    section.style.transition = 'opacity 1s ease, transform 1s ease';
    observer.observe(section);
});

// Contact form AJAX submission
const contactForm = document.getElementById('contactForm');
if (contactForm) {
    contactForm.addEventListener('submit', async function(e) {
        e.preventDefault();

        // Hidden inputs (treatment select, date/time picker) skip native
        // validation, so check them here and flash the field if empty.
        const missing = Array.from(contactForm.querySelectorAll('input[type="hidden"][required]')).filter(i => !i.value);
        if (missing.length) {
            missing.forEach(i => {
                const box = i.closest('.custom-select-wrapper, .datetime-wrapper');
                const t = box && box.querySelector('.custom-select, .datetime-trigger');
                if (t) {
                    t.style.borderColor = '#e05c5c';
                    setTimeout(() => { t.style.borderColor = ''; }, 2500);
                }
            });
            return;
        }

        const data = new FormData(contactForm);
        try {
            const response = await fetch(contactForm.action, {
                method: 'POST',
                body: data,
                headers: { 'Accept': 'application/json' }
            });
            if (response.ok) {
                contactForm.innerHTML = `
                    <div class="form-success">
                        <span>✦</span>
                        Your message has been sent!<br>We'll be in touch with you soon.
                    </div>`;
            }
        } catch (err) {
            console.error(err);
        }
    });
}

