// Fixtures are JSON trees stored in child-before-parent order.
module quint_itf_test {
  import quint_itf.* from "./quint_itf"
  import quint_values.* from "./quint_values"

  pure val richTrace: ItfDocument = {
    root: 30,
    nodes: List(
      RawText({ spelling: "state", codePoints: List(115, 116, 97, 116, 101) }), // 0
      RawText({ spelling: "mbt::actionTaken", codePoints: List(109, 98, 116, 58, 58, 97, 99, 116, 105, 111, 110, 84, 97, 107, 101, 110) }), // 1
      RawArray(List(0, 1, 1)), // 2
      RawNumber, // 3
      RawObject(List(("index", 3))), // 4
      RawText({ spelling: "recordedInit", codePoints: List(114, 101, 99, 111, 114, 100, 101, 100, 73, 110, 105, 116) }), // 5
      RawText({ spelling: "Some", codePoints: List(83, 111, 109, 101) }), // 6
      RawText({ spelling: "7", codePoints: List(55) }), // 7
      RawObject(List(("#bigint", 7))), // 8
      RawObject(List(("tag", 6), ("value", 8))), // 9
      RawText({ spelling: "None", codePoints: List(78, 111, 110, 101) }), // 10
      RawArray(List()), // 11
      RawObject(List(("#tup", 11))), // 12
      RawObject(List(("tag", 10), ("value", 12))), // 13
      RawObject(List(("inner", 13))), // 14
      RawBoolean(true), // 15
      RawObject(List(("tag", 6), ("value", 8), ("extra", 15))), // 16
      RawObject(List(("used", 9), ("absent", 13), ("nested", 14), ("lookalike", 16))), // 17
      RawText({ spelling: "1", codePoints: List(49) }), // 18
      RawObject(List(("#bigint", 18))), // 19
      RawArray(List(19, 15)), // 20
      RawObject(List(("#set", 20))), // 21
      RawObject(List(("sub", 21))), // 22
      RawText({ spelling: "explicitInit", codePoints: List(101, 120, 112, 108, 105, 99, 105, 116, 73, 110, 105, 116) }), // 23
      RawObject(List(("tag", 23), ("value", 12))), // 24
      RawObject(List(("op", 24))), // 25
      RawText({ spelling: "Nat", codePoints: List(78, 97, 116) }), // 26
      RawObject(List(("#unserializable", 26))), // 27
      RawObject(List(("#meta", 4), ("mbt::actionTaken", 5), ("mbt::nondetPicks", 17), ("state", 22), ("call", 25), ("ignored", 27))), // 28
      RawArray(List(28)), // 29
      RawObject(List(("vars", 2), ("states", 29))), // 30
    ),
  }

  pure val laterError: ItfDocument = {
    root: 19,
    nodes: List(
      RawText({ spelling: "count", codePoints: List(99, 111, 117, 110, 116) }), // 0
      RawArray(List(0)), // 1
      RawText({ spelling: "0", codePoints: List(48) }), // 2
      RawObject(List(("#bigint", 2))), // 3
      RawText({ spelling: "init", codePoints: List(105, 110, 105, 116) }), // 4
      RawObject(List()), // 5
      RawObject(List(("count", 3), ("mbt::actionTaken", 4), ("mbt::nondetPicks", 5))), // 6
      RawText({ spelling: "1", codePoints: List(49) }), // 7
      RawObject(List(("#bigint", 7))), // 8
      RawText({ spelling: "", codePoints: List() }), // 9
      RawObject(List(("count", 8), ("mbt::actionTaken", 9), ("mbt::nondetPicks", 5))), // 10
      RawText({ spelling: "2", codePoints: List(50) }), // 11
      RawObject(List(("#bigint", 11))), // 12
      RawText({ spelling: "later", codePoints: List(108, 97, 116, 101, 114) }), // 13
      RawText({ spelling: "Nat", codePoints: List(78, 97, 116) }), // 14
      RawObject(List(("#unserializable", 14))), // 15
      RawObject(List(("bad", 15))), // 16
      RawObject(List(("count", 12), ("mbt::actionTaken", 13), ("mbt::nondetPicks", 16))), // 17
      RawArray(List(6, 10, 17)), // 18
      RawObject(List(("vars", 1), ("states", 18))), // 19
    ),
  }

  pure val plainTrace: ItfDocument = {
    root: 10,
    nodes: List(
      RawText({ spelling: "count", codePoints: List(99, 111, 117, 110, 116) }), // 0
      RawArray(List(0)), // 1
      RawText({ spelling: "0", codePoints: List(48) }), // 2
      RawObject(List(("#bigint", 2))), // 3
      RawText({ spelling: "init", codePoints: List(105, 110, 105, 116) }), // 4
      RawObject(List()), // 5
      RawNumber, // 6
      RawObject(List(("index", 6))), // 7
      RawObject(List(("count", 3), ("mbt::actionTaken", 4), ("mbt::nondetPicks", 5), ("#meta", 7))), // 8
      RawArray(List(8)), // 9
      RawObject(List(("vars", 1), ("states", 9))), // 10
    ),
  }

