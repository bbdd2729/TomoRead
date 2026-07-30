import './foliate-paginator.js'

const runtimeVersion = '2'
const stage = document.getElementById('reader-stage')

let session
let book
let paginator

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
  paginator.setAttribute('flow', settings.flow ?? 'paginated')
  paginator.setAttribute('max-column-count', String(settings.columnCount ?? 1))
  paginator.setAttribute('max-inline-size', `${settings.maxInlineSize ?? 760}px`)
  paginator.setAttribute('margin', `${settings.margin ?? 32}px`)
  paginator.setAttribute('animated', '')
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

const emitRelocation = detail => {
  const section = getSections()[detail.index]
  if (!section || !paginator) return
  postMessage({
    type: 'runtimeRelocate',
    href: section.href,
    chapterIndex: detail.index,
    ratio: Number.isFinite(detail.fraction) ? detail.fraction : 0,
    anchor: nearestAnchor(detail.range),
    pageIndex: Math.max(0, paginator.page || 0),
    pageCount: Math.max(1, paginator.pages || 1),
  })
}

const attachDocumentInteractions = ({ detail: { doc } }) => {
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
      void paginator.prev()
    } else if (ratio >= 0.75) {
      void paginator.next()
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
  await paginator.goTo({ index: paginator.primaryIndex, anchor: fraction })
}

window.TomoReadEpubRuntime = Object.freeze({
  runtimeVersion,
  loadManifest,
  open,
  goToHref,
  goToPage,
  setSettings: applySettings,
  postMessage,
})

window.addEventListener('DOMContentLoaded', () => {
  postMessage({ type: 'runtimeReady', runtimeVersion })
}, { once: true })
