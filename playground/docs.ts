// Docs viewer module - can be embedded in main playground

interface DocField {
  name: string;
  view?: string;
  desc?: string;
  rawdesc?: string;
  file?: string;
  type?: string;
}

interface DocEntry {
  name: string;
  type?: string;
  view?: string;
  defines?: Array<{
    file?: string;
    desc?: string;
    view?: string;
  }>;
  fields?: DocField[];
}

let allDocs: DocEntry[] = [];
let currentModule: string | null = null;
let currentSearch: string = "";
let container: HTMLElement | null = null;

function getModule(name: string): string {
  const parts = name.split(".");
  if (parts.length >= 2) {
    return parts.slice(0, 2).join(".");
  }
  if (["vec2", "vec3", "vec4", "mat3", "mat4", "vec_base"].includes(name)) {
    return "glm";
  }
  return name;
}

function getModuleGroup(mod: string): string {
  return mod.split(".")[0];
}

function getModules(docs: DocEntry[]): string[] {
  const modules = new Set<string>();
  for (const entry of docs) {
    modules.add(getModule(entry.name));
  }
  return Array.from(modules).sort();
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

const skipNames = new Set([
  "LuaLS",
  "boolean",
  "function",
  "integer",
  "nil",
  "number",
  "string",
  "table",
  "thread",
  "userdata",
  "lightuserdata",
  "any",
  "unknown",
  "true",
  "false",
  "metatable",
  "init",
  "frame",
  "event",
  "cleanup",
]);

function isForeign(d: DocEntry): boolean {
  return d.defines?.every((def) => def.file?.startsWith("[FOREIGN]")) ?? false;
}

function filterDocs(
  docs: DocEntry[],
  module: string | null,
  search: string,
): DocEntry[] {
  let result = docs.filter(
    (d) => !skipNames.has(d.name) && !d.name.startsWith("_") && !isForeign(d),
  );

  if (module) {
    result = result.filter((d) => getModule(d.name) === module);
  }

  if (search) {
    const lower = search.toLowerCase();
    result = result.filter((d) => {
      if (d.name.toLowerCase().includes(lower)) return true;
      if (d.fields?.some((f) => f.name.toLowerCase().includes(lower)))
        return true;
      return false;
    });
  }

  return result;
}

function extractSourceLink(desc: string): {
  link: string | null;
  rest: string;
} {
  const match = desc.match(/\[source\]\((https?:\/\/[^\s)]+)\)/);
  const link = match ? match[1] : null;
  let rest = match ? desc.replace(match[0], "").trim() : desc;
  // Remove auto-generated header comments
  rest = rest
    .replace(/LuaCATS type definitions for \S+/g, "")
    .replace(/Auto-generated, do not edit/g, "")
    .trim();
  return { link, rest };
}

function renderEntry(entry: DocEntry): string {
  const fields = entry.fields || [];
  const define = entry.defines?.[0];
  const file = define?.file || "";
  const rawDesc = define?.desc || "";
  const { link: sourceLink, rest: desc } = extractSourceLink(rawDesc);

  let html = `<div class="doc-entry" id="${escapeHtml(entry.name)}">
    <h3>${escapeHtml(entry.name)}`;
  if (sourceLink) {
    html += ` <a class="source-link" href="${escapeHtml(sourceLink)}" target="_blank" rel="noopener">source</a>`;
  }
  html += `</h3>`;

  if (file) {
    html += `<div class="doc-file">${escapeHtml(file)}</div>`;
  }

  if (desc) {
    html += `<div class="doc-desc">${escapeHtml(desc)}</div>`;
  }

  if (entry.view) {
    html += `<pre class="doc-type">${escapeHtml(entry.view)}</pre>`;
  }

  if (fields.length > 0) {
    html += `<div class="doc-fields">`;
    for (const field of fields) {
      const fieldDesc = field.desc || field.rawdesc || "";
      html += `<div class="doc-field">
        <span class="field-name">${escapeHtml(field.name)}</span>`;
      if (field.view) {
        html += `<span class="field-type">${escapeHtml(field.view)}</span>`;
      }
      if (fieldDesc) {
        html += `<div class="field-desc">${escapeHtml(fieldDesc)}</div>`;
      }
      html += `</div>`;
    }
    html += `</div>`;
  }

  html += `</div>`;
  return html;
}

function render() {
  if (!container) return;

  const cleanDocs = allDocs.filter(
    (d) => !skipNames.has(d.name) && !d.name.startsWith("_") && !isForeign(d),
  );
  const modules = getModules(cleanDocs);
  const filtered = filterDocs(allDocs, currentModule, currentSearch);

  let sidebar = `<div class="docs-sidebar-inner">
    <input type="text" id="docs-search" placeholder="Search..." value="${escapeHtml(currentSearch)}" />
    <div class="module-list">`;

  // Group modules by top-level namespace
  const groups = new Map<string, string[]>();
  for (const mod of modules) {
    const group = getModuleGroup(mod);
    if (!groups.has(group)) groups.set(group, []);
    groups.get(group)!.push(mod);
  }

  for (const [group, mods] of groups) {
    if (mods.length === 1 && mods[0] === group) {
      // Single module, no grouping needed
      const activeClass = group === currentModule ? "active" : "";
      sidebar += `<a href="#" class="module-item ${activeClass}" data-module="${escapeHtml(group)}">${escapeHtml(group)}</a>`;
    } else {
      // Group header + children
      sidebar += `<div class="module-group"><div class="module-group-label">${escapeHtml(group)}</div>`;
      for (const mod of mods) {
        const label = mod.includes(".")
          ? mod.split(".").slice(1).join(".")
          : mod;
        const activeClass = mod === currentModule ? "active" : "";
        sidebar += `<a href="#" class="module-item module-child ${activeClass}" data-module="${escapeHtml(mod)}">${escapeHtml(label)}</a>`;
      }
      sidebar += `</div>`;
    }
  }
  sidebar += `</div></div>`;

  const content =
    filtered.length > 0
      ? filtered.map(renderEntry).join("")
      : '<div class="no-results">No results found</div>';

  container.innerHTML = `
    <div class="docs-layout">
      <nav class="docs-sidebar">${sidebar}</nav>
      <main class="docs-content">${content}</main>
    </div>
  `;

  // Event listeners
  container.querySelector("#docs-search")?.addEventListener("input", (e) => {
    currentSearch = (e.target as HTMLInputElement).value;
    render();
  });

  container.querySelectorAll(".module-item").forEach((el) => {
    el.addEventListener("click", (e) => {
      e.preventDefault();
      const mod = (el as HTMLElement).dataset.module!;
      currentModule = mod === currentModule ? null : mod;
      render();
    });
  });
}

export async function initDocs(containerEl: HTMLElement): Promise<void> {
  container = containerEl;
  container.innerHTML = '<div class="loading">Loading documentation...</div>';

  try {
    const res = await fetch("/doc.json");
    allDocs = await res.json();
    render();
  } catch (e) {
    container.innerHTML = `<div class="error">Failed to load documentation: ${e}</div>`;
  }
}
