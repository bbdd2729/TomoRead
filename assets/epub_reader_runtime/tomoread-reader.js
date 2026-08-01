import './foliate-paginator.js'
import * as CFI from './epubcfi.js'

const runtimeVersion = '21'
const stage = document.getElementById('reader-stage')

let session
let book
let paginator
let annotations = []
let focusedAnnotationId
let searchQuery = ''
let pageTransition = 'slide'
let tapNavigationEnabled = false
let turnLocked = false
let currentSectionIndex = 0
let currentRatio = 0
let currentPageIndex = 0
let currentPageCount = 1
let measuredRelocationRevision = 0
let commandTail = Promise.resolve()
let nextCommandId = 1

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
  tapNavigationEnabled = settings.tapNavigationEnabled === true
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

const turnUnsafe = async direction => {
  await runPageTransition(
    direction,
    () => direction === 'previous' ? paginator.prev() : paginator.next(),
  )
  // A continuous paginator already emits its measured relocation as it
  // scrolls. Sending a synthetic snapshot here can report the old ratio and
  // snap Flutter's progress slider back to the chapter start.
  if (paginator?.getAttribute('flow') !== 'scrolled') {
    await reportPaginatorPosition()
  }
}

const anchorFor = (fragment, fraction, cfi) => {
  const cfiAnchor = cfi ? doc => rangeForCfi(doc, cfi) : null
  if (cfiAnchor) {
    return doc => cfiAnchor(doc) ?? anchorFor(fragment, fraction)(doc)
  }
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
  }
  for (const [color, ranges] of groups) highlights.set(`tomoread-${color}`, ranges)
  // The caller navigates to a focused annotation before this method runs.
  // Scrolling a range from a preloaded iframe through the paginator can map it
  // against a different primary document.
}

const applySearchHighlights = doc => {
  const highlights = doc.defaultView.CSS?.highlights
  const Highlight = doc.defaultView.Highlight
  if (!highlights || !Highlight) return
  const ranges = new Highlight()
  const query = searchQuery.toLocaleLowerCase()
  if (query) {
    const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
    let node
    while (node = walker.nextNode()) {
      const text = node.textContent.toLocaleLowerCase()
      let offset = text.indexOf(query)
      while (offset >= 0) {
        const range = doc.createRange()
        range.setStart(node, offset)
        range.setEnd(node, offset + query.length)
        ranges.add(range)
        offset = text.indexOf(query, offset + query.length)
      }
    }
  }
  highlights.set('tomoread-search', ranges)
  let style = doc.getElementById('tomoread-runtime-search')
  if (!style) {
    style = doc.createElement('style')
    style.id = 'tomoread-runtime-search'
    doc.head.append(style)
  }
  style.textContent = '::highlight(tomoread-search) { background: #ffb74d99; }'
}

const readSelection = (doc, index) => {
  const selection = doc.getSelection()
  if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return null
  const range = selection.getRangeAt(0)
  if (!doc.body.contains(range.commonAncestorContainer)) return null
  const text = selection.toString().replace(/\s+/g, ' ').trim()
  if (!text) return null
  const before = range.cloneRange()
  before.selectNodeContents(doc.body)
  before.setEnd(range.startContainer, range.startOffset)
  return {
    href: getSections()[index]?.href,
    text,
    startOffset: before.toString().length,
    endOffset: before.toString().length + range.toString().length,
    cfi: cfiFor(range),
  }
}

const applySelectionListener = (doc, index) => {
  if (doc.__tomoReadSelectionBridge) return
  doc.__tomoReadSelectionBridge = true
  let pending = false
  const reportSelection = () => {
    if (pending) return
    pending = true
    window.setTimeout(() => {
      pending = false
      const selection = readSelection(doc, index)
      if (selection) postMessage({ type: 'textSelection', ...selection })
    }, 80)
  }
  doc.addEventListener('selectionchange', reportSelection)
  // Some embedded WebView implementations do not consistently forward
  // selectionchange from sandboxed EPUB iframes. These end-of-selection
  // signals provide the same payload after mouse, touch, or keyboard input.
  doc.addEventListener('pointerup', reportSelection)
  doc.addEventListener('touchend', reportSelection, { passive: true })
  doc.addEventListener('keyup', reportSelection)
}

