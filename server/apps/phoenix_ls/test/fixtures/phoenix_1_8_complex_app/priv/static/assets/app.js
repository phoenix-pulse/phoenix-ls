const Hooks = {}

Hooks.SortableOrders = {
  mounted() {
    this.el.dataset.hookReady = "true"
  }
}

export default Hooks
