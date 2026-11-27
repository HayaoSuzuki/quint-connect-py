module counter {
  type RecordedAction = Reset | Add({ delta: int })
  var count: int
  var op: RecordedAction

  action init = all { count' = 0, op' = Reset }
  action step = all { count' = count + 1, op' = Add({ delta: 1 }) }

  run roundTripTest = init.then(step).then(step).expect(count == 2)
}
