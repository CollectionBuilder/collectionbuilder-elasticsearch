/*
 * Search Facet Value Component
 *
 * This component is used to implement a single facet value.
 *
 */

export default class SearchFacetValue extends HTMLElement {
  constructor () {
    super()

    // Add Bootstrap component classes.
    this.classList.add(
      "d-flex",
      "py-1",
      "px-2",
      "btn",
      "btn-light",
      "border-bottom",
      "rounded-0",
    )

    // Add custom component classes.
    this.classList.add("cursor-pointer")

    // Define the component's inner structure.
    this.innerHTML = (
      `<span class="text-truncate pr-2 name"></span>
       <span class="ml-auto doc-count"></span>
      `
    )
  }

  connectedCallback () {
    // Read the custom element attributes.
    const name = this.getAttribute("value")
    const docCount = this.getAttribute("doc-count")
    const selected = this.hasAttribute("selected")

    // Update the name element.
    const nameEl = this.querySelector(".name")
    nameEl.textContent = name
    // Set the title attribute to show untruncated value on hover.
    nameEl.setAttribute("title", name)

    // Update the doc-count element.
    this.querySelector(".doc-count").textContent = selected ? "x" : docCount

    // If selected, replace the btn-light class with btn-info.
    if (selected) {
      this.classList.remove("btn-light")
      this.classList.add("btn-info")
    }
  }
}

// Add this component to the custom elements registry.
customElements.define("search-facet-value", SearchFacetValue)
