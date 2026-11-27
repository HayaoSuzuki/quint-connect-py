// JSON names and strings contain Unicode scalar values. Object entries retain source order
// and multiplicity for ITF validation. Number nodes record syntax without converting magnitude.
// The node list is in child-before-parent order. A leading BOM and unpaired UTF-16 escapes
// are syntax errors for ITF input.
module quint_json {
  type JsonNode =
    | JsonBoolean(bool)
    | JsonString(List[int])
    | JsonNumber
    | JsonNull
    | JsonArray(List[int])
    | JsonObject(List[(List[int], int)])

  type JsonDocument = { nodes: List[JsonNode], root: int }
  type JsonResult = ParsedJson(JsonDocument) | InvalidUtf8 | InvalidJsonSyntax

  type Utf8Progress =
    | Utf8Decoded(List[int])
    | Utf8Pending({ points: List[int], remaining: int, minimum: int, scalar: int })
    | Utf8Failed

  pure def isHighSurrogate(point: int): bool = 0xD800 <= point and point <= 0xDBFF
  pure def isLowSurrogate(point: int): bool = 0xDC00 <= point and point <= 0xDFFF

  pure def nextUtf8(progress: Utf8Progress, byte: int): Utf8Progress =
    match progress {
      | Utf8Failed => Utf8Failed
      | Utf8Decoded(points) =>
        if (0 <= byte and byte <= 0x7F)
          Utf8Decoded(points.append(byte))
        else if (0xC2 <= byte and byte <= 0xDF)
          Utf8Pending({ points: points, remaining: 1, minimum: 0x80, scalar: byte - 0xC0 })
        else if (0xE0 <= byte and byte <= 0xEF)
          Utf8Pending({ points: points, remaining: 2, minimum: 0x800, scalar: byte - 0xE0 })
        else if (0xF0 <= byte and byte <= 0xF4)
          Utf8Pending({ points: points, remaining: 3, minimum: 0x10000, scalar: byte - 0xF0 })
        else
          Utf8Failed
      | Utf8Pending(pending) =>
        if (byte < 0x80 or byte > 0xBF) Utf8Failed
        else {
          val scalar = 64 * pending.scalar + byte - 0x80
          if (pending.remaining > 1)
            Utf8Pending({ ...pending, remaining: pending.remaining - 1, scalar: scalar })
          else if (pending.minimum <= scalar and scalar <= 0x10FFFF and
                   not(isHighSurrogate(scalar) or isLowSurrogate(scalar)))
            Utf8Decoded(pending.points.append(scalar))
          else
            Utf8Failed
        }
    }

  type JsonToken =
    | OpenArray
    | CloseArray
    | OpenObject
    | CloseObject
    | CommaToken
    | ColonToken
    | StringToken(List[int])
    | AtomToken(JsonNode)

  type NumberPhase =
    | AfterMinus
    | AfterZero
    | IntegerDigits
    | AfterPoint
    | FractionDigits
    | AfterExponent
    | AfterExponentSign
    | ExponentDigits

  type NumberStep = NumberContinues(NumberPhase) | NumberEnds | NumberFails

  pure def digit(point: int): bool = 48 <= point and point <= 57

  pure def numberCanEnd(phase: NumberPhase): bool =
    Set(AfterZero, IntegerDigits, FractionDigits, ExponentDigits).contains(phase)

  pure def nextNumber(phase: NumberPhase, point: int): NumberStep =
    if (digit(point))
      match phase {
        | AfterMinus => NumberContinues(if (point == 48) AfterZero else IntegerDigits)
        | AfterZero => NumberFails
        | IntegerDigits => NumberContinues(IntegerDigits)
        | AfterPoint => NumberContinues(FractionDigits)
        | FractionDigits => NumberContinues(FractionDigits)
        | _ => NumberContinues(ExponentDigits)
      }
    else if (point == 46 and Set(AfterZero, IntegerDigits).contains(phase))
      NumberContinues(AfterPoint)
    else if (Set(69, 101).contains(point) and Set(AfterZero, IntegerDigits, FractionDigits).contains(phase))
      NumberContinues(AfterExponent)
    else if (Set(43, 45).contains(point) and phase == AfterExponent)
      NumberContinues(AfterExponentSign)
    else if (numberCanEnd(phase))
      NumberEnds
    else
      NumberFails

  type JsonEscape = Escape({ point: int, width: int }) | BadEscape

  pure def pointAt(points: List[int], index: int): int =
    if (0 <= index and index < points.length()) points.nth(index) else -1

  pure def hexDigit(point: int): int =
    if (digit(point)) point - 48
    else if (65 <= point and point <= 70) point - 55
    else if (97 <= point and point <= 102) point - 87
    else -1

  pure def hexUnitAt(points: List[int], start: int): int =
    range(start, start + 4).foldl(0, (unit, index) => {
      val hex = hexDigit(pointAt(points, index))
      if (unit < 0 or hex < 0) -1 else 16 * unit + hex
    })

