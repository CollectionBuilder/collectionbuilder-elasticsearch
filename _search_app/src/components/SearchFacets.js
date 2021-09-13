/*
 * Search Facets Component
 *
 * This component is used to contain a list of <search-facet> elements.
 *
 */

// Import the following component modules just to register the custom elements.
import "./SearchFacet.js"
import "./SearchFacetValues.js"
import "./SearchFacetValue.js"

import {
  createElement,
  snakeToTitleCase,
} from "../lib/helpers.js"

const getSelectedFacetVals = name =>
  new URLSearchParams(window.location.search).getAll(`${name}[]`)

export default class SearchFacets extends HTMLElement {
  constructor (aggregations, includeKeys) {
    super()

    // Save the aggregations for later.
    this.aggregations = aggregations
    this.includeKeys = includeKeys

    // Define an array for value toggle listener functions.
    this.valueClickListeners = []
  }

  connectedCallback () {
    // Iterate through the aggregations, creating a SearchFacet for each.
    (this.includeKeys || Object.keys(this.aggregations)).forEach(key => {
      const { buckets } = this.aggregations[key]

      // Ignore the facet if no values were returned.
      if (buckets.length === 0) {
        return
      }

      // Sort the value by the order in which they were applied, as indicated
      // by the search URL params.
      const selectedFacetVals = getSelectedFacetVals(key).reverse()
      buckets.sort(
        (a, b) => selectedFacetVals.indexOf(b.key) - selectedFacetVals.indexOf(a.key)
      )

      // Define a helper that will create an HTML search-facet-value element
      // string from a search response aggregation bucket.
      const bucketToSearchFacetValueStr = bucket =>
        `<search-facet-value value="${bucket.key}"
                             doc-count="${bucket.doc_count}"
                             ${selectedFacetVals.includes(bucket.key) ? "selected" : ""}>
         </search-facet-value>`

      // Create the SearchFacet component.
      const searchFacetEl = createElement(
        `<search-facet name="${key}" display-name="${snakeToTitleCase(key)}">
           <search-facet-values initial-num-visible="14">
             ${buckets.map(bucketToSearchFacetValueStr).join("")}
           </search-facet-values>
         </search-facet>`
      )

      this.appendChild(searchFacetEl)

      // Remove the bottom border from the last value.
      const searchFacetValues = searchFacetEl.querySelectorAll("search-facet-value")
      searchFacetValues[searchFacetValues.length - 1].classList.remove("border-bottom")

      // Register the value click listener for this facet.
      searchFacetEl.addValueClickListener(this.valueClickHandler.bind(this))
    })
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

  valueClickHandler (name, value) {
    /* Invoke all registered value click listeners.
     */
    this.valueClickListeners.forEach(fn => fn(name, value))
  }
}

customElements.define("search-facets", SearchFacets)
