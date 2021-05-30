/*
 * Paginator Component
 *
 * This component is used to page through results.
 *
 */

import PaginatorButton from "./PaginatorButton.js"

import { createElement, getAttribute } from "../lib/helpers.js"

// Define an Ellipsis element.
const ellipsisElement = createElement(
  '<span class="position-relative mr-1" style="top: .4em">&#8230;</span>'
)

export default class Paginator extends HTMLElement {
  connectedCallback () {
    // Parse the component properties.
    const numTotal = parseInt(getAttribute(this, "num-total"), 10)
    const pageSize = parseInt(getAttribute(this, "page-size"), 10)
    const currentPage = parseInt(getAttribute(this, "current-page"), 10)

    const maxPage = Math.ceil(numTotal / pageSize)

    // Define the max number of page number button to display on each side
    // of the current page.
    const MAX_NUM_REACHABLE_PAGES = 2

    // Determine whether we're going to show the first and last page buttons.
    const showFirstPageButton = currentPage > MAX_NUM_REACHABLE_PAGES + 1
    const showLastPageButton = maxPage - currentPage > MAX_NUM_REACHABLE_PAGES

    // Define a helper to calculate the 'start' value for a given page number.
    const pageToStart = pageNum => pageSize * (pageNum - 1)

    // Add the previous page button.
    this.appendChild(
      new PaginatorButton(
        "&laquo;&nbsp;prev", pageToStart(currentPage - 1), currentPage === 1
      )
    )

    // Maybe add a first page button.
    if (showFirstPageButton) {
      this.appendChild(new PaginatorButton("1", pageToStart(1), false))
      this.appendChild(ellipsisElement.cloneNode(true))
    }

    // Add the adjacent page buttons.
    let pageDelta = -MAX_NUM_REACHABLE_PAGES
    while (pageDelta <= MAX_NUM_REACHABLE_PAGES) {
      const page = currentPage + pageDelta
      if (
        page > 0
        && (page !== 1 || !showFirstPageButton)
        && (page !== maxPage || !showLastPageButton)
        && page <= maxPage
      ) {
        const isCurrentPage = page === currentPage
        this.appendChild(
          new PaginatorButton(
            `${page}`, pageToStart(page), isCurrentPage, isCurrentPage
          )
        )
      }
      pageDelta += 1
    }

    // Maybe add a last page button.
    if (showLastPageButton) {
      this.appendChild(ellipsisElement.cloneNode(true))
      this.appendChild(
        new PaginatorButton(
          `${maxPage}`, pageToStart(maxPage), false
        )
      )
    }

    // Add the next page button.
    const nextPageButton = new PaginatorButton(
      "next&nbsp;&raquo;", pageToStart(currentPage + 1), currentPage === maxPage
    )
    this.appendChild(nextPageButton)
    // Remove the right margin from this last button.
    nextPageButton.classList.remove("mr-1")
  }
}

customElements.define("paginator-control", Paginator)