  pure val shortEscapes: int -> int = Map(
    34 -> 34, 47 -> 47, 92 -> 92, 98 -> 8, 102 -> 12, 110 -> 10, 114 -> 13, 116 -> 9
  )

  pure def readEscape(points: List[int], index: int): JsonEscape = {
    val escaped = pointAt(points, index + 1)
    if (shortEscapes.keys().contains(escaped))
      Escape({ point: shortEscapes.get(escaped), width: 2 })
    else if (escaped != 117)
      BadEscape
    else {
      val first = hexUnitAt(points, index + 2)
      if (first < 0 or isLowSurrogate(first))
        BadEscape
      else if (not(isHighSurrogate(first)))
        Escape({ point: first, width: 6 })
      else if (pointAt(points, index + 6) == 92 and pointAt(points, index + 7) == 117) {
        val second = hexUnitAt(points, index + 8)
        if (isLowSurrogate(second))
          Escape({ point: 0x10000 + 1024 * (first - 0xD800) + second - 0xDC00, width: 12 })
        else
          BadEscape
      } else
        BadEscape
    }
  }

  type LexPhase = BetweenTokens | InString(List[int]) | InNumber(NumberPhase) | LexFailed
  // The cursor skips code points consumed together by a literal or escape.
  type Lexer = { phase: LexPhase, tokens: List[JsonToken], cursor: int }

  pure val punctuation: int -> JsonToken =
    Map(91 -> OpenArray, 93 -> CloseArray, 123 -> OpenObject, 125 -> CloseObject, 44 -> CommaToken, 58 -> ColonToken)

  pure val literals: int -> (List[int], JsonNode) = Map(
    116 -> (List(116, 114, 117, 101), JsonBoolean(true)),
    102 -> (List(102, 97, 108, 115, 101), JsonBoolean(false)),
    110 -> (List(110, 117, 108, 108), JsonNull),
  )

  pure def emitToken(lexer: Lexer, token: JsonToken): Lexer =
    { ...lexer, phase: BetweenTokens, tokens: lexer.tokens.append(token) }

  pure def beginToken(lexer: Lexer, points: List[int], index: int, point: int): Lexer =
    if (Set(9, 10, 13, 32).contains(point))
      lexer
    else if (punctuation.keys().contains(point))
      emitToken(lexer, punctuation.get(point))
    else if (point == 34)
      { ...lexer, phase: InString(List()) }
    else if (point == 45)
      { ...lexer, phase: InNumber(AfterMinus) }
    else if (digit(point))
      { ...lexer, phase: InNumber(if (point == 48) AfterZero else IntegerDigits) }
    else if (literals.keys().contains(point)) {
      val literal = literals.get(point)
      val end = index + literal._1.length()
      if (end <= points.length()) {
        if (points.slice(index, end) == literal._1)
          { ...emitToken(lexer, AtomToken(literal._2)), cursor: end }
        else
          { ...lexer, phase: LexFailed }
      } else
        { ...lexer, phase: LexFailed }
    } else
      { ...lexer, phase: LexFailed }

  pure def nextToken(lexer: Lexer, points: List[int], index: int): Lexer =
    if (index < lexer.cursor) lexer
    else {
      val point = points.nth(index)
      match lexer.phase {
        | BetweenTokens => beginToken(lexer, points, index, point)
        | InString(text) =>
          if (point == 34)
            emitToken(lexer, StringToken(text))
          else if (point == 92)
            match readEscape(points, index) {
              | Escape(escape) =>
                { ...lexer, phase: InString(text.append(escape.point)), cursor: index + escape.width }
              | BadEscape => { ...lexer, phase: LexFailed }
            }
          else if (point < 32)
            { ...lexer, phase: LexFailed }
          else
            { ...lexer, phase: InString(text.append(point)) }
        | InNumber(phase) =>
          match nextNumber(phase, point) {
            | NumberContinues(nextPhase) => { ...lexer, phase: InNumber(nextPhase) }
            | NumberEnds => beginToken(emitToken(lexer, AtomToken(JsonNumber)), points, index, point)
            | NumberFails => { ...lexer, phase: LexFailed }
          }
        | LexFailed => lexer
      }
    }

  type ArrayPhase = FirstArrayItem | ArrayItem | AfterArrayItem
  type ObjectPhase = FirstObjectKey | ObjectKey | BeforeColon(List[int]) | MemberValue(List[int]) | AfterMember
  type ArrayBody = { phase: ArrayPhase, items: List[int] }
  type ObjectBody = { phase: ObjectPhase, members: List[(List[int], int)] }
  type Frame = ArrayFrame(ArrayBody) | ObjectFrame(ObjectBody)
  // The innermost open container is first. A completed container becomes a child of its parent.
  type Parser = { document: JsonDocument, frames: List[Frame] }
  type ParseProgress = Parsing(Parser) | ParseFailed

  pure def replaceFrame(parser: Parser, frame: Frame): Parser =
    { ...parser, frames: parser.frames.replaceAt(0, frame) }

