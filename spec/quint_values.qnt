module quint_values {
  type NodeId = int
  // Decoded Unicode scalar values, in order.
  type Text = List[int]
  type Decimal = { negative: bool, digits: List[int] }
  type ValueNode =
    | BooleanNode(bool)
    | IntegerNode(Decimal)
    | TextNode(Text)
    | ListNode(List[NodeId])
    | TupleNode(List[NodeId])
    | RecordNode(Text -> NodeId)
    | SetNode(List[NodeId])
    | MapNode(List[(NodeId, NodeId)])
    | UnusableNode

  type ItfValue = { nodes: List[ValueNode], root: NodeId }

  pure def validText(text: Text): bool =
    text.indices().forall(i => {
      val point = text.nth(i)
      0 <= point and point <= 0x10FFFF and (point < 0xD800 or point > 0xDFFF)
    })

  pure def validDecimal(number: Decimal): bool =
    number.digits.length() > 0 and
      number.digits.indices().forall(i => {
        val digit = number.digits.nth(i)
        digit >= 0 and digit <= 9
      })

  pure def normalizeDecimal(number: Decimal): Decimal = {
    val digits = number.digits.foldl(List(), (significant, digit) =>
      if (significant.length() == 0 and digit == 0) significant
      else significant.append(digit))
    if (digits.length() == 0) { negative: false, digits: List(0) }
    else { negative: number.negative, digits: digits }
  }

  // Children of canonical nodes use IDs from one shared pool. The tags
  // distinguish types even when their children or primitive contents agree.
  type CanonicalNode =
    | CanonicalBoolean(bool)
    | CanonicalInteger(Decimal)
    | CanonicalText(Text)
    | CanonicalList(List[NodeId])
    | CanonicalTuple(List[NodeId])
    | CanonicalRecord(Text -> NodeId)
    | CanonicalSet(Set[NodeId])
    | CanonicalMap(NodeId -> NodeId)
    | CanonicalUnusable

  type NodePool = { ids: CanonicalNode -> NodeId, nextId: NodeId }
  type Canonicalization = { pool: NodePool, nodeIds: List[NodeId] }

  pure val emptyNodePool: NodePool = { ids: Map(), nextId: 0 }
  pure val invalidNodeId = -1

  // The input lists nodes with children before their parents. A reference
  // outside the processed prefix is missing, forward, or to the node itself.
  pure def childId(nodeIds: List[NodeId], child: NodeId): NodeId =
    if (child >= 0 and child < nodeIds.length()) nodeIds.nth(child)
    else invalidNodeId

  pure def remapChildren(nodeIds: List[NodeId], children: List[NodeId]): List[NodeId] =
    children.foldl(List(), (ids, child) => ids.append(childId(nodeIds, child)))

  pure def allChildrenUsable(children: List[NodeId]): bool =
    children.indices().forall(i => children.nth(i) != invalidNodeId)

  pure def canonicalShape(nodeIds: List[NodeId], node: ValueNode): CanonicalNode =
    match node {
      | BooleanNode(value) => CanonicalBoolean(value)
      | IntegerNode(number) =>
          if (validDecimal(number)) CanonicalInteger(normalizeDecimal(number))
          else CanonicalUnusable
      | TextNode(value) => if (validText(value)) CanonicalText(value) else CanonicalUnusable
      | ListNode(children) => {
          val ids = remapChildren(nodeIds, children)
          if (allChildrenUsable(ids)) CanonicalList(ids) else CanonicalUnusable
        }
      | TupleNode(children) => {
          val ids = remapChildren(nodeIds, children)
          if (allChildrenUsable(ids)) CanonicalTuple(ids) else CanonicalUnusable
        }
      | RecordNode(recordFields) => {
          val ids = recordFields.keys().mapBy(key => childId(nodeIds, recordFields.get(key)))
          if (ids.keys().forall(key => validText(key) and ids.get(key) != invalidNodeId)) CanonicalRecord(ids)
          else CanonicalUnusable
        }
      | SetNode(elements) => {
          val ids = elements.foldl(Set(), (seen, element) => seen.union(Set(childId(nodeIds, element))))
          if (ids.contains(invalidNodeId)) CanonicalUnusable else CanonicalSet(ids)
        }
      | MapNode(entries) => {
          val ids = entries.foldl(Map(), (bindings, entry) =>
            bindings.put(childId(nodeIds, entry._1), childId(nodeIds, entry._2)))
          // Even identical bindings are invalid when the input repeats a key.
          val valid = ids.keys().size() == entries.length() and
            ids.keys().forall(key => key != invalidNodeId and ids.get(key) != invalidNodeId)
          if (valid) CanonicalMap(ids) else CanonicalUnusable
        }
      | UnusableNode => CanonicalUnusable
    }

  pure def intern(state: Canonicalization, node: ValueNode): Canonicalization = {
    val shape = canonicalShape(state.nodeIds, node)
    if (shape == CanonicalUnusable) { ...state, nodeIds: state.nodeIds.append(invalidNodeId) }
    else if (state.pool.ids.keys().contains(shape)) {
      ...state,
      nodeIds: state.nodeIds.append(state.pool.ids.get(shape)),
    }
    else {
      pool: { ids: state.pool.ids.put(shape, state.pool.nextId), nextId: state.pool.nextId + 1 },
      nodeIds: state.nodeIds.append(state.pool.nextId),
    }
  }

  // Only the selected root needs to be usable. Unusable nodes reached from
  // that root invalidate their parents as the fold processes them.
  pure def canonicalize(
    value: ItfValue, pool: NodePool
  ): { pool: NodePool, root: NodeId, nodeIds: List[NodeId] } =
    if (value.root < 0 or value.root >= value.nodes.length())
      { pool: pool, root: invalidNodeId, nodeIds: List() }
    else {
      val initial: Canonicalization = { pool: pool, nodeIds: List() }
      val result = value.nodes.slice(0, value.root + 1).foldl(initial, intern)
      { pool: result.pool, root: result.nodeIds.nth(value.root), nodeIds: result.nodeIds }
    }

  pure def isUsable(value: ItfValue): bool =
    canonicalize(value, emptyNodePool).root != invalidNodeId

  pure def uniqueSetChildren(children: List[NodeId], nodeIds: List[NodeId]): List[NodeId] =
    children.foldl({ seen: Set(), kept: List() }, (acc, child) => {
      val id = nodeIds.nth(child)
      if (acc.seen.contains(id)) acc
      else { seen: acc.seen.union(Set(id)), kept: acc.kept.append(child) }
    }).kept

  pure def normalizedNode(node: ValueNode, nodeIds: List[NodeId]): ValueNode =
    match node {
      | IntegerNode(number) => IntegerNode(normalizeDecimal(number))
      | SetNode(children) => SetNode(uniqueSetChildren(children, nodeIds))
      | _ => node
    }

  type ObservableValue = InvalidObservableValue | NormalizedObservableValue(ItfValue)

  // Preserve node references. Keep the first representative of each equivalent set element.
  pure def prepareObservableValue(value: ItfValue): ObservableValue = {
    val canonical = canonicalize(value, emptyNodePool)
    if (canonical.root == invalidNodeId) InvalidObservableValue
    else {
      val nodes = range(0, value.root + 1).foldl(value.nodes, (acc, index) =>
        if (canonical.nodeIds.nth(index) == invalidNodeId) acc
        else {
          val node = value.nodes.nth(index)
          val normalized = normalizedNode(node, canonical.nodeIds)
          if (node == normalized) acc else acc.replaceAt(index, normalized)
        }
      )
      NormalizedObservableValue({ ...value, nodes: nodes })
    }
  }

  pure def normalizeObservableValue(value: ItfValue): ItfValue =
    match prepareObservableValue(value) {
      | NormalizedObservableValue(normalized) => normalized
      | InvalidObservableValue => value
    }

  pure def equalValues(left: ItfValue, right: ItfValue): bool = {
    val leftResult = canonicalize(left, emptyNodePool)
    if (leftResult.root == invalidNodeId) false
    else canonicalize(right, leftResult.pool).root == leftResult.root
  }
}
