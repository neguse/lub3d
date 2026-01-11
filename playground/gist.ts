const GIST_API = 'https://api.github.com/gists'

export async function loadGist(gistId: string): Promise<string | null> {
  try {
    const res = await fetch(`${GIST_API}/${gistId}`)
    if (!res.ok) return null

    const data = await res.json()
    const files = Object.values(data.files) as { content: string }[]
    return files[0]?.content ?? null
  } catch {
    console.error('Failed to load gist:', gistId)
    return null
  }
}

export async function saveGist(code: string): Promise<string | null> {
  try {
    const res = await fetch(GIST_API, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        description: 'Måne3D Playground',
        public: true,
        files: {
          'main.lua': { content: code },
        },
      }),
    })

    if (!res.ok) {
      console.error('Failed to create gist:', res.status)
      return null
    }

    const data = await res.json()
    const gistId = data.id as string
    return `${location.origin}${location.pathname}?gist=${gistId}`
  } catch (e) {
    console.error('Failed to save gist:', e)
    return null
  }
}
