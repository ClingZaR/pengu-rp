import { createOptions } from "./createOptions.js";
import { fetchNui } from "./fetchNui.js";

const optionsWrapper = document.getElementById("options-wrapper");
const body = document.body;
const eye = document.getElementById("eyeSvg");
const eyeRing = document.getElementById("eye-ring");

// PenguRP: hold-to-confirm. While the eye is up (you are holding Alt aimed at a target),
// fill the ring around the eye over HOLD_DEFAULT ms and then activate the option WITHOUT a
// click. The option the cursor is over takes priority; if there is exactly ONE option it is
// confirmed with no cursor movement. window.__oxFired latches a single activation (shared
// with the click handler) so it can never spam, and releases once no option is targeted.
// Options with an explicit holdTime use their own duration. Clicking still works (instant).
const HOLD_DEFAULT = 700;
let holdEl = null;
let holdStart = 0;

function holdLoop(ts) {
  const active = body.style.visibility === "visible";

  let target = null;
  if (active) {
    const all = optionsWrapper.querySelectorAll(".option-container");
    target =
      optionsWrapper.querySelector(".option-container:hover") ||
      (all.length === 1 ? all[0] : null);
  }

  if (!target) {
    holdEl = null;
    window.__oxFired = false;
    if (eyeRing) {
      eyeRing.classList.remove("active");
      eyeRing.style.setProperty("--p", 0);
    }
  } else if (!window.__oxFired) {
    if (target !== holdEl) {
      holdEl = target;
      holdStart = ts;
    }
    const dur = Number(target.dataset.holdtime) || HOLD_DEFAULT;
    const p = Math.min(1, (ts - holdStart) / dur);
    if (eyeRing) {
      eyeRing.style.setProperty("--p", p);
      eyeRing.classList.add("active");
    }
    if (p >= 1) {
      window.__oxFired = true;
      if (eyeRing) {
        eyeRing.classList.remove("active");
        eyeRing.style.setProperty("--p", 0);
      }
      const args = target.selectArgs;
      target.style.pointerEvents = "none";
      if (args) fetchNui("select", args);
      setTimeout(() => {
        if (target) target.style.pointerEvents = "auto";
      }, 100);
    }
  }
  // target present but already fired: wait until it clears (no spam).

  requestAnimationFrame(holdLoop);
}
requestAnimationFrame(holdLoop);

window.addEventListener("message", (event) => {
  switch (event.data.event) {
    case "visible": {
      optionsWrapper.innerHTML = "";
      body.style.visibility = event.data.state ? "visible" : "hidden";
      return eye.classList.remove("eye-hover");
    }

    case "leftTarget": {
      optionsWrapper.innerHTML = "";
      return eye.classList.remove("eye-hover");
    }

    case "setTarget": {
      optionsWrapper.innerHTML = "";
      eye.classList.add("eye-hover");

      if (event.data.options) {
        for (const type in event.data.options) {
          event.data.options[type].forEach((data, id) => {
            createOptions(type, data, id + 1);
          });
        }
      }

      if (event.data.zones) {
        for (let i = 0; i < event.data.zones.length; i++) {
          event.data.zones[i].forEach((data, id) => {
            createOptions("zones", data, id + 1, i + 1);
          });
        }
      }
    }
  }
});
