module quint_values {
  type NodeId = int
  type Decimal = { negative: bool, digits: List[int] }
  type ValueNode =
    | BooleanNode(bool)
    | IntegerNode(Decimal)
    | TextNode(str)
    | ListNode(List[NodeId])
    | TupleNode(List[NodeId])
    | RecordNode(str -> NodeId)
    | SetNode(List[NodeId])
    | MapNode(List[(NodeId, NodeId)])
    | UnusableNode

  type ItfValue = { nodes: List[ValueNode], root: NodeId }

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
    { negative: number.negative and digits.length() > 0, digits: digits }
  }

  // Children of canonical nodes use IDs from one shared pool. The tags
  // distinguish types even when their children or primitive contents agree.
  type CanonicalNode =
    | CanonicalBoolean(bool)
    | CanonicalInteger(Decimal)
    | CanonicalText(str)
    | CanonicalList(List[NodeId])
    | CanonicalTuple(List[NodeId])
    | CanonicalRecord(str -> NodeId)
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
      | TextNode(value) => CanonicalText(value)
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
          if (ids.keys().forall(key => ids.get(key) != invalidNodeId)) CanonicalRecord(ids)
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
  pure def canonicalize(value: ItfValue, pool: NodePool): { pool: NodePool, root: NodeId } =
    if (value.root < 0 or value.root >= value.nodes.length()) { pool: pool, root: invalidNodeId }
    else {
      val initial: Canonicalization = { pool: pool, nodeIds: List() }
      val result = value.nodes.slice(0, value.root + 1).foldl(initial, intern)
      { pool: result.pool, root: result.nodeIds.nth(value.root) }
    }

  pure def isUsable(value: ItfValue): bool =
    canonicalize(value, emptyNodePool).root != invalidNodeId

  pure def equalValues(left: ItfValue, right: ItfValue): bool = {
    val leftResult = canonicalize(left, emptyNodePool)
    if (leftResult.root == invalidNodeId) false
    else canonicalize(right, leftResult.pool).root == leftResult.root
  }
}
