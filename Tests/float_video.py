#!/usr/bin/env python3
"""Native PiP regression checks. Build with ./build.sh debug, then run this file.

Uses an isolated Search probe and loopback fixtures. These checks briefly open
macOS's PiP window; the source browser starts hidden.
"""
import functools
import json
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import split_view as sv

ROOT = Path(__file__).resolve().parents[1]
sv.use('native-pip-tests')

class Quiet(SimpleHTTPRequestHandler):
    def log_message(self, *args): pass


def wait(read, check=lambda x: bool(x), seconds=8):
    end = time.monotonic() + seconds
    while True:
        value = read()
        if check(value): return value
        if time.monotonic() > end: raise AssertionError(f'Timed out: {value}')
        time.sleep(.1)


def js(tab, code):
    result = sv.cmd({'do': 'eval', 'id': tab, 'js': code})
    assert 'error' not in result, result
    return result.get('value')


def state(tab, **fields): return sv.cmd({'do': 'pip', 'action': 'state', 'id': tab, **fields})
def pip(tab, action, **fields):
    result = sv.cmd({'do': 'pip', 'action': action, 'id': tab, **fields})
    if action == 'exit': wait(lambda:state(tab, **fields),lambda x:not x['busy'])
    return result

def geometry(tab):
    return json.loads(js(tab, "JSON.stringify({id:fixtureIdentity,w:innerWidth,h:innerHeight,scroll:scrollY,video:document.querySelector('video')?.getBoundingClientRect().toJSON(),form:document.querySelector('#note')?.value})"))