  pure val mapPayloadTrace: ItfDocument = {
    root: 10,
    nodes: List(
      RawText({ spelling: "count", codePoints: List(99, 111, 117, 110, 116) }), // 0
      RawArray(List(0)), // 1
      RawText({ spelling: "0", codePoints: List(48) }), // 2
      RawObject(List(("#bigint", 2))), // 3
      RawText({ spelling: "start", codePoints: List(115, 116, 97, 114, 116) }), // 4
      RawArray(List()), // 5
      RawObject(List(("#map", 5))), // 6
      RawObject(List(("tag", 4), ("value", 6))), // 7
      RawObject(List(("count", 3), ("dispatch", 7))), // 8
      RawArray(List(8)), // 9
      RawObject(List(("vars", 1), ("states", 9))), // 10
    ),
  }

  pure val badArgumentTrace: ItfDocument = {
    root: 12,
    nodes: List(
      RawText({ spelling: "count", codePoints: List(99, 111, 117, 110, 116) }), // 0
      RawArray(List(0)), // 1
      RawText({ spelling: "0", codePoints: List(48) }), // 2
      RawObject(List(("#bigint", 2))), // 3
      RawText({ spelling: "init", codePoints: List(105, 110, 105, 116) }), // 4
      RawText({ spelling: "Some", codePoints: List(83, 111, 109, 101) }), // 5
      RawText({ spelling: "Nat", codePoints: List(78, 97, 116) }), // 6
      RawObject(List(("#unserializable", 6))), // 7
      RawObject(List(("tag", 5), ("value", 7))), // 8
      RawObject(List(("bad", 8))), // 9
      RawObject(List(("count", 3), ("mbt::actionTaken", 4), ("mbt::nondetPicks", 9))), // 10
      RawArray(List(10)), // 11
      RawObject(List(("vars", 1), ("states", 11))), // 12
    ),
  }

  pure val mbtSelection: Selection = { actionPath: List(), statePath: List("state", "sub") }
  pure val explicitSelection: Selection = { actionPath: List("call", "op"), statePath: List("state", "sub") }
  pure val defaults: Selection = { actionPath: List(), statePath: List() }

  pure def oneStepMatches(result: DecodeResult, predicate: (DecodedStep) => bool): bool =
    match result {
      | DecodedTrace(steps) => if (steps.length() == 1) predicate(steps.nth(0)) else false
      | _ => false
    }

  pure val reversedSet: ItfValue = {
    nodes: List(BooleanNode(true), IntegerNode({ negative: false, digits: List(1) }), SetNode(List(0, 1))),
    root: 2,
  }

  pure val sevenValue: ItfValue = { nodes: List(IntegerNode({ negative: false, digits: List(7) })), root: 0 }

  pure val innerNone: ItfValue = {
    nodes: List(TextNode("None"), TupleNode(List()), RecordNode(Map("tag" -> 0, "value" -> 1)),
      RecordNode(Map("inner" -> 2))),
    root: 3,
  }

  pure val lookalikeValue: ItfValue = {
    nodes: List(TextNode("Some"), IntegerNode({ negative: false, digits: List(7) }), BooleanNode(true),
      RecordNode(Map("tag" -> 0, "value" -> 1, "extra" -> 2))),
    root: 3,
  }

  pure def validMbtStep(stepData: DecodedStep): bool =
    if (stepData.arguments.keys() == Set("used", "nested", "lookalike"))
      stepData.name == "recordedInit" and equalValues(stepData.expected, reversedSet) and
        equalValues(stepData.arguments.get("used"), sevenValue) and
        equalValues(stepData.arguments.get("nested"), innerNone) and
        equalValues(stepData.arguments.get("lookalike"), lookalikeValue)
    else false

  run mbtOptionsAffectOnlyImmediateNamedArgumentsTest =
    assert(oneStepMatches(decodeItf(richTrace, mbtSelection), validMbtStep))

  run explicitPathWinsAndEmptyTupleMeansNoArgumentsTest =
    assert(oneStepMatches(decodeItf(richTrace, explicitSelection), stepData =>
      stepData.name == "explicitInit" and stepData.arguments.keys().size() == 0 and
        equalValues(stepData.expected, reversedSet)
    ))

