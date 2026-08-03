(() => {
'use strict'

const CFI = globalThis.TomoReadEpubCfi
const runtimeVersion = '32'
const bridgeVersion = 1
const stage = document.getElementById('reader-stage')

let session
let book
let paginator
let annotations = []
let focusedAnnotationId
let searchQuery = ''
let ttsHighlight
let textColoring = { enabled: false, tokens: [], colors: {}, terms: [] }
let pageTransition = 'slide'
let tapNavigationEnabled = false
let readingDirection = 'ltr'
let turnLocked = false
let currentSectionIndex = 0
let currentRatio = 0
let currentPageIndex = 0
let currentPageCount = 1
let measuredRelocationRevision = 0
let commandTail = Promise.resolve()
let nextCommandId = 1
let interactionOverlay
let interactionOverlayKeyHandler
let navigationBackButton
let autoScrollFrame
let autoScrollStartedAt = 0
let autoScrollAppliedDistance = 0
let autoScrollOptions
const navigationHistory = []

const postMessage = message => {
  const payload = { ...message, bridgeVersion }
  if (window.chrome?.webview?.postMessage) {
    window.chrome.webview.postMessage(payload)
    return
  }
  if (window.TomoRead?.postMessage) {
    window.TomoRead.postMessage(JSON.stringify(payload))
  }
}

const stopAutoScroll = (reason = 'explicit') => {
  if (autoScrollFrame == null && !autoScrollOptions) return
  if (autoScrollFrame != null) cancelAnimationFrame(autoScrollFrame)
  autoScrollFrame = undefined
  autoScrollOptions = undefined
  autoScrollAppliedDistance = 0
  postMessage({ type: 'autoScrollChanged', active: false, reason })
}

const activeScrollDocument = () => (paginator?.getContents?.() ?? [])
  .find(content => content.index === currentSectionIndex)?.doc

const autoScrollPixelsPerSecond = () => {
  const doc = activeScrollDocument()
  const viewport = doc?.defaultView?.innerHeight ?? window.innerHeight
  if (autoScrollOptions?.unit === 'screensPerMinute') {
    return viewport * autoScrollOptions.speed / 60
  }
  const rootStyle = doc?.defaultView?.getComputedStyle(doc.documentElement)
  const fontSize = Number.parseFloat(rootStyle?.fontSize) || 16
  const lineHeight = Number.parseFloat(rootStyle?.lineHeight) || fontSize * 1.6
  return lineHeight * autoScrollOptions.speed / 60
}

const startAutoScroll = options => {
  stopAutoScroll('restart')
  if (!paginator || paginator.getAttribute('flow') !== 'scrolled') {
    postMessage({ type: 'autoScrollChanged', active: false, reason: 'layoutUnavailable' })
    return
  }
  const speed = Number(options?.speed)
  autoScrollOptions = {
    unit: options?.unit === 'screensPerMinute' ? 'screensPerMinute' : 'linesPerMinute',
    speed: Number.isFinite(speed) ? Math.max(.1, Math.min(240, speed)) : 30,
  }
  autoScrollStartedAt = performance.now()
  autoScrollAppliedDistance = 0
  const tick = timestamp => {
    if (!autoScrollOptions || !paginator) return
    if (currentSectionIndex >= getSections().length - 1 && currentRatio >= .999) {
      stopAutoScroll('reachedEnd')
      return
    }
    const targetDistance = autoScrollPixelsPerSecond()
      * Math.max(0, timestamp - autoScrollStartedAt) / 1000
    const delta = targetDistance - autoScrollAppliedDistance
    if (delta > 0) paginator.scrollBy(delta, delta)
    autoScrollAppliedDistance = targetDistance
    autoScrollFrame = requestAnimationFrame(tick)
  }
  autoScrollFrame = requestAnimationFrame(tick)
  postMessage({ type: 'autoScrollChanged', active: true })
}

const scrollByViewport = amount => {
  if (!paginator || paginator.getAttribute('flow') !== 'scrolled') return
  const doc = activeScrollDocument()
  const viewport = doc?.defaultView?.innerHeight ?? window.innerHeight
  const delta = viewport * Math.max(-1, Math.min(1, Number(amount) || 0))
  paginator.scrollBy(delta, delta)
}

window.addEventListener('blur', () => stopAutoScroll('windowBlur'))
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState !== 'visible') stopAutoScroll('visibility')
})

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
  readingDirection = settings.direction === 'rtl' ? 'rtl' : 'ltr'
  paginator.setAttribute('flow', settings.flow ?? 'paginated')
  if (paginator.getAttribute('flow') !== 'scrolled') {
    stopAutoScroll('layoutUnavailable')
  }
  paginator.setAttribute('max-column-count', String(settings.columnCount ?? 1))
  paginator.setAttribute('max-inline-size', `${settings.maxInlineSize ?? 760}px`)
  paginator.setAttribute('margin', `${settings.margin ?? 32}px`)
  paginator.toggleAttribute('animated', pageTransition !== 'none')
  paginator.setStyles(`
    ${settings.fontFaceCss ?? ''}
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
  const relocationRevisionAtStart = measuredRelocationRevision
  await runPageTransition(
    direction,
    () => direction === 'previous' ? paginator.prev() : paginator.next(),
  )
  // A continuous paginator already emits its measured relocation as it
  // scrolls. Sending a synthetic snapshot here can report the old ratio and
  // snap Flutter's progress slider back to the chapter start.
  if (paginator?.getAttribute('flow') !== 'scrolled') {
    await reportPaginatorPosition({ relocationRevisionAtStart })
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
    ::highlight(tomoread-underline-yellow) { color: #b8860b; text-decoration: underline 2px #d2a72c; text-underline-offset: .16em; }
    ::highlight(tomoread-underline-green) { color: #397a48; text-decoration: underline 2px #53a56b; text-underline-offset: .16em; }
    ::highlight(tomoread-underline-blue) { color: #397fbd; text-decoration: underline 2px #5a9bd5; text-underline-offset: .16em; }
    ::highlight(tomoread-underline-pink) { color: #b95373; text-decoration: underline 2px #d76d8c; text-underline-offset: .16em; }
  `
  for (const name of Array.from(highlights.keys())) {
    if (/^tomoread-(underline-)?(yellow|green|blue|pink)$/.test(name)) {
      highlights.delete(name)
    }
  }
  const groups = new Map()
  const href = getSections()[index]?.href
  for (const annotation of annotations) {
    if (annotation.href !== href) continue
    const locator = typeof annotation.locator === 'string'
      ? annotation.locator
      : ''
    if (!locator) continue
    const range = locator.startsWith('cfi:')
      ? rangeForCfi(doc, locator.slice(4))
      : (() => {
          const [start, end] = locator.split(':').map(Number)
          return Number.isFinite(start) && Number.isFinite(end)
            ? rangeForOffsets(doc, start, end)
            : null
        })()
    if (!range) continue
    const key = annotation.style === 'underline'
      ? `underline-${annotation.color}`
      : annotation.color
    if (!groups.has(key)) groups.set(key, new Highlight())
    groups.get(key).add(range)
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

const applyTtsHighlight = (doc, index) => {
  const highlights = doc.defaultView.CSS?.highlights
  const Highlight = doc.defaultView.Highlight
  if (!highlights || !Highlight) return
  const ranges = new Highlight()
  const sectionHref = getSections()[index]?.href
  const text = String(ttsHighlight?.text ?? '')
  if (text && ttsHighlight?.href === sectionHref) {
    const content = doc.body?.textContent ?? ''
    let start = Number(ttsHighlight.start)
    const expectedEnd = Number(ttsHighlight.end)
    const hasVerifiedOffsets = Number.isInteger(start)
      && Number.isInteger(expectedEnd)
      && expectedEnd > start
      && content.slice(start, expectedEnd) === text
    if (!hasVerifiedOffsets) start = content.indexOf(text)
    if (start >= 0) {
      const range = rangeForOffsets(doc, start, start + text.length)
      if (range) ranges.add(range)
    }
  }
  highlights.set('tomoread-tts', ranges)
  let style = doc.getElementById('tomoread-runtime-tts')
  if (!style) {
    style = doc.createElement('style')
    style.id = 'tomoread-runtime-tts'
    doc.head.append(style)
  }
  style.textContent = '::highlight(tomoread-tts) { background: #64b5f680; }'
}

const textColorHighlightPrefix = 'tomoread-text-color-'

const clearTextColoring = doc => {
  const highlights = doc.defaultView.CSS?.highlights
  if (highlights) {
    for (const name of [...highlights.keys()]) {
      if (name.startsWith(textColorHighlightPrefix)) highlights.delete(name)
    }
  }
  const style = doc.getElementById('tomoread-runtime-text-coloring')
  if (style) style.textContent = ''
}

const textNodeIsColorable = node => {
  const element = node.parentElement
  if (!element || !node.textContent?.trim()) return false
  if (element.closest('script, style, code, pre, textarea, input, select, option')) return false
  if (element.closest('[hidden], [aria-hidden="true"]')) return false
  return element.getClientRects().length > 0
}

const semanticColorRules = enabledTokens => {
  const rules = []
  if (enabledTokens.has('quoted')) {
    rules.push({
      key: 'token-quoted',
      regex: /“[^”\n]+”|‘[^’\n]+’|「[^」\n]+」|『[^』\n]+』|"[^"\n]+"/gu,
      inset: 1,
    })
  }
  if (enabledTokens.has('bracketed')) {
    rules.push({
      key: 'token-bracketed',
      regex: /（[^）\n]+）|\([^()\n]+\)|【[^】\n]+】|\[[^\]\n]+\]/gu,
      inset: 1,
    })
  }
  if (enabledTokens.has('latin')) {
    rules.push({
      key: 'token-latin',
      regex: /[A-Za-z]+(?:['’\-][A-Za-z]+)*/gu,
      inset: 0,
    })
  }
  if (enabledTokens.has('number')) {
    rules.push({
      key: 'token-number',
      regex: /\p{N}+(?:[.,]\p{N}+)*/gu,
      inset: 0,
    })
  }
  if (enabledTokens.has('punctuation')) {
    rules.push({
      key: 'token-punctuation',
      regex: /[\p{P}\p{S}]/gu,
      inset: 0,
    })
  }
  return rules
}

const applyTextColoring = doc => {
  clearTextColoring(doc)
  const highlights = doc.defaultView.CSS?.highlights
  const Highlight = doc.defaultView.Highlight
  if (!textColoring.enabled || !highlights || !Highlight) return

  const configuredColors = Object.entries(textColoring.colors ?? {})
    .filter(([key, value]) => /^[a-z0-9-]+$/i.test(key)
      && /^#[0-9a-f]{6}$/i.test(String(value)))
  if (!configuredColors.length) return
  const colors = new Map(configuredColors)
  const groups = new Map(
    configuredColors.map(([key]) => [key, new Highlight()]),
  )
  let style = doc.getElementById('tomoread-runtime-text-coloring')
  if (!style) {
    style = doc.createElement('style')
    style.id = 'tomoread-runtime-text-coloring'
    doc.head.append(style)
  }
  style.textContent = configuredColors
    .map(([key, value]) => `::highlight(${textColorHighlightPrefix}${key}) { color: ${value}; }`)
    .join('\n')

  const terms = [...(textColoring.terms ?? [])]
    .filter(term => typeof term?.text === 'string'
      && term.text.length > 0
      && Array.from(term.text).length <= 100
      && colors.has(term.colorKey))
    .sort((a, b) => Array.from(b.text).length - Array.from(a.text).length
      || (a.scope === b.scope ? 0 : a.scope === 'book' ? -1 : 1))
    .map(term => ({
      key: term.colorKey,
      regex: new RegExp(
        term.text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'),
        'giu',
      ),
    }))
  const enabledTokens = new Set(textColoring.tokens ?? [])
  const tokenRules = semanticColorRules(enabledTokens)
  const nodeFilter = doc.defaultView.NodeFilter ?? NodeFilter
  const walker = doc.createTreeWalker(
    doc.body,
    nodeFilter.SHOW_TEXT,
    {
      acceptNode: node => textNodeIsColorable(node)
        ? nodeFilter.FILTER_ACCEPT
        : nodeFilter.FILTER_REJECT,
    },
  )
  let node
  while (node = walker.nextNode()) {
    const source = node.textContent
    const occupied = []
    const addRange = (key, start, end) => {
      if (!colors.has(key) || start < 0 || end <= start || end > source.length) return
      if (occupied.some(range => start < range.end && end > range.start)) return
      const range = doc.createRange()
      range.setStart(node, start)
      range.setEnd(node, end)
      groups.get(key).add(range)
      occupied.push({ start, end })
    }

    for (const term of terms) {
      term.regex.lastIndex = 0
      let match
      while (match = term.regex.exec(source)) {
        addRange(term.key, match.index, match.index + match[0].length)
      }
    }
    for (const rule of tokenRules) {
      rule.regex.lastIndex = 0
      let match
      while (match = rule.regex.exec(source)) {
        addRange(
          rule.key,
          match.index + rule.inset,
          match.index + match[0].length - rule.inset,
        )
      }
    }
  }
  for (const [key, ranges] of groups) {
    highlights.set(`${textColorHighlightPrefix}${key}`, ranges)
  }
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
  const flow = paginator.getAttribute('flow') ?? 'paginated'
  let ratio = Number.isFinite(detail.fraction) ? detail.fraction : 0
  const message = {
    type: 'runtimeRelocate',
    flow,
    href: section.href,
    chapterIndex: detail.index,
    anchor: nearestAnchor(detail.range),
    cfi: cfiFor(detail.range),
  }
  if (flow !== 'scrolled') {
    const fallbackPageCount = Math.max(
      1,
      paginator.sectionPageCount || paginator.pages || 1,
    )
    const pageCount = Math.max(1, detail.pageCount ?? fallbackPageCount)
    const pageIndex = Math.max(0, Math.min(
      pageCount - 1,
      detail.pageIndex ?? paginator.sectionPageIndex ?? paginator.page ?? 0,
    ))
    currentPageIndex = pageIndex
    currentPageCount = pageCount
    ratio = pageCount > 1 ? pageIndex / (pageCount - 1) : ratio
    message.pageIndex = pageIndex
    message.pageCount = pageCount
  }
  currentRatio = Math.max(0, Math.min(1, ratio))
  message.ratio = currentRatio
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

const nextFrame = () => new Promise(resolve => {
  let completed = false
  const finish = () => {
    if (completed) return
    completed = true
    window.clearTimeout(timeout)
    resolve()
  }
  const timeout = window.setTimeout(finish, 80)
  requestAnimationFrame(finish)
})

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
  // Preserve the exact Range/CFI relocation emitted by Foliate. A synthetic
  // page snapshot would otherwise overwrite annotation navigation with a
  // locator that has the right page but no CFI.
  if (relocationRevisionAtStart != null
      && measuredRelocationRevision > relocationRevisionAtStart) return
  if (paginator.getAttribute('flow') === 'scrolled') {
    emitRelocation({
      index,
      fraction: fallbackRatio ?? currentRatio,
      range: null,
    })
    return
  }
  const pageCount = Math.max(
    1,
    paginator.sectionPageCount || paginator.pages || 0,
  )
  const pageIndex = Math.max(0, Math.min(
    pageCount - 1,
    Number.isFinite(paginator.sectionPageIndex)
      ? paginator.sectionPageIndex
      : currentPageIndex,
  ))
  const ratio = pageCount > 1
    ? pageIndex / (pageCount - 1)
    : fallbackRatio ?? currentRatio
  emitPagePosition({ index, ratio, pageIndex, pageCount })
}

const interactionLocator = (doc, index, element) => {
  let range
  try {
    range = doc.createRange()
    range.selectNodeContents(element)
  } catch {
    range = null
  }
  return {
    chapterIndex: index,
    ratio: index === currentSectionIndex ? currentRatio : 0,
    anchor: nearestAnchor(range),
    cfi: cfiFor(range),
  }
}

const postInteraction = (action, doc, index, element, details = {}) => {
  const section = getSections()[index]
  if (!section) return
  postMessage({
    type: 'epubInteraction',
    action,
    href: section.href,
    locator: interactionLocator(doc, index, element),
    ...details,
  })
}

const closeInteractionOverlay = () => {
  if (!interactionOverlay) return
  const overlay = interactionOverlay
  interactionOverlay = null
  window.removeEventListener('keydown', interactionOverlayKeyHandler)
  interactionOverlayKeyHandler = null
  overlay.remove()
  overlay.__tomoReadOnClose?.()
  overlay.__tomoReadRestoreFocus?.focus?.()
}

const showInteractionOverlay = ({ title, content, onClose, restoreFocus }) => {
  closeInteractionOverlay()
  const overlay = document.createElement('div')
  overlay.style.cssText = [
    'position:fixed',
    'inset:0',
    'z-index:2147483646',
    'display:flex',
    'align-items:center',
    'justify-content:center',
    'padding:24px',
    'box-sizing:border-box',
    'background:rgba(0,0,0,.68)',
  ].join(';')
  overlay.setAttribute('role', 'presentation')
  overlay.__tomoReadOnClose = onClose
  overlay.__tomoReadRestoreFocus = restoreFocus

  const panel = document.createElement('section')
  panel.style.cssText = [
    'position:relative',
    'display:flex',
    'flex-direction:column',
    'gap:16px',
    'width:min(760px,100%)',
    'max-height:90vh',
    'overflow:auto',
    'box-sizing:border-box',
    'padding:24px',
    'border-radius:16px',
    'color:CanvasText',
    'background:Canvas',
    'box-shadow:0 18px 60px rgba(0,0,0,.4)',
  ].join(';')
  panel.setAttribute('role', 'dialog')
  panel.setAttribute('aria-modal', 'true')
  panel.setAttribute('aria-label', title)

  const heading = document.createElement('h2')
  heading.textContent = title
  heading.style.cssText = 'margin:0;font:600 1.15rem/1.4 system-ui,sans-serif'
  const closeButton = document.createElement('button')
  closeButton.type = 'button'
  closeButton.textContent = '关闭'
  closeButton.setAttribute('aria-label', `关闭${title}`)
  closeButton.style.cssText = [
    'align-self:flex-end',
    'min-width:72px',
    'padding:8px 16px',
    'border:0',
    'border-radius:999px',
    'font:inherit',
    'cursor:pointer',
  ].join(';')
  closeButton.addEventListener('click', closeInteractionOverlay)
  panel.append(heading, content, closeButton)
  overlay.append(panel)
  overlay.addEventListener('click', event => {
    if (event.target === overlay) closeInteractionOverlay()
  })
  interactionOverlayKeyHandler = event => {
    if (event.key === 'Escape') closeInteractionOverlay()
  }
  window.addEventListener('keydown', interactionOverlayKeyHandler)
  document.body.append(overlay)
  interactionOverlay = overlay
  closeButton.focus()
}

const decodedFragment = target => {
  if (!target.hash || target.hash.length <= 1) return null
  try {
    return decodeURIComponent(target.hash.slice(1))
  } catch {
    return null
  }
}

const relativeBookResource = target => {
  const root = new URL('../', location.href)
  const targetWithoutFragment = target.href.split('#')[0].split('?')[0]
  const rootHref = root.href
  if (!targetWithoutFragment.startsWith(rootHref)) return null
  const value = targetWithoutFragment.slice(rootHref.length)
  if (!value || value.split('/').includes('..')) return null
  try {
    return decodeURIComponent(value)
  } catch {
    return value
  }
}

const footnoteType = element => [
  element?.getAttribute?.('epub:type'),
  element?.getAttribute?.('role'),
  element?.getAttribute?.('class'),
].filter(Boolean).join(' ').toLowerCase()

const isFootnoteReference = (link, targetElement, target) => {
  const referenceType = footnoteType(link)
  const targetType = footnoteType(targetElement)
  const resourceId = decodedFragment(target) ?? ''
  const targetName = target.pathname.split('/').pop() ?? ''
  return /\b(noteref|footnote-ref|footnoteref)\b/.test(referenceType)
    || /\b(doc-footnote|footnote|endnote|rearnote)\b/.test(targetType)
    || /^(?:fn|note|footnote|endnote)[-_.:]?\d*$/i.test(resourceId)
    || /^(?:footnotes?|endnotes?|notes?)\.(?:x?html?)$/i.test(targetName)
}

const loadFootnoteText = async ({ doc, index, targetIndex, resourceId }) => {
  let targetDocument = doc
  if (targetIndex !== index) {
    const response = await fetch(sectionUrl(getSections()[targetIndex].href))
    if (!response.ok) throw new Error(`脚注资源加载失败 (${response.status})`)
    const source = await response.text()
    targetDocument = new DOMParser().parseFromString(source, 'text/html')
  }
  const targetElement = targetDocument.getElementById(resourceId)
  if (!targetElement) throw new Error('未找到脚注内容。')
  const text = targetElement.textContent?.replace(/\s+/g, ' ').trim()
  if (!text) throw new Error('脚注内容为空。')
  return text.slice(0, 12000)
}

const openFootnote = async ({ link, doc, index, targetIndex, target }) => {
  const resourceId = decodedFragment(target)
  const targetHref = getSections()[targetIndex]?.href
  if (!resourceId || !targetHref) {
    postInteraction('interactionError', doc, index, link, {
      message: '脚注链接缺少有效目标。',
    })
    return
  }
  try {
    const text = await loadFootnoteText({ doc, index, targetIndex, resourceId })
    const content = document.createElement('p')
    content.textContent = text
    content.style.cssText = 'margin:0;white-space:pre-wrap;font:1rem/1.75 system-ui,sans-serif'
    const details = { targetHref, resourceId }
    postInteraction('footnoteOpened', doc, index, link, details)
    showInteractionOverlay({
      title: link.getAttribute('aria-label')?.trim() || '脚注',
      content,
      restoreFocus: link,
      onClose: () => postInteraction('footnoteClosed', doc, index, link, details),
    })
  } catch (error) {
    postInteraction('interactionError', doc, index, link, {
      message: String(error?.message ?? error).slice(0, 500),
    })
  }
}

const openImage = ({ element, doc, index }) => {
  const inlineSvg = element.localName === 'svg'
  if (inlineSvg) {
    postInteraction('imageFailed', doc, index, element, {
      resourceId: `inline-svg-${element.id || index}`.replace(/[^a-z0-9._-]/gi, '-'),
      message: '为避免执行 EPUB 内嵌脚本，内联 SVG 仅在正文中显示。',
    })
    return
  }
  const source = inlineSvg
    ? null
    : element.currentSrc || element.href?.baseVal || element.getAttribute('src')
      || element.getAttribute('href') || element.getAttribute('xlink:href')
  let resourceId
  let target
  if (inlineSvg) {
    resourceId = `inline-svg-${element.id || index}`.replace(/[^a-z0-9._-]/gi, '-')
  } else {
    try {
      target = new URL(source, doc.location.href)
      resourceId = relativeBookResource(target)
    } catch {
      resourceId = null
    }
  }
  if (!resourceId) {
    postInteraction('imageFailed', doc, index, element, {
      resourceId: 'invalid-image-resource',
      message: '图片来源不在当前 EPUB 资源范围内。',
    })
    return
  }

  const content = document.createElement('div')
  content.style.cssText = 'display:grid;place-items:center;min-height:160px;overflow:auto'
  const status = document.createElement('p')
  status.textContent = '正在加载图片…'
  status.style.cssText = 'margin:0;font:1rem/1.5 system-ui,sans-serif'
  content.append(status)
  const details = { resourceId }
  postInteraction('imageOpened', doc, index, element, details)
  showInteractionOverlay({
    title: element.getAttribute('alt')?.trim() || '图片查看器',
    content,
    restoreFocus: element,
    onClose: () => postInteraction('imageClosed', doc, index, element, details),
  })

  const image = document.createElement('img')
  image.alt = element.getAttribute('alt') ?? ''
  image.style.cssText = 'display:block;max-width:100%;max-height:72vh;width:auto;height:auto;object-fit:contain'
  image.addEventListener('load', () => {
    if (image.naturalWidth * image.naturalHeight > 64000000) {
      image.removeAttribute('src')
      status.textContent = '图片尺寸过大，已停止解码以保护阅读器。'
      content.replaceChildren(status)
      postInteraction('imageFailed', doc, index, element, {
        ...details,
        message: status.textContent,
      })
      return
    }
    content.replaceChildren(image)
  })
  image.addEventListener('error', () => {
    status.textContent = '图片加载失败，可以关闭后继续阅读。'
    content.replaceChildren(status)
    postInteraction('imageFailed', doc, index, element, {
      ...details,
      message: status.textContent,
    })
  })
  image.src = target.href
}

const updateNavigationBackButton = () => {
  if (!navigationBackButton) {
    navigationBackButton = document.createElement('button')
    navigationBackButton.type = 'button'
    navigationBackButton.textContent = '返回链接前位置'
    navigationBackButton.style.cssText = [
      'position:fixed',
      'left:16px',
      'bottom:16px',
      'z-index:2147483645',
      'padding:9px 14px',
      'border:0',
      'border-radius:999px',
      'box-shadow:0 4px 18px rgba(0,0,0,.28)',
      'cursor:pointer',
    ].join(';')
    navigationBackButton.addEventListener('click', () => {
      const target = navigationHistory.pop()
      updateNavigationBackButton()
      if (!target) return
      const source = getSections()[currentSectionIndex]
      if (source) {
        postMessage({
          type: 'epubInteraction',
          action: 'internalBack',
          href: source.href,
          targetHref: target.href,
          locator: {
            chapterIndex: currentSectionIndex,
            ratio: currentRatio,
            anchor: null,
            cfi: null,
          },
        })
      }
      void executeCommand({
        type: 'goToLocation',
        payload: target,
      })
    })
    document.body.append(navigationBackButton)
  }
  navigationBackButton.hidden = navigationHistory.length === 0
}

const navigateInternalLink = ({ link, doc, index, targetIndex, target }) => {
  const source = getSections()[index]
  const destination = getSections()[targetIndex]
  if (!source || !destination) return
  const sourceLocator = interactionLocator(doc, index, link)
  navigationHistory.push({
    href: source.href,
    ratio: sourceLocator.ratio,
    anchor: sourceLocator.anchor,
    cfi: sourceLocator.cfi,
  })
  updateNavigationBackButton()
  postInteraction('internalLink', doc, index, link, {
    targetHref: destination.href,
  })
  void executeCommand({
    type: 'goToLocation',
    payload: {
      href: destination.href,
      ratio: 0,
      anchor: target.hash,
    },
  })
}

const attachDocumentInteractions = ({ detail: { doc, index } }) => {
  applyAnnotations(doc, index)
  applySearchHighlights(doc)
  applyTtsHighlight(doc, index)
  applyTextColoring(doc)
  applySelectionListener(doc, index)
  // A section can emit more than one `load` event while Foliate rebuilds its
  // views. Registering click handlers each time sends duplicate page commands.
  if (doc.__tomoReadInteractionBridge) return
  doc.__tomoReadInteractionBridge = true
  let tapNavigationPending = false
  let wheelDelta = 0
  let wheelResetTimer
  let wheelNavigationPending = false
  doc.addEventListener('pointerdown', () => stopAutoScroll('pointer'))
  doc.addEventListener('selectionchange', () => {
    if (!doc.getSelection()?.isCollapsed) stopAutoScroll('selection')
  })
  doc.addEventListener('click', event => {
    const link = event.target.closest?.('a[href]')
    if (link) {
      event.preventDefault()
      let target
      try {
        target = new URL(link.href, doc.location.href)
      } catch {
        postInteraction('blockedLink', doc, index, link)
        return
      }
      const targetIndex = getSections().findIndex(section => sectionUrl(section.href) === target.href.split('#')[0])
      if (targetIndex >= 0) {
        const resourceId = decodedFragment(target)
        const targetElement = targetIndex === index && resourceId
          ? doc.getElementById(resourceId)
          : null
        if (isFootnoteReference(link, targetElement, target)) {
          void openFootnote({ link, doc, index, targetIndex, target })
        } else {
          navigateInternalLink({ link, doc, index, targetIndex, target })
        }
      } else if (target.protocol === 'http:' || target.protocol === 'https:') {
        postInteraction('externalLinkRequested', doc, index, link, {
          externalUrl: target.href,
        })
      } else {
        postInteraction('blockedLink', doc, index, link)
      }
      return
    }
    const image = event.target.closest?.('img,svg,image')
    if (image) {
      event.preventDefault()
      openImage({ element: image, doc, index })
      return
    }
    if (doc.getSelection()?.toString().trim()) return
    const readerRect = paginator?.getBoundingClientRect()
    const frameRect = doc.defaultView?.frameElement?.getBoundingClientRect()
    const viewportX = (frameRect?.left ?? readerRect?.left ?? 0) + event.clientX
    const ratio = readerRect?.width > 0
      ? Math.max(0, Math.min(1, (viewportX - readerRect.left) / readerRect.width))
      : .5
    if (!tapNavigationEnabled) {
      if (ratio >= 0.25 && ratio <= 0.75) postMessage({ type: 'readerControls' })
      return
    }
    const direction = ratio <= 0.25
      ? readingDirection === 'rtl' ? 'nextPage' : 'previousPage'
      : ratio >= 0.75
        ? readingDirection === 'rtl' ? 'previousPage' : 'nextPage'
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
    stopAutoScroll('wheel')
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
    const frameRect = doc.defaultView?.frameElement?.getBoundingClientRect?.()
    postMessage({
      type: 'selectionContextMenu',
      ...selection,
      x: event.clientX + (frameRect?.left ?? 0),
      y: event.clientY + (frameRect?.top ?? 0),
    })
  })
}

const createPaginator = () => {
  paginator?.destroy()
  paginator = document.createElement('foliate-paginator')
  // Flutter's Chromium accessibility bridge is not stable when preloaded
  // iframe subtrees repeatedly enter and leave the AX tree.
  paginator.setAttribute('no-a11y-pruning', '')
  stage.replaceChildren(paginator)
  paginator.addEventListener('relocate', ({ detail }) => emitRelocation(detail))
  paginator.addEventListener('pagechange', ({ detail }) => emitPagePosition(detail))
  paginator.addEventListener('load', attachDocumentInteractions)
  paginator.addEventListener('error', error => {
    postMessage({ type: 'runtimeError', message: String(error.message ?? error) })
  })
  updateNavigationBackButton()
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
  const pages = Math.max(1, paginator.sectionPageCount || paginator.pages || 1)
  const fraction = pages <= 1 ? 0 : Math.max(0, Math.min(1, pageIndex / (pages - 1)))
  await runPageTransition(
    pageIndex < (paginator.sectionPageIndex ?? 0) ? 'previous' : 'next',
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
          stopAutoScroll('navigation')
          await goToHrefUnsafe(payload.href, payload.ratio, payload.anchor, payload.cfi)
          break
        case 'nextPage':
          stopAutoScroll('navigation')
          await turnUnsafe('next')
          break
        case 'previousPage':
          stopAutoScroll('navigation')
          await turnUnsafe('previous')
          break
        case 'goToPage':
          stopAutoScroll('navigation')
          await goToPageUnsafe(payload.pageIndex)
          break
        case 'scrollBy':
          stopAutoScroll('navigation')
          scrollByViewport(payload.amount)
          break
        case 'startAutoScroll':
          startAutoScroll(payload)
          break
        case 'stopAutoScroll':
          stopAutoScroll('explicit')
          break
        case 'setSettings':
          applySettings(payload.settings)
          break
        default:
          throw new Error(`Unsupported EPUB command: ${type}`)
      }
      postMessage({ type: 'commandCompleted', id, command: type })
    } catch (error) {
      const message = String(error?.message ?? error)
      postMessage({ type: 'commandFailed', id, command: type, message })
      if (type === 'open') postMessage({ type: 'runtimeError', message })
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

const setTtsHighlight = nextHighlight => {
  ttsHighlight = nextHighlight ?? null
  for (const { doc, index } of paginator?.getContents?.() ?? []) {
    applyTtsHighlight(doc, index)
  }
}

const setTextColoring = nextTextColoring => {
  textColoring = nextTextColoring ?? {
    enabled: false,
    tokens: [],
    colors: {},
    terms: [],
  }
  for (const { doc } of paginator?.getContents?.() ?? []) {
    applyTextColoring(doc)
  }
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
  setTtsHighlight,
  setTextColoring,
  setSettings: applySettings,
  postMessage,
})

postMessage({ type: 'runtimeBoot', runtimeVersion })

window.addEventListener('DOMContentLoaded', () => {
  postMessage({ type: 'runtimeReady', runtimeVersion })
}, { once: true })
})()