  pure def storeNode(parser: Parser, node: JsonNode): ParseProgress = {
    val id = parser.document.nodes.length()
    val nodes = parser.document.nodes.append(node)
    if (parser.frames.length() == 0)
      Parsing({ ...parser, document: { nodes: nodes, root: id } })
    else {
      val active = { ...parser, document: { ...parser.document, nodes: nodes } }
      match parser.frames.head() {
        | ArrayFrame(body) =>
          Parsing(replaceFrame(active, ArrayFrame({ phase: AfterArrayItem, items: body.items.append(id) })))
        | ObjectFrame(body) =>
          match body.phase {
            | MemberValue(name) =>
              Parsing(replaceFrame(active,
                ObjectFrame({ phase: AfterMember, members: body.members.append((name, id)) })))
            | _ => ParseFailed
          }
      }
    }
  }

  pure def closeFrame(parser: Parser, node: JsonNode): ParseProgress =
    storeNode({ ...parser, frames: parser.frames.tail() }, node)

  pure def startValue(parser: Parser, token: JsonToken): ParseProgress =
    match token {
      | OpenArray =>
        Parsing({ ...parser, frames: List(ArrayFrame({ phase: FirstArrayItem, items: List() })).concat(parser.frames) })
      | OpenObject =>
        Parsing({ ...parser, frames: List(ObjectFrame({ phase: FirstObjectKey, members: List() })).concat(parser.frames) })
      | StringToken(text) => storeNode(parser, JsonString(text))
      | AtomToken(node) => storeNode(parser, node)
      | _ => ParseFailed
    }

  pure def parseArray(parser: Parser, body: ArrayBody, token: JsonToken): ParseProgress =
    match body.phase {
      | FirstArrayItem =>
        if (token == CloseArray) closeFrame(parser, JsonArray(body.items)) else startValue(parser, token)
      | ArrayItem => startValue(parser, token)
      | AfterArrayItem =>
        if (token == CloseArray)
          closeFrame(parser, JsonArray(body.items))
        else if (token == CommaToken)
          Parsing(replaceFrame(parser, ArrayFrame({ ...body, phase: ArrayItem })))
        else
          ParseFailed
    }

  pure def parseObjectKey(parser: Parser, body: ObjectBody, token: JsonToken): ParseProgress =
    match token {
      | StringToken(name) => Parsing(replaceFrame(parser, ObjectFrame({ ...body, phase: BeforeColon(name) })))
      | _ => ParseFailed
    }

  pure def parseObject(parser: Parser, body: ObjectBody, token: JsonToken): ParseProgress =
    match body.phase {
      | FirstObjectKey =>
        if (token == CloseObject) closeFrame(parser, JsonObject(body.members)) else parseObjectKey(parser, body, token)
      | ObjectKey => parseObjectKey(parser, body, token)
      | BeforeColon(name) =>
        if (token == ColonToken)
          Parsing(replaceFrame(parser, ObjectFrame({ ...body, phase: MemberValue(name) })))
        else
          ParseFailed
      | MemberValue(_) => startValue(parser, token)
      | AfterMember =>
        if (token == CloseObject)
          closeFrame(parser, JsonObject(body.members))
        else if (token == CommaToken)
          Parsing(replaceFrame(parser, ObjectFrame({ ...body, phase: ObjectKey })))
        else
          ParseFailed
    }

  pure def parseToken(progress: ParseProgress, token: JsonToken): ParseProgress =
    match progress {
      | Parsing(parser) =>
        if (parser.frames.length() == 0)
          if (parser.document.root == -1) startValue(parser, token) else ParseFailed
        else
          match parser.frames.head() {
            | ArrayFrame(body) => parseArray(parser, body, token)
            | ObjectFrame(body) => parseObject(parser, body, token)
          }
      | ParseFailed => ParseFailed
    }

  pure def parseTokens(tokens: List[JsonToken]): JsonResult = {
    val initial = Parsing({ document: { nodes: List(), root: -1 }, frames: List() })
    match tokens.foldl(initial, parseToken) {
      | Parsing(parser) =>
        if (parser.frames.length() == 0 and parser.document.root >= 0)
          ParsedJson(parser.document)
        else
          InvalidJsonSyntax
      | ParseFailed => InvalidJsonSyntax
    }
  }

  pure def parsePoints(points: List[int]): JsonResult = {
    val initial = { phase: BetweenTokens, tokens: List(), cursor: 0 }
    val lexer = range(0, points.length()).foldl(initial, (state, index) => nextToken(state, points, index))
    match lexer.phase {
      | BetweenTokens => parseTokens(lexer.tokens)
      | InNumber(phase) =>
        if (numberCanEnd(phase)) parseTokens(lexer.tokens.append(AtomToken(JsonNumber))) else InvalidJsonSyntax
      | _ => InvalidJsonSyntax
    }
  }

  pure def parseJson(bytes: List[int]): JsonResult =
    match bytes.foldl(Utf8Decoded(List()), nextUtf8) {
      | Utf8Decoded(points) => parsePoints(points)
      | _ => InvalidUtf8
    }
}
