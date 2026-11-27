module quint_values_test {
  import quint_values.* from "./quint_values"

  pure def atom(node: ValueNode): ItfValue = { nodes: List(node), root: 0 }

  pure val hugeDigits = List(1, 8, 4, 4, 6, 7, 4, 4, 0, 7, 3, 7, 0, 9, 5, 5, 1, 6, 1, 6)

  run decimalValidationTest = all {
    validDecimal({ negative: false, digits: hugeDigits }),
    validDecimal({ negative: true, digits: List(0, 0) }),
    not(validDecimal({ negative: false, digits: List() })),
    not(validDecimal({ negative: true, digits: List(1, -1) })),
    not(validDecimal({ negative: false, digits: List(10) })),
    not(isUsable(atom(IntegerNode({ negative: false, digits: List(10) })))),
  }

  run integerEqualityTest = {
    val positive = atom(IntegerNode({ negative: false, digits: hugeDigits }))
    val padded = atom(IntegerNode({ negative: false, digits: List(0, 0).concat(hugeDigits) }))
    val negative = atom(IntegerNode({ negative: true, digits: hugeDigits }))
    val preceding = atom(IntegerNode({
      negative: false,
      digits: List(1, 8, 4, 4, 6, 7, 4, 4, 0, 7, 3, 7, 0, 9, 5, 5, 1, 6, 1, 5),
    }))
    val zero = atom(IntegerNode({ negative: false, digits: List(0) }))
    val negativeZero = atom(IntegerNode({ negative: true, digits: List(0, 0) }))
    all {
      equalValues(positive, padded),
      not(equalValues(positive, negative)),
      not(equalValues(positive, preceding)),
      equalValues(zero, negativeZero),
    }
  }

  run strictTypesTest = {
    val one = atom(IntegerNode({ negative: false, digits: List(1) }))
    val record = {
      nodes: List(TextNode("Some"), BooleanNode(true), RecordNode(Map("tag" -> 0, "value" -> 1))),
      root: 2,
    }
    val sameFieldsMap = {
      nodes: List(TextNode("Some"), BooleanNode(true), TextNode("tag"), TextNode("value"), MapNode(List((2, 0), (3, 1)))),
      root: 4,
    }
    all {
      not(equalValues(atom(BooleanNode(true)), one)),
      not(equalValues(atom(TextNode("1")), one)),
      not(equalValues(atom(ListNode(List())), atom(TupleNode(List())))),
      not(equalValues(atom(SetNode(List())), atom(ListNode(List())))),
      not(equalValues(record, sameFieldsMap)),
      not(equalValues(record, atom(BooleanNode(true)))),
      equalValues(record, record),
    }
  }

  run orderedChildrenTest = {
    val children = List(BooleanNode(false), BooleanNode(true))
    val list = { nodes: children.append(ListNode(List(0, 1))), root: 2 }
    val reversedList = { nodes: children.append(ListNode(List(1, 0))), root: 2 }
    val tuple = { nodes: children.append(TupleNode(List(0, 1))), root: 2 }
    val reversedTuple = { nodes: children.append(TupleNode(List(1, 0))), root: 2 }
    val renamedRecord = { nodes: children.append(RecordNode(Map("y" -> 0))), root: 2 }
    val record = { nodes: children.append(RecordNode(Map("x" -> 0))), root: 2 }
    all {
      not(equalValues(list, reversedList)),
      not(equalValues(tuple, reversedTuple)),
      not(equalValues(record, renamedRecord)),
    }
  }

  run nestedMapOrderTest = {
    val left = {
      nodes: List(
        BooleanNode(true),
        TextNode("x"),
        TextNode("y"),
        ListNode(List(1, 2)),
        SetNode(List(0, 3)),
        RecordNode(Map("labels" -> 3, "content" -> 4)),
        TupleNode(List(2, 0)),
        IntegerNode({ negative: true, digits: List(0, 0).concat(hugeDigits) }),
        MapNode(List((5, 6), (3, 7))),
      ),
      root: 8,
    }
    val renumbered = List(
      IntegerNode({ negative: true, digits: hugeDigits }),
      TextNode("y"),
      TextNode("x"),
      ListNode(List(2, 1)),
      BooleanNode(true),
      SetNode(List(3, 4, 4)),
      RecordNode(Map("content" -> 5, "labels" -> 3)),
      TupleNode(List(1, 4)),
    )
    val right = { nodes: renumbered.append(MapNode(List((3, 0), (6, 7)))), root: 8 }
    val switchedValues = { nodes: renumbered.append(MapNode(List((3, 7), (6, 0)))), root: 8 }
    all {
      isUsable(left),
      isUsable(right),
      equalValues(left, right),
      equalValues(right, left),
      not(equalValues(left, switchedValues)),
    }
  }

  run duplicateMapKeyTest = {
    val children = List(
      IntegerNode({ negative: true, digits: List(0, 0) }),
      IntegerNode({ negative: false, digits: List(0) }),
      ListNode(List(0)),
      ListNode(List(1)),
      BooleanNode(false),
      BooleanNode(true),
    )
    val duplicate = { nodes: children.append(MapNode(List((2, 4), (3, 5)))), root: 6 }
    val sameValue = { nodes: children.append(MapNode(List((2, 4), (3, 4)))), root: 6 }
    val distinct = { nodes: children.append(MapNode(List((2, 4), (1, 5)))), root: 6 }
    all {
      not(isUsable(duplicate)),
      not(equalValues(duplicate, duplicate)),
      not(isUsable(sameValue)),
      isUsable(distinct),
    }
  }

  run onlyReachableNodesTest = {
    val value = {
      nodes: List(UnusableNode, ListNode(List(5)), TextNode("usable"), ListNode(List(0, 2))),
      root: 2,
    }
    all {
      equalValues(value, atom(TextNode("usable"))),
      not(isUsable({ ...value, root: 0 })),
      not(isUsable({ ...value, root: 1 })),
      not(isUsable({ ...value, root: 3 })),
      not(isUsable({ ...value, root: -1 })),
      not(isUsable({ ...value, root: 4 })),
      not(isUsable({ nodes: List(), root: 0 })),
    }
  }

  run invalidChildReferencesTest = all {
    not(isUsable(atom(ListNode(List(-1))))),
    not(isUsable(atom(TupleNode(List(0))))),
    not(isUsable({ nodes: List(SetNode(List(1)), BooleanNode(true)), root: 0 })),
    not(isUsable(atom(RecordNode(Map("missing" -> 10))))),
    not(isUsable({ nodes: List(BooleanNode(true), MapNode(List((0, 10)))), root: 1 })),
  }

  pure def permutations(arity: int): Set[List[int]] =
    range(0, arity).foldl(Set(List()), (orders, index) =>
      orders.fold(Set(), (extended, order) =>
        extended.union(0.to(order.length()).map(position =>
          order.slice(0, position).append(index).concat(order.slice(position, order.length()))))))

  type CollectionKind = SetKind | MapKind | ListKind | TupleKind
  pure val collectionKinds = Set(SetKind, MapKind, ListKind, TupleKind)

  // The alternate encoding pads a decimal and reorders nested set elements and map entries.
  pure def nestedNodes(alternate: bool): List[ValueNode] = List(
    IntegerNode({ negative: false, digits: if (alternate) List(0, 7) else List(7) }),
    BooleanNode(true),
    TextNode("field"),
    SetNode(if (alternate) List(1, 0) else List(0, 1)),
    TupleNode(List(3, 2)),
    RecordNode(Map("tuple" -> 4, "number" -> 0)),
    ListNode(List(4, 3)),
    MapNode(if (alternate) List((3, 2), (4, 5)) else List((4, 5), (3, 2))),
  )

  pure def nestedCollection(kind: CollectionKind, order: List[int], alternate: bool): ItfValue = {
    val nodes = nestedNodes(alternate)
    val elements = order.foldl(List(), (ids, index) => ids.append(3 + index))
    val bindings = List((3, 6), (4, 7), (5, 4))
    val rootNode = match kind {
      | SetKind => SetNode(elements)
      | MapKind => MapNode(order.foldl(List(), (entries, index) => entries.append(bindings.nth(index))))
      | ListKind => ListNode(elements)
      | TupleKind => TupleNode(elements)
    }
    { nodes: nodes.append(rootNode), root: nodes.length() }
  }

  run nestedCollectionPermutationTest = {
    val permutationCounts = List(1, 1, 2, 6)
    all {
      permutationCounts.indices().forall(arity => {
        val orders = permutations(arity)
        orders.size() == permutationCounts.nth(arity) and
          orders.forall(order =>
            order.length() == arity and
              order.foldl(Set(), (seen, index) => seen.union(Set(index))) == order.indices())
      }),
      permutationCounts.indices().forall(arity => {
        val orders = permutations(arity)
        collectionKinds.forall(kind => orders.forall(leftOrder => orders.forall(rightOrder => {
          val left = nestedCollection(kind, leftOrder, false)
          val right = nestedCollection(kind, rightOrder, true)
          val unordered = kind == SetKind or kind == MapKind
          all {
            isUsable(left),
            isUsable(right),
            equalValues(left, right) == (unordered or leftOrder == rightOrder),
          }
        })))
      }),
    }
  }

  run compoundEqualityLawsTest = {
    val ordinaryOrder = List(0, 1, 2)
    val orders = permutations(ordinaryOrder.length())
    val records = Set(false, true).map(alternate => { nodes: nestedNodes(alternate), root: 5 })
    val values = collectionKinds.fold(records, (allValues, kind) =>
      allValues.union(orders.map(order => nestedCollection(kind, order, false)))
        .union(Set(nestedCollection(kind, ordinaryOrder, true))))
    val equalTo = values.mapBy(left => values.filter(right => equalValues(left, right)))
    val mapExample = nestedCollection(MapKind, ordinaryOrder, false)
    all {
      values.size() == 30,
      values.forall(isUsable),
      // Seven different representations of the same map give nontrivial transitive chains.
      equalTo.get(mapExample).size() == 7,
      values.forall(left => equalTo.get(left).contains(left)),
      values.forall(left => values.forall(right =>
        equalTo.get(left).contains(right) == equalTo.get(right).contains(left))),
      values.forall(left => equalTo.get(left).forall(middle =>
        equalTo.get(middle).subseteq(equalTo.get(left)))),
    }
  }
}
