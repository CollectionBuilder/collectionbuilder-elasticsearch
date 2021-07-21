/*
 * The Main Search App Component
 */

import "./ClearFilters.js"

import MultiCollectionCTAFacet from "./MultiCollectionCTAFacet.js"
import SearchFacets from "./SearchFacets.js"
import MobileSearchFacets from "./MobileSearchFacets.js"
import SearchResultsHeader from "./SearchResultsHeader.js"
import SearchResults from "./SearchResults.js"

import {
  buildQuery,
  executeQuery,
  getIndicesDirectory,
} from "../lib/elasticsearch.js"

import {
  createElement,
  getUrlSearchParams,
  removeChildren,
  updateUrlSearchParams,
} from "../lib/helpers.js"

export default class Search extends HTMLElement {
  constructor () {
    super()

    this.indicesDirectoryIndexTitleMap = new Map()
    this.indicesDirectoryTitleIndexMap = new Map()

    // Set component styles.
    this.style.fontSize = "1rem"

    // Define the component's inner structure.
    this.appendChild(createElement(
      `
      <div class="container position-relative">

        <div id="search-overlay" class="position-absolute w-100 h-100 d-flex"
             style="top: 0; background-color: rgba(255, 255, 255, 0.5);">
          <div class="spinner-border ml-auto mr-auto" role="status">
            <span class="sr-only">Loading...</span>
          </div>
        </div>

        <div class="row">
          <div class="col-4 d-none d-lg-block" id="search-facets"></div>
          <div class="col">
            <input type="text" class="form-control mb-2" placeholder="Search" aria-label="search box">
            <div id="mobile-search-facets" class="d-lg-none"></div>
            <clear-filters num-applied="0"></clear-filters>
            <div class="results-header"></div>
            <div class="results"></div>
          </div>
        </div>
      </div>
      `
      )
    )

    // Extricate the overlay element from the DOM so that we can inject it as necessary.
    this.searchOverlay = this.querySelector("#search-overlay")
    this.searchOverlay.remove()

    // Get a reference to the clear filters button.
    this.clearFiltersButton = this.querySelector("clear-filters")

    // Get a reference to the search input and initialize it with the value from the
    // URL search params.
    this.searchInput = this.querySelector("input[type=text]")
    const searchParams = getUrlSearchParams()
    if (searchParams.has("q")) {
      this.searchInput.value = searchParams.get("q")
    }
  }

  async connectedCallback () {
    // Parse the Elasticsearch URL value.
    const elasticsearchUrl = this.getAttribute("elasticsearch-url")
    try {
      // Use the origin property value which discards trailing slashes.
      this.esUrl = new URL(elasticsearchUrl).origin
    } catch (e) {
      throw new Error(
        'Please specify a valid <es-search> element "elasticsearch-url" value'
      )
    }

    // Parse the search-multi property.
    this.isMulti = this.hasAttribute("search-multi")

    // Read the Elasticsearch index property.
    this.esIndex = this.getAttribute("elasticsearch-index")
    if (!this.esIndex && !this.isMulti) {
      throw new Error(
        'Please specify a valid <es-search> element "elasticsearch-index" value'
      )
    }

    // Parse the list of all fields.
    if (this.hasAttribute("fields")) {
      let fields = this.getAttribute("fields")
      // Split the list of comma-separated field names.
      fields = fields.split(",")
      // Ignore the trailing empty element and assign to this.
      this.allFields = fields.slice(0, fields.length - 1)
    } else {
      this.allFields = []
    }

    // Parse the list of faceted fields.
    if (this.hasAttribute("faceted-fields")) {
      let facetedFields = this.getAttribute("faceted-fields")
      // Split the list of comma-separated field names.
      facetedFields = facetedFields.split(",")
      // Ignore the trailing empty element and assign to this.
      this.facetedFields = facetedFields.slice(0, facetedFields.length - 1)
    } else {
      this.facetedFields = []
    }

    // Parse the list of display fields.
    if (this.hasAttribute("display-fields")) {
      let displayFields = this.getAttribute("display-fields")
      // Split the list of comma-separated field names.
      displayFields = displayFields.split(",")
      // Ignore the trailing empty element and assign to this.
      this.displayFields = displayFields.slice(0, displayFields.length - 1)
    } else {
      this.displayFields = []
    }

    // Get the indices directory data and use it to init the title/index maps.
    const indicesDirectory = await getIndicesDirectory(this.esUrl)
    indicesDirectory.forEach(({ index, title }) => {
      this.indicesDirectoryIndexTitleMap.set(index, title)
      this.indicesDirectoryTitleIndexMap.set(title, index)
    })

    // Register the search input keydown handler.
    this.searchInput.addEventListener(
      "keydown",
      this.searchInputKeydownHandler.bind(this)
    )

    // Register the clear filters button click handler.
    this.clearFiltersButton.addEventListener(
      "click",
      this.clearFiltersClickHandler.bind(this)
    )

    // Execute a new search on popstate event to handle the
    // browser back button.
    window.addEventListener("popstate", () => this.search.bind(this)())

    // Execute the initial search.
    this.search()
  }

