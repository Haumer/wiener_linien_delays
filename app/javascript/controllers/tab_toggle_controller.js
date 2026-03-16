import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["btn", "panel"]

  switch(event) {
    const tab = event.currentTarget.dataset.tab

    this.btnTargets.forEach((btn) => {
      btn.classList.toggle("tab-toggle__btn--active", btn.dataset.tab === tab)
    })

    this.panelTargets.forEach((panel) => {
      panel.style.display = panel.dataset.tab === tab ? "" : "none"
    })
  }
}
