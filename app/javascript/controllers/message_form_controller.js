import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }

  onSubmitEnd(event) {
    if (event.detail.success) this.element.reset()
  }
}