  run projectedValueIgnoresUnselectedUnserializableTest =
    assert(and {
      oneStepMatches(decodeItf(richTrace, mbtSelection), _ => true),
      decodeItf(richTrace, defaults) == InvalidTrace(AtState({ index: 0, problem: InvalidExpectedValue })),
      decodeItf(richTrace, { ...mbtSelection, statePath: List("absent") }) ==
        InvalidTrace(AtState({ index: 0, problem: InvalidExpectedValue })),
      decodeItf(richTrace, { ...mbtSelection, statePath: List("state", "sub", "#set") }) ==
        InvalidTrace(AtState({ index: 0, problem: InvalidExpectedValue })),
    })

  run defaultExpectedValueExcludesOnlyRuntimeMetadataTest =
    assert(oneStepMatches(decodeItf(plainTrace, defaults), stepData =>
      equalValues(stepData.expected, {
        nodes: List(IntegerNode({ negative: false, digits: List(0) }), RecordNode(Map("count" -> 0))),
        root: 1,
      })
    ))

  run firstBadStateIsReportedBeforeAnyStepsAreReturnedTest =
    assert(decodeItf(laterError, defaults) == InvalidTrace(AtState({ index: 1, problem: InvalidOperation })))

  run mapPayloadAndUnserializableArgumentAreInvalidTest =
    assert(and {
      decodeItf(mapPayloadTrace, { ...defaults, actionPath: List("dispatch") }) ==
        InvalidTrace(AtState({ index: 0, problem: InvalidOperation })),
      decodeItf(badArgumentTrace, defaults) == InvalidTrace(AtState({ index: 0, problem: InvalidArgument })),
    })

  run envelopeSeparatesEmptyStatesMissingVarsAndLoopsTest =
    assert(and {
      decodeItf({ nodes: List(RawArray(List()), RawObject(List(("vars", 0), ("states", 0)))), root: 1 }, defaults)
        == NoStates,
      decodeItf({ nodes: List(RawArray(List()), RawObject(List(("states", 0)))), root: 1 }, defaults)
        == InvalidTrace(InvalidEnvelope),
      decodeItf({ nodes: List(RawArray(List()), RawNumber,
        RawObject(List(("vars", 0), ("states", 0), ("loop", 1)))), root: 2 }, defaults)
        == InvalidTrace(InvalidEnvelope),
    })

  run malformedJsonTreeAndMissingDeclaredVariableAreDistinctTest =
    assert(and {
      decodeItf({ nodes: List(RawArray(List(0))), root: 0 }, defaults) == InvalidTrace(InvalidJsonTree),
      decodeItf({ nodes: List(RawArray(List()), RawObject(List(("states", 0), ("states", 0)))), root: 1 }, defaults)
        == InvalidTrace(InvalidJsonTree),
      decodeItf({ nodes: List(RawText({ spelling: "missing", codePoints: List(109, 105, 115, 115, 105, 110, 103) }), RawArray(List(0)), RawObject(List()), RawArray(List(2)),
        RawObject(List(("vars", 1), ("states", 3)))), root: 4 }, defaults)
        == InvalidTrace(AtState({ index: 0, problem: MissingDeclaredVariable })),
    })

  run bigintRequiresAnOptionalMinusAndDecimalDigitsTest =
    assert(and {
      decimalFromCodePoints(List(45, 48, 55)) ==
        ReadDecimal({ negative: true, digits: List(0, 7) }),
      decimalFromCodePoints(List()) == NotDecimal,
      decimalFromCodePoints(List(45)) == NotDecimal,
      decimalFromCodePoints(List(43, 49)) == NotDecimal,
      decimalFromCodePoints(List(49, 46, 48)) == NotDecimal,
      decimalFromCodePoints(List(1633)) == NotDecimal,
    })

  pure val byteTestLabels: TextLabels = Map(
    List(118, 97, 114, 115) -> "vars",
    List(115, 116, 97, 116, 101, 115) -> "states",
    List(105, 116, 101, 109, 115) -> "items",
    List(35, 116, 117, 112) -> "#tup",
    List(128578) -> "🙂",
    List(35, 98, 105, 103, 105, 110, 116) -> "#bigint",
    List(49) -> "1",
    List(109, 98, 116, 58, 58, 97, 99, 116, 105, 111, 110, 84, 97, 107, 101, 110) -> "mbt::actionTaken",
    List(109, 98, 116, 58, 58, 110, 111, 110, 100, 101, 116, 80, 105, 99, 107, 115) -> "mbt::nondetPicks",
    List(105, 110, 105, 116) -> "init",
  )

  pure val rawUnicodeItf: List[int] = List(
    123, 34, 118, 97, 114, 115, 34, 58, 91, 34, 105, 116, 101, 109, 115, 34,
    93, 44, 34, 115, 116, 97, 116, 101, 115, 34, 58, 91, 123, 34, 105, 116,
    101, 109, 115, 34, 58, 123, 34, 35, 116, 117, 112, 34, 58, 91, 34, 240,
    159, 153, 130, 34, 44, 123, 34, 35, 98, 105, 103, 105, 110, 116, 34, 58,
    34, 49, 34, 125, 93, 125, 44, 34, 109, 98, 116, 58, 58, 97, 99, 116,
    105, 111, 110, 84, 97, 107, 101, 110, 34, 58, 34, 105, 110, 105, 116, 34,
    44, 34, 109, 98, 116, 58, 58, 110, 111, 110, 100, 101, 116, 80, 105, 99,
    107, 115, 34, 58, 123, 125, 125, 93, 125,
  )

