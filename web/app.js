(async () => {
  const out = document.getElementById("out");
  try {
    const res = await fetch("./latest.json", { cache: "no-store" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    out.textContent = JSON.stringify(data, null, 2);
  } catch (e) {
    out.textContent = `Failed to load latest.json: ${e}`;
  }
})();
