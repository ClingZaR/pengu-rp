(async () => {
    const RESOURCE_NAME = 'qbx_chat_theme';

    const data = await fetchNui('config');

    /** @type {{ property: string; value: string | null }[]} */
    const vars = [
        { property: '--main-color', value: data.mainColor },
        { property: '--border-color', value: data.borderColor },
        { property: '--text-color', value: data.textColor },
        { property: '--faint-color', value: data.faintColor },
        { property: '--font-family', value: data.fontFamily },
        { property: '--console-font-family', value: data.consoleFontFamily },
        { property: '--suggestion-font-family', value: data.suggestionFontFamily },
        { property: '--input-icon-url', value: `url(${data.inputIconUrl})` },
        { property: '--message-icon-url', value: `url(${data.messageIconUrl})` },
        { property: '--console-icon-url', value: `url(${data.consoleIconUrl})` },
        { property: '--join-icon-url', value: `url(${data.joinIconUrl})` },
        { property: '--quit-icon-url', value: `url(${data.quitIconUrl})` },
        { property: '--user-icon-url', value: `url(${data.userIconUrl})` },
    ];

    for (const { property, value } of vars) {
        document.documentElement.style.setProperty(property, value);
    }

    /**
     * @param {string} endpoint
     * @param {unknown} data
     */
    async function fetchNui(endpoint, data) {
        const body = typeof data === 'undefined' || data === null ? null : JSON.stringify(data);

        const response = await fetch(`https://${RESOURCE_NAME}/${endpoint}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json; charset=UTF-8',
            },
            body,
        });

        return await response.json();
    }
})();

// Chat visibility: stay visible after any new message, auto-hide after 60s idle.
// Works together with client/chat-persist.lua forcing the engine to "always show".
(function () {
    const IDLE_MS = 60000;
    let lastActivity = Date.now();

    function chatRoot() {
        return document.querySelector('.chat-window');
    }
    function hasSelection() {
        const s = window.getSelection && window.getSelection();
        return !!(s && !s.isCollapsed);
    }
    function setIdle(hidden) {
        const el = chatRoot();
        if (el) el.classList.toggle('pengu-chat-idle', hidden);
    }
    function bump() {
        lastActivity = Date.now();
        setIdle(false);
    }

    window.addEventListener('message', (e) => {
        const t = e.data && e.data.type;
        if (t === 'ON_MESSAGE' || t === 'ON_OPEN') bump();
    });

    // Pointer/scroll activity OVER the chat, and any active text selection, count as activity - so the
    // chat never fades to pointer-events:none while the player is reading or copying messages (which
    // was collapsing the selection and forcing them to spam-click to copy).
    ['mousedown', 'mousemove', 'wheel'].forEach((ev) => {
        document.addEventListener(ev, (e) => {
            const root = chatRoot();
            if (root && e.target && root.contains(e.target)) bump();
        }, true);
    });
    document.addEventListener('selectionchange', () => { if (hasSelection()) bump(); });

    setInterval(() => {
        const typing = document.activeElement && document.activeElement.tagName === 'TEXTAREA';
        const idle = (Date.now() - lastActivity) > IDLE_MS;
        setIdle(idle && !typing && !hasSelection());
    }, 1000);
})();

// Prepend a [HH:MM] timestamp to every chat message. Source-agnostic (MutationObserver), so it
// covers /me /do /stats, system lines, and everything else. (An enable/disable toggle comes later.)
(function () {
    // UTC HH:MM:SS to match the server-stamped /me /do timestamps (server os.date is UTC).
    function utcTime() {
        const d = new Date();
        const p = (n) => ('0' + n).slice(-2);
        return p(d.getUTCHours()) + ':' + p(d.getUTCMinutes()) + ':' + p(d.getUTCSeconds());
    }

    function hasSelection() {
        const s = window.getSelection && window.getSelection();
        return !!(s && !s.isCollapsed);
    }

    // Stamp a message-content line, unless it already has a timestamp (.ts from a template, or ours).
    const pending = [];
    function stamp(line) {
        if (!line || line.querySelector('.chat-ts') || line.querySelector('.ts')) return;
        // Defer stamping while the user has an active text selection: inserting a node now would
        // collapse their selection (a new message arriving mid-copy was clearing it). Flush on clear.
        if (hasSelection()) { if (pending.indexOf(line) === -1) pending.push(line); return; }
        const ts = document.createElement('span');
        ts.className = 'chat-ts';
        ts.textContent = '[' + utcTime() + '] ';
        line.insertBefore(ts, line.firstChild);
    }
    document.addEventListener('selectionchange', () => {
        if (!hasSelection() && pending.length) {
            const queued = pending.splice(0, pending.length);
            queued.forEach((line) => { if (line.isConnected) stamp(line); });
        }
    });

    const obs = new MutationObserver((muts) => {
        for (const m of muts) {
            m.addedNodes.forEach((n) => {
                if (n.nodeType !== 1) return;
                if (n.matches && n.matches('.rp-line, .message-wrapper')) stamp(n);
                if (n.querySelectorAll) n.querySelectorAll('.rp-line, .message-wrapper').forEach(stamp);
            });
        }
    });

    function start() {
        const container = document.querySelector('.chat-messages');
        if (!container) { setTimeout(start, 400); return; }
        obs.observe(container, { childList: true, subtree: true });
        container.querySelectorAll('.rp-line, .message-wrapper').forEach(stamp);
    }
    start();
})();

// Show the chat scrollbar while the chat is open (input focused with T) or while the user
// is hovering/selecting in the message history. The messages container is always overflow-y:auto
// (scroll never resets, selected text is never clipped); this only controls scrollbar visibility.
(function () {
    function setOpen(open) {
        const w = document.querySelector('.chat-window');
        if (w) w.classList.toggle('chat-open', open);
    }
    function hasSelection() {
        const s = window.getSelection && window.getSelection();
        return !!(s && !s.isCollapsed);
    }

    let pointerInMessages = false;

    function bindMessages() {
        const messages = document.querySelector('.chat-messages');
        if (!messages) { setTimeout(bindMessages, 200); return; }
        messages.addEventListener('mouseenter', () => { pointerInMessages = true; setOpen(true); });
        messages.addEventListener('mouseleave', () => {
            pointerInMessages = false;
            if (!(document.activeElement && document.activeElement.tagName === 'TEXTAREA') && !hasSelection()) setOpen(false);
        });
    }
    bindMessages();

    document.addEventListener('focusin', (e) => {
        if (e.target && e.target.tagName === 'TEXTAREA') setOpen(true);
    });
    document.addEventListener('focusout', (e) => {
        if (e.target && e.target.tagName === 'TEXTAREA' && !pointerInMessages && !hasSelection()) setOpen(false);
    });
    // Keep scrollbar visible while selecting; hide when selection is gone and user is elsewhere.
    document.addEventListener('selectionchange', () => {
        if (hasSelection()) setOpen(true);
    });
})();
