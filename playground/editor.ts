import { EditorView, basicSetup } from 'codemirror'
import { StreamLanguage } from '@codemirror/language'
import { lua } from '@codemirror/legacy-modes/mode/lua'
import { oneDark } from '@codemirror/theme-one-dark'

const defaultCode = '-- Loading...'

let editorView: EditorView | null = null

export function createEditor(container: HTMLElement): EditorView {
  editorView = new EditorView({
    doc: defaultCode,
    extensions: [
      basicSetup,
      StreamLanguage.define(lua),
      oneDark,
      EditorView.theme({
        '&': { height: '100%' },
        '.cm-scroller': { overflow: 'auto' },
      }),
    ],
    parent: container,
  })
  return editorView
}

export function getCode(): string {
  return editorView?.state.doc.toString() ?? ''
}

export function setCode(code: string): void {
  if (!editorView) return
  editorView.dispatch({
    changes: { from: 0, to: editorView.state.doc.length, insert: code },
  })
}
