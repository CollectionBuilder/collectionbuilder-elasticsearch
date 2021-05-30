import { createElement } from "../lib/helpers.js"

/*
 * Search Facet Component
 *
 * This component is used to implement a single facet.
 *
 */

export default class SearchFacet extends HTMLElement {
  constructor () {
    super()

    // Define a flag to indicate whether the facet values are collapsed.
    this.collapsed = false

    // Define an array for value toggle listener functions.
    this.valueClickListeners = []

    // Define properties that will be populated within connectedCallback.
    this.name = undefined
    this.displayName = undefined

    // Add component styles.
    this.classList.add(
      "d-block",
      "border",
      "border-secondary",
      "rounded",
      "overflow-hidden",
      "mb-4",
      "w-100"
    )

    // Define the component's inner structure.
    this.appendChild(createElement(
      `<h1 class="d-flex bg-dark text-white-50 font-weight-bold p-2 mb-0 text-nowrap h6
                  cursor-pointer">
         <span class="name"></span>
         <span class="font-weight-bold text-monospace ml-auto collapsed-icon">-</span>
       </h1>`
    ))

    this.appendChild(createElement(`<slot></slot>`))
  }

  connectedCallback () {
    // Read the custom element attributes.
    this.name = this.getAttribute("name")
    this.displayName = this.getAttribute("display-name")

    // Insert the <search-facet-values> element into its slot.
    // Note that this would happen automatically if we were using a shadow DOM.
    const searchFacetValuesEl = this.querySelector("search-facet-values")
    this.querySelector("slot").replaceWith(searchFacetValuesEl)

    // If collapsed was specified, collapse the values.
    if (this.hasAttribute("collapsed")) {
      this.toggleCollapsed()
    }

    // Update the component with the attribute values.
    this.querySelector("h1 > span.name").textContent = this.displayName

    // Register the facet header collapse click handler.
    this.querySelector("h1")
      .addEventListener("click", this.toggleCollapsed.bind(this))

    // Register the value click handler.
    this.querySelector("search-facet-values")
      .addEventListener("click", this.valueClickHandler.bind(this))
  }

  toggleCollapsed () {
    // Toggle the state variable.
    this.collapsed = !this.collapsed

    // Update the collapsed icon.
    this
      .querySelector('h1 > span.collapsed-icon')
      .textContent = this.collapsed ? "+" : "-"

    // Update the search facet values display.
    // Note the assumption that both search-facet-values element has a default
    // display value of "block".
    const searchFacetValuesEl = this.querySelector("search-facet-values")
    if (this.collapsed) {
      searchFacetValuesEl.classList.remove("d-block")
      searchFacetValuesEl.classList.add("d-none")
    } else {
      searchFacetValuesEl.classList.remove("d-none")
      searchFacetValuesEl.classList.add("d-block")
    }
  }

  addValueClickListener (fn) {
    /* Add a function to the value click listeners array.
     */
    this.valueClickListeners.push(fn)
  }

  removeValueClickListener (fn) {
    /* Remove a function from the value click listeners array.
     */
    for (let i = 0; i < this.valueClickListeners.length; i += 1) {
      if (this.valueClickListeners[i] === fn) {
        // Remove the function from the listeners array and return.
        this.valueClickListeners.splice(i, 1)
        return
      }
    }
  }

  valueClickHandler (e) {
    /* Invoke all registered value click listeners.
     */
    const target = e.target.closest("search-facet-value")
    // Ignore clicks not inside a <search-facet-value>.
    if (target === null) {
      return
    }
    const value = target.getAttribute("value")
    this.valueClickListeners.forEach(
      fn => fn(this.name, value)
    )
  }
}

// Add this component to the custom elements registry.
customElements.define("search-facet", SearchFacet)
