(function () {
  const clock = document.querySelector("[data-mission-clock]");
  if (clock) {
    const tick = () => {
      const d = new Date();
      clock.textContent = d.toISOString().replace("T", " ").replace(/\.\d+Z$/, "Z");
    };
    tick();
    setInterval(tick, 1000);
  }
})();