def main():
    server = ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Quiet, directory=str(ROOT/'Tests/Fixtures/PictureInPicture')))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f'http://127.0.0.1:{server.server_port}/index.html'
    t = sv.T()
    try:
        sv.setup(**{'float.leave': False, 'float.away': False}); sv.launch()
        sv.cmd({'do': 'window'})
        t.ok('the optional toolbar button defaults to off', not sv.cmd({'do':'pip'})['buttonEnabled'])
        sv.cmd({'do':'ui','pipButton':True})
        t.ok('the toolbar button can be enabled', sv.cmd({'do':'pip'})['buttonEnabled'])
        for kind in ['landscape', 'portrait', 'iframe']:
            tab = sv.sp('open', url=f'{base}?kind={kind}')['resultID']
            sv.sp('select', id=tab)
            wait(lambda: state(tab), lambda x: x.get('available'))
            js(tab, "document.querySelector('#note').value='My draft'; window.scrollTo(0,80)")
            before = geometry(tab)
            result = pip(tab, 'enter')
            t.ok(f'{kind}: native entry succeeds', result.get('result') == 'started', result)
            wait(lambda: state(tab), lambda x: x.get('active'))
            after = geometry(tab)
            t.ok(f'{kind}: entry keeps the same document and geometry', before == after, [before, after])
            t.ok(f'{kind}: the live page remains attached to the browser', state(tab)['inBrowser'])
            js(tab, "document.querySelector('#form').requestSubmit(); document.querySelector('#jump').click()")
            t.ok(f'{kind}: forms and links remain usable', js(tab, "document.querySelector('#saved').textContent === 'Saved: My draft' && location.hash === '#end' && scrollY > 80"))
            if kind != 'iframe':
                t.ok(f'{kind}: actual WebKit presentation is native PiP', js(tab, "document.querySelector('video').webkitPresentationMode") == 'picture-in-picture')
            pip(tab, 'exit')
            wait(lambda: state(tab), lambda x: not x.get('active'))
            t.ok(f'{kind}: return preserves the page and form', js(tab, "document.querySelector('#note').value === 'My draft' && document.querySelector('#form').checkVisibility()"))
            if kind != 'iframe':
                t.ok(f'{kind}: returning a playing video keeps it playing',js(tab,"!document.querySelector('video').paused"))
            pip(tab, 'enter')
            if kind != 'iframe':
                js(tab, "document.querySelector('video').webkitSetPresentationMode('inline')")
                wait(lambda: state(tab), lambda x: not x.get('active'))
                t.ok(f'{kind}: site exit clears Search state', not state(tab)['active'])
            pip(tab, 'exit')
            sv.sp('close', id=tab)
        tab = sv.sp('open', url=base)['resultID']; sv.sp('select', id=tab)
        wait(lambda: state(tab), lambda x: x.get('available'))
        pip(tab, 'enter')
        other = sv.sp('open', url=base+'?kind=empty')['resultID']
        sv.sp('select', id=other); sv.sp('select', id=tab)
        t.ok('manual PiP survives switching away and returning', state(tab)['active'] and state(tab)['inBrowser'])
        sv.sp('select',id=other); pip(tab,'restore')
        wait(lambda:state(tab),lambda x:not x['active'])
        t.ok('native Restore returns to the source tab',sv.sp('state')['activeID']==tab and state(tab)['inBrowser'])
        pip(tab,'enter')
        sv.cmd({'do':'resize', 'width':1050, 'height':760, 'steps':3})
        t.ok('browser resizing keeps native PiP and page content', state(tab)['active'] and js(tab,"document.querySelector('#form').checkVisibility()"))
        pip(tab, 'exit'); wait(lambda: state(tab), lambda x: not x['active'])
        for n in range(5):
            result = pip(tab, 'enter')
            t.ok(f'rapid round trip {n+1}: native entry', result.get('result') == 'started', result)
            pip(tab, 'exit'); wait(lambda: state(tab), lambda x: not x['active'])
        js(tab, "document.querySelector('video').pause()")
        wait(lambda: js(tab, "document.querySelector('video').paused"))
        pip(tab,'enter')
        js(tab,"document.querySelector('video').pause()")
        wait(lambda:js(tab,"document.querySelector('video').paused"))
        pip(tab,'exit')
        wait(lambda:state(tab),lambda x:not x['active'])
        t.ok('returning a paused video leaves it paused',js(tab,"document.querySelector('video').paused"))
        t.ok('return preserves inline presentation without a resize',js(tab,"document.querySelector('video').webkitPresentationMode")=='inline')
        pip(tab,'enter')
        js(tab,"document.querySelector('video').pause(); document.querySelector('video').currentTime = 1")
        wait(lambda:js(tab,"!document.querySelector('video').seeking && Math.abs(document.querySelector('video').currentTime - 1) < .1"))
        t.ok('seeking while floating preserves native PiP',state(tab)['active'] and js(tab,"document.querySelector('video').webkitPresentationMode")=='picture-in-picture')
        pip(tab,'exit')
        t.ok('return preserves the seek position',js(tab,"Math.abs(document.querySelector('video').currentTime - 1) < .1"))
        time.sleep(.1)
        result = sv.cmd({'do':'pip','action':'enter','id':tab,'automatic':True})
        t.ok('automatic PiP does not start a paused video', result['result'] == 'unavailable', result)
        js(tab, "document.querySelector('video').play(); true")
        wait(lambda: js(tab, "!document.querySelector('video').paused")); time.sleep(.1)
        result = sv.cmd({'do':'pip','action':'enter','id':tab,'automatic':True})
        t.ok('automatic PiP follows a playing video', result['result'] == 'started', result)
        sv.sp('select',id=other); sv.sp('select',id=tab)
        wait(lambda: state(tab), lambda x: not x['active'])
        t.ok('automatic PiP returns when its source tab is selected', not state(tab)['active'])
        wait(lambda: (js(tab, "document.querySelector('video').webkitSetPresentationMode('picture-in-picture')"), state(tab))[1], lambda x: x['active'])
        t.ok('site-initiated PiP is reflected in Search', state(tab)['active'])
        pip(tab,'exit'); wait(lambda: state(tab), lambda x: not x['active'])
        pip(tab,'enter')
        js(tab, "location.href='index.html?kind=empty'")
        wait(lambda: js(tab,'document.readyState'), lambda x: x == 'complete')
        wait(lambda: state(tab), lambda x: not x['active'] and not x['available'])
        t.ok('source navigation clears PiP and video availability', not state(tab)['active'])
        sv.sp('close',id=tab); sv.sp('close',id=other)
        tab = sv.sp('open',url=base+'?kind=iframe')['resultID'];sv.sp('select',id=tab)
        wait(lambda: state(tab),lambda x:x['available']);pip(tab,'enter')
        js(tab,"document.querySelector('iframe').remove()")
        wait(lambda: state(tab),lambda x:not x['active'] and not x['available'])
        t.ok('removing an embedded player clears its session',not state(tab)['active'])
        sv.sp('close',id=tab)
        tab = sv.sp('open',url=base)['resultID']; sv.sp('select',id=tab)
        wait(lambda:state(tab),lambda x:x['available'])
        sv.cmd({'do':'keyeq','chars':'p','code':35,'mods':['shift']})
        wait(lambda:state(tab),lambda x:x['active'])
        t.ok('the existing shortcut enters native PiP',state(tab)['active'])
        other = sv.sp('open',url=base+'?kind=empty')['resultID']
        sv.sp('close',id=tab)
        wait(lambda:state(other),lambda x:not x['busy'])
        t.ok('closing the source tab clears the native session',not state(other)['owner'])
        tab = sv.sp('open',url=base)['resultID']; sv.sp('select',id=tab)
        wait(lambda:state(tab),lambda x:x['available'])
        sv.cmd({'do':'eval','id':tab,'world':'search','js':"const enter = __searchPiP.enter; __searchPiP.enter = async (...args) => { const ok = await enter(...args); await new Promise(r => setTimeout(r,700)); return ok; }; true"})
        with ThreadPoolExecutor(max_workers=1) as executor:
            entering = executor.submit(pip,tab,'enter')
            wait(lambda:state(tab),lambda x:x['pending'] and x['active'])
            js(tab,"document.querySelector('video').webkitSetPresentationMode('inline')")
            wait(lambda:js(tab,"document.querySelector('video').webkitPresentationMode"),lambda x:x=='inline')
            result = entering.result(timeout=8)
        t.ok('an early native exit cannot be undone by a late entry reply',result['result']=='cancelled' and not state(tab)['active'] and not state(tab)['busy'],result)
        sv.sp('close',id=tab)
        tab = sv.sp('open',url=base)['resultID']; sv.sp('select',id=tab)
        wait(lambda:state(tab),lambda x:x['available'])
        # Delay the reply, so cancellation is checked even on a fast native transition.
        sv.cmd({'do':'eval','id':tab,'world':'search','js':"const enter = __searchPiP.enter; __searchPiP.enter = async (...args) => { const ok = await enter(...args); await new Promise(r => setTimeout(r,700)); return ok; }; true"})
        with ThreadPoolExecutor(max_workers=1) as executor:
            entering = executor.submit(pip,tab,'enter')
            wait(lambda:state(tab),lambda x:x['pending'])
            sv.sp('close',id=tab)
            result = entering.result(timeout=8)
        wait(lambda:state(other),lambda x:not x['busy'])
        t.ok('closing a source during entry cancels its request',result['result']=='cancelled' and not state(other)['owner'],result)
        tab = sv.sp('open',url=base)['resultID']; sv.sp('select',id=tab)
        wait(lambda:state(tab),lambda x:x['available']); pip(tab,'enter')
        sv.cmd({'do':'windows','action':'new'})
        second = sv.sp('open',url=base,window=2)['resultID']; sv.sp('select',id=second,window=2)
        sv.cmd({'do':'windows','action':'front','n':2})
        wait(lambda:state(second,window=2),lambda x:x['available'])
        sv.cmd({'do':'keyeq','chars':'p','code':35,'mods':['shift'],'window':2})
        wait(lambda:state(second,window=2),lambda x:x['active'])
        t.ok('another window can take over PiP',not state(tab,window=1)['active'] and state(second,window=2)['active'])
        sv.cmd({'do':'windows','action':'close','n':2})
        sv.cmd({'do':'windows','action':'front','n':1})
        wait(lambda:pip(tab,'enter'),lambda x:x['result']=='started')
        t.ok('closing the source window permits a new session',state(tab)['active'])
        pip(tab,'exit'); wait(lambda:state(tab),lambda x:not x['active'])
        sv.sp('close',id=tab); sv.sp('close',id=other)
        tab = sv.sp('open',url=base)['resultID']; sv.sp('select',id=tab)
        wait(lambda:state(tab),lambda x:x['available'])
        before = geometry(tab)
        js(tab, "document.querySelector('video').disablePictureInPicture = true")
        wait(lambda:state(tab),lambda x:not x['available'])
        result = pip(tab,'enter')
        t.ok('a site disabling PiP after load is respected',result['result']=='unavailable' and geometry(tab)==before,result)
        js(tab, "document.querySelector('video').disablePictureInPicture = false")
        wait(lambda:state(tab),lambda x:x['available'])
        t.ok('a site enabling PiP again can enter',pip(tab,'enter')['result']=='started')
        pip(tab,'exit')
        # Single-page players replace their media without navigating the document.
        js(tab, "window.oldVideo = document.querySelector('video'); oldVideo.pause(); oldVideo.remove()")
        wait(lambda:state(tab),lambda x:not x['available'])
        t.ok('removing the inline player clears availability',pip(tab,'enter')['result']=='unavailable')
        js(tab, "const v = oldVideo.cloneNode(true); document.querySelector('#player').append(v); v.play(); true")
        wait(lambda:state(tab),lambda x:x['available'])
        result = pip(tab,'enter')
        t.ok('a replacement player enters without reloading the page',result['result']=='started' and geometry(tab)['id']==before['id'],result)
        pip(tab,'exit')
        t.ok('return preserves the replacement player and leaves the removed one paused',js(tab,"document.querySelector('video').webkitPresentationMode === 'inline' && !document.querySelector('video').paused && oldVideo.paused && !oldVideo.isConnected"))
        sv.sp('close',id=tab)
        for kind in ['disabled', 'empty']:
            tab = sv.sp('open', url=f'{base}?kind={kind}')['resultID']
            wait(lambda: js(tab, 'document.readyState'), lambda x: x == 'complete')
            time.sleep(.3)
            before = geometry(tab)
            result = pip(tab, 'enter')
            t.ok(f'{kind}: refused without disturbing the page', result.get('result') == 'unavailable' and geometry(tab) == before and not state(tab)['active'], result)
            sv.sp('close', id=tab)
        tab = sv.sp('open',url=base)['resultID']; sv.sp('select',id=tab)
        wait(lambda:state(tab),lambda x:x['available']); pip(tab,'enter')
        sv.cmd({'do':'windows','action':'close','n':1})
        wait(lambda:state(tab),lambda x:not x['active'] and not x['owner'])
        t.ok('closing the last browser window also returns its video',not state(tab)['active'])
    finally:
        t.done(); sv.finish(); server.shutdown()
    raise SystemExit(1 if t.failed else 0)

if __name__ == '__main__': main()
