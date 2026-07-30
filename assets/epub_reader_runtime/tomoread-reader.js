import './foliate-paginator.js'

const runtimeVersion = '1'

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

window.TomoReadEpubRuntime = Object.freeze({
  runtimeVersion,
  loadManifest,
  postMessage,
})

window.addEventListener('DOMContentLoaded', () => {
  postMessage({ type: 'runtimeReady', runtimeVersion })
}, { once: true })