  pure val escapedUnicodeItf: List[int] = List(
    123, 34, 118, 97, 114, 115, 34, 58, 91, 34, 105, 116, 101, 109, 115, 34,
    93, 44, 34, 115, 116, 97, 116, 101, 115, 34, 58, 91, 123, 34, 105, 116,
    101, 109, 115, 34, 58, 123, 34, 35, 116, 117, 112, 34, 58, 91, 34, 92,
    117, 68, 56, 51, 68, 92, 117, 68, 69, 52, 50, 34, 44, 123, 34, 35,
    98, 105, 103, 105, 110, 116, 34, 58, 34, 92, 117, 48, 48, 51, 49, 34,
    125, 93, 125, 44, 34, 109, 98, 116, 58, 58, 97, 99, 116, 105, 111, 110,
    84, 97, 107, 101, 110, 34, 58, 34, 105, 110, 105, 116, 34, 44, 34, 109,
    98, 116, 58, 58, 110, 111, 110, 100, 101, 116, 80, 105, 99, 107, 115, 34,
    58, 123, 125, 125, 93, 125,
  )

  pure val rawNumberItf: List[int] = List(
    123, 34, 118, 97, 114, 115, 34, 58, 91, 34, 105, 116, 101, 109, 115, 34,
    93, 44, 34, 115, 116, 97, 116, 101, 115, 34, 58, 91, 123, 34, 105, 116,
    101, 109, 115, 34, 58, 49, 44, 34, 109, 98, 116, 58, 58, 97, 99, 116,
    105, 111, 110, 84, 97, 107, 101, 110, 34, 58, 34, 105, 110, 105, 116, 34,
    44, 34, 109, 98, 116, 58, 58, 110, 111, 110, 100, 101, 116, 80, 105, 99,
    107, 115, 34, 58, 123, 125, 125, 93, 125,
  )

  pure val duplicateKeyItf: List[int] = List(
    123, 34, 118, 97, 114, 115, 34, 58, 91, 93, 44, 34, 92, 117, 48, 48,
    55, 54, 97, 114, 115, 34, 58, 91, 93, 44, 34, 115, 116, 97, 116, 101,
    115, 34, 58, 91, 93, 125,
  )

  pure val tupleFromBytes: ItfValue = {
    nodes: List(TextNode("🙂"), IntegerNode({ negative: false, digits: List(1) }), TupleNode(List(0, 1))),
    root: 2,
  }

  pure def bytesDecodeToSameTuple(bytes: List[int]): bool =
    match parseItfBytes(bytes, byteTestLabels) {
      | ByteInputParsed(document) =>
        oneStepMatches(decodeItf(document, { ...defaults, statePath: List("items") }), stepData =>
          stepData.name == "init" and equalValues(stepData.expected, tupleFromBytes)
        )
      | _ => false
    }

  run rawAndEscapedUnicodeBytesGiveTheSameItfValueTest =
    assert(bytesDecodeToSameTuple(rawUnicodeItf) and bytesDecodeToSameTuple(escapedUnicodeItf))

  run escapedDuplicateIsDetectedAtTheItfBoundaryTest =
    assert(match parseItfBytes(duplicateKeyItf, byteTestLabels) {
      | ByteInputParsed(document) => decodeItf(document, defaults) == InvalidTrace(InvalidJsonTree)
      | _ => false
    })

  run numberGrammarAndItfNumberEncodingAreBothCheckedTest =
    assert(match parseItfBytes(rawNumberItf, byteTestLabels) {
      | ByteInputParsed(document) => decodeItf(document, { ...defaults, statePath: List("items") }) ==
        InvalidTrace(AtState({ index: 0, problem: InvalidExpectedValue }))
      | _ => false
    })

  run invalidUtf8AndJsonSyntaxAreDistinguishedTest =
    assert(and {
      parseItfBytes(List(192, 175), byteTestLabels) == ByteInputInvalidUtf8,
      parseItfBytes(List(123), byteTestLabels) == ByteInputInvalidJson,
    })

  run byteAdapterRequiresCompleteDistinctTextLabelsTest =
    assert(and {
      parseItfBytes(List(34, 97, 34), Map()) == ByteInputUnlabeledText,
      parseItfBytes(List(91, 34, 97, 34, 44, 34, 98, 34, 93),
        Map(List(97) -> "same", List(98) -> "same")) == ByteInputUnlabeledText,
    })
}
