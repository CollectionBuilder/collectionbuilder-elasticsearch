import "./SearchFacetValues.js"
import "./SearchFacetValue.js"

import SearchFacet from "./SearchFacet.js"

import { createElement } from "../lib/helpers.js"

/*
 * Mult-Collection CTA Facet Component
 *
 * This component subclasses SearchFacet to create a call-to-action for
 * multi-collection search.
 *
 */

export default class MultiCollectionCTAFacet extends SearchFacet {
  constructor (numAdditionalCollections) {
    super()

    // Set the collapsed attribute.
    this.setAttribute("collapsed", "")

    const searchFacetValues = createElement(
      `<search-facet-values>
        <search-facet-value
           value="Go to the multi-collection search page to access ${numAdditionalCollections} additional collections"
           doc-count="">
        </search-facet-value>
      </search-facet-values>`
    )

    // Remove the text-truncate class from the name.
    searchFacetValues
      .querySelector("search-facet-value .name")
      .classList.remove("text-truncate")

    // Override the valueClickHandler to navigate to the multi-collection
    // search page.
    this.valueClickHandler = e => {
      e.stopPropagation()
      window.location.pathname = `/multi-collection-search/`
    }

    this.appendChild(searchFacetValues)
  }

  connectedCallback () {
    this.setAttribute("name", "other-collections")
    this.setAttribute("display-name", "Other Collections")

    super.connectedCallback()
  }
}

customElements.define("multi-collection-cta-facet", MultiCollectionCTAFacet)
