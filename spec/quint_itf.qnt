// The input is the lossless JSON syntax tree, with children before parents.
// String tokens supply the opaque spelling and its Unicode code points from lexing.
module quint_itf {
  import quint_values.* from "./quint_values"
  import quint_json as json from "./quint_json"

  type RawNode =
    | RawBoolean(bool)
    | RawText({ spelling: str, codePoints: List[int] })
    | RawNumber
    | RawNull
    | RawArray(List[NodeId])
    | RawObject(List[(str, NodeId)])

  type ItfDocument = {
    nodes: List[RawNode],
    root: NodeId,
  }

  type Selection = {
    actionPath: List[str],
    statePath: List[str],
  }

  type DecodedStep = {
    name: str,
    arguments: str -> ItfValue,
    expected: ItfValue,
  }

  type StepProblem =
    | StateNotRecord
    | MissingDeclaredVariable
    | InvalidOperation
    | InvalidArgument
    | InvalidExpectedValue

  type ItfError =
    | InvalidJsonTree
    | InvalidEnvelope
    | AtState({ index: int, problem: StepProblem })

  type DecodeResult =
    | DecodedTrace(List[DecodedStep])
    | NoStates
    | InvalidTrace(ItfError)

  type RawRef = MissingRef | FoundRef(NodeId)
  type RawFields = NotObject | Fields(str -> NodeId)
  type RawItems = NotArray | Items(List[NodeId])
  type RawName = NotText | Name(str)
  type DecimalText = NotDecimal | ReadDecimal(Decimal)
  type Argument = OmitArgument | TakeArgument(NodeId)

  pure val mbtAction: str = "mbt::actionTaken"
  pure val mbtPicks: str = "mbt::nondetPicks"
  pure val reservedValueTags: Set[str] = Set("#bigint", "#tup", "#set", "#map", "#unserializable")

  pure def rawAt(document: ItfDocument, id: NodeId): RawNode =
    if (document.nodes.indices().contains(id)) document.nodes.nth(id) else RawNull

  pure def objectFields(entries: List[(str, NodeId)]): str -> NodeId =
    entries.foldl(Map(), (members, entry) => members.put(entry._1, entry._2))

  pure def childrenBefore(ids: List[NodeId], parent: NodeId): bool =
    ids.indices().forall(i => 0 <= ids.nth(i) and ids.nth(i) < parent)

  pure def rawNodeIsWellFormed(node: RawNode, index: NodeId): bool =
    match node {
      | RawText(text) =>
        text.codePoints.indices().forall(i =>
          0 <= text.codePoints.nth(i) and text.codePoints.nth(i) <= 1114111
        )
      | RawArray(ids) => childrenBefore(ids, index)
      | RawObject(entries) =>
        objectFields(entries).keys().size() == entries.length() and
          entries.indices().forall(i => 0 <= entries.nth(i)._2 and entries.nth(i)._2 < index)
      | _ => true
    }

  pure def rawTreeIsWellFormed(document: ItfDocument): bool =
    document.nodes.indices().contains(document.root) and
      document.nodes.indices().forall(i => rawNodeIsWellFormed(document.nodes.nth(i), i))

  pure def fieldsAt(document: ItfDocument, id: NodeId): RawFields =
    match rawAt(document, id) {
      | RawObject(entries) => Fields(objectFields(entries))
      | _ => NotObject
    }

  pure def recordFieldsAt(document: ItfDocument, id: NodeId): RawFields =
    match fieldsAt(document, id) {
      | Fields(members) =>
        if (members.keys().intersect(reservedValueTags).size() == 0) Fields(members) else NotObject
      | NotObject => NotObject
    }

  pure def fieldAt(members: str -> NodeId, key: str): RawRef =
    if (members.keys().contains(key)) FoundRef(members.get(key)) else MissingRef

  pure def arrayAt(document: ItfDocument, target: RawRef): RawItems =
    match target {
      | FoundRef(id) =>
        match rawAt(document, id) {
          | RawArray(ids) => Items(ids)
          | _ => NotArray
        }
      | MissingRef => NotArray
    }

  pure def textAt(document: ItfDocument, target: RawRef): RawName =
    match target {
      | FoundRef(id) =>
        match rawAt(document, id) {
          | RawText(text) => Name(text.spelling)
          | _ => NotText
        }
      | MissingRef => NotText
    }

