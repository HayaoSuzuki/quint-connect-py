module quint_json_test {
  import quint_json.* from "./quint_json"

  pure def singleNode(node: JsonNode): JsonResult =
    ParsedJson({ nodes: List(node), root: 0 })

  run utf8ScalarBoundariesTest =
    assert(parseJson(
      List(34, 194, 128, 223, 191, 224, 160, 128, 237, 159, 191, 238, 128, 128,
        239, 191, 191, 240, 144, 128, 128, 244, 143, 191, 191, 34)
    ) == singleNode(JsonString(List(128, 2047, 2048, 55295, 57344, 65535, 65536, 1114111))))

  run invalidUtf8PrecedesJsonSyntaxTest =
    assert(Set(
      List(-1), // Negative integer
      List(256), // Integer above the octet range
      List(128), // Stray continuation byte
      List(192, 175), // Overlong two-byte sequence
      List(194, 32), // Missing continuation byte
      List(224, 159, 191), // Overlong three-byte sequence
      List(237, 160, 128), // UTF-8 encoded surrogate
      List(239, 191), // Truncated three-byte sequence
      List(240, 143, 191, 191), // Overlong four-byte sequence
      List(244, 144, 128, 128), // Scalar above U+10FFFF
      List(245, 128, 128, 128), // Invalid start byte for a four-byte sequence
      List(255), // Invalid start byte
      List(91, 93, 32, 240, 144, 128), // Truncated UTF-8 after a complete JSON value
    ).forall(bytes => parseJson(bytes) == InvalidUtf8))

  run nestedValuesAndWhitespaceTest = {
    // { "a": [true, {}, null], "second": [false, []] }
    val bytes = List(32, 123, 9, 34, 97, 34, 58, 91, 116, 114, 117, 101, 44, 123, 125, 44,
      110, 117, 108, 108, 93, 44, 10, 34, 115, 101, 99, 111, 110, 100, 34, 58, 91,
      102, 97, 108, 115, 101, 44, 91, 93, 93, 125, 13)
    assert(parseJson(bytes) == ParsedJson({
      nodes: List(JsonBoolean(true), JsonObject(List()), JsonNull, JsonArray(List(0, 1, 2)),
        JsonBoolean(false), JsonArray(List()), JsonArray(List(4, 5)),
        JsonObject(List((List(97), 3), (List(115, 101, 99, 111, 110, 100), 6)))),
      root: 7,
    }))
  }

  run duplicateKeysRetainDecodedSpellingAndOrderTest = {
    // {"a":0,"\u0061":true}
    val bytes = List(123, 34, 97, 34, 58, 48, 44, 34, 92, 117, 48, 48, 54, 49, 34, 58, 116, 114, 117, 101, 125)
    assert(parseJson(bytes) == ParsedJson({
      nodes: List(JsonNumber, JsonBoolean(true), JsonObject(List((List(97), 0), (List(97), 1)))),
      root: 2,
    }))
  }

  run escapesDecodeToCodePointsTest = {
    // All short escapes, a NUL, a BMP escape with lower-case hex, and a surrogate pair.
    val bytes = List(34, 92, 34, 92, 92, 92, 47, 92, 98, 92, 102, 92, 110, 92, 114, 92, 116,
      92, 117, 48, 48, 48, 48, 92, 117, 48, 48, 54, 97, 92, 117, 68, 56, 51, 68,
      92, 117, 100, 101, 48, 48, 34)
    assert(and {
      parseJson(bytes) == singleNode(JsonString(List(34, 92, 47, 8, 12, 10, 13, 9, 0, 106, 128512))),
      parseJson(List(34, 92, 117, 68, 66, 102, 102, 92, 117, 68, 102, 70, 102, 34)) ==
        singleNode(JsonString(List(0x10FFFF))),
    })
  }

  run invalidStringSyntaxTest =
    assert(Set(
      List(34), // Missing closing quote
      List(34, 0, 34), // Raw NUL
      List(34, 10, 34), // Raw newline
      List(34, 31, 34), // Raw control character
      List(34, 92), // Truncated escape
      List(34, 92, 113, 34), // "\q"
      List(34, 92, 85, 48, 48, 54, 49, 34), // "\U0061"
      List(34, 92, 117, 49, 50, 51, 34), // "\u123"
      List(34, 92, 117, 48, 43, 48, 49, 34), // "\u0+01"
      List(34, 92, 117, 68, 67, 48, 48, 34), // "\uDC00"
      List(34, 92, 117, 68, 56, 48, 48, 34), // "\uD800"
      List(34, 92, 117, 68, 56, 48, 48, 120, 34), // "\uD800x"
      List(34, 92, 117, 68, 56, 48, 48, 92, 117, 49, 50, 51, 52, 34), // "\uD800\u1234"
      List(34, 92, 117, 68, 56, 48, 48, 92, 117, 68, 56, 48, 48, 34), // "\uD800\uD800"
    ).forall(bytes => parseJson(bytes) == InvalidJsonSyntax))

  run numberLexicalFormsTest =
    assert(Set(
      List(48), // 0
      List(45, 48), // -0
      List(55), // 7
      List(45, 52, 50), // -42
      List(48, 46, 48), // 0.0
      List(45, 53, 46, 48, 55, 48), // -5.070
      List(48, 101, 48), // 0e0
      List(51, 69, 43, 50), // 3E+2
      List(50, 46, 55, 53, 101, 45, 49, 50), // 2.75e-12
      List(49, 101, 49, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48), // 1e100000000000000000000
    ).forall(bytes => parseJson(bytes) == singleNode(JsonNumber)))

  run invalidNumberSyntaxTest =
    assert(Set(
      List(43, 49), // +1
      List(45), // -
      List(48, 49), // 01
      List(45, 48, 49), // -01
      List(46, 49), // .1
      List(49, 46), // 1.
      List(48, 101), // 0e
      List(48, 101, 43), // 0e+
      List(45, 48, 69, 45), // -0E-
      List(49, 46, 50, 46, 51), // 1.2.3
      List(49, 32, 50), // 1 2
      List(48, 120, 50), // 0x2
      List(78, 97, 78), // NaN
      List(73, 110, 102, 105, 110, 105, 116, 121), // Infinity
      List(45, 73, 110, 102, 105, 110, 105, 116, 121), // -Infinity
      List(217, 161), // Arabic-Indic digit one.
    ).forall(bytes => parseJson(bytes) == InvalidJsonSyntax))

  run invalidDocumentSyntaxTest =
    assert(Set(
      List(), // Empty document
      List(32), // Whitespace only
      List(116, 114, 117), // tru
      List(84, 114, 117, 101), // True
      List(116, 114, 117, 101, 32, 102, 97, 108, 115, 101), // true false
      List(110, 117, 108, 108, 123, 125), // null{}
      List(91), // [
      List(91, 49, 44, 93), // [1,]
      List(91, 44, 49, 93), // [,1]
      List(91, 49, 32, 50, 93), // [1 2]
      List(91, 125), // [}
      List(123), // {
      List(123, 49, 58, 50, 125), // {1:2}
      List(123, 34, 97, 34, 125), // {"a"}
      List(123, 34, 97, 34, 32, 50, 125), // {"a" 2}
      List(123, 34, 97, 34, 58, 125), // {"a":}
      List(123, 34, 97, 34, 58, 49, 44, 125), // {"a":1,}
      List(123, 34, 97, 34, 58, 49, 32, 34, 98, 34, 58, 50, 125), // {"a":1 "b":2}
      List(39, 120, 39), // 'x'
      List(11, 91, 93), // Vertical tab is outside the JSON whitespace set.
      List(239, 187, 191, 91, 93), // A BOM before the document is a syntax error.
    ).forall(bytes => parseJson(bytes) == InvalidJsonSyntax))

  run nestedContainersHaveNoFixedDepthTest = {
    val depth = 150
    val opens = range(0, depth).foldl(List(), (bytes, _) => bytes.append(91))
    val closes = range(0, depth).foldl(List(), (bytes, _) => bytes.append(93))
    val expected = range(0, depth).foldl(List(JsonNumber), (nodes, id) => nodes.append(JsonArray(List(id))))
    assert(parseJson(opens.append(48).concat(closes)) == ParsedJson({ nodes: expected, root: depth }))
  }
}