  async search () {
    /* Execute a new search based on the current URL search params and return the
       result.
     */
    // Show the search overlay spinner.
    this.showOverlay()

    const searchParams = getUrlSearchParams()

    // Track the total number of applied filter values.
    let numAppliedFilters = 0

    // Set the array of indices to search against.
    let indiceTitles
    if (!this.isMulti) {
      // This is not the multi-collection search page, so only search against the host
      // collection.
      indiceTitles = [ this.indicesDirectoryIndexTitleMap.get(this.esIndex) ]
    } else {
      // This is the multi-collection search page, so search against the collections
      // specified by the collection[] URL params, or all collections if no such
      // param is specified.
      indiceTitles = searchParams.get("collection[]")
      if (!indiceTitles) {
        // Search all collections if none is specified.
        indiceTitles = Array.from(this.indicesDirectoryTitleIndexMap.keys())
      } else {
        // Delete collection[] from the searchParams to prevent
        // it being specified as filter.
        searchParams.delete("collection[]")
        numAppliedFilters += indiceTitles.length
      }
    }
    const indices = indiceTitles.map(x =>
      this.indicesDirectoryTitleIndexMap.get(x)
    )

    // Get any query string.
    const q = searchParams.pop("q") || ""

    // Get any paging values.
    const start = parseInt(searchParams.pop("start") || 0, 10)
    const size = parseInt(searchParams.pop("size") || 10, 10)

    // Get any list of fields on which to search.
    let fields = [ "*" ]
    if (searchParams.has("fields")) {
      fields = searchParams.pop("fields").split(",")
    }

    // Define which document fields to retrieve.
    const _source = {
      excludes: [
        "full_text"
      ],
    }

    // Use the remaining searchParams entries to build the filters list.
    const filters = new Map()
    Array.from(searchParams.entries()).forEach(([ k, v ]) => {
      const isArray = k.endsWith("[]")
      const name = `${isArray ? k.slice(0, k.length - 2) : k}.raw`
      const values = isArray ? v : [ v ]
      filters.set(name, values)
      numAppliedFilters += values.length
    })

    // Define the aggregations.
    const aggregationNameFieldMap = new Map()
    this.facetedFields.forEach(name =>
      aggregationNameFieldMap.set(name, `${name}.raw`)
    )

    const searchQuery = buildQuery(indices, {
      q,
      filters,
      start,
      size,
      fields,
      aggregationNameFieldMap,
      _source,
    })

    const allIndices = Array.from(this.indicesDirectoryIndexTitleMap.keys())

    // Create a count query that counts hits across all indices and returns
    // no documents.
    const countQuery = {
      size: 0,
      query: searchQuery.query,
      aggs: {
        collection: {
          terms: {
            field: "_index",
            size: allIndices.length,
          },
        },
      },
    }

    const [ searchResponse, countResponse ] = await Promise.all([
      executeQuery(this.esUrl, indices, searchQuery),
      executeQuery(this.esUrl, allIndices, countQuery),
    ])

    // Augment the search response with the count response collection aggregation.
    const collectionAgg = countResponse.aggregations.collection
    // Add zero-count buckets for any unrepresented indices.
    const representedIndices = collectionAgg.buckets.map(({ key }) => key)
    allIndices
      .filter(x => !representedIndices.includes(x))
      .forEach(indice =>
        collectionAgg.buckets.push({ key: indice, doc_count: 0 })
      )
    // Swap the indice names with their titles.
    for (let i = 0; i < collectionAgg.buckets.length; i += 1) {
      const bucket = collectionAgg.buckets[i]
      bucket.key = this.indicesDirectoryIndexTitleMap.get(bucket.key)
    }
    searchResponse.aggregations.collection = collectionAgg

    // Update the clear filters button.
    this.clearFiltersButton.setAttribute("num-applied", numAppliedFilters)

    // Render the facets.
    this.renderFacets(searchResponse.aggregations)

    // Render the results header.
    this.renderResultsHeader(searchResponse.hits.total.value, start, size)

    // Render the results.
    this.renderResults(searchResponse.hits.hits)

    // Hide the search overlay spinner.
    this.hideOverlay()
  }

  showOverlay () {
    /* Show the search spinner overlay.
     */
    this.querySelector(".container").appendChild(this.searchOverlay)
  }

  hideOverlay () {
    /* Hide the search spinner overlay.
     */
    this.searchOverlay.remove()
  }