  pure def tupleAt(document: ItfDocument, id: NodeId): RawItems =
    match fieldsAt(document, id) {
      | Fields(members) =>
        if (members.keys() == Set("#tup")) arrayAt(document, fieldAt(members, "#tup")) else NotArray
      | NotObject => NotArray
    }

  pure def isEmptyTuple(document: ItfDocument, id: NodeId): bool =
    tupleAt(document, id) == Items(List())

  pure def pairAt(document: ItfDocument, id: NodeId): RawItems =
    match rawAt(document, id) {
      | RawArray(ids) => if (ids.length() == 2) Items(ids) else NotArray
      | _ => NotArray
    }

  pure def asMapNode(document: ItfDocument, pairs: List[NodeId]): ValueNode =
    if (pairs.indices().forall(i => pairAt(document, pairs.nth(i)) != NotArray))
      MapNode(pairs.foldl(List(), (acc, id) =>
        match pairAt(document, id) {
          | Items(ids) => acc.append((ids.nth(0), ids.nth(1)))
          | NotArray => acc
        }
      ))
    else
      UnusableNode

  pure def decimalFromCodePoints(codePoints: List[int]): DecimalText =
    if (codePoints.length() == 0) NotDecimal
    else {
      val negative = codePoints.head() == 45
      val start = if (negative) 1 else 0
      val digits = codePoints.slice(start, codePoints.length()).foldl(List(), (acc, symbol) =>
        acc.append(symbol - 48)
      )
      val number = { negative: negative, digits: digits }
      if (validDecimal(number)) ReadDecimal(number) else NotDecimal
    }

  pure def asIntegerNode(document: ItfDocument, target: RawRef): ValueNode =
    match target {
      | FoundRef(id) =>
        match rawAt(document, id) {
          | RawText(text) =>
            match decimalFromCodePoints(text.codePoints) {
              | NotDecimal => UnusableNode
              | ReadDecimal(number) => IntegerNode(number)
            }
          | _ => UnusableNode
        }
      | MissingRef => UnusableNode
    }

  pure def asObjectNode(document: ItfDocument, members: str -> NodeId): ValueNode = {
    val memberNames = members.keys()
    if (Set("#bigint") == memberNames)
      asIntegerNode(document, fieldAt(members, "#bigint"))
    else if (Set("#tup") == memberNames)
      match arrayAt(document, fieldAt(members, "#tup")) {
        | Items(ids) => TupleNode(ids)
        | NotArray => UnusableNode
      }
    else if (Set("#set") == memberNames)
      match arrayAt(document, fieldAt(members, "#set")) {
        | Items(ids) => SetNode(ids)
        | NotArray => UnusableNode
      }
    else if (Set("#map") == memberNames)
      match arrayAt(document, fieldAt(members, "#map")) {
        | Items(ids) => asMapNode(document, ids)
        | NotArray => UnusableNode
      }
    else if (memberNames.intersect(reservedValueTags).size() == 0)
      RecordNode(members)
    else
      UnusableNode
  }

  pure def asValueNode(document: ItfDocument, node: RawNode): ValueNode =
    match node {
      | RawBoolean(value) => BooleanNode(value)
      | RawText(text) => TextNode(text.spelling)
      | RawArray(ids) => ListNode(ids)
      | RawObject(entries) => asObjectNode(document, objectFields(entries))
      | _ => UnusableNode
    }

  pure def valueNodes(document: ItfDocument): List[ValueNode] =
    document.nodes.foldl(List(), (acc, node) => acc.append(asValueNode(document, node)))

  pure def pickPath(document: ItfDocument, start: NodeId, path: List[str]): RawRef =
    path.foldl(FoundRef(start), (position, key) =>
      match position {
        | FoundRef(id) =>
          match recordFieldsAt(document, id) {
            | Fields(members) => fieldAt(members, key)
            | NotObject => MissingRef
          }
        | MissingRef => MissingRef
      }
    )

  type OperationInput = NoOperation | OperationFound({ name: str, members: str -> NodeId })
  type DecodedArguments = BadArguments | Arguments(str -> ItfValue)
  type StepResult = StepDecoded(DecodedStep) | StepRejected(StepProblem)
  type Variables = BadVariables | DeclaredVariables(Set[str])

