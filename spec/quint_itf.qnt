// The input is the lossless JSON syntax tree, with children before parents.
// Object names and string tokens retain their decoded Unicode scalar values.
module quint_itf {
  import quint_values.* from "./quint_values"
  import quint_json as json from "./quint_json"

  type RawNode =
    | RawBoolean(bool)
    | RawText(Text)
    | RawNumber
    | RawNull
    | RawArray(List[NodeId])
    | RawObject(List[(Text, NodeId)])

  type ItfDocument = {
    nodes: List[RawNode],
    root: NodeId,
  }

  type Selection = {
    actionPath: List[Text],
    statePath: List[Text],
  }

  type DecodedStep = {
    name: Text,
    arguments: Text -> ItfValue,
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
  type RawFields = NotObject | Fields(Text -> NodeId)
  type RawItems = NotArray | Items(List[NodeId])
  type RawName = NotText | Name(Text)
  type DecimalText = NotDecimal | ReadDecimal(Decimal)
  type Argument = OmitArgument | TakeArgument(NodeId)

  // Names reserved by the ITF envelope, MBT metadata, and tagged values.
  pure val mbtAction: Text = List(109, 98, 116, 58, 58, 97, 99, 116, 105, 111, 110, 84, 97, 107, 101, 110)
  pure val mbtPicks: Text = List(109, 98, 116, 58, 58, 110, 111, 110, 100, 101, 116, 80, 105, 99, 107, 115)
  pure val bigintKey: Text = List(35, 98, 105, 103, 105, 110, 116)
  pure val tupleKey: Text = List(35, 116, 117, 112)
  pure val setKey: Text = List(35, 115, 101, 116)
  pure val mapKey: Text = List(35, 109, 97, 112)
  pure val unserializableKey: Text = List(35, 117, 110, 115, 101, 114, 105, 97, 108, 105, 122, 97, 98, 108, 101)
  pure val metadataKey: Text = List(35, 109, 101, 116, 97)
  pure val tagKey: Text = List(116, 97, 103)
  pure val valueKey: Text = List(118, 97, 108, 117, 101)
  pure val someTag: Text = List(83, 111, 109, 101)
  pure val noneTag: Text = List(78, 111, 110, 101)
  pure val loopKey: Text = List(108, 111, 111, 112)
  pure val varsKey: Text = List(118, 97, 114, 115)
  pure val statesKey: Text = List(115, 116, 97, 116, 101, 115)
  pure val reservedValueTags: Set[Text] = Set(bigintKey, tupleKey, setKey, mapKey, unserializableKey)

  pure def rawAt(document: ItfDocument, id: NodeId): RawNode =
    if (document.nodes.indices().contains(id)) document.nodes.nth(id) else RawNull

  pure def objectFields(entries: List[(Text, NodeId)]): Text -> NodeId =
    entries.foldl(Map(), (members, entry) => members.put(entry._1, entry._2))

  pure def childrenBefore(ids: List[NodeId], parent: NodeId): bool =
    ids.indices().forall(i => 0 <= ids.nth(i) and ids.nth(i) < parent)

  pure def rawNodeIsWellFormed(node: RawNode, index: NodeId): bool =
    match node {
      | RawText(text) => validText(text)
      | RawArray(ids) => childrenBefore(ids, index)
      | RawObject(entries) =>
        objectFields(entries).keys().size() == entries.length() and
          entries.indices().forall(i => {
            val entry = entries.nth(i)
            validText(entry._1) and 0 <= entry._2 and entry._2 < index
          })
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

  pure def fieldAt(members: Text -> NodeId, key: Text): RawRef =
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
          | RawText(text) => Name(text)
          | _ => NotText
        }
      | MissingRef => NotText
    }