const emitRelocation = detail => {
  const section = getSections()[detail.index]
  if (!section || !paginator) return
  measuredRelocationRevision += 1
  currentSectionIndex = detail.index
  currentRatio = Number.isFinite(detail.fraction) ? detail.fraction : 0
  const message = {
    type: 'runtimeRelocate',
    flow: paginator.getAttribute('flow') ?? 'paginated',
    href: section.href,
    chapterIndex: detail.index,
    ratio: Number.isFinite(detail.fraction) ? detail.fraction : 0,
    anchor: nearestAnchor(detail.range),
    cfi: cfiFor(detail.range),
  }
  if (message.flow !== 'scrolled') {
    const fallbackPageCount = Math.max(1, paginator.pages || 1)
    const pageCount = Math.max(1, detail.pageCount ?? fallbackPageCount)
    const pageIndex = Math.max(0, Math.min(
      pageCount - 1,
      detail.pageIndex ?? paginator.page ?? 0,
    ))
    currentPageIndex = pageIndex
    currentPageCount = pageCount
    message.pageIndex = pageIndex
    message.pageCount = pageCount
  }
  postMessage(message)
}

const emitPagePosition = detail => {
  if (paginator?.getAttribute('flow') === 'scrolled') return
  const section = getSections()[detail.index]
  if (!section) return
  currentSectionIndex = detail.index
  currentRatio = Number.isFinite(detail.fraction) ? detail.fraction : 0
  currentPageIndex = Math.max(0, detail.pageIndex ?? 0)
  currentPageCount = Math.max(1, detail.pageCount ?? 1)
  postMessage({
    type: 'runtimeRelocate',
    flow: paginator?.getAttribute('flow') ?? 'paginated',
    href: section.href,
    chapterIndex: detail.index,
    ratio: currentRatio,
    anchor: null,
    cfi: null,
    pageIndex: currentPageIndex,
    pageCount: currentPageCount,
  })
}

const nextFrame = () => new Promise(resolve => requestAnimationFrame(resolve))

const reportPaginatorPosition = async ({
  fallbackIndex,
  fallbackRatio,
  relocationRevisionAtStart,
} = {}) => {
  // The paginator updates its iframe dimensions after the page animation.
  // Wait two frames so this snapshot reflects the final rendered spread.
  await nextFrame()
  await nextFrame()
  if (!paginator) return
  const index = Number.isInteger(paginator.primaryIndex)
    ? paginator.primaryIndex
    : fallbackIndex ?? currentSectionIndex
  const section = getSections()[index]
  if (!section) return
  if (paginator.getAttribute('flow') === 'scrolled') {
    // CFI navigation emits an exact relocation from Foliate. Do not overwrite
    // that measured chapter ratio with the command's default ratio (usually 0).
    if (measuredRelocationRevision > (relocationRevisionAtStart ?? -1)) return
    emitRelocation({
      index,
      fraction: fallbackRatio ?? currentRatio,
      range: null,
    })
    return
  }
  const size = paginator.size || 0
  const measuredPages = size > 0 ? Math.ceil(paginator.viewSize / size) : 0
  const pageCount = Math.max(1, paginator.pages || 0, measuredPages)
  const pageIndex = Math.max(0, Math.min(
    pageCount - 1,
    Number.isFinite(paginator.page) ? paginator.page : currentPageIndex,
  ))
  const ratio = pageCount > 1
    ? pageIndex / (pageCount - 1)
    : fallbackRatio ?? currentRatio
  emitPagePosition({ index, ratio, pageIndex, pageCount })
}