  pure def chosenOperation(name: RawName, payload: RawFields): OperationInput =
    match name {
      | Name(text) =>
        match payload {
          | Fields(members) => if (text == "") NoOperation else OperationFound({ name: text, members: members })
          | NotObject => NoOperation
        }
      | NotText => NoOperation
    }

  pure def operationPayload(document: ItfDocument, payload: RawRef): RawFields =
    match payload {
      | FoundRef(id) =>
        if (isEmptyTuple(document, id)) Fields(Map()) else recordFieldsAt(document, id)
      | MissingRef => NotObject
    }

  pure def explicitOperation(document: ItfDocument, target: RawRef): OperationInput =
    match target {
      | FoundRef(id) =>
        match fieldsAt(document, id) {
          | Fields(members) =>
            if (members.keys() == Set("tag", "value"))
              chosenOperation(
                textAt(document, fieldAt(members, "tag")),
                operationPayload(document, fieldAt(members, "value"))
              )
            else NoOperation
          | NotObject => NoOperation
        }
      | MissingRef => NoOperation
    }

  pure def mbtOperation(document: ItfDocument, members: str -> NodeId): OperationInput =
    match fieldAt(members, mbtPicks) {
      | FoundRef(id) => chosenOperation(textAt(document, fieldAt(members, mbtAction)), recordFieldsAt(document, id))
      | MissingRef => NoOperation
    }

  pure def argumentAt(document: ItfDocument, id: NodeId): Argument =
    match fieldsAt(document, id) {
      | Fields(members) =>
        if (members.keys() == Set("tag", "value")) {
          val tag = textAt(document, fieldAt(members, "tag"))
          val payload = members.get("value")
          if (tag == Name("Some")) TakeArgument(payload)
          else if (tag == Name("None") and isEmptyTuple(document, payload)) OmitArgument
          else TakeArgument(id)
        } else TakeArgument(id)
      | NotObject => TakeArgument(id)
    }

  pure def decodeArguments(
    document: ItfDocument, nodes: List[ValueNode], members: str -> NodeId
  ): DecodedArguments =
    members.keys().fold(Arguments(Map()), (result, key) =>
      match result {
        | BadArguments => BadArguments
        | Arguments(values) =>
          match argumentAt(document, members.get(key)) {
            | OmitArgument => Arguments(values)
            | TakeArgument(id) => {
              val decoded = { nodes: nodes, root: id }
              if (isUsable(decoded)) Arguments(values.put(key, decoded)) else BadArguments
            }
          }
      }
    )

  pure def expectedValue(
    document: ItfDocument, nodes: List[ValueNode], id: NodeId, members: str -> NodeId, path: List[str]
  ): ItfValue =
    if (path.length() == 0) {
      val modelVariables = members.keys().exclude(Set("#meta", mbtAction, mbtPicks))
      { nodes: nodes.append(RecordNode(modelVariables.mapBy(key => members.get(key)))), root: nodes.length() }
    } else
      match pickPath(document, id, path) {
        | FoundRef(position) => { nodes: nodes, root: position }
        | MissingRef => { nodes: nodes, root: -1 }
      }

  pure def decodeStep(
    document: ItfDocument, nodes: List[ValueNode], selection: Selection, required: Set[str], id: NodeId
  ): StepResult =
    match fieldsAt(document, id) {
      | NotObject => StepRejected(StateNotRecord)
      | Fields(members) =>
        if (not(required.subseteq(members.keys()))) StepRejected(MissingDeclaredVariable)
        else {
          val input =
            if (selection.actionPath.length() == 0) mbtOperation(document, members)
            else explicitOperation(document, pickPath(document, id, selection.actionPath))
          match input {
            | NoOperation => StepRejected(InvalidOperation)
            | OperationFound(operation) =>
              match decodeArguments(document, nodes, operation.members) {
                | BadArguments => StepRejected(InvalidArgument)
                | Arguments(arguments) => {
                  val expected = expectedValue(document, nodes, id, members, selection.statePath)
                  if (isUsable(expected))
                    StepDecoded({ name: operation.name, arguments: arguments, expected: expected })
                  else
                    StepRejected(InvalidExpectedValue)
                }
              }
          }
        }
    }

