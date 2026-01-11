import './style.css'
import { createEditor, getCode, setCode } from './editor'
import { loadGist, saveGist } from './gist'

const app = document.querySelector<HTMLDivElement>('#app')!

app.innerHTML = `
  <div class="container">
    <header class="toolbar">
      <button id="run-btn">▶ Run (Alt+Enter)</button>
      <select id="sample-select">
        <option value="">-- Samples --</option>
        <option value="triangle">Triangle</option>
        <option value="raytracer">Raytracer</option>
        <option value="breakout">Breakout</option>
      </select>
      <button id="share-btn">📤 Share</button>
      <button id="license-btn">📜 License</button>
    </header>
    <main class="editor-canvas">
      <div id="editor"></div>
      <div id="canvas-container">
        <iframe id="player-frame" src="about:blank"></iframe>
      </div>
    </main>
  </div>
`

// Initialize editor
const editorContainer = document.querySelector<HTMLDivElement>('#editor')!
createEditor(editorContainer)

// Run function
function runCode() {
  const iframe = document.querySelector<HTMLIFrameElement>('#player-frame')!
  const code = getCode()

  // Listen for player ready message
  const handleMessage = (e: MessageEvent) => {
    if (e.data.type === 'playerReady') {
      iframe.contentWindow?.postMessage({ type: 'setCode', code }, '*')
      window.removeEventListener('message', handleMessage)
    }
  }
  window.addEventListener('message', handleMessage)

  // Load player
  iframe.src = '/player.html'
  console.log('Starting WASM in iframe...')
}

// Button handlers
document.querySelector('#run-btn')?.addEventListener('click', runCode)

// Alt+Enter to run
document.addEventListener('keydown', (e) => {
  if (e.altKey && e.key === 'Enter') {
    e.preventDefault()
    runCode()
  }
})

document.querySelector('#share-btn')?.addEventListener('click', async () => {
  const code = getCode()
  const url = await saveGist(code)
  if (url) {
    await navigator.clipboard.writeText(url)
    alert(`URL copied: ${url}`)
  }
})

// Sample selection
document.querySelector('#sample-select')?.addEventListener('change', async (e) => {
  const sample = (e.target as HTMLSelectElement).value
  if (!sample) return
  const res = await fetch(`/examples/${sample}.lua`)
  if (res.ok) {
    setCode(await res.text())
    runCode()
  }
})

// License button
document.querySelector('#license-btn')?.addEventListener('click', async () => {
  const res = await fetch('/examples/license.lua')
  if (res.ok) {
    setCode(await res.text())
    runCode()
  }
})

// Load from URL params or default to triangle
const params = new URLSearchParams(location.search)
const gistId = params.get('gist')
if (gistId) {
  loadGist(gistId).then((code) => {
    if (code) setCode(code)
  })
} else {
  // Load default sample (raytracer) and run
  fetch('/examples/raytracer.lua')
    .then(res => res.ok ? res.text() : Promise.reject('Failed to load'))
    .then(code => {
      setCode(code)
      runCode()
    })
    .catch(() => setCode('-- Failed to load default example'))
}
