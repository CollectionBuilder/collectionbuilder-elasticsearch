/*
 * Assorted Helper Classes and Functions
 */

// Define a subclass of Map that implements a pop() method.
class PoppableMap extends Map {
  pop (k) {
    /* If the Map has the key, delete the key and return its value, otherwise return
       undefined.
     */
    if (!this.has(k)) {
      return undefined
    }
    const v = this.get(k)
    this.delete(k)
    return v
  }
}

export function createElement (DOMString) {
  // Return an HTML element object for the given DOM string.
  const wrapper = document.createElement("div")
  wrapper.innerHTML = DOMString.trim()
  const el = wrapper.firstChild
  wrapper.removeChild(el)
  return el
}

export const snakeToTitleCase = s =>
  s.split("_")
    .map(_s => _s[0].toUpperCase() + _s.slice(1))
    .join(" ")

export const clone = tmplEl => tmplEl.content.cloneNode(true).children[0]

export const removeChildren = el => Array.from(el.children).forEach(x => x.remove())

export function getUrlSearchParams () {
  // Parse the URL search params, collecting array-type values into actual
  // arrays and return the resulting <key> -> <value(s)> map.
  const params = new PoppableMap()
  const searchParams = new URLSearchParams(window.location.search)
  Array.from(searchParams.entries()).forEach(([ k, v ]) => {
    const isArray = k.endsWith("[]")
    if (!params.has(k)) {
      params.set(k, isArray ? [ v ] : v)
    } else if (isArray) {
      params.get(k).push(v)
    } else {
      console.warn(`Duplicate search key "${k}" does not end with "[]"`)
    }
  })
  return params
}

export function updateUrlSearchParams (searchParams) {
  // Create a URL object from the current location and update its search property.
  const url = new URL(window.location.href)
  url.search = searchParams
  // Use pushState() to update the address bar without reloading the page.
  window.history.pushState(null, document.title, url)
}

export function getAttribute (el, attr, defaultValue = undefined) {
  /* Return an HTMLElement's attribute value. If the attribute doesn't exist and a
     default value is specified, return the default value, otherwise throw an error.
  */
  if (el.hasAttribute(attr)) {
    return el.getAttribute(attr)
  }
  if (defaultValue !== undefined) {
    return defaultValue
  }
  console.warn(el)
  throw new Error(
    `Element (previous console warning) has no attribute: "${attr}"`
  )
}
