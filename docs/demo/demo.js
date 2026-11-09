(() => {
  "use strict";

  const data = window.VIDEOGRAPHR_DEMO_DATA;
  const app = document.querySelector(".app");
  const views = [...document.querySelectorAll("[data-view]")];
  const navButtons = [...document.querySelectorAll("[data-tab]")];
  const toast = document.querySelector("#toast");
  const state = {
    scopes: new Map(data.scopes.map((scope) => [scope.id, scope.enabled])),
    markers: [...data.reflection.markers],
    speech: "pending",
    recording: false,
    seconds: 0,
  };
  let toastTimer;
  let recordTimer;
  let speechTimer;

  function showToast(message) {
    window.clearTimeout(toastTimer);
    toast.textContent = message;
    toast.hidden = false;
    toastTimer = window.setTimeout(() => { toast.hidden = true; }, 4200);
  }

  function setText(element, value) {
    element.textContent = value;
  }

  function time(seconds) {
    const hours = String(Math.floor(seconds / 3600)).padStart(2, "0");
    const minutes = String(Math.floor((seconds % 3600) / 60)).padStart(2, "0");
    const remaining = String(seconds % 60).padStart(2, "0");
    return `${hours}:${minutes}:${remaining}`;
  }

  function activeScopes() {
    return [...state.scopes.values()].filter(Boolean).length;
  }

  function isExportEligible() {
    return state.scopes.get("secondary") && state.scopes.get("sharing");
  }

  function make(tag, className, text) {
    const element = document.createElement(tag);
    if (className) element.className = className;
    if (text) element.textContent = text;
    return element;
  }

  function renderScopes() {
    const list = document.querySelector("#scope-list");
    list.replaceChildren(...data.scopes.map((scope) => {
      const item = make("li", "scope");
      const control = make("button", `switch${state.scopes.get(scope.id) ? " is-on" : ""}`);
      control.type = "button";
      control.dataset.scope = scope.id;
      control.setAttribute("role", "switch");
      control.setAttribute("aria-checked", String(state.scopes.get(scope.id)));
      control.setAttribute("aria-label", `${scope.label}: ${state.scopes.get(scope.id) ? "aktiv" : "inaktiv"}`);
      control.append(make("span"));
      const copy = document.createElement("div");
      copy.append(make("strong", "", scope.label), make("small", "", scope.detail));
      item.append(control, copy);
      return item;
    }));
    setText(document.querySelector("#consent-count"), `${activeScopes()} aktiv`);
    setText(document.querySelector("#consent-summary"), `Einwilligung ${activeScopes()}/4`);
  }

  function renderReadiness() {
    const sessionPresent = document.querySelector("#session-name").value.trim().length > 0;
    const checks = [
      [sessionPresent, "Sitzungskontext", "Zweck und Lernziel sind als Fixture angegeben."],
      [state.scopes.get("collection"), "Einwilligung", "Lokale Erhebung ist im Demo-Zustand aktiv."],
      [false, "Geräteprüfung", "Nur die native App kann Gerätebedingungen prüfen."],
      [state.speech === "done", "Sprechprobe", state.speech === "done" ? "Simulierte Probe abgeschlossen, kein Mikrofon verwendet." : "Noch nicht simuliert."],
    ];
    const open = checks.filter(([met]) => !met).length;
    const list = document.querySelector("#readiness-list");
    list.replaceChildren(...checks.map(([met, title, detail]) => {
      const item = make("li", met ? "check-met" : "");
      item.append(make("span", "check-mark", met ? "✓" : "○"));
      const copy = document.createElement("div");
      copy.append(make("strong", "", title), make("small", "", detail));
      item.append(copy);
      return item;
    }));
    setText(document.querySelector("#ready-count"), `${open} offen`);
    const notice = document.querySelector("#readiness-notice");
    notice.replaceChildren(make("strong", "", "Nicht nativ aufnahmebereit"), make("p", "", "Die Geräteprüfung bleibt in dieser Web-Demo ausdrücklich nicht verfügbar."));
  }

  function renderExport() {
    const notice = document.querySelector("#export-notice");
    const eligible = isExportEligible();
    notice.className = `callout ${eligible ? "callout-ok" : "callout-warn"}`;
    notice.replaceChildren(
      make("strong", "", eligible ? "Freigabe in der Demo vollständig" : "Export gesperrt"),
      make("p", "", eligible
        ? "Sekundärnutzung und externe Weitergabe sind aktiv. Die Web-Demo erzeugt trotzdem keine Datei."
        : "Sekundärnutzung und externe Weitergabe müssen beide aktiv sein.")
    );
  }

  function renderMarkers() {
    const list = document.querySelector("#marker-list");
    list.replaceChildren(...state.markers.map((marker) => make("span", "marker", `Zeitmarke ${marker}`)));
  }

  function renderSignals() {
    const speechReady = state.speech === "done";
    const signals = [
      ["Bild verfügbar", "○ Nicht prüfbar", "signal-unknown"],
      ["Belichtung", "○ Nicht prüfbar", "signal-unknown"],
      ["Kameraruhe", "○ Nicht prüfbar", "signal-unknown"],
      ["Audiopegel", speechReady ? "◐ Synthetische Anzeige" : "◐ Ohne Sprechprobe", "signal-warn"],
    ];
    const list = document.querySelector("#signal-list");
    list.replaceChildren(...signals.map(([label, value, valueClass], index) => {
      const item = document.createElement("li");
      item.append(make("span", "signal-label", label), make("span", `signal-value ${valueClass}`, value));
      if (index === 3) {
        const meter = make("div", "meter");
        meter.setAttribute("aria-hidden", "true");
        meter.append(make("div", "meter-fill"), make("div", "meter-mark"));
        item.append(meter);
      }
      return item;
    }));
  }

  function updateMeter() {
    const fill = document.querySelector(".meter-fill");
    if (fill) fill.style.width = state.recording ? `${22 + Math.round(Math.abs(Math.sin(state.seconds / 2)) * 54)}%` : "12%";
  }

  function setView(name, updateHash = true) {
    const next = views.find((view) => view.dataset.view === name) || views[0];
    views.forEach((view) => { view.hidden = view !== next; view.classList.toggle("is-active", view === next); });
    navButtons.forEach((button) => {
      const active = button.dataset.tab === next.dataset.view;
      button.classList.toggle("is-active", active);
      button.toggleAttribute("aria-current", active);
      if (active) button.setAttribute("aria-current", "page");
    });
    app.dataset.surface = next.dataset.view === "live" ? "night" : "day";
    if (updateHash) history.replaceState(null, "", `#${next.dataset.view}`);
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    window.scrollTo({ top: 0, behavior: reduced ? "auto" : "smooth" });
    next.querySelector("h1")?.focus({ preventScroll: true });
  }

  function startSpeech() {
    if (state.speech === "running") return;
    state.speech = "running";
    let remaining = 10;
    const status = document.querySelector("#speech-status");
    setText(status, "Simulation 10 s");
    showToast("Sprechprobe wird nur sichtbar simuliert. Es wird kein Mikrofon verwendet.");
    window.clearInterval(speechTimer);
    speechTimer = window.setInterval(() => {
      remaining -= 1;
      setText(status, `Simulation ${remaining} s`);
      if (remaining <= 0) {
        window.clearInterval(speechTimer);
        state.speech = "done";
        status.className = "badge badge-ok";
        setText(status, "Simuliert abgeschlossen");
        document.querySelector("#live-notice").replaceChildren(make("strong", "", "Sprechprobe simuliert"), make("p", "", "Es wurde kein Ton aufgenommen, gespeichert oder ausgewertet."));
        renderReadiness();
        renderSignals();
        showToast("Sprechprobe simuliert abgeschlossen. Keine Audioinhalte wurden erfasst.");
      }
    }, 1000);
  }

  function toggleRecording() {
    state.recording = !state.recording;
    const button = document.querySelector("#record-button");
    const recordState = document.querySelector("#record-state");
    button.classList.toggle("is-recording", state.recording);
    button.setAttribute("aria-pressed", String(state.recording));
    button.setAttribute("aria-label", state.recording ? "Simulierte Aufnahme stoppen" : "Simulierte Aufnahme starten");
    if (state.recording) {
      setText(document.querySelector("#protocol-state"), "Simulation läuft");
      setText(recordState, "Simulierter Take läuft, keine Aufnahme");
      showToast("Simulierter Take gestartet. Es wird weder Kamera noch Mikrofon verwendet.");
      recordTimer = window.setInterval(() => {
        state.seconds += 1;
        setText(document.querySelector("#record-timer"), time(state.seconds));
        updateMeter();
      }, 1000);
    } else {
      window.clearInterval(recordTimer);
      const duration = time(state.seconds);
      state.seconds = 0;
      setText(document.querySelector("#record-timer"), "00:00:00");
      setText(document.querySelector("#protocol-state"), "Entwurf");
      setText(recordState, "Bereit zur simulierten Aufnahme");
      updateMeter();
      showToast(`Simulierter Take nach ${duration} beendet. Es wurde kein Medium erzeugt.`);
    }
  }

  function openTopic(id) {
    const topic = data.catalogue.find((entry) => entry.id === id);
    if (!topic) return;
    document.querySelector("#catalogue-list").hidden = true;
    const reader = document.querySelector("#reader");
    reader.hidden = false;
    setText(document.querySelector("#reader-kicker"), topic.label);
    setText(document.querySelector("#reader-title"), topic.title);
    const content = document.querySelector("#reader-content");
    content.replaceChildren(...topic.paragraphs.map((paragraph) => make("p", "", paragraph)));
    reader.focus();
  }

  function renderCatalogue() {
    const list = document.querySelector("#catalogue-list");
    list.replaceChildren(...data.catalogue.map((topic, index) => {
      const button = make("button", "catalogue-row");
      button.type = "button";
      button.dataset.topic = topic.id;
      button.append(make("span", "catalogue-number", String(index + 1).padStart(2, "0")));
      const copy = document.createElement("span");
      copy.append(make("strong", "", `${topic.label}: ${topic.title}`), make("small", "", topic.summary));
      button.append(copy, make("span", "catalogue-arrow", "→"));
      return button;
    }));
  }

  const actions = new Map([
    ["goto-live", () => setView("live")],
    ["record", toggleRecording],
    ["speech", startSpeech],
    ["save-consent", () => showToast("Einwilligungsstand nur simuliert. Es wurde nichts gespeichert.")],
    ["show-document", () => showToast("Dokumentversion ist nur eine simulierte native Aktion.")],
    ["import", () => showToast("Dateizugriff ist deaktiviert. Es wurde keine MP4 ausgewählt.")],
    ["save-note", () => showToast("Notiz nur simuliert gespeichert. Die Demo persistiert nichts.")],
    ["marker", () => {
      const candidates = ["16:08", "31:26", "39:54"];
      const marker = candidates[state.markers.length - data.reflection.markers.length] || "44:12";
      state.markers.push(marker); renderMarkers(); showToast(`Zeitmarke ${marker} nur simuliert hinzugefügt.`);
    }],
    ["export", () => showToast(isExportEligible() ? "Paket wäre in der Demo freigegeben. Es wurde keine .videographrstudy-Datei erzeugt." : "Paket bleibt simuliert gesperrt, bis beide erforderlichen Scopes aktiv sind.")],
    ["back-catalogue", () => {
      document.querySelector("#reader").hidden = true;
      document.querySelector("#catalogue-list").hidden = false;
      document.querySelector("[data-topic]")?.focus();
    }]
  ]);

  document.addEventListener("click", (event) => {
    const scope = event.target.closest("[data-scope]");
    if (scope) {
      const id = scope.dataset.scope;
      state.scopes.set(id, !state.scopes.get(id));
      renderScopes(); renderReadiness(); renderExport();
      return;
    }
    const tab = event.target.closest("[data-tab]");
    if (tab) { setView(tab.dataset.tab); return; }
    const topic = event.target.closest("[data-topic]");
    if (topic) { openTopic(topic.dataset.topic); return; }
    const action = event.target.closest("[data-action]")?.dataset.action;
    actions.get(action)?.();
  });

  document.querySelector("#session-name").addEventListener("input", renderReadiness);
  document.querySelector("#reflection-note").addEventListener("input", (event) => {
    setText(document.querySelector("#note-summary"), event.target.value.trim() ? "1 / 4 Antworten" : "0 / 4 Antworten");
  });
  window.addEventListener("hashchange", () => setView(location.hash.slice(1), false));

  document.querySelector("#reflection-note").value = data.reflection.note;
  renderScopes(); renderReadiness(); renderExport(); renderMarkers(); renderSignals(); renderCatalogue();
  setView(location.hash.slice(1) || "setup", false);
})();
