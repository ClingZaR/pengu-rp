import { fetchNui } from "./fetchNui.js";

const optionsWrapper = document.getElementById("options-wrapper");

function onClick() {
  // when nuifocus is disabled after a click, the hover event is never released
  this.style.pointerEvents = "none";
  // PenguRP: shared latch so the hold-to-confirm loop (main.js) does not also fire
  // this same option right after a click.
  window.__oxFired = true;
  fetchNui("select", [this.targetType, this.targetId, this.zoneId]);
  // is there a better way to handle this? probably
  setTimeout(() => (this.style.pointerEvents = "auto"), 100);
}

export function createOptions(type, data, id, zoneId) {
  if (data.hide) return;

  const option = document.createElement("div");
  const iconElement = `<i class="fa-fw ${data.icon} option-icon" ${
    data.iconColor ? `style = color:${data.iconColor} !important` : null
  }"></i>`;

  option.innerHTML = `${iconElement}<p class="option-label">${data.label}</p>`;
  option.className = "option-container";
  option.targetType = type;
  option.targetId = id;
  option.zoneId = zoneId;
  // PenguRP: used by BOTH the click handler and the hold-to-confirm loop in main.js.
  option.selectArgs = [type, id, zoneId];

  // PenguRP: an explicit numeric holdTime (e.g. the armoury ring) is hold-ONLY (no click).
  // Everything else is click-activated AND can be confirmed by holding Alt (main.js loop).
  if (data.holdTime && Number(data.holdTime) > 0) {
    option.classList.add("holdable");
    option.dataset.holdtime = Number(data.holdTime);
  } else {
    option.addEventListener("click", onClick);
  }

  optionsWrapper.appendChild(option);
}
