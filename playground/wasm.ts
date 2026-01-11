import { getCode } from './editor'

declare global {
  interface Window {
    getEditorCode: () => string
    onWasmReady: () => void
    Module: EmscriptenModule
  }
}

interface EmscriptenModule {
  canvas: HTMLCanvasElement
  onRuntimeInitialized?: () => void
}

let wasmReady = false
let wasmReadyPromise: Promise<void> | null = null
let wasmReadyResolve: (() => void) | null = null

export function initWasm(canvas: HTMLCanvasElement): Promise<void> {
  if (wasmReadyPromise) return wasmReadyPromise

  wasmReadyPromise = new Promise((resolve) => {
    wasmReadyResolve = resolve
  })

  // Set up callbacks for WASM
  window.getEditorCode = () => getCode()
  window.onWasmReady = () => {
    wasmReady = true
    if (wasmReadyResolve) wasmReadyResolve()
  }

  // Create Module object for Emscripten
  window.Module = {
    canvas: canvas,
    onRuntimeInitialized: () => {
      console.log('WASM runtime initialized')
    },
  }

  // Prevent WASM from capturing keyboard events when editor is focused
  const isEditorFocused = () => {
    const active = document.activeElement
    return active?.closest('.cm-editor') ||
           active?.tagName === 'INPUT' ||
           active?.tagName === 'TEXTAREA'
  }

  // Block on canvas directly
  canvas.addEventListener('keydown', (e) => {
    if (isEditorFocused()) e.stopImmediatePropagation()
  }, true)
  canvas.addEventListener('keyup', (e) => {
    if (isEditorFocused()) e.stopImmediatePropagation()
  }, true)

  // Also block on window level
  window.addEventListener('keydown', (e) => {
    if (isEditorFocused()) e.stopImmediatePropagation()
  }, true)
  window.addEventListener('keyup', (e) => {
    if (isEditorFocused()) e.stopImmediatePropagation()
  }, true)

  // Load the WASM JS file
  const script = document.createElement('script')
  script.src = '/mane3d-example.js'
  script.async = true
  document.body.appendChild(script)

  return wasmReadyPromise
}

export function isWasmReady(): boolean {
  return wasmReady
}