const attachDocumentInteractions = ({ detail: { doc, index } }) => {
  applyAnnotations(doc, index)
  applySearchHighlights(doc)
  applySelectionListener(doc, index)
  // A section can emit more than one `load` event while Foliate rebuilds its
  // views. Registering click handlers each time sends duplicate page commands.
  if (doc.__tomoReadInteractionBridge) return
  doc.__tomoReadInteractionBridge = true
  let tapNavigationPending = false
  let wheelDelta = 0
  let wheelResetTimer
  let wheelNavigationPending = false
  doc.addEventListener('click', event => {
    const link = event.target.closest?.('a[href]')
    if (link) {
      const target = new URL(link.href, doc.location.href)
      const targetIndex = getSections().findIndex(section => sectionUrl(section.href) === target.href.split('#')[0])
      if (targetIndex >= 0) {
        event.preventDefault()
        void executeCommand({
          type: 'goToLocation',
          payload: { href: getSections()[targetIndex].href, ratio: 0, anchor: target.hash },
        })
      }
      return
    }
    if (doc.getSelection()?.toString().trim()) return
    const ratio = event.clientX / doc.defaultView.innerWidth
    if (!tapNavigationEnabled) {
      if (ratio >= 0.25 && ratio <= 0.75) postMessage({ type: 'readerControls' })
      return
    }
    const direction = ratio <= 0.25
      ? 'previousPage'
      : ratio >= 0.75
        ? 'nextPage'
        : null
    if (!direction) {
      postMessage({ type: 'readerControls' })
      return
    }
    // Ignore a duplicate DOM click from a view rebuild, but do not keep the
    // reader locked while the paginator is animating or loading a chapter.
    if (tapNavigationPending) return
    tapNavigationPending = true
    const command = executeCommand({ type: direction })
    void command.finally(() => { tapNavigationPending = false })
  })
  doc.addEventListener('wheel', event => {
    if (event.ctrlKey || Math.abs(event.deltaY) <= Math.abs(event.deltaX)) return
    event.preventDefault()
    if (paginator?.getAttribute('flow') === 'scrolled') {
      const unit = event.deltaMode === WheelEvent.DOM_DELTA_LINE
        ? 16
        : event.deltaMode === WheelEvent.DOM_DELTA_PAGE
          ? doc.defaultView.innerHeight
          : 1
      const delta = event.deltaY * unit
      // Paginator uses the first value for horizontal writing and the second
      // for vertical writing, while both move its active scroll axis.
      paginator.scrollBy(delta, delta)
      return
    }
    if (wheelNavigationPending) return

    // Browsers report wheels in pixels, lines, or pages. Normalize enough to
    // make a physical wheel notch and a trackpad gesture feel consistent.
    const unit = event.deltaMode === WheelEvent.DOM_DELTA_LINE
      ? 16
      : event.deltaMode === WheelEvent.DOM_DELTA_PAGE
        ? doc.defaultView.innerHeight
        : 1
    wheelDelta += event.deltaY * unit
    window.clearTimeout(wheelResetTimer)
    wheelResetTimer = window.setTimeout(() => { wheelDelta = 0 }, 160)
    if (Math.abs(wheelDelta) < 48) return

    const direction = wheelDelta > 0 ? 'nextPage' : 'previousPage'
    wheelDelta = 0
    wheelNavigationPending = true
    const command = executeCommand({ type: direction })
    void command.finally(() => { wheelNavigationPending = false })
  }, { passive: false })
  doc.addEventListener('contextmenu', event => {
    const selection = readSelection(doc, index)
    if (!selection) return
    event.preventDefault()
    postMessage({
      type: 'selectionContextMenu',
      ...selection,
      x: event.clientX,
      y: event.clientY,
    })
  })
}

const createPaginator = () => {
  paginator?.destroy()
  paginator = document.createElement('foliate-paginator')
  stage.replaceChildren(paginator)
  paginator.addEventListener('relocate', ({ detail }) => emitRelocation(detail))
  paginator.addEventListener('pagechange', ({ detail }) => emitPagePosition(detail))
  paginator.addEventListener('load', attachDocumentInteractions)
  paginator.addEventListener('error', error => {
    postMessage({ type: 'runtimeError', message: String(error.message ?? error) })
  })
}

