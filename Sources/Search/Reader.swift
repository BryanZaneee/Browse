import SwiftUI

// Reading mode: the article, and nothing that was arranged around it.
//
// The hard part is deciding what the article is. The heuristic here is the old
// one and it holds up: the piece of the page carrying the most prose, punished
// for every link inside it — because navigation, related-articles rails and
// comment threads are all made of links, and prose is not.

enum Reader {
    static let script = """
    (function () {
      function prose(el) {
        var paragraphs = el.querySelectorAll('p');
        if (paragraphs.length < 2) return 0;
        var letters = 0;
        for (var i = 0; i < paragraphs.length; i++) {
          letters += (paragraphs[i].innerText || '').length;
        }
        if (letters < 400) return 0;
        // A rail of related links has plenty of text and nothing to read.
        var links = el.querySelectorAll('a').length;
        return letters / (1 + links * 14);
      }

      function best() {
        var candidates = document.querySelectorAll(
          'article, main, [role="main"], .post, .entry, .article, .content, #content, div, section'
        );
        var top = null, mark = 0;
        for (var i = 0; i < candidates.length; i++) {
          var score = prose(candidates[i]);
          if (score > mark) { mark = score; top = candidates[i]; }
        }
        return top;
      }

      // Already an article: going back can bring one as it was left, after
      // the page in between let go of reading mode (Tab.didCommit).
      if (window.__browseReaderDocument === document) return 'read';

      var article = best();
      if (!article) return 'none';
      var heading = document.querySelector('h1');

      // Bloomberg keeps an article's byline, its takeaways and the video it
      // opens with between the headline and the text, outside the part with
      // the most prose. Such parts of its head come along, in the page's
      // order: those drawn on the page, and never one from a menu, a rail or
      // a footer. Class names are matched in part and whatever their case,
      // as sites build them (BasicByline_byline__VTyoS); a subheading is an
      // h2.
      var above = [];
      if (heading) {
        var found = document.querySelectorAll(
          '[class*="byline" i],[class*="takeaways" i],[class*="lede" i],h2'
        );
        for (var a = 0; a < found.length; a++) {
          var part = found[a];
          if (part.contains(article) || article.contains(part) ||
              above.some(function (o) { return o.contains(part); })) continue;
          if (!(heading.compareDocumentPosition(part) & Node.DOCUMENT_POSITION_FOLLOWING)) continue;
          if (!(article.compareDocumentPosition(part) & Node.DOCUMENT_POSITION_PRECEDING)) continue;
          if (part.closest('nav, aside, footer, [role="banner"]') || !part.getClientRects().length) continue;
          above.push(part);
        }
      }

      // What the page itself hides stays out: a box it keeps in a copy for
      // each size of screen, of which only one shows. Copied out of the
      // page, every copy comes along, and whether the site's own rules still
      // hide them in the reader depends on how those rules were written.
      // Not when it holds paragraphs, though: an article's folded-away rest
      // is still the article.
      [article].concat(above).forEach(function (root) {
        var every = root.querySelectorAll('*');
        for (var h = 0; h < every.length; h++) {
          var el = every[h];
          if (el.closest('svg') || /^(SOURCE|TRACK|SCRIPT|STYLE|TEMPLATE|BR|WBR)$/.test(el.tagName)) continue;
          if (getComputedStyle(el).display === 'none' && !el.querySelector('p')) el.setAttribute('data-office-gone', '');
        }
      });

      // The photo an article opens with isn't always in it: the FT keeps its
      // own in a topper beside the <article>. So the first large picture
      // before the text comes too, looked for no more than four boxes out,
      // and never in a menu, a rail or a footer.
      var lead = null;
      for (var up = article.parentElement, depth = 0;
           up && up !== document.body && depth < 4 && !lead;
           up = up.parentElement, depth++) {
        var shown = up.querySelectorAll('figure, picture');
        for (var l = 0; l < shown.length && !lead; l++) {
          var face = shown[l].querySelector('img');
          // Before the text, and not around it.
          if (face && article.compareDocumentPosition(shown[l]) === Node.DOCUMENT_POSITION_PRECEDING &&
              !shown[l].closest('nav, aside, footer, [role="banner"]') &&
              face.getBoundingClientRect().width >= 400) lead = shown[l];
        }
      }

      // A chart's frame is as tall as its own script made it, and that script
      // won't run in the reader: the height is read while the page shows it.
      var framed = article.querySelectorAll('iframe');
      for (var z = 0; z < framed.length; z++) {
        framed[z].setAttribute('data-office-height', Math.round(framed[z].getBoundingClientRect().height));
      }

      // The size they gave a drawing in the text, an icon as often as not,
      // goes with them too: left to itself, an <svg> fills the column. The
      // size it is drawn at is written onto it, and nothing for one the page
      // doesn't show.
      var drawings = article.querySelectorAll('svg');
      for (var d = 0; d < drawings.length; d++) {
        if (drawings[d].parentElement.closest('svg')) continue;
        var drawn = drawings[d].getBoundingClientRect();
        drawings[d].setAttribute('width', Math.round(drawn.width));
        drawings[d].setAttribute('height', Math.round(drawn.height));
      }

      // Every picture is resolved while the real page is still standing.
      //
      // currentSrc is what the browser actually chose and loaded, after srcset,
      // sizes and <picture> have had their say. Reading it here and writing it
      // back as a plain src is the only way to be sure the reader shows the
      // same image the page did — copying the markup alone gets you a lazy
      // placeholder, or nothing at all.
      var late = ['data-src', 'data-original', 'data-lazy-src', 'data-lazy',
                  'data-full-src', 'data-hi-res-src', 'data-image', 'data-echo'];
      var pictures = Array.prototype.slice.call(article.querySelectorAll('img'));
      if (lead) pictures = pictures.concat(Array.prototype.slice.call(lead.querySelectorAll('img')));
      above.forEach(function (o) {
        pictures = pictures.concat(Array.prototype.slice.call(o.querySelectorAll('img')));
      });
      for (var i = 0; i < pictures.length; i++) {
        var picture = pictures[i];
        var real = picture.currentSrc || picture.getAttribute('src') || '';
        // A one-pixel placeholder counts as nothing.
        if (!real || real.indexOf('data:image') === 0 || picture.naturalWidth <= 2) {
          for (var k = 0; k < late.length; k++) {
            var kept = picture.getAttribute(late[k]);
            if (kept) { real = kept; break; }
          }
        }
        if (real) picture.setAttribute('data-office-src', real);
      }

      var title = (heading && heading.innerText.trim()) || document.title;

      // Light or dark as the window is, or as chosen in the article's corner
      // (ReaderLook puts it on <html>, which the reader keeps). A page
      // follows the window it is drawn in, so with nothing chosen the
      // article goes dark with the window, and changes with it while open.
      // The dark ground is the window's own (Palette.ground); the text is a
      // shade softer than Palette.ink, there being a lot of it.
      var dark = 'color-scheme:dark;--r-ground:#1c1c1c;--r-ink:#e0e0e0;--r-quiet:#8a8a8a;' +
        '--r-aside:#a8a8a8;--r-rule:#333;--r-code:#2a2a2a;--r-picture:brightness(.92)';
      var sheet = document.createElement('style');
      sheet.textContent = [
        ':root{color-scheme:light;--r-ground:#fff;--r-ink:#171717;--r-quiet:#707070;',
        '--r-aside:#555;--r-rule:#e8e8e8;--r-code:#f5f5f5;--r-picture:none}',
        '@media (prefers-color-scheme:dark){:root:not([data-office-look=light]){' + dark + '}}',
        ':root[data-office-look=dark]{' + dark + '}',
        'html,body{background:var(--r-ground) !important;margin:0 !important;padding:0 !important}',
        '#office-reader{max-width:38em;margin:0 auto;padding:72px 24px 160px;',
        'font:400 18px/1.72 ui-serif,Georgia,"Times New Roman",serif;color:var(--r-ink)}',
        '#office-reader h1{font:600 30px/1.24 -apple-system,BlinkMacSystemFont,sans-serif;',
        'margin:0 0 8px;letter-spacing:-0.01em}',
        '#office-reader .office-from{font:400 12px/1 -apple-system,sans-serif;color:var(--r-quiet);',
        'margin:0 0 40px;text-transform:uppercase;letter-spacing:.06em}',
        '#office-reader p{margin:0 0 1.35em}',
        '#office-reader img,#office-reader video,#office-reader audio,#office-reader iframe{max-width:100%;',
        'height:auto;border-radius:6px;margin:1.6em 0;display:block}',
        // A photo, a touch dimmer on dark, so it doesn't glare.
        '#office-reader img{filter:var(--r-picture)}',
        '#office-reader iframe{width:100%;aspect-ratio:16/9;height:auto;border:0}',
        '#office-reader iframe.office-chart{aspect-ratio:auto}',
        '#office-reader figure{margin:1.8em 0}',
        '#office-reader figcaption{font:400 13px/1.5 -apple-system,sans-serif;',
        'color:var(--r-quiet);margin-top:.6em}',
        // A caption and its credit, which the site's own layout kept apart.
        '#office-reader figcaption > * + *{margin-left:.35em}',
        // The byline and a summary, quieter than the text.
        '#office-reader .office-above{font:400 14px/1.55 -apple-system,sans-serif;',
        'color:var(--r-aside);margin:0 0 1.6em}',
        '#office-reader .office-above ul{padding-left:1.2em}',
        '#office-reader .office-above h2{margin:.4em 0}',
        '#office-reader a{color:var(--r-ink);text-underline-offset:3px}',
        '#office-reader svg{max-width:100%}',
        '#office-reader h2,#office-reader h3{font:600 20px/1.3 -apple-system,sans-serif;',
        'margin:2em 0 .6em}',
        '#office-reader pre,#office-reader code{font-family:ui-monospace,monospace;font-size:14px}',
        '#office-reader pre{background:var(--r-code);padding:14px;border-radius:8px;overflow:auto}',
        '#office-reader blockquote{margin:1.6em 0;padding-left:1.2em;',
        'border-left:2px solid var(--r-rule);color:var(--r-aside)}',
        // A colour written onto an element was picked for the site's own
        // ground, and on dark it can be all but invisible.
        '#office-reader [style]{color:inherit !important;background-color:transparent !important}'
      ].join('');

      // Parse into an inert template: copied resources cannot start loading
      // before the allowlist and media limits below have been applied.
      function inert(markup) {
        var template = document.createElement('template');
        template.innerHTML = markup;
        return template.content.firstElementChild;
      }
      var wrap = inert('<div id="office-reader">' + article.innerHTML + '</div>');
      // The photo comes without the topper's own classes and styles, which
      // the page's stylesheet would still lay out as a topper: off to one
      // side, cropped.
      if (lead) {
        var opening = inert(lead.outerHTML);
        var parts = [opening].concat(Array.prototype.slice.call(opening.querySelectorAll('*')));
        for (var y = 0; y < parts.length; y++) {
          parts[y].removeAttribute('class');
          parts[y].removeAttribute('style');
        }
        wrap.insertBefore(opening, wrap.firstChild);
      }
      for (var o = above.length - 1; o >= 0; o--) {
        var copy = inert(above[o].outerHTML);
        copy.classList.add('office-above');
        wrap.insertBefore(copy, wrap.firstChild);
      }

      // A picture in a button, a click to see it larger, is the picture:
      // Bloomberg puts every photo in one. The button goes and what it holds
      // stays.
      var pressed = wrap.querySelectorAll('button');
      for (var b = 0; b < pressed.length; b++) {
        if (!pressed[b].querySelector('img, picture, video')) continue;
        while (pressed[b].firstChild) pressed[b].parentNode.insertBefore(pressed[b].firstChild, pressed[b]);
        pressed[b].remove();
      }

      // What was arranged around the words rather than being part of them.
      // Not header: an article's opening image lives there as often as not.
      // A video.js player's controls, title bar and read-outs go too; the
      // video stays.
      var clutter = wrap.querySelectorAll(
        'script,style,noscript,object,embed,form,nav,aside,footer,button,input,select,textarea,' +
        '[role="complementary"],[role="navigation"],[role="banner"],[aria-hidden="true"],' +
        '[data-office-gone],.video-js > [class*="vjs-"]:not(video)'
      );
      for (var c = 0; c < clutter.length; c++) clutter[c].remove();

      // So does a box inviting you to a newsletter, which Bloomberg sets in
      // the middle of the text. Only a short one: a newsletter's own page
      // may keep its whole text in a box named the same.
      var invites = wrap.querySelectorAll('[class*="newsletter" i]');
      for (var n = 0; n < invites.length; n++) {
        if (invites[n].querySelectorAll('p').length < 3) invites[n].remove();
      }

      // Only known HTTPS embed endpoints survive; neither a familiar word
      // in a URL nor placement inside a figure makes a frame trustworthy.
      var endpoints = {
        'www.youtube.com': ['/embed'], 'youtube.com': ['/embed'],
        'www.youtube-nocookie.com': ['/embed'], 'youtube-nocookie.com': ['/embed'],
        'player.vimeo.com': ['/video'], 'www.dailymotion.com': ['/embed/video'],
        'www.loom.com': ['/embed'], 'streamable.com': ['/e'],
        'fast.wistia.net': ['/embed/iframe'], 'fast.wistia.com': ['/embed/iframe'],
        'embed.ted.com': ['/talks'], 'flo.uri.sh': ['/visualisation', '/story'],
        'public.flourish.studio': ['/visualisation', '/story'],
        'datawrapper.dwcdn.net': ['/'], 'e.infogram.com': ['/'],
        'public.tableau.com': ['/views'], 'www.google.com': ['/maps/embed']
      };
      var frames = wrap.querySelectorAll('iframe'), accepted = 0;
      for (var f = 0; f < frames.length; f++) {
        var frame = frames[f], url;
        try { url = new URL(frame.getAttribute('src') || frame.getAttribute('data-src') || '', document.baseURI); }
        catch (_) { frame.remove(); continue; }
        var paths = endpoints[url.hostname];
        if (url.protocol !== 'https:' || url.username || url.password ||
            (url.port && url.port !== '443') || !paths ||
            !paths.some(function (path) { return path === '/' || url.pathname === path || url.pathname.startsWith(path + '/'); }) ||
            accepted >= 8) { frame.remove(); continue; }
        accepted++;
        ['autoplay', 'autoPlay', 'autostart'].forEach(function (key) { url.searchParams.delete(key); });
        frame.removeAttribute('srcdoc');
        frame.setAttribute('src', url.href);
        frame.setAttribute('loading', 'lazy');
        frame.setAttribute('allow', "autoplay 'none'; fullscreen");
        frame.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-presentation');
        frame.removeAttribute('width');
        frame.removeAttribute('height');
        var tall = +frame.getAttribute('data-office-height');
        frame.setAttribute('style', 'height:' + Math.max(240, Math.min(800, tall || 420)) + 'px');
        frame.className = 'office-chart';
      }

      // A video's poster, which its player also shows as a picture beside it:
      // once is enough.
      var videos = wrap.querySelectorAll('video'), posters = [];
      for (var v = 0; v < videos.length; v++) {
        if (videos[v].poster) posters.push(videos[v].poster);
      }
      var stills = wrap.querySelectorAll('img');
      for (var s = 0; s < stills.length; s++) {
        if (posters.indexOf(stills[s].src) >= 0 && !stills[s].closest('video')) stills[s].remove();
      }

      // A video its player fed from the page itself, through a blob: address,
      // has nothing to play once that player is gone. It plays from the plain
      // stream it names beside that, which WebKit plays on its own, with
      // controls and never by itself; with none, it is its poster; with no
      // poster, it goes.
      for (var q = 0; q < videos.length; q++) {
        var video = videos[q], fed = /^blob:/.test(video.getAttribute('src') || ''), plain = '';
        var named = video.querySelectorAll('source');
        for (var m = 0; m < named.length; m++) {
          if (/^blob:/.test(named[m].getAttribute('src') || '')) fed = true;
          else if (!plain && /^https?:/.test(named[m].src)) plain = named[m].src;
        }
        if (!fed) continue;
        if (plain) {
          for (var r = 0; r < named.length; r++) named[r].remove();
          video.setAttribute('src', plain);
          video.setAttribute('controls', '');
          video.setAttribute('playsinline', '');
          video.removeAttribute('autoplay');
          // Out of the player's box, which the page's stylesheet still sizes
          // for the player: kept around it, the box's room for the picture
          // and the picture itself would both take a screen's height.
          var player = video.parentNode.closest('.video-js');
          if (player) player.parentNode.replaceChild(video, player);
        } else if (video.poster) {
          var still = document.createElement('img');
          still.setAttribute('src', video.poster);
          video.parentNode.replaceChild(still, video);
        } else {
          video.remove();
        }
      }

      // Media waits for the reader. Bound the copied resource count too,
      // so an unusually long page cannot create unlimited players.
      var media = wrap.querySelectorAll('video, audio');
      for (var m = 0; m < media.length; m++) {
        if (m >= 16) { media[m].remove(); continue; }
        media[m].removeAttribute('autoplay');
        media[m].removeAttribute('loop');
        media[m].setAttribute('preload', 'none');
        media[m].setAttribute('controls', '');
        media[m].pause();
      }
      wrap.querySelectorAll('picture source').forEach(function (source) { source.remove(); });
      var kept = wrap.querySelectorAll('img');
      for (var g = 0; g < kept.length; g++) {
        var src = kept[g].getAttribute('data-office-src') || kept[g].getAttribute('src') || '';
        if (g >= 128 || !src || src.indexOf('data:image') === 0) { kept[g].remove(); continue; }
        kept[g].setAttribute('src', src);
        kept[g].removeAttribute('srcset');
        kept[g].removeAttribute('sizes');
        kept[g].setAttribute('loading', 'lazy');
      }
      // Copied inline event handlers must not restart the site's players.
      wrap.querySelectorAll('*').forEach(function (el) {
        Array.from(el.attributes).forEach(function (attr) {
          if (attr.name.toLowerCase().startsWith('on')) el.removeAttribute(attr.name);
        });
      });

      // A box whose content went (the figure a frame sat in, the one a
      // picture with nothing behind it left) goes too, rather than stay as
      // an empty band in the site's colours.
      var boxes = wrap.querySelectorAll('figure, picture, div, section, p');
      for (var e = boxes.length - 1; e >= 0; e--) {
        if (!boxes[e].textContent.trim() &&
            !boxes[e].querySelector('img, video, audio, iframe, svg, canvas, table')) boxes[e].remove();
      }
      // The article's own heading goes when it only says the title again,
      // which the reader puts on top.
      var own = wrap.querySelector('h1');
      if (own && own.textContent.replace(/\\s+/g, ' ').trim().toLowerCase() ===
          title.replace(/\\s+/g, ' ').toLowerCase()) own.remove();

      var top = document.createElement('h1');
      top.textContent = title;
      var from = document.createElement('p');
      from.className = 'office-from';
      from.textContent = location.host.replace(/^www\\./, '');

      document.body.innerHTML = '';
      // The site's own stylesheets go with its layout. Kept, a rule of theirs
      // like p{color:#222} outranks the article's colour: nothing to see on
      // white, and text that disappears on dark. Search's own stay (office-*:
      // what was hidden on this site, a video floating out of it).
      var theirs = document.querySelectorAll('link[rel~="stylesheet"], style');
      for (var t = 0; t < theirs.length; t++) {
        if (!/^office-/.test(theirs[t].id)) theirs[t].remove();
      }
      if (document.adoptedStyleSheets) document.adoptedStyleSheets = [];
      document.head.appendChild(sheet);
      wrap.insertBefore(from, wrap.firstChild);
      wrap.insertBefore(top, wrap.firstChild);
      wrap.querySelectorAll('#office-reader').forEach(function (el) { el.removeAttribute('id'); });
      document.body.appendChild(wrap);
      window.__browseReaderDocument = document;
      window.scrollTo(0, 0);
      return 'read';
    })();
    """