  pure def tupleAt(document: ItfDocument, id: NodeId): RawItems =
    match fieldsAt(document, id) {
      | Fields(members) =>
        if (members.keys() == Set(tupleKey)) arrayAt(document, fieldAt(members, tupleKey)) else NotArray
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

  pure def decimalFromCodePoints(codePoints: Text): DecimalText =
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
            match decimalFromCodePoints(text) {
              | NotDecimal => UnusableNode
              | ReadDecimal(number) => IntegerNode(number)
            }
          | _ => UnusableNode
        }
      | MissingRef => UnusableNode
    }

  pure def asObjectNode(document: ItfDocument, members: Text -> NodeId): ValueNode = {
    val memberNames = members.keys()
    if (Set(bigintKey) == memberNames)
      asIntegerNode(document, fieldAt(members, bigintKey))
    else if (Set(tupleKey) == memberNames)
      match arrayAt(document, fieldAt(members, tupleKey)) {
        | Items(ids) => TupleNode(ids)
        | NotArray => UnusableNode
      }
    else if (Set(setKey) == memberNames)
      match arrayAt(document, fieldAt(members, setKey)) {
        | Items(ids) => SetNode(ids)
        | NotArray => UnusableNode
      }
    else if (Set(mapKey) == memberNames)
      match arrayAt(document, fieldAt(members, mapKey)) {
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
      | RawText(text) => TextNode(text)
      | RawArray(ids) => ListNode(ids)
      | RawObject(entries) => asObjectNode(document, objectFields(entries))
      | _ => UnusableNode
    }

  pure def valueNodes(document: ItfDocument): List[ValueNode] =
    document.nodes.foldl(List(), (acc, node) => acc.append(asValueNode(document, node)))

  pure def pickPath(document: ItfDocument, start: NodeId, path: List[Text]): RawRef =
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

  type OperationInput = NoOperation | OperationFound({ name: Text, members: Text -> NodeId })
  type DecodedArguments = BadArguments | Arguments(Text -> ItfValue)
  type StepResult = StepDecoded(DecodedStep) | StepRejected(StepProblem)
  type Variables = BadVariables | DeclaredVariables(Set[Text])

  pure def chosenOperation(name: RawName, payload: RawFields): OperationInput =
    match name {
      | Name(text) =>
        match payload {
          | Fields(members) =>
            OperationFound({ name: text, members: members })
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
            if (members.keys() == Set(tagKey, valueKey)) {
              val name = textAt(document, fieldAt(members, tagKey))
              if (name == Name(List())) NoOperation
              else chosenOperation(name, operationPayload(document, fieldAt(members, valueKey)))
            }
            else NoOperation
          | NotObject => NoOperation
        }
      | MissingRef => NoOperation
    }

  pure def mbtOperation(document: ItfDocument, members: Text -> NodeId): OperationInput =
    match fieldAt(members, mbtPicks) {
      | FoundRef(id) => chosenOperation(textAt(document, fieldAt(members, mbtAction)), recordFieldsAt(document, id))
      | MissingRef => NoOperation
    }

  pure def argumentAt(document: ItfDocument, id: NodeId): Argument =
    match fieldsAt(document, id) {
      | Fields(members) =>
        if (members.keys() == Set(tagKey, valueKey)) {
          val tag = textAt(document, fieldAt(members, tagKey))
          val payload = members.get(valueKey)
          if (tag == Name(someTag)) TakeArgument(payload)
          else if (tag == Name(noneTag) and isEmptyTuple(document, payload)) OmitArgument
          else TakeArgument(id)
        } else TakeArgument(id)
      | NotObject => TakeArgument(id)
    }

  pure def decodeArguments(
    document: ItfDocument, nodes: List[ValueNode], members: Text -> NodeId
  ): DecodedArguments =
    members.keys().fold(Arguments(Map()), (result, key) =>
      match result {
        | BadArguments => BadArguments
        | Arguments(values) =>
          match argumentAt(document, members.get(key)) {
            | OmitArgument => Arguments(values)
            | TakeArgument(id) =>
              match prepareObservableValue({ nodes: nodes, root: id }) {
                | NormalizedObservableValue(value) => Arguments(values.put(key, value))
                | InvalidObservableValue => BadArguments
              }
          }
      }
    )

  pure def expectedValue(
    document: ItfDocument, nodes: List[ValueNode], id: NodeId, members: Text -> NodeId, path: List[Text]
  ): ItfValue =
    if (path.length() == 0) {
      val modelVariables = members.keys().exclude(Set(metadataKey, mbtAction, mbtPicks))
      { nodes: nodes.append(RecordNode(modelVariables.mapBy(key => members.get(key)))), root: nodes.length() }
    } else
      match pickPath(document, id, path) {
        | FoundRef(position) => { nodes: nodes, root: position }
        | MissingRef => { nodes: nodes, root: -1 }
      }

  pure def decodeStep(
    document: ItfDocument, nodes: List[ValueNode], selection: Selection, required: Set[Text], id: NodeId
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
                | Arguments(arguments) =>
                  match prepareObservableValue(expectedValue(document, nodes, id, members, selection.statePath)) {
                    | NormalizedObservableValue(expected) =>
                      StepDecoded({ name: operation.name, arguments: arguments, expected: expected })
                    | InvalidObservableValue => StepRejected(InvalidExpectedValue)
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
    document: ItfDocument, selection: Selection, variables: Set[Text], states: List[NodeId]
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

  pure def decodeEnvelope(document: ItfDocument, selection: Selection, members: Text -> NodeId): DecodeResult =
    if (members.keys().contains(loopKey)) InvalidTrace(InvalidEnvelope)
    else
      match variablesFrom(document, fieldAt(members, varsKey)) {
        | BadVariables => InvalidTrace(InvalidEnvelope)
        | DeclaredVariables(variables) =>
          match arrayAt(document, fieldAt(members, statesKey)) {
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

  type ItfByteInput =
    | ByteInputInvalidUtf8
    | ByteInputInvalidJson
    | ByteInputParsed(ItfDocument)

  pure def jsonToRaw(node: json::JsonNode): RawNode =
    match node {
      | JsonBoolean(value) => RawBoolean(value)
      | JsonString(points) => RawText(points)
      | JsonNumber => RawNumber
      | JsonNull => RawNull
      | JsonArray(ids) => RawArray(ids)
      | JsonObject(entries) => RawObject(entries)
    }

  pure def parseItfBytes(bytes: List[int]): ItfByteInput =
    match json::parseJson(bytes) {
      | InvalidUtf8 => ByteInputInvalidUtf8
      | InvalidJsonSyntax => ByteInputInvalidJson
      | ParsedJson(document) =>
        ByteInputParsed({
          root: document.root,
          nodes: document.nodes.foldl(List(), (acc, node) => acc.append(jsonToRaw(node))),
        })
    }
}
