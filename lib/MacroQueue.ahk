class MacroQueue {
  static pending := []
  static running := false

  static Cancel(owner) {
    previousCritical := Critical("On")
    try {
      index := this.pending.Length
      while (index > 0) {
        if (this.pending[index].owner = owner) {
          this.pending.RemoveAt(index)
        }
        index -= 1
      }
    } finally {
      Critical(previousCritical)
    }
  }

  static Run(callback, owner := "", repeat := false) {
    previousCritical := Critical("On")
    try {
      if (repeat) {
        for item in this.pending {
          if (item.owner = owner) {
            return 0
          }
        }
      }
      this.pending.Push({ callback: callback, owner: owner })
      if (this.running) {
        return 0
      }
      this.running := true
      try {
        loop {
          if (!this.pending.Length) {
            this.running := false
            return 0
          }
          next := this.pending.RemoveAt(1)
          Critical(previousCritical)
          next.callback.Call()
          Critical("On")
        }
      } catch as err {
        Critical("On")
        this.pending.Length := 0
        this.running := false
        throw err
      }
    } finally {
      Critical(previousCritical)
    }
  }
}
