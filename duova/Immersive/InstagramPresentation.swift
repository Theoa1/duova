import Foundation

/// Keeps Instagram's working DOM and event handlers, but exposes only the
/// requested surface. No copied messages, private API calls, or React remounts.
enum InstagramPresentation {
    static let css = #"""
    html[data-duova-instagram="5"] [data-duova-native-navigation],
    html[data-duova-instagram="5"] [data-duova-back],
    html[data-duova-instagram="5"] :is(nav,[role="navigation"]):has(a[href="/"]):has(a[href^="/reels"]),
    html[data-duova-instagram="5"] :is(nav,[role="navigation"]):has(a[href="/explore/"]):has(a[href^="/direct/"]),
    html[data-duova-instagram="5"] header:has(a[href="/"] svg[aria-label="Instagram"]),
    html[data-duova-instagram="5"] a[href="/"]:has(svg[aria-label="Instagram"]),
    html[data-duova-instagram="5"] a[href="/"]:has(svg[aria-label="Home"]),
    html[data-duova-instagram="5"] a[href="/explore/"]:has(svg[aria-label="Explore"]),
    html[data-duova-instagram="5"] a[href="/reels/"]:has(svg[aria-label="Reels"]),
    html[data-duova-instagram="5"] a[href="/direct/inbox/"]:has(svg[aria-label="Messenger"]) {
      display: none !important;
    }
    html[data-duova-instagram="5"] { width:100%; min-height:100%; overflow-x:clip; }
    html[data-duova-instagram="5"] body { margin:0 !important; width:100%; min-width:0 !important; }
    html[data-duova-instagram="5"] main,
    html[data-duova-instagram="5"] [role="main"] {
      margin-inline:0 !important; width:100% !important; max-width:none !important; min-width:0 !important;
    }
    /* The companion is never allowed to flash the complete website while
       its requested component is being found. Authentication remains visible. */
    html[data-duova-pane="companion"][data-duova-instagram="5"]:not([data-duova-component-ready]) body {
      visibility:hidden !important;
    }
    html[data-duova-component-ready] [data-duova-component-path] {
      display:block !important; position:static !important; transform:none !important;
      width:100% !important; max-width:none !important; min-width:0 !important;
      height:auto !important; min-height:0 !important; margin:0 !important;
      padding:0 !important; border:0 !important; overflow:visible !important;
    }
    html[data-duova-component-ready] [data-duova-component-path] > :not([data-duova-component-path]):not([data-duova-component]) {
      display:none !important;
    }
    html[data-duova-pane="companion"][data-duova-component-ready] [data-duova-component] {
      visibility:visible !important; position:relative !important; inset:auto !important;
      width:100% !important; max-width:100% !important; min-width:0 !important;
      margin-inline:0 !important; box-sizing:border-box !important;
    }
    html[data-duova-context="messages"][data-duova-component-ready],
    html[data-duova-context="messages"][data-duova-component-ready] body,
    html[data-duova-context="messages"][data-duova-component-ready] [data-duova-component-path],
    html[data-duova-context="messages"][data-duova-component-ready] [data-duova-component] {
      height:100% !important; min-height:0 !important;
    }
    html[data-duova-context="comments"][data-duova-component-ready] body {
      overflow-y:auto !important; height:auto !important;
    }
    html[data-duova-context="comments"] [data-duova-component] video { display:none !important; }
    """#

    static let script = #"""
    (() => {
      if (window.__duovaPresentation || location.protocol !== 'https:' ||
          !['www.instagram.com','instagram.com'].includes(location.host)) return;
      window.__duovaPresentation = true;
      const root = document.documentElement;
      const companion = root.dataset.duovaPane === 'companion';
      const auth = () => /^\/(accounts|challenge|oauth|emails|session)(\/|$)/.test(location.pathname);
      const mark = (element, key, value = '') => {
        if (element && element.getAttribute(key) !== value) element.setAttribute(key,value);
      };
      const safePath = a => {
        try { const u = new URL(a.href,location.href); return u.origin === location.origin ? u.pathname : ''; }
        catch (_) { return ''; }
      };
      const destinations = new Set(['/','/explore/','/reels/','/direct/inbox/']);
      const stripNavigation = () => {
        for (const a of document.querySelectorAll('a[href="/"],a[href="/explore/"],a[href="/reels/"],a[href="/direct/inbox/"]')) {
          let node = a.parentElement;
          for (let depth=0; node && node !== document.body && depth<9; depth++,node=node.parentElement) {
            if (node.hasAttribute('data-duova-native-navigation')) break;
            if (node.matches('main,[role="main"],article,form,[role="dialog"]') ||
                node.querySelector('main,[role="main"],article,form,[role="dialog"]')) break;
            const routes = new Set(Array.from(node.querySelectorAll('a[href]')).map(safePath).filter(p => destinations.has(p)));
            if (routes.size >= 3) { mark(node,'data-duova-native-navigation'); break; }
          }
        }
        if (companion) {
          for (const icon of document.querySelectorAll('svg[aria-label="Back"],svg[aria-label="Go back"],svg[aria-label="Close"]')) {
            const control = icon.closest('button,a,[role="button"]');
            // Keep attachment/dialog dismissal; remove only the page-level controls.
            if (control && (!control.closest('[role="dialog"]') || root.dataset.duovaContext === 'comments'))
              mark(control,'data-duova-back');
          }
          for (const control of document.querySelectorAll('button[aria-label="Back"],a[aria-label="Back"],[role="button"][aria-label="Back"],button[aria-label="Go back"],[role="button"][aria-label="Go back"]'))
            mark(control.closest('button,a,[role="button"]') || control,'data-duova-back');
        }
      };
      if (companion) {
        document.addEventListener('click', e => {
          if (!e.isTrusted || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey ||
              e.altKey || !(e.target instanceof Element)) return;
          const a = e.target.closest('a[href]');
          if (!a) return;
          const path = safePath(a);
          if (!/^\/(p|reel)\/[^/]+\/?$/.test(path)) return;
          try {
            window.webkit.messageHandlers.duova.postMessage({type:'focusPost',path});
            e.preventDefault(); e.stopImmediatePropagation();
          } catch (_) {}
        },true);
      }
      let previousRoots = [];
      let previousPath = '';
      let requestedCommentsPath = '';
      let lastReported = '';
      const report = value => {
        if (lastReported === value) return;
        lastReported = value;
        try { window.webkit.messageHandlers.duova.postMessage({type:'component',status:value}); } catch (_) {}
      };
      const clearComponent = () => {
        root.removeAttribute('data-duova-component-ready');
        for (const e of document.querySelectorAll('[data-duova-component],[data-duova-component-path]')) {
          e.removeAttribute('data-duova-component');
          e.removeAttribute('data-duova-component-path');
        }
        previousRoots = [];
      };
      const isolate = elements => {
        const candidates = [...new Set(elements.filter(Boolean))];
        const roots = candidates.filter(e => !candidates.some(other => other !== e && other.contains(e)));
        if (!roots.length) { report('waiting'); return false; }
        if (roots.length !== previousRoots.length || roots.some((e,i) => e !== previousRoots[i] || !e.isConnected)) {
          clearComponent();
          for (const element of roots) {
            mark(element,'data-duova-component');
            for (let parent=element.parentElement; parent && parent !== root; parent=parent.parentElement)
              mark(parent,'data-duova-component-path');
          }
          previousRoots = roots;
        }
        mark(root,'data-duova-component-ready');
        report('ready');
        return true;
      };
      const comments = () => {
        const input = Array.from(document.querySelectorAll('textarea[placeholder],textarea[aria-label],[contenteditable="true"][aria-label]')).find(e =>
          /comment|comentario|commentaire|kommentar|commento/i.test((e.getAttribute('placeholder') || '')+' '+(e.getAttribute('aria-label') || '')));
        if (input) {
          let region = input.closest('[role="dialog"],article,main,[role="main"]');
          const list = region && Array.from(region.querySelectorAll('ul,[role="list"],[aria-label="Comments"],[aria-label="Comment thread"]'))
            .find(e => !e.closest('[data-duova-native-navigation]') && !e.querySelector('video'));
          const composer = input.closest('form') || input.closest('section') || input.parentElement;
          if (list) return isolate([list,composer]);
          const empty = region && Array.from(region.querySelectorAll('p,span')).find(e =>
            /^(no comments yet[.!]?|be the first to comment[.!]?)$/i.test(e.textContent.trim()));
          if (empty) return isolate([empty,composer]);
          // Don't call a composer-only view a complete discussion.
          report('waiting');
          return false;
        }
        if (requestedCommentsPath !== location.pathname) {
          const icon = document.querySelector('svg[aria-label="Comment"],svg[aria-label="Comments"]');
          const control = icon && icon.closest('button,[role="button"]');
          if (control && !control.closest('form')) {
            requestedCommentsPath = location.pathname;
            control.click(); // Explicitly requested, read-only discussion navigation.
          }
        }
        report('waiting');
        return false;
      };
      const update = () => {
        if (auth()) {
          clearComponent();
          root.removeAttribute('data-duova-instagram');
          report('ready');
          return true;
        }
        if (window.__duovaRefreshStyle) window.__duovaRefreshStyle();
        stripNavigation();
        if (!companion) {
          const main = document.querySelector('main,[role="main"]');
          // Keep the main canvas and live dialogs/menus. Drop the surrounding
          // website shell without removing or relocating React-owned nodes.
          if (main) isolate([main,...document.querySelectorAll('[role="dialog"],[role="menu"],[role="listbox"]')]);
          return true;
        }
        if (previousPath !== location.pathname) {
          previousPath = location.pathname;
          clearComponent();
          report('waiting');
        }
        const context = /^\/(p|reel)\/[^/]+/.test(location.pathname) ? 'comments'
          : location.pathname.startsWith('/direct/') ? 'messages'
          : location.pathname.startsWith('/explore/') ? 'explore' : 'profile';
        mark(root,'data-duova-context',context);
        if (context === 'comments') return comments();
        // Inbox/thread and Explore keep their own content, not the global shell.
        const main = document.querySelector('main,[role="main"]');
        return isolate([main]);
      };
      window.__duovaPresentComponent = update;
      // Mutation callbacks run before paint. Observe structure only: our marker
      // attributes never retrigger this observer or compete with React styles.
      const observer = new MutationObserver(update);
      observer.observe(root,{subtree:true,childList:true});
      document.addEventListener('DOMContentLoaded',update,{once:true});
      window.addEventListener('pageshow',update);
      window.addEventListener('popstate',update);
      update();
    })();
    """#
}