  async renderFacets (aggregations) {
    /* Reinstantiate the SearchFacets component with the specified aggregations.
     */
    // Get the ordered array of facet names.
    let includeKeys = this.facetedFields

    // If this is the multi-search page, so include a collection facet.
    if (this.isMulti) {
      includeKeys = [ "collection" ].concat(includeKeys)
    }

    /* Render the desktop search facets */
    // Get the desktop container element.
    const searchFacetsContainerEl = this.querySelector("#search-facets")
    const mobileSearchFacetsContainerEl = this.querySelector(
      "#mobile-search-facets"
    )

    // Remove any existing children.
    removeChildren(searchFacetsContainerEl)
    removeChildren(mobileSearchFacetsContainerEl)

    // Instantiate the SearchFacets component.
    const searchFacets = new SearchFacets(aggregations, includeKeys)
    const mobileSearchFacets = new SearchFacets(aggregations, includeKeys)

    // If this is not the multisearch page, include a multi-search call-to-action
    // as the first facet.
    if (!this.isMulti) {
      const numAdditionalCollections =
        this.indicesDirectoryIndexTitleMap.size - 1
      searchFacets.insertBefore(
        new MultiCollectionCTAFacet(numAdditionalCollections),
        searchFacets.children[0]
      )
      mobileSearchFacets.insertBefore(
        new MultiCollectionCTAFacet(numAdditionalCollections),
        mobileSearchFacets.children[0]
      )
    }

    // Register the facet value click handler.
    searchFacets.addValueClickListener(this.facetValueClickHandler.bind(this))
    mobileSearchFacets.addValueClickListener(
      this.facetValueClickHandler.bind(this)
    )

    // Append the new <search-facets> element.
    searchFacetsContainerEl.appendChild(searchFacets)

    // Create and append the search facets modal component.
    mobileSearchFacetsContainerEl.appendChild(
      new MobileSearchFacets(mobileSearchFacets)
    )
  }

  async renderResultsHeader (numHits, start, size) {
    // Get the results header container and remove any existing children.
    const container = this.querySelector("div.results-header")
    removeChildren(container)

    const searchResultsHeader = new SearchResultsHeader(numHits, start, size)
    container.appendChild(searchResultsHeader)

    if (numHits > 0) {
      // Register the page size selector change handler.
      searchResultsHeader
        .querySelector("select[is=page-size-selector]")
        .addEventListener(
          "change",
          this.pageSizeSelectorChangeHandler.bind(this)
        )

      // Register the paginator click handler.
      searchResultsHeader
        .querySelector("paginator-control")
        .addEventListener("click", this.paginatorClickHandler.bind(this))
    }
  }

  async renderResults (hits) {
    /* Reinstantiate the SearchResults component with the specified hits.
     */
    // Get the results container element and remove any existing <search-results> element.
    const searchResultsContainerEl = this.querySelector("div.results")
    let searchResults = searchResultsContainerEl.querySelector(
      "search-results"
    )
    if (searchResults !== null) {
      searchResults.remove()
    }

    // Instantiate the SearchFacets component.
    searchResults = new SearchResults(hits, this.displayFields, this.isMulti)

    // Append the component to the container.
    searchResultsContainerEl.appendChild(searchResults)
  }

  facetValueClickHandler (name, value) {
    /* Handle a facet value click by updating the URL search params and initiating
       a new search.
    */
    const params = new URLSearchParams(window.location.search)
    const paramKey = `${name}[]`
    let paramVals = params.getAll(paramKey)

    if (paramVals.includes(value)) {
      paramVals = paramVals.filter(x => x !== value)
    } else {
      paramVals.push(value)
    }
    params.delete(paramKey)
    paramVals.forEach(v => params.append(paramKey, v))

    // Delete any start param.
    params.delete("start")

    updateUrlSearchParams(params)
    this.search()
  }

  searchInputKeydownHandler (e) {
    /* Execute a new search when the user presse the Enter button inside the
       text input box.
    */
    if (e.key !== "Enter") {
      return
    }
    const el = e.target
    // Blur the input.
    el.blur()
    // Update the URL "q" search param.
    const q = el.value
    const params = new URLSearchParams(window.location.search)
    params.set("q", q)

    // Delete any start param.
    params.delete("start")

    updateUrlSearchParams(params)
    this.search()
  }

  pageSizeSelectorChangeHandler (e) {
    /* Execute a new search when the page size selector is changed.
     */
    // Update the URL "q" search param.
    const size = e.target.value
    const params = new URLSearchParams(window.location.search)
    params.set("size", size)

    // Delete any start param.
    params.delete("start")

    updateUrlSearchParams(params)
    this.search()
  }

  clearFiltersClickHandler (e) {
    /* Handler a click on the clear-filters button.
     */
    e.stopPropagation()

    // Parse the unique list of applied filter keys from the current URL.
    const params = new URLSearchParams(window.location.search)
    const filterKeys = new Set(
      Array.from(params.keys()).filter(x => x.endsWith("[]"))
    )

    // Delete all filter params.
    filterKeys.forEach(k => params.delete(k))

    // Also delete start if present.
    params.delete("start")

    // Update the URL search params.
    updateUrlSearchParams(params)

    // Execute a new search.
    this.search()
  }

  paginatorClickHandler (e) {
    /* Handler a click on a paginator button.
     */
    e.stopPropagation()
    const { target } = e
    if (target.tagName !== "BUTTON") {
      return
    }

    // Get the page button's start attribute.
    const { start } = target

    // Add or update the URL search param start value.
    const params = new URLSearchParams(window.location.search)
    if (start === 0) {
      params.delete("start")
    } else {
      params.set("start", start)
    }

    // Update the URL search params.
    updateUrlSearchParams(params)

    // Execute a new search.
    this.search()
  }
}

customElements.define("search-app", Search)
