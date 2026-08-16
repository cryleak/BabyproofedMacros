(() => {
  "use strict";

  const app = {
    ahk: null,
    state: null,
    activeTab: null,
    tabTransition: null,
    dirty: false,
    capture: null,
    updateInfo: null,
    updateDialogOpen: false,
    updateInstalling: false,
    appearanceMenuOpen: null,
    colorTheme: "monochrome",
    layout: "orbit",
    colorThemes: [
      { id: "neon", name: "Neon Spectrum" },
      { id: "midnight", name: "Midnight" },
      { id: "sunset", name: "Sunset" },
      { id: "arctic", name: "Arctic" },
      { id: "monochrome", name: "Monochrome" },
      { id: "rosewood", name: "Rosewood" },
      { id: "solar", name: "Solar" },
      { id: "blueprint", name: "Blueprint" }
    ],
    layouts: [
      { id: "orbit", name: "Orbit Station" },
      { id: "toprail", name: "Top Rail" }
    ],

    initTheme() {
      this.initAppearancePicker("color", this.colorThemes);
      this.initAppearancePicker("layout", this.layouts);
      document.addEventListener("click", event => {
        if (!event.target.closest(".theme-select-shell")) this.setAppearanceMenuOpen(null, false);
      });

      let colorTheme = "monochrome";
      let layout = "orbit";
      try {
        colorTheme = localStorage.getItem("bpm-ui-color") || "";
        layout = localStorage.getItem("bpm-ui-layout") || "";
        if (!colorTheme || !layout) {
          const legacy = localStorage.getItem("bpm-ui-theme");
          const migration = {
            neon: ["neon", "orbit"], terminal: ["midnight", "orbit"], sunset: ["sunset", "orbit"],
            arctic: ["arctic", "orbit"], tactical: ["blueprint", "orbit"], vaporwave: ["midnight", "orbit"],
            monochrome: ["monochrome", "orbit"], blueprint: ["blueprint", "toprail"], solar: ["solar", "orbit"],
            rosewood: ["rosewood", "orbit"], orbit: ["midnight", "orbit"]
          }[legacy];
          if (migration) {
            colorTheme ||= migration[0];
            layout ||= migration[1];
          }
        }
      } catch (_) {
        // WebView2 profiles can be configured without storage access.
      }
      if (!this.colorThemes.some(item => item.id === colorTheme)) colorTheme = "monochrome";
      if (!this.layouts.some(item => item.id === layout)) layout = "orbit";
      this.applyColorTheme(colorTheme || "monochrome", false);
      this.applyLayout(layout || "orbit", false);
    },

    initAppearancePicker(kind, items) {
      const trigger = document.getElementById(`${kind}-select`);
      const menu = document.getElementById(`${kind}-menu`);
      if (!trigger || !menu) return;
      menu.replaceChildren();
      items.forEach(item => {
        const option = document.createElement("button");
        option.className = "theme-option";
        option.type = "button";
        option.setAttribute("role", "option");
        option.dataset.appearanceOption = item.id;
        const swatch = document.createElement("span");
        swatch.className = "theme-swatch theme-option-swatch";
        swatch.dataset.themeSwatch = item.id;
        swatch.setAttribute("aria-hidden", "true");
        const copy = document.createElement("span");
        copy.className = "theme-option-copy";
        const name = document.createElement("span");
        name.className = "theme-option-name";
        name.textContent = item.name;
        copy.append(name);
        const check = document.createElement("span");
        check.className = "theme-option-check";
        check.textContent = "✓";
        check.setAttribute("aria-hidden", "true");
        option.append(swatch, copy, check);
        option.addEventListener("click", () => {
          kind === "color" ? this.applyColorTheme(item.id, true) : this.applyLayout(item.id, true);
          this.setAppearanceMenuOpen(kind, false);
          trigger.focus();
        });
        option.addEventListener("keydown", event => this.onAppearanceOptionKeyDown(event, kind, item.id));
        menu.appendChild(option);
      });
      trigger.addEventListener("click", () => this.setAppearanceMenuOpen(kind, this.appearanceMenuOpen !== kind));
      trigger.addEventListener("keydown", event => this.onAppearanceTriggerKeyDown(event, kind));
    },

    applyColorTheme(themeId, announce = false) {
      const theme = this.colorThemes.find(item => item.id === themeId) || this.colorThemes.find(item => item.id === "monochrome") || this.colorThemes[0];
      this.colorTheme = theme.id;
      document.documentElement.dataset.colorTheme = theme.id;
      this.updateAppearancePicker("color", theme);
      try { localStorage.setItem("bpm-ui-color", theme.id); } catch (_) {}
      if (announce) this.toast(`Color: ${theme.name}`, "success");
    },

    applyLayout(layoutId, announce = false) {
      const layout = this.layouts.find(item => item.id === layoutId) || this.layouts[0];
      this.layout = layout.id;
      document.documentElement.dataset.layout = layout.id;
      this.updateAppearancePicker("layout", layout);
      try { localStorage.setItem("bpm-ui-layout", layout.id); } catch (_) {}
      if (announce) this.toast(`Layout: ${layout.name}`, "success");
    },

    updateAppearancePicker(kind, item) {
      const trigger = document.getElementById(`${kind}-select`);
      const name = document.getElementById(`${kind}-select-name`);
      const swatch = document.getElementById(`${kind}-swatch`);
      if (trigger) trigger.setAttribute("aria-label", `Choose ${kind}. Current selection: ${item.name}`);
      if (name) name.textContent = item.name;
      if (swatch) swatch.dataset.themeSwatch = item.id;
      document.querySelectorAll(`#${kind}-menu .theme-option`).forEach(option => {
        const active = option.dataset.appearanceOption === item.id;
        option.classList.toggle("active", active);
        option.setAttribute("aria-selected", active ? "true" : "false");
      });
    },

    setAppearanceMenuOpen(kind, open) {
      document.querySelectorAll(".theme-select-shell").forEach(shell => {
        const shellKind = shell.dataset.appearanceKind;
        const isOpen = Boolean(open && shellKind === kind);
        shell.classList.toggle("open", isOpen);
        const menu = document.getElementById(`${shellKind}-menu`);
        const trigger = document.getElementById(`${shellKind}-select`);
        if (menu) menu.hidden = !isOpen;
        if (trigger) trigger.setAttribute("aria-expanded", isOpen ? "true" : "false");
      });
      this.appearanceMenuOpen = open ? kind : null;
    },

    onAppearanceTriggerKeyDown(event, kind) {
      const items = kind === "color" ? this.colorThemes : this.layouts;
      const currentId = kind === "color" ? this.colorTheme : this.layout;
      const currentIndex = Math.max(0, items.findIndex(item => item.id === currentId));
      if (event.key === "Escape" && this.appearanceMenuOpen === kind) {
        event.preventDefault();
        this.setAppearanceMenuOpen(kind, false);
        return;
      }
      if (["Enter", " "].includes(event.key)) {
        event.preventDefault();
        this.setAppearanceMenuOpen(kind, this.appearanceMenuOpen !== kind);
        return;
      }
      if (!["ArrowDown", "ArrowUp"].includes(event.key)) return;
      event.preventDefault();
      this.setAppearanceMenuOpen(kind, true);
      const offset = event.key === "ArrowDown" ? 1 : -1;
      const next = items[(currentIndex + offset + items.length) % items.length];
      kind === "color" ? this.applyColorTheme(next.id) : this.applyLayout(next.id);
      document.querySelector(`#${kind}-menu [data-appearance-option="${next.id}"]`)?.focus();
    },

    onAppearanceOptionKeyDown(event, kind, itemId) {
      if (event.key === "Escape") {
        event.preventDefault();
        this.setAppearanceMenuOpen(kind, false);
        document.getElementById(`${kind}-select`)?.focus();
        return;
      }
      if (!["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return;
      event.preventDefault();
      const items = kind === "color" ? this.colorThemes : this.layouts;
      const currentIndex = items.findIndex(item => item.id === itemId);
      let nextIndex = currentIndex;
      if (event.key === "ArrowDown") nextIndex = (currentIndex + 1) % items.length;
      if (event.key === "ArrowUp") nextIndex = (currentIndex - 1 + items.length) % items.length;
      if (event.key === "Home") nextIndex = 0;
      if (event.key === "End") nextIndex = items.length - 1;
      const next = items[nextIndex];
      kind === "color" ? this.applyColorTheme(next.id) : this.applyLayout(next.id);
      document.querySelector(`#${kind}-menu [data-appearance-option="${next.id}"]`)?.focus();
    },

    async boot() {
      // Always start in normal settings mode; capture is opt-in per hotkey button.
      this.closeCapture();
      try {
        // The AHK bridge is synchronous. Using the async proxy makes WebView2
        // treat the host object like a thenable and fail with a vague
        // "Missing a required parameter" error before any method is called.
        this.ahk = window.chrome.webview.hostObjects.sync.ahk;
        this.state = JSON.parse(this.ahk.call("getState"));
        this.activeTab = this.state.tabs[0]?.id ?? null;
        this.render();
        this.setRuntime("Engine ready");
        await this.checkForUpdate();
      } catch (error) {
        await this.reportError("boot", error);
        this.setRuntime("UI bridge unavailable", true);
        this.toast("The settings bridge could not start: " + error, "error");
      }
    },

    async checkForUpdate() {
      if (!this.state?.compiled) return;
      try {
        const result = JSON.parse(await this.call("checkForUpdate"));
        if (result.ok && result.available) this.openUpdateDialog(result);
      } catch (error) {
        await this.reportError("checkForUpdate", error);
        this.toast("Could not check for updates right now.", "error");
      }
    },

    openUpdateDialog(updateInfo) {
      this.updateInfo = updateInfo;
      this.updateDialogOpen = true;
      const current = document.getElementById("update-current-version");
      const latest = document.getElementById("update-latest-version");
      if (current) current.textContent = "v" + (updateInfo.currentVersion || this.state?.version || "—");
      if (latest) latest.textContent = "v" + (updateInfo.latestVersion || "—");
      this.setUpdateStatus("Your saved settings and customizations will stay in place.");
      const layer = document.getElementById("update-layer");
      if (layer) layer.hidden = false;
      requestAnimationFrame(() => document.getElementById("update-install")?.focus());
    },

    closeUpdateDialog() {
      if (this.updateInstalling) return;
      this.updateDialogOpen = false;
      this.updateInfo = null;
      const layer = document.getElementById("update-layer");
      if (layer) layer.hidden = true;
    },

    setUpdateStatus(message, error = false) {
      const status = document.getElementById("update-status");
      if (!status) return;
      status.textContent = message;
      status.classList.toggle("error", error);
    },

    async installUpdate() {
      if (!this.updateDialogOpen || this.updateInstalling) return;
      this.updateInstalling = true;
      const install = document.getElementById("update-install");
      const cancel = document.getElementById("update-cancel");
      if (install) {
        install.disabled = true;
        install.textContent = "Downloading…";
      }
      if (cancel) cancel.disabled = true;
      this.setUpdateStatus("Downloading the latest build…");
      try {
        const result = JSON.parse(await this.call("downloadAndInstallUpdate"));
        if (!result.ok) throw new Error(result.message || "The update could not be started.");
        if (install) install.textContent = "Restarting…";
        this.setUpdateStatus("Update ready. Restarting Babyproofed Macros…");
      } catch (error) {
        await this.reportError("downloadAndInstallUpdate", error);
        this.updateInstalling = false;
        if (install) {
          install.disabled = false;
          install.textContent = "Download & restart";
        }
        if (cancel) cancel.disabled = false;
        this.setUpdateStatus("The update could not be installed. You can try again.", true);
        this.toast("Update failed: " + error, "error");
      }
    },

    async call(method, ...args) {
      if (!this.ahk) throw new Error("The AHK bridge is not ready.");
      try {
        return await this.ahk.call(method, ...args);
      } catch (error) {
        await this.reportError("bridge." + method, error);
        throw error;
      }
    },

    formatError(error) {
      if (error instanceof Error) {
        return [
          `${error.name}: ${error.message}`,
          error.stack ? "Stack: " + error.stack : ""
        ].filter(Boolean).join("\n");
      }
      try {
        return JSON.stringify(error, Object.getOwnPropertyNames(error), 2);
      } catch (_) {
        return String(error);
      }
    },

    async reportError(context, error) {
      const details = "Context: " + context + "\n" + this.formatError(error);
      try {
        window.chrome.webview.postMessage(JSON.stringify({
          type: "error",
          context,
          details
        }));
      } catch (postError) {
        console.error("Could not post error to native logger", postError, details);
      }
      try {
        const bridge = this.ahk || window.chrome.webview.hostObjects.sync.ahk;
        await bridge.call("logError", details, context);
      } catch (loggingError) {
        console.error("Could not write error log", context, loggingError, details);
      }
    },

    render() {
      if (!this.state) return;
      this.renderNavigation();
      this.renderPage();
      this.updateDirtyUi();
      document.getElementById("version-label").textContent = "v" + (this.state.version || "—");
    },

    renderNavigation() {
      const nav = document.getElementById("navigation");
      nav.replaceChildren();
      const icons = ["✦", "◈", "⌘", "⚙"];
      this.state.tabs.forEach((tab, index) => {
        const button = document.createElement("button");
        button.className = "nav-item" + (tab.id === this.activeTab ? " active" : "");
        button.type = "button";
        button.setAttribute("aria-current", tab.id === this.activeTab ? "page" : "false");
        button.innerHTML = `<span class="nav-icon">${icons[index % icons.length]}</span><span class="nav-label"></span>`;
        button.querySelector(".nav-label").textContent = tab.label;
        button.addEventListener("click", () => {
          this.switchTab(tab.id);
        });
        nav.appendChild(button);
      });
    },

    switchTab(tabId) {
      if (this.capture || tabId === this.activeTab) return;
      const currentIndex = this.state.tabs.findIndex(tab => tab.id === this.activeTab);
      const nextIndex = this.state.tabs.findIndex(tab => tab.id === tabId);
      this.tabTransition = { direction: nextIndex >= currentIndex ? "forward" : "back" };
      this.activeTab = tabId;
      this.render();
    },

    animateTabElement(element, direction) {
      if (!direction) return;
      element.classList.remove("tab-enter-forward", "tab-enter-back");
      void element.offsetWidth;
      element.classList.add(direction === "forward" ? "tab-enter-forward" : "tab-enter-back");
      window.setTimeout(() => element.classList.remove("tab-enter-forward", "tab-enter-back"), 460);
    },

    animateHeading(direction) {
      if (!direction) return;
      const heading = document.querySelector(".topbar-copy");
      if (!heading) return;
      heading.classList.remove("tab-heading-forward", "tab-heading-back");
      void heading.offsetWidth;
      heading.classList.add(direction === "forward" ? "tab-heading-forward" : "tab-heading-back");
      window.setTimeout(() => heading.classList.remove("tab-heading-forward", "tab-heading-back"), 420);
    },

    renderPage() {
      const tab = this.state.tabs.find(item => item.id === this.activeTab) || this.state.tabs[0];
      if (!tab) return;
      this.activeTab = tab.id;
      document.getElementById("breadcrumb").textContent = tab.label.toUpperCase();
      document.getElementById("page-title").textContent = tab.label;
      document.getElementById("page-description").textContent = tab.description || "Configure the way your macros behave in-game.";

      const content = document.getElementById("content");
      content.replaceChildren();
      const intro = document.createElement("p");
      intro.className = "section-intro";
      intro.textContent = tab.help || "Changes stay local to this profile and take effect when you save them.";
      content.appendChild(intro);

      const grid = document.createElement("div");
      grid.className = "settings-grid";
      tab.settings.forEach((setting, index) => {
        const card = this.renderSetting(setting);
        card.style.setProperty("--card-index", index);
        grid.appendChild(card);
      });
      content.appendChild(grid);

      const transition = this.tabTransition;
      this.tabTransition = null;
      if (transition) {
        this.animateTabElement(content, transition.direction);
        this.animateHeading(transition.direction);
      }
    },

    renderSetting(setting) {
      const card = document.createElement("article");
      const compact = ["bool", "string", "hotkey"].includes(setting.type);
      card.className = "setting-card" + (compact ? " compact" : "") + (setting.experimental ? " experimental" : "") + (setting.danger ? " danger" : "");

      const top = document.createElement("div");
      top.className = "card-top";
      const label = document.createElement("div");
      label.className = "setting-label";
      label.textContent = setting.label || setting.name;
      top.appendChild(label);
      if (setting.experimental) {
        const badge = document.createElement("span");
        badge.className = "badge";
        badge.textContent = "Experimental";
        top.appendChild(badge);
      }
      card.appendChild(top);

      const description = document.createElement("p");
      description.className = "setting-description";
      description.textContent = setting.description || "Configure this macro setting.";
      card.appendChild(description);

      const controls = document.createElement("div");
      controls.className = "setting-control";
      const hint = document.createElement("span");
      hint.className = "control-hint";
      hint.textContent = setting.type === "hotkey" ? "Click to capture" : setting.type === "bool" ? "Toggle setting" : "Value";
      controls.appendChild(hint);
      controls.appendChild(this.controlFor(setting));
      card.appendChild(controls);
      return card;
    },

    controlFor(setting) {
      if (setting.type === "bool") {
        const label = document.createElement("label");
        label.className = "switch";
        const input = document.createElement("input");
        input.type = "checkbox";
        input.checked = Boolean(Number(setting.value));
        input.addEventListener("change", () => this.changeSetting(setting, input.checked ? 1 : 0));
        const track = document.createElement("span");
        track.className = "switch-track";
        label.append(input, track);
        return label;
      }

      if (setting.type === "string") {
        const input = document.createElement("input");
        input.className = "text-input";
        input.type = "text";
        input.value = setting.value ?? "";
        input.addEventListener("change", () => this.changeSetting(setting, input.value));
        return input;
      }

      const button = document.createElement("button");
      button.type = "button";
      button.className = "hotkey-button";
      button.setAttribute("aria-label", `Change hotkey for ${setting.label || setting.name}`);
      this.setHotkeyButton(button, setting.value);
      button.addEventListener("click", () => this.beginCapture(setting, button));
      return button;
    },

    createHotkeyTokens(value, emptyText = "Not bound") {
      const fragment = document.createDocumentFragment();
      const parts = formatHotkey(value);
      if (!parts.length) {
        const empty = document.createElement("span");
        empty.className = "hotkey-empty";
        empty.textContent = emptyText;
        fragment.appendChild(empty);
        return fragment;
      }

      parts.forEach((part, index) => {
        if (index) {
          const plus = document.createElement("span");
          plus.className = "hotkey-plus";
          plus.textContent = "+";
          fragment.appendChild(plus);
        }
        const key = document.createElement("span");
        key.className = "keycap";
        key.textContent = part;
        fragment.appendChild(key);
      });
      return fragment;
    },

    setHotkeyButton(button, value, emptyText = "Not bound") {
      button.replaceChildren();
      button.appendChild(this.createHotkeyTokens(value, emptyText));
      button.classList.toggle("unbound", !value);
    },

    setCapturePreview(value, emptyText = "Waiting for input") {
      const chips = document.getElementById("capture-chips");
      const previewValue = document.getElementById("capture-preview-value");
      chips.replaceChildren(this.createHotkeyTokens(value, emptyText));
      previewValue.textContent = value || "—";
      previewValue.classList.toggle("is-ready", Boolean(value));
    },

    updateCapturePreview() {
      if (!this.capture) return;
      const modifiers = Array.from(this.capture.activeModifiers);
      if (!modifiers.length) {
        this.setCapturePreview("", "Press a key or hold a modifier");
        document.getElementById("capture-state").textContent = "Listening for your next input";
        return;
      }
      const prefix = prefixesForModifiers(new Set(modifiers));
      this.setCapturePreview(prefix + "…", "Press a key");
      document.getElementById("capture-state").textContent = `${modifiers.map(displayModifier).join(" + ")} held — add a key or release to bind`;
    },

    async changeSetting(setting, value) {
      const previous = setting.value;
      setting.value = value;
      this.dirty = true;
      this.updateDirtyUi();
      try {
        await this.call("setSetting", setting.name, value);
      } catch (error) {
        await this.reportError("changeSetting", error);
        setting.value = previous;
        this.render();
        this.toast("Could not update “" + (setting.label || setting.name) + "”: " + error, "error");
      }
    },

    async beginCapture(setting, button) {
      if (this.capture) return;
      this.capture = {
        setting,
        button,
        activeModifiers: new Set(),
        usedModifiers: new Set()
      };
      this.setHotkeyButton(button, "", "Listening…");
      button.classList.add("capturing");
      document.getElementById("capture-target").textContent = setting.label || setting.name;
      document.getElementById("capture-copy").textContent = "Hold any modifiers, then press the key you want to use.";
      document.getElementById("capture-layer").hidden = false;
      this.setCapturePreview("", "Press a key or hold a modifier");
      document.getElementById("capture-state").textContent = "Listening for your next input";
      document.addEventListener("keydown", this.onCaptureKeyDown, true);
      document.addEventListener("keyup", this.onCaptureKeyUp, true);
      try {
        await this.call("beginHotkeyCapture", setting.name);
      } catch (error) {
        await this.reportError("beginHotkeyCapture", error);
        await this.cancelCapture();
        this.toast("Could not start hotkey capture: " + error, "error");
      }
    },

    onCaptureKeyDown(event) {
      if (!app.capture) return;
      event.preventDefault();
      event.stopPropagation();
      if (event.key === "Escape" && !hasEventModifier(event)) {
        app.cancelCapture();
        return;
      }
      const modifier = modifierForEvent(event);
      if (modifier) {
        if (!event.repeat) {
          app.capture.activeModifiers.add(modifier);
          app.capture.usedModifiers.add(modifier);
        }
        app.updateCapturePreview();
        return;
      }
      const value = normalizeHotkey(event, app.capture);
      if (!value) return;
      app.setCapturePreview(value);
      document.getElementById("capture-state").textContent = "Hotkey ready — assigning it now";
      app.finishCapture(value);
    },

    onCaptureKeyUp(event) {
      if (!app.capture) return;
      event.preventDefault();
      event.stopPropagation();
      const modifier = modifierForEvent(event);
      if (!modifier) return;
      app.capture.activeModifiers.delete(modifier);
      app.updateCapturePreview();
      if (!app.capture.activeModifiers.size && app.capture.usedModifiers.size === 1) {
        const modifierName = Array.from(app.capture.usedModifiers)[0];
        const value = modifierOnlyName(modifierName, event);
        app.setCapturePreview(value);
        document.getElementById("capture-state").textContent = "Modifier ready — assigning it now";
        app.finishCapture(value);
      }
    },

    async finishCapture(value) {
      if (!this.capture || this.capture.unbinding) return;
      const capture = this.capture;
      const { setting } = capture;
      try {
        await this.call("setSetting", setting.name, value);
        if (this.capture !== capture || capture.unbinding) return;
        setting.value = value;
        this.dirty = true;
        this.closeCapture();
        this.render();
      } catch (error) {
        await this.reportError("finishHotkeyCapture", error);
        this.toast("Could not assign that hotkey: " + error, "error");
      }
    },

    receiveHotkey(payload) {
      if (!this.capture || this.capture.unbinding || payload.name !== this.capture.setting.name) return;
      this.setCapturePreview(payload.value);
      document.getElementById("capture-state").textContent = "Mouse binding ready — assigning it now";
      this.finishCapture(payload.value);
    },

    async unbindCapture() {
      if (!this.capture) return;
      const capture = this.capture;
      capture.unbinding = true;
      const { setting } = capture;
      document.getElementById("capture-state").textContent = "Removing hotkey binding…";
      this.setCapturePreview("", "Not bound");
      try {
        await this.call("cancelHotkeyCapture");
        await this.call("setSetting", setting.name, "");
        setting.value = "";
        this.dirty = true;
        this.closeCapture();
        this.render();
        this.toast("Hotkey unbound", "success");
      } catch (error) {
        await this.reportError("unbindHotkey", error);
        this.toast("Could not unbind that hotkey: " + error, "error");
      }
    },

    async cancelCapture() {
      try {
        await this.call("cancelHotkeyCapture");
      } catch (error) {
        await this.reportError("cancelHotkeyCapture", error);
      }
      this.closeCapture();
      this.render();
    },

    closeCapture() {
      document.removeEventListener("keydown", this.onCaptureKeyDown, true);
      document.removeEventListener("keyup", this.onCaptureKeyUp, true);
      document.getElementById("capture-layer").hidden = true;
      if (this.capture?.button) this.capture.button.classList.remove("capturing");
      this.capture = null;
    },

    async save() {
      this.setSaveStatus("Saving…");
      try {
        const result = JSON.parse(await this.call("saveSettings"));
        if (!result.ok) throw new Error(result.message || "Save failed");
        this.state = JSON.parse(await this.call("getState"));
        this.dirty = false;
        this.render();
        this.setSaveStatus("All changes saved");
        this.toast("Settings saved", "success");
      } catch (error) {
        await this.reportError("save", error);
        this.setSaveStatus("Save failed");
        this.toast(String(error), "error");
      }
    },

    async discard() {
      try {
        this.state = JSON.parse(await this.call("discardSettings"));
        this.dirty = false;
        this.render();
        this.setSaveStatus("Changes discarded");
      } catch (error) {
        await this.reportError("discard", error);
        this.toast("Could not discard changes: " + error, "error");
      }
    },

    async importGtaKeys() {
      this.setSaveStatus("Importing GTA keybinds…");
      try {
        const result = JSON.parse(await this.call("importGtaKeys"));
        if (!result.ok) throw new Error(result.message || "Import failed");
        this.state = JSON.parse(result.state);
        this.dirty = true;
        this.render();
        this.setSaveStatus("Imported — save to apply");
        this.toast("GTA keybinds imported. Review and save the changes.", "success");
      } catch (error) {
        await this.reportError("importGtaKeys", error);
        this.setSaveStatus("Import failed");
        this.toast(String(error), "error");
      }
    },

    updateDirtyUi() {
      document.getElementById("dirty-badge").hidden = !this.dirty;
      document.getElementById("save-button").disabled = !this.dirty;
      document.getElementById("discard-button").disabled = !this.dirty;
      if (this.dirty) this.setSaveStatus("Changes are waiting to be saved");
    },

    setSaveStatus(text) { document.getElementById("save-status").textContent = text; },
    setRuntime(text, error = false) {
      document.getElementById("runtime-label").textContent = text;
      document.querySelector(".status-dot").style.background = error ? "var(--danger)" : "var(--cyan)";
    },
    toast(message, kind = "info") {
      const toast = document.createElement("div");
      toast.className = "toast " + kind;
      toast.innerHTML = `<span class="toast-icon">${kind === "error" ? "!" : "✓"}</span><span></span>`;
      toast.lastElementChild.textContent = message;
      document.getElementById("toast-region").appendChild(toast);
      setTimeout(() => toast.remove(), 4200);
    },

    receive(eventName, payload) {
      if (eventName === "toast") this.toast(payload.message, payload.kind);
      if (eventName === "hotkeyCaptured") this.receiveHotkey(payload);
      if (eventName === "sendInputStatus") document.getElementById("send-input-status").textContent = payload;
    }
  };

  const MODIFIER_LABELS = { ctrl: "Ctrl", alt: "Alt", shift: "Shift", meta: "Win" };
  const MODIFIER_PREFIXES = { ctrl: "^", alt: "!", shift: "+", meta: "#" };

  function modifierForEvent(event) {
    if (["Control", "Ctrl"].includes(event.key) || ["ControlLeft", "ControlRight"].includes(event.code)) return "ctrl";
    if (event.key === "Alt" || ["AltLeft", "AltRight"].includes(event.code)) return "alt";
    if (event.key === "Shift" || ["ShiftLeft", "ShiftRight"].includes(event.code)) return "shift";
    if (event.key === "Meta" || ["MetaLeft", "MetaRight", "OSLeft", "OSRight"].includes(event.code)) return "meta";
    return null;
  }

  function hasEventModifier(event) {
    return event.ctrlKey || event.altKey || event.shiftKey || event.metaKey;
  }

  function prefixesForModifiers(modifiers) {
    return ["ctrl", "alt", "shift", "meta"]
      .filter(modifier => modifiers.has(modifier))
      .map(modifier => MODIFIER_PREFIXES[modifier])
      .join("");
  }

  function displayModifier(modifier) {
    return MODIFIER_LABELS[modifier] || modifier;
  }

  function modifierOnlyName(modifier, event) {
    if (modifier === "meta") return event.location === 2 ? "RWin" : "LWin";
    return { ctrl: "Control", alt: "Alt", shift: "Shift" }[modifier];
  }

  function keyNameFromEvent(event) {
    const code = event.code || "";
    const codeNames = {
      Space: "Space", Enter: "Enter", NumpadEnter: "NumpadEnter", Tab: "Tab", Backspace: "BackSpace",
      Delete: "Delete", Insert: "Insert", Home: "Home", End: "End", PageUp: "PgUp", PageDown: "PgDn",
      ArrowUp: "Up", ArrowDown: "Down", ArrowLeft: "Left", ArrowRight: "Right", CapsLock: "CapsLock",
      NumLock: "NumLock", ScrollLock: "ScrollLock", PrintScreen: "PrintScreen", ContextMenu: "AppsKey",
      Pause: "Pause", NumpadMultiply: "NumpadMult", NumpadAdd: "NumpadAdd", NumpadSubtract: "NumpadSub",
      NumpadDecimal: "NumpadDot", NumpadDivide: "NumpadDiv", Backquote: "vkC0", Minus: "vkBD",
      Equal: "vkBB", BracketLeft: "vkDB", BracketRight: "vkDD", Backslash: "vkDC", Semicolon: "vkBA",
      Quote: "vkDE", Comma: "vkBC", Period: "vkBE", Slash: "vkBF",
      AudioVolumeMute: "Volume_Mute", AudioVolumeDown: "Volume_Down", AudioVolumeUp: "Volume_Up",
      MediaTrackNext: "Media_Next", MediaTrackPrevious: "Media_Prev", MediaStop: "Media_Stop", MediaPlayPause: "Media_Play_Pause"
    };
    if (codeNames[code]) return codeNames[code];
    if (/^Key[A-Z]$/.test(code)) return code.slice(3).toLowerCase();
    if (/^Digit[0-9]$/.test(code)) return code.slice(5);
    if (/^F(?:[1-9]|1[0-9]|2[0-4])$/.test(code)) return code;
    if (/^Numpad[0-9]$/.test(code)) return code;
    const named = {
      " ": "Space", Escape: "Esc", Enter: "Enter", Tab: "Tab", Backspace: "BackSpace", Delete: "Delete",
      Insert: "Insert", Home: "Home", End: "End", PageUp: "PgUp", PageDown: "PgDn",
      ArrowUp: "Up", ArrowDown: "Down", ArrowLeft: "Left", ArrowRight: "Right", CapsLock: "CapsLock",
      NumLock: "NumLock", ScrollLock: "ScrollLock", PrintScreen: "PrintScreen", ContextMenu: "AppsKey"
    };
    if (named[event.key]) return named[event.key];
    return event.key && event.key.length === 1 ? event.key.toLowerCase() : null;
  }

  function normalizeHotkey(event, capture) {
    if (modifierForEvent(event)) return null;
    const modifiers = new Set(capture?.activeModifiers || []);
    if (event.ctrlKey) modifiers.add("ctrl");
    if (event.altKey) modifiers.add("alt");
    if (event.shiftKey) modifiers.add("shift");
    if (event.metaKey) modifiers.add("meta");
    const key = keyNameFromEvent(event);
    return key ? prefixesForModifiers(modifiers) + key : null;
  }

  function displayKeyName(key) {
    const lower = String(key).toLowerCase();
    const names = {
      control: "Ctrl", ctrl: "Ctrl", alt: "Alt", shift: "Shift", lwin: "Win", rwin: "Win",
      lcontrol: "Ctrl", rcontrol: "Ctrl", lctrl: "Ctrl", rctrl: "Ctrl", lalt: "Alt", ralt: "Alt",
      lshift: "Shift", rshift: "Shift", space: "Space", back_space: "Backspace", backspace: "Backspace",
      esc: "Esc", escape: "Esc", enter: "Enter", tab: "Tab", pgup: "Page Up", pgdn: "Page Down",
      up: "↑", down: "↓", left: "←", right: "→", appskey: "Menu", printscreen: "PrtSc",
      capslock: "Caps Lock", numlock: "Num Lock", scrolllock: "Scroll Lock", vkba: ";", vkbb: "=",
      vkbc: ",", vkbd: "-", vkbe: ".", vkbf: "/", vkc0: "`", vkdb: "[", vkdc: "\\", vkdd: "]", vkde: "'",
      lbutton: "Mouse 1", rbutton: "Mouse 2", mbutton: "Mouse 3", xbutton1: "Mouse 4", xbutton2: "Mouse 5"
    };
    return names[lower] || (String(key).length === 1 ? String(key).toUpperCase() : String(key));
  }

  function formatHotkey(value) {
    if (!value) return [];
    let remainder = String(value);
    const parts = [];
    const symbols = [["^", "Ctrl"], ["!", "Alt"], ["+", "Shift"], ["#", "Win"]];
    symbols.forEach(([symbol, label]) => {
      if (remainder.includes(symbol)) {
        parts.push(label);
        remainder = remainder.split(symbol).join("");
      }
    });
    if (remainder) parts.push(displayKeyName(remainder));
    return parts;
  }

  window.bpmReceive = (eventName, payload) => app.receive(eventName, payload);
  window.bpmHotkeyCaptured = payload => app.receiveHotkey(payload);
  window.app = app;
  window.addEventListener("error", event => {
    app.reportError("window.error", event.error || event.message);
  });
  window.addEventListener("unhandledrejection", event => {
    app.reportError("unhandledrejection", event.reason);
  });
  document.addEventListener("contextmenu", event => event.preventDefault());
  document.addEventListener("keydown", event => {
    if (event.key === "Escape" && app.updateDialogOpen && !app.updateInstalling) {
      event.preventDefault();
      app.closeUpdateDialog();
    }
  });
  document.getElementById("save-button").addEventListener("click", () => app.save());
  document.getElementById("discard-button").addEventListener("click", () => app.discard());
  document.getElementById("import-button").addEventListener("click", () => app.importGtaKeys());
  document.getElementById("capture-unbind").addEventListener("click", () => app.unbindCapture());
  document.getElementById("capture-cancel").addEventListener("click", () => app.cancelCapture());
  document.getElementById("update-cancel").addEventListener("click", () => app.closeUpdateDialog());
  document.getElementById("update-install").addEventListener("click", () => app.installUpdate());
  document.getElementById("hide-button").addEventListener("click", async () => {
    try {
      await app.call("hideWindow");
    } catch (error) {
      await app.reportError("hideWindow", error);
      app.toast(String(error), "error");
    }
  });
  window.addEventListener("beforeunload", () => { if (app.capture) app.cancelCapture(); });
  app.initTheme();
  app.boot();
})();
