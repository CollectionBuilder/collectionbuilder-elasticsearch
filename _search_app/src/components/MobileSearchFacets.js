/*
 * Clear Filters Component
 *
 * This component is used to clear any applied search filters.
 *
 */

export default class MobileSearchFacets extends HTMLElement {
  constructor (searchFacets) {
    super()

    // Define this element's inner structure.
    this.innerHTML = `<button class="btn btn-secondary mb-2 w-100">Show Filters</button>
       <div class="outer d-none position-fixed"
            style="top: 0; right: 0; bottom: 0; left: 0;
                   background-color: rgba(200, 200, 200, 0.95); z-index: 2;
                   overflow-y: auto;">
         <div class="inner w-75 my-2 mx-auto"></div>
       </div>
      `

    // Get references to the outer and inner div elements.
    this.outerEl = this.querySelector(".outer")
    this.innerEl = this.querySelector(".inner")

    // Append the searchFacets element as a child of the inner div.
    this.innerEl.appendChild(searchFacets)

    // Register a click handler on the button that will show the modal.
    this.querySelector("button").addEventListener(
      "click",
      this.buttonClickHandler.bind(this)
    )

    // Register a click handler on the outer div that will conditionally
    // close the modal.
    this.outerEl.addEventListener("click", this.facetsClickHandler.bind(this))

    // Register a keydown handler to close the modal on Escape.
    this.addEventListener("keydown", this.keydownHandler)
  }

  show () {
    // Show the modal.
    this.outerEl.classList.remove("d-none")
    this.outerEl.classList.add("d-flex")
    // Set the body overflow to hidden to hide any visible scrollbar.
    document.body.style.overflow = "hidden"
    // Assuming a scrollbar was visible, add some right-side margin to the
    // body to compensate for the lost scrollbar to prevent the body content
    // from shifting behind the visible modal.
    document.body.style.marginRight = "16px"
  }

  hide () {
    // Hide the modal.
    this.outerEl.classList.remove("d-flex")
    this.outerEl.classList.add("d-none")
    // Restore the body elements pre-modal style.
    document.body.style.overflow = "visible"
    document.body.style.marginRight = 0
  }

  buttonClickHandler (e) {
    // Show the modal on "Show Filters" button click.
    e.stopPropagation()
    this.show()
  }

  facetsClickHandler (e) {
    // Maybe hide the modal.
    e.stopPropagation()
    // If the user clicked on anything other than a facet header or show more/fewer
    // button, hide the modal.
    if (
      e.target.tagName !== "H1" &&
      e.target.tagName !== "BUTTON" &&
      e.target.parentElement.tagName !== "H1"
    ) {
      this.hide()
    }
  }

  keydownHandler (e) {
    // Hide the modal on Escape.
    if (e.key === "Escape") {
      this.hide()
    }
  }
}

customElements.define("mobile-search-facets", MobileSearchFacets)