    /// Light, dark, or as the window is: chosen on an article, and kept for
    /// the next one.
    static var look: Look {
        get { Store.settings.string(forKey: "reader.look").flatMap(Look.init) ?? .system }
        set { Store.settings.set(newValue.rawValue, forKey: "reader.look") }
    }

    /// Puts a look on the page. It is on <html>, which the reader keeps, so
    /// it holds for the article and goes when the page does.
    static func apply(_ look: Look) -> String {
        look == .system
            ? "document.documentElement.removeAttribute('data-office-look');"
            : "document.documentElement.setAttribute('data-office-look','\(look.rawValue)');"
    }
}

/// The article’s own light and dark, in its corner while it is up.
struct ReaderLook: View {
    @ObservedObject var tab: Tab
    private var look: Look { tab.readerLook }
    @Environment(\.colorScheme) private var window

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Look.allCases) { each in
                Button {
                    tab.readerLook = each
                    Reader.look = each
                } label: {
                    Image(systemName: each == .light ? "sun.max" : each == .dark ? "moon" : "circle.lefthalf.filled")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(look == each ? Palette.ink : Palette.muted)
                        .frame(width: 24, height: 22)
                        .background(Capsule().fill(look == each ? Palette.wash : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(each == .system ? "Follow window appearance" : "Reader appearance: \(each.title)")
                .accessibilityAddTraits(look == each ? .isSelected : [])
                .help(each == .system ? "As the window is" : each.title)
            }
        }
        .padding(3)
        .background(Palette.ground, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
        // In the article's colours, which may not be the window's.
        .environment(\.colorScheme, look == .dark ? .dark : look == .light ? .light : window)
        .padding(14)

    }
}
