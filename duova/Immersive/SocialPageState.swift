import Foundation

/// Only structural positions and public content references; never text, input values,
/// media source URLs, cookies, or a copy of the document.
struct SocialPageState: Codable, Equatable {
    struct Scroller: Codable, Equatable {
        var path: [Int]
        var tag: String
        var x: Double
        var y: Double
    }
    struct Media: Codable, Equatable {
        var anchor: String?
        var index: Int
        var seconds: Double
    }
    var route: String
    var x: Double
    var y: Double
    var anchor: String?
    var anchorOffset: Double?
    var scrollers: [Scroller]
    var media: [Media]
}

/// Adapter-independent, bounded DOM position capture. No scripts click controls or
/// resume playback; restoring a time is deliberately separate from autoplay.
enum SocialPageScripts {
    static let runtime = #"""
    (() => {
      if (window.__duovaState) return;
      const path = () => location.pathname;
      const permalink = element => {
        const article = element.closest('article');
        const link = article && article.querySelector('a[href*="/p/"],a[href*="/reel/"]');
        if (!link) return null;
        try {
          const u = new URL(link.href, location.href);
          return u.origin === location.origin && /^\/(p|reel)\/[A-Za-z0-9_-]+\/$/.test(u.pathname) ? u.pathname : null;
        } catch (_) { return null; }
      };
      const structuralPath = element => {
        const parts = [];
        while (element && element !== document.body && parts.length < 12) {
          const parent = element.parentElement;
          if (!parent) return null;
          parts.unshift(Array.prototype.indexOf.call(parent.children, element));
          element = parent;
        }
        return element === document.body ? parts : null;
      };
      const resolve = parts => {
        let e = document.body;
        for (const i of parts) { e = e && e.children[i]; }
        return e;
      };
      let interaction = 0;
      const touched = () => { interaction++; };
      ['pointerdown','touchstart','wheel','keydown'].forEach(name =>
        document.addEventListener(name, touched, {capture:true, passive:true}));
      const restoredStates = new Map();
      window.__duovaState = {
        interaction: () => interaction,
        capture: () => {
          let anchor = null, offset = null, distance = Infinity;
          for (const article of Array.from(document.querySelectorAll('article')).slice(0,80)) {
            const r = article.getBoundingClientRect();
            if (r.bottom <= 0 || r.top >= innerHeight) continue;
            const key = permalink(article);
            if (key && Math.abs(r.top) < distance) {
              anchor = key; offset = r.top; distance = Math.abs(r.top);
            }
          }
          const scrollers = [];
          for (const e of Array.from(document.querySelectorAll('main,section,div,ul,[role="dialog"]')).slice(0,1800)) {
            if (scrollers.length >= 6) break;
            if ((e.scrollTop > 0 || e.scrollLeft > 0) && e.clientHeight > 0) {
              const p = structuralPath(e);
              if (p) scrollers.push({path:p,tag:e.tagName,x:e.scrollLeft,y:e.scrollTop});
            }
          }
          const media = Array.from(document.querySelectorAll('video')).slice(0,4).flatMap((v,index) => {
            const r = v.getBoundingClientRect();
            if (r.bottom < 0 || r.top > innerHeight || !Number.isFinite(v.currentTime)) return [];
            return [{anchor:permalink(v),index,seconds:v.currentTime}];
          });
          return {route:path(),x:scrollX,y:scrollY,anchor,anchorOffset:offset,scrollers,media};
        },
        restore: (s, token) => {
          if (interaction !== token || path() !== s.route) return {done:false,interrupted:true};
          if (document.readyState === 'loading' || !document.body) return {done:false};
          const key = JSON.stringify(s);
          let applied = restoredStates.get(key);
          if (!applied) {
            restoredStates.clear();
            applied = {positioned:false, nested:new Set(), media:new Set()};
            restoredStates.set(key, applied);
          }
          let positioned = applied.positioned;
          if (!positioned && s.anchor) {
            for (const article of Array.from(document.querySelectorAll('article')).slice(0,80)) {
              if (permalink(article) === s.anchor) {
                scrollBy(0, article.getBoundingClientRect().top - (s.anchorOffset || 0));
                positioned = true; break;
              }
            }
          } else if (!positioned) {
            const root = document.scrollingElement;
            if (root && root.scrollHeight >= s.y + Math.min(innerHeight, 100)) scrollTo(s.x, s.y);
            positioned = Math.abs(scrollY - s.y) < 4 &&
              root && root.scrollHeight >= s.y + Math.min(innerHeight, 100);
          }
          applied.positioned = positioned;
          let nested = true;
          for (const item of s.scrollers) {
            const key = JSON.stringify(item.path);
            if (applied.nested.has(key)) continue;
            const e = resolve(item.path);
            if (!e || e.tagName !== item.tag) { nested = false; continue; }
            e.scrollTop = item.y; e.scrollLeft = item.x;
            if (Math.abs(e.scrollTop - item.y) > 4) nested = false;
            else applied.nested.add(key);
          }
          let sought = true;
          const videos = Array.from(document.querySelectorAll('video')).slice(0,4);
          for (const item of s.media) {
            if (applied.media.has(item.index)) continue;
            const v = item.anchor ? videos.find(v => permalink(v) === item.anchor) : videos[item.index];
            if (!v || v.readyState < 1 || !Number.isFinite(v.duration) || v.duration <= 0) {
              sought = false; continue;
            }
            try { v.currentTime = Math.min(item.seconds, Math.max(0,v.duration - 0.1)); applied.media.add(item.index); }
            catch (_) { sought = false; }
          }
          return {done:!!positioned && nested && sought,interrupted:false};
        }
      };
      let queued = false;
      const notify = () => {
        if (queued || document.hidden) return;
        queued = true;
        setTimeout(() => {
          queued = false;
          try { window.webkit.messageHandlers.duova.postMessage({type:'state'}); } catch (_) {}
        }, 1500);
      };
      document.addEventListener('scroll',notify,{capture:true,passive:true});
      document.addEventListener('timeupdate',notify,true);
      document.addEventListener('pause',notify,true);
      window.addEventListener('popstate',notify);
      let lastPath = path();
      setInterval(() => {
        if (!document.hidden && lastPath !== path()) {
          lastPath = path();
          if (window.__duovaRefreshStyle) window.__duovaRefreshStyle();
          notify();
        }
      },1500);
    })();
    """#

    static func restore(_ state: SocialPageState, interaction: Int) -> String? {
        guard let data = try? JSONEncoder().encode(state),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return "window.__duovaState ? window.__duovaState.restore(\(json), \(interaction)) : null"
    }
}
