/*
 * Search Results Header Component
 *
 * This component displays search results stats and paging controls.
 *
 */

import "./Paginator.js"
import "./PageSizeSelector.js"

export default class SearchResultsHeader extends HTMLElement {
  constructor (numHits, start, size) {
    super()

    this.numHits = numHits
    this.start = start
    this.size = size
    this.startIdx = start + 1
    this.endIdx = this.startIdx + Math.min(numHits - this.startIdx, size - 1)

    this.classList.add("d-flex")
  }

  connectedCallback () {
    // Display a no results found message if there are no results.
    if (this.numHits === 0) {
      this.innerHTML = (
        `<span class="h4 text-nowrap">
           No results found
         </span>`
      )
      return
    }

    // Display an error message if the start value is invalid.
    if (this.endIdx < this.startIdx) {
      this.classList.add("bg-warning", "text-dark", "p-3")
      this.textContent = (
        `Query "start" value (${this.start}) exceeds the number of total `
        + `results (${this.numHits})`
      )
      return
    }

    this.innerHTML = (
      `<span class="h4 text-nowrap">
         Showing ${this.startIdx} - ${this.endIdx} of ${this.numHits} Results
       </span>
       <div class="ml-auto text-right">
         <span class="text-nowrap">
           <label for="results-per-page">Results per page</label>
           <select is="page-size-selector" value="${this.size}" options="10,25,50,100"
                   class="cursor-pointer">
           </select>
         </span>
         <paginator-control num-total="${this.numHits}" page-size="${this.size}"
                            current-page="${Math.floor(this.startIdx / this.size) + 1}"
                            class="d-block mt-1 mb-2">
         </paginator-control>
       </div>
      `
    )
  }
}

customElements.define("search-results-header", SearchResultsHeader)
