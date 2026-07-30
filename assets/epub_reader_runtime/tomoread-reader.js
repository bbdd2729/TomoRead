import './foliate-paginator.js'
import * as CFI from './epubcfi.js'

const runtimeVersion = '5'
const stage = document.getElementById('reader-stage')

let session
let book
let paginator
let annotations = []
let focusedAnnotationId
let pageTransition = 'slide'
let turnLocked = false

const postMessage = message => {
  if (window.chrome?.webview?.postMessage) {
    window.chrome.webview.postMessage(message)
    return
  }
  if (window.TomoRead?.postMessage) {
    window.TomoRead.postMessage(JSON.stringify(message))
  }
}

const loadManifest = async () => {
  const response = await fetch('./manifest.json')
  if (!response.ok) throw new Error(`Unable to load session manifest (${response.status})`)
  return response.json()
}

const getSections = () => session.manifest.spine ?? []

const sectionUrl = href => new URL(`../${href.split('#')[0]}`, location.href).href

const findSection = href => {
  const path = href.split('#')[0]
  return getSections().findIndex(section => section.href === path)
}

const applySettings = settings => {
  if (!paginator) return
  pageTransition = settings.pageTransition ?? 'slide'
  paginator.setAttribute('flow', settings.flow ?? 'paginated')
  paginator.setAttribute('max-column-count', String(settings.columnCount ?? 1))
  paginator.setAttribute('max-inline-size', `${settings.maxInlineSize ?? 760}px`)
  paginator.setAttribute('margin', `${settings.margin ?? 32}px`)
  paginator.toggleAttribute('animated', pageTransition !== 'none')
  paginator.setStyles(`
    html {
      color: ${settings.foreground};
      background: ${settings.background};
      font-family: ${JSON.stringify(settings.fontFamily)}, sans-serif;
      font-size: ${settings.fontSize}px;
      line-height: ${settings.lineHeight};
      direction: ${settings.direction};
    }
    body {
      box-sizing: border-box;
      margin: 0;
      color: inherit;
      background: transparent;
    }
    img, svg, video { max-width: 100%; height: auto; }
  `)
}

const runPageTransition = async (direction, operation) => {
  if (turnLocked) return
  turnLocked = true
  const sign = direction === 'previous' ? -1 : 1
  const animation = pageTransition === 'fade'
    ? paginator.animate([{ opacity: 1 }, { opacity: .28 }, { opacity: 1 }], { duration: 220, easing: 'ease-out' })
    : pageTransition === 'cover'
      ? paginator.animate([
        { transform: `translateX(${sign * 4}%)`, opacity: .72 },
        { transform: 'translateX(0)', opacity: 1 },
      ], { duration: 220, easing: 'cubic-bezier(.2,.75,.2,1)' })
      : null
  try {
    await operation()
    await animation?.finished
  } finally {
    turnLocked = false
  }
}

const turn = direction => runPageTransition(
  direction,
  () => direction === 'previous' ? paginator.prev() : paginator.next(),
)