  pure def variablesFrom(document: ItfDocument, target: RawRef): Variables =
    match arrayAt(document, target) {
      | NotArray => BadVariables
      | Items(ids) =>
        ids.foldl(DeclaredVariables(Set()), (result, id) =>
          match result {
            | BadVariables => BadVariables
            | DeclaredVariables(variables) =>
              match textAt(document, FoundRef(id)) {
                | Name(text) => DeclaredVariables(variables.union(Set(text)))
                | NotText => BadVariables
              }
          }
        )
    }

  pure def decodeStates(
    document: ItfDocument, selection: Selection, variables: Set[str], states: List[NodeId]
  ): DecodeResult =
    if (states.length() == 0) NoStates
    else {
      val nodes = valueNodes(document)
      range(0, states.length()).foldl(DecodedTrace(List()), (result, index) =>
        match result {
          | DecodedTrace(steps) =>
            match decodeStep(document, nodes, selection, variables, states.nth(index)) {
              | StepDecoded(decoded) => DecodedTrace(steps.append(decoded))
              | StepRejected(problem) => InvalidTrace(AtState({ index: index, problem: problem }))
            }
          | _ => result
        }
      )
    }

  pure def decodeEnvelope(document: ItfDocument, selection: Selection, members: str -> NodeId): DecodeResult =
    if (members.keys().contains("loop")) InvalidTrace(InvalidEnvelope)
    else
      match variablesFrom(document, fieldAt(members, "vars")) {
        | BadVariables => InvalidTrace(InvalidEnvelope)
        | DeclaredVariables(variables) =>
          match arrayAt(document, fieldAt(members, "states")) {
            | NotArray => InvalidTrace(InvalidEnvelope)
            | Items(states) => decodeStates(document, selection, variables, states)
          }
      }

  pure def decodeItf(document: ItfDocument, selection: Selection): DecodeResult =
    if (not(rawTreeIsWellFormed(document))) InvalidTrace(InvalidJsonTree)
    else
      match fieldsAt(document, document.root) {
        | NotObject => InvalidTrace(InvalidEnvelope)
        | Fields(members) => decodeEnvelope(document, selection, members)
      }

  // Quint strings are opaque. An instance names each decoded code-point sequence
  // with its corresponding string; the finite map includes its fixture vocabulary.
  type TextLabels = List[int] -> str

  type ItfByteInput =
    | ByteInputInvalidUtf8
    | ByteInputInvalidJson
    | ByteInputUnlabeledText
    | ByteInputParsed(ItfDocument)

  pure def neededLabels(document: json::JsonDocument): Set[List[int]] =
    document.nodes.foldl(Set(), (needed, node) =>
      match node {
        | JsonString(points) => needed.union(Set(points))
        | JsonObject(entries) => entries.foldl(needed, (acc, entry) => acc.union(Set(entry._1)))
        | _ => needed
      }
    )

  pure def jsonToRaw(node: json::JsonNode, names: TextLabels): RawNode =
    match node {
      | JsonBoolean(value) => RawBoolean(value)
      | JsonString(points) => RawText({ spelling: names.get(points), codePoints: points })
      | JsonNumber => RawNumber
      | JsonNull => RawNull
      | JsonArray(ids) => RawArray(ids)
      | JsonObject(entries) =>
        RawObject(entries.foldl(List(), (acc, entry) => acc.append((names.get(entry._1), entry._2))))
    }

  pure def parseItfBytes(bytes: List[int], names: TextLabels): ItfByteInput =
    match json::parseJson(bytes) {
      | InvalidUtf8 => ByteInputInvalidUtf8
      | InvalidJsonSyntax => ByteInputInvalidJson
      | ParsedJson(document) => {
        val needed = neededLabels(document)
        if (not(needed.subseteq(names.keys())))
          ByteInputUnlabeledText
        else if (needed.map(points => names.get(points)).size() != needed.size())
          ByteInputUnlabeledText
        else
          ByteInputParsed({
            root: document.root,
            nodes: document.nodes.foldl(List(), (acc, node) => acc.append(jsonToRaw(node, names))),
          })
      }
    }
}