const ensureOpen = async options => {
  // Android WebView blocks fetch() from a file:// document. The host provides
  // the already-parsed manifest there, while Windows keeps its virtual HTTPS
  // origin and can load the generated manifest file directly.
  session ??= options.session ?? await loadManifest()
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
  if (options.settings) applySettings(options.settings)
}

const goToHrefUnsafe = async (href, ratio = 0, anchor, cfi) => {
  if (!paginator) return
  const index = findSection(href)
  if (index < 0) return
  // A relocate event is intentionally suppressed for some first-page layouts.
  // Keep the target index at the command boundary so page commands never fall
  // back to the first spine item in that case.
  currentSectionIndex = index
  const fragment = anchor || href.split('#')[1]
  const relocationRevisionAtStart = measuredRelocationRevision
  await paginator.goTo({ index, anchor: anchorFor(fragment, ratio, cfi) })
  await reportPaginatorPosition({
    fallbackIndex: index,
    fallbackRatio: ratio,
    relocationRevisionAtStart,
  })
}

const goToPageUnsafe = async pageIndex => {
  if (!paginator) return
  const pages = Math.max(1, paginator.pages || 1)
  const fraction = pages <= 1 ? 0 : Math.max(0, Math.min(1, pageIndex / (pages - 1)))
  await runPageTransition(
    pageIndex < paginator.page ? 'previous' : 'next',
    () => paginator.goTo({ index: currentSectionIndex, anchor: fraction }),
  )
}

const executeCommand = command => {
  const id = Number.isInteger(command?.id) ? command.id : nextCommandId++
  const type = command?.type
  const payload = command?.payload ?? {}
  commandTail = commandTail.catch(() => undefined).then(async () => {
    postMessage({ type: 'commandStarted', id, command: type })
    try {
      switch (type) {
        case 'open':
          await ensureOpen(payload)
          await goToHrefUnsafe(payload.href, payload.ratio, payload.anchor, payload.cfi)
          postMessage({ type: 'runtimeOpened', runtimeVersion })
          break
        case 'goToLocation':
          await goToHrefUnsafe(payload.href, payload.ratio, payload.anchor, payload.cfi)
          break
        case 'nextPage':
          await turnUnsafe('next')
          break
        case 'previousPage':
          await turnUnsafe('previous')
          break
        case 'goToPage':
          await goToPageUnsafe(payload.pageIndex)
          break
        case 'setSettings':
          applySettings(payload.settings)
          break
        default:
          throw new Error(`Unsupported EPUB command: ${type}`)
      }
      postMessage({ type: 'commandCompleted', id, command: type })
    } catch (error) {
      postMessage({ type: 'commandFailed', id, command: type, message: String(error?.message ?? error) })
    }
  })
  return commandTail
}

const open = options => executeCommand({
  id: options?.commandId,
  type: 'open',
  payload: options,
})

const goToHref = (href, ratio = 0, anchor, cfi) => executeCommand({
  type: 'goToLocation',
  payload: { href, ratio, anchor, cfi },
})

const goToPage = pageIndex => executeCommand({
  type: 'goToPage',
  payload: { pageIndex },
})

const turn = direction => executeCommand({
  type: direction === 'previous' ? 'previousPage' : 'nextPage',
})

const setAnnotations = (nextAnnotations, nextFocusedAnnotationId) => {
  annotations = nextAnnotations ?? []
  focusedAnnotationId = nextFocusedAnnotationId
  for (const { doc, index } of paginator?.getContents?.() ?? []) {
    applyAnnotations(doc, index)
  }
}

const setSearchQuery = nextQuery => {
  searchQuery = String(nextQuery ?? '').trim()
  for (const { doc } of paginator?.getContents?.() ?? []) applySearchHighlights(doc)
}

window.TomoReadEpubRuntime = Object.freeze({
  runtimeVersion,
  loadManifest,
  open,
  goToHref,
  goToPage,
  turn,
  command: executeCommand,
  setAnnotations,
  setSearchQuery,
  setSettings: applySettings,
  postMessage,
})

window.addEventListener('DOMContentLoaded', () => {
  postMessage({ type: 'runtimeReady', runtimeVersion })
}, { once: true })
