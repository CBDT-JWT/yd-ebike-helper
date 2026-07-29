const root = document.documentElement;
const themeToggle = document.querySelector("[data-theme-toggle]");
const storedTheme = localStorage.getItem("yd-theme");

if (storedTheme === "light" || storedTheme === "dark") {
  root.dataset.theme = storedTheme;
}

function currentTheme() {
  if (root.dataset.theme) {
    return root.dataset.theme;
  }
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function updateThemeLabel() {
  const nextTheme = currentTheme() === "dark" ? "浅色" : "深色";
  themeToggle.textContent = nextTheme;
  themeToggle.setAttribute("aria-label", `切换到${nextTheme}主题`);
}

themeToggle.addEventListener("click", () => {
  const nextTheme = currentTheme() === "dark" ? "light" : "dark";
  root.dataset.theme = nextTheme;
  localStorage.setItem("yd-theme", nextTheme);
  updateThemeLabel();
});

updateThemeLabel();

const revealItems = document.querySelectorAll(".reveal");

if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.14 }
  );

  revealItems.forEach((item) => observer.observe(item));
} else {
  revealItems.forEach((item) => item.classList.add("is-visible"));
}
