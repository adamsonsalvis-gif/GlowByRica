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
    }
}

// Hamburger menu toggle
const hamburger = document.getElementById('hamburger');
const navMenu = document.getElementById('nav-menu');

if (hamburger && navMenu) {
    hamburger.addEventListener('click', () => {
        hamburger.classList.toggle('open');
        navMenu.classList.toggle('open');
    });

    // Close menu when a link is clicked
    navMenu.querySelectorAll('a').forEach(link => {
        link.addEventListener('click', () => {
            hamburger.classList.remove('open');
            navMenu.classList.remove('open');
        });
    });
}

// Smooth scrolling for anchor links
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
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

// Page fade-in on load
window.addEventListener('load', () => {
    document.body.style.opacity = '0';
    document.body.style.transition = 'opacity 0.4s ease';
    document.body.offsetHeight;
    document.body.style.opacity = '1';
});

// Contact form AJAX submission
const contactForm = document.getElementById('contactForm');
if (contactForm) {
    contactForm.addEventListener('submit', async function(e) {
        e.preventDefault();
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

// Smooth page transition
function smoothNavigate(url) {
    document.body.style.transition = 'opacity 0.4s ease';
    document.body.style.opacity = '0';
    setTimeout(() => { window.location.href = url; }, 400);
}

// Learn More buttons
document.querySelectorAll('.service-button').forEach(button => {
    button.addEventListener('click', function (e) {
        e.preventDefault();
        smoothNavigate(this.getAttribute('href'));
    });
});

// Back to Home links
document.querySelectorAll('.back-link').forEach(link => {
    link.addEventListener('click', function (e) {
        e.preventDefault();
        smoothNavigate(this.getAttribute('href'));
    });
});

// Logo links on service pages
document.querySelectorAll('.page-hero-left a').forEach(link => {
    link.addEventListener('click', function (e) {
        e.preventDefault();
        smoothNavigate(this.getAttribute('href'));
    });
});
