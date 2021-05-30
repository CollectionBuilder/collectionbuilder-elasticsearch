/*
 * Paginator Button Component
 *
 * This component implements a single page button.
 *
 */

export default class PaginatorButton extends HTMLButtonElement {
  constructor (html, start, disabled, isCurrent = false) {
    super()

    this.innerHTML = html
    this.start = start
    this.disabled = disabled

    // Add Bootstrap component classes.
    this.classList.add("mr-1", "btn")

    if (isCurrent) {
      this.classList.add("btn-primary")
    } else {
      this.classList.add("btn-light", "border-secondary")
    }
  }
}

customElements.define("paginator-button", PaginatorButton, { extends: "button" })