const anchorFor = (fragment, fraction) => {
  if (!fragment) return fraction ?? 0
  const id = decodeURIComponent(fragment.replace(/^#/, ''))
  return doc => doc.getElementById(id) ?? doc.querySelector(`[name="${CSS.escape(id)}"]`) ?? fraction ?? 0
}

const nearestAnchor = range => {
  let element = range?.startContainer
  if (element?.nodeType !== Node.ELEMENT_NODE) element = element?.parentElement
  return element?.closest?.('[id]')?.id ?? null
}

const cfiFor = range => {
  try {
    return range ? CFI.fromRange(range) : null
  } catch {
    return null
  }
}

const rangeForCfi = (doc, cfi) => {
  try {
    return CFI.toRange(doc, CFI.parse(cfi))
  } catch {
    return null
  }
}

const rangeForOffsets = (doc, startOffset, endOffset) => {
  const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
  let node
  let offset = 0
  let start
  let end
  while (node = walker.nextNode()) {
    const length = node.textContent.length
    if (!start && startOffset <= offset + length) {
      start = [node, Math.max(0, startOffset - offset)]
    }
    if (!end && endOffset <= offset + length) {
      end = [node, Math.max(0, endOffset - offset)]
      break
    }
    offset += length
  }
  if (!start || !end) return null
  const range = doc.createRange()
  range.setStart(...start)
  range.setEnd(...end)
  return range
}

const applyAnnotations = (doc, index) => {
  const highlights = doc.defaultView.CSS?.highlights
  const Highlight = doc.defaultView.Highlight
  if (!highlights || !Highlight) return
  const styleId = 'tomoread-runtime-annotations'
  let style = doc.getElementById(styleId)
  if (!style) {
    style = doc.createElement('style')
    style.id = styleId
    doc.head.append(style)
  }
  style.textContent = `
    ::highlight(tomoread-yellow) { background: #f7d15499; }
    ::highlight(tomoread-green) { background: #80c78399; }
    ::highlight(tomoread-blue) { background: #7db8f299; }
    ::highlight(tomoread-pink) { background: #ec91b699; }
  `
  const groups = new Map(['yellow', 'green', 'blue', 'pink'].map(color => [color, new Highlight()]))
  const href = getSections()[index]?.href
  let focusedRange
  for (const annotation of annotations) {
    if (annotation.href !== href) continue
    const range = annotation.locator.startsWith('cfi:')
      ? rangeForCfi(doc, annotation.loc.slice(4))
      : (() => {
          const [start, end] = annotation.locator.split(':').map(Number)
          return Number.isFinite(start) && Number.isFinite(end)
            ? rangeForOffsets(doc, start, end)
            : null
        })()
    if (!range) continue
    groups.get(annotation.color)?.add(range)
    if (annotation.id === focusedAnnotationId) focusedRange = range
  }
  for (const [color, ranges] of groups) highlights.set(`tomoread-${color}`, ranges)
  if (focusedRange) window.setTimeout(() => void paginator?.scrollToAnchor(focusedRange), 0)
}

const applySelectionListener = (doc, index) => {
  let pending = false
  doc.addEventListener('selectionchange', () => {
    if (pending) return
    pending = true
    window.setTimeout(() => {
      pending = false
      const selection = doc.getSelection()
      if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return
      const range = selection.getRangeAt(0)
      if (!doc.body.contains(range.commonAncestorContainer)) return
      const text = selection.toString().replace(/\s+/g, ' ').trim()
      if (!text) return
      const before = range.cloneRange()
      before.selectNodeContents(doc.body)
      before.setEnd(range.startContainer, range.startOffset)
      postMessage({
        type: 'textSelection',
        href: getSections()[index]?.href,
        text,
        startOffset: before.toString().length,
        endOffset: before.toString().length + range.toString().length,
        cfi: cfiFor(range),
      })
    }, 80)
  })
}

const emitRelocation = detail => {
  const section = getSections()[detail.index]
  if (!section || !paginator) return
  postMessage({
    type: 'runtimeRelocate',
    href: section.href,
    chapterIndex: detail.index,
    ratio: Number.isFinite(detail.fraction) ? detail.fraction : 0,
    anchor: nearestAnchor(detail.range),
    cfi: cfiFor(detail.range),
    pageIndex: Math.max(0, paginator.page || 0),
    pageCount: Math.max(1, paginator.pages || 1),
  })
}

const attachDocumentInteractions = ({ detail: { doc, index } }) => {
  applyAnnotations(doc, index)
  applySelectionListener(doc, index)
  doc.addEventListener('click', event => {
    const link = event.target.closest?.('a[href]')
    if (link) {
      const target = new URL(link.href, doc.location.href)
      const targetIndex = getSections().findIndex(section => sectionUrl(section.href) === target.href.split('#')[0])
      if (targetIndex >= 0) {
        event.preventDefault()
        void paginator.goTo({ index: targetIndex, anchor: anchorFor(target.hash, 0) })
      }
      return
    }
    if (doc.getSelection()?.toString().trim()) return
    const ratio = event.clientX / doc.defaultView.innerWidth
    if (ratio <= 0.25) {
      void turn('previous')
    } else if (ratio >= 0.75) {
      void turn('next')
    } else {
      postMessage({ type: 'readerControls' })
    }
  })
}

const createPaginator = () => {
  paginator?.destroy()
  paginator = document.createElement('foliate-paginator')
  stage.replaceChildren(paginator)
  paginator.addEventListener('relocate', ({ detail }) => emitRelocation(detail))
  paginator.addEventListener('load', attachDocumentInteractions)
  paginator.addEventListener('error', error => {
    postMessage({ type: 'runtimeError', message: String(error.message ?? error) })
  })
}

const open = async options => {
  session ??= await loadManifest()
  if (!paginator) {
    createPaginator()
    book = {
      dir: session.manifest.direction,
      sections: getSections().map(section => ({
        linear: section.linear ? 'yes' : 'no',
        load: async () => sectionUrl(section.href),
      })),
    }
    paginator.open(book)
  }
  applySettings(options.settings)
  await goToHref(options.href, options.ratio, options.anchor)
  postMessage({ type: 'runtimeOpened', runtimeVersion })
}

const goToHref = async (href, ratio = 0, anchor) => {
  if (!paginator) return
  const index = findSection(href)
  if (index < 0) return
  const fragment = anchor || href.split('#')[1]
  await paginator.goTo({ index, anchor: anchorFor(fragment, ratio) })
}

const goToPage = async pageIndex => {
  if (!paginator) return
  const pages = Math.max(1, paginator.pages || 1)
  const fraction = pages <= 1 ? 0 : Math.max(0, Math.min(1, pageIndex / (pages - 1)))
  await runPageTransition(
    pageIndex < paginator.page ? 'previous' : 'next',
    () => paginator.goTo({ index: paginator.primaryIndex, anchor: fraction }),
  )
}

const setAnnotations = (nextAnnotations, nextFocusedAnnotationId) => {
  annotations = nextAnnotations ?? []
  focusedAnnotationId = nextFocusedAnnotationId
  for (const { doc, index } of paginator?.getContents?.() ?? []) {
    applyAnnotations(doc, index)
  }
}

window.TomoReadEpubRuntime = Object.freeze({
  runtimeVersion,
  loadManifest,
  open,
  goToHref,
  goToPage,
  turn,
  setAnnotations,
  setSettings: applySettings,
  postMessage,
})

window.addEventListener('DOMContentLoaded', () => {
  postMessage({ type: 'runtimeReady', runtimeVersion })
}, { once: true })
