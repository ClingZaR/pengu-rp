(function () {
    'use strict';

    // Speed unit suffix shown next to each contact's speed.
    var UNIT = 'MPH';

    function el(id) {
        return document.getElementById(id);
    }

    function renderList(plates, selected) {
        var rows = el('radar-rows');
        if (!rows) {
            return;
        }

        rows.innerHTML = '';

        if (!Array.isArray(plates) || plates.length === 0) {
            var empty = document.createElement('div');
            empty.className = 'radar-empty';
            empty.textContent = 'No contacts';
            rows.appendChild(empty);
            return;
        }

        var sel = Number(selected) || 0;

        for (var i = 0; i < plates.length; i++) {
            var entry = plates[i] || {};

            var item = document.createElement('div');
            item.className = 'radar-item';
            if (i === sel - 1) {
                item.className += ' selected';
            }

            var plate = document.createElement('span');
            plate.className = 'radar-plate';
            plate.textContent = entry.plate || '';
            item.appendChild(plate);

            var speedWrap = document.createElement('span');
            speedWrap.className = 'radar-speed';

            var speedNum = document.createElement('span');
            speedNum.className = 'radar-speed-num';
            var speedVal = (entry.speed === undefined || entry.speed === null) ? 0 : entry.speed;
            if (Number(speedVal) > 80) {
                speedNum.className += ' over';
            }
            speedNum.textContent = speedVal;
            speedWrap.appendChild(speedNum);

            var speedUnit = document.createElement('span');
            speedUnit.className = 'radar-speed-unit';
            speedUnit.textContent = UNIT;
            speedWrap.appendChild(speedUnit);

            item.appendChild(speedWrap);
            rows.appendChild(item);
        }
    }

    window.addEventListener('message', function (e) {
        var data = e.data || {};

        switch (data.action) {
            case 'radarShow': {
                var cardShow = el('radar');
                if (cardShow) {
                    cardShow.classList.remove('hidden');
                }
                break;
            }

            case 'radarHide': {
                var cardHide = el('radar');
                if (cardHide) {
                    cardHide.classList.add('hidden');
                }
                break;
            }

            case 'radarList': {
                renderList(data.plates, data.selected);
                break;
            }

            default:
                break;
        }
    });
})();
