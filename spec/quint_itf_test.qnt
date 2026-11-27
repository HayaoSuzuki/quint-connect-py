// Fixtures are JSON trees stored in child-before-parent order.
module quint_itf_test {
  import quint_itf.* from "./quint_itf"
  import quint_values.* from "./quint_values"

  pure val stateName: Text = List(115, 116, 97, 116, 101)
  pure val subName: Text = List(115, 117, 98)
  pure val callName: Text = List(99, 97, 108, 108)
  pure val opName: Text = List(111, 112)
  pure val countName: Text = List(99, 111, 117, 110, 116)
  pure val initName: Text = List(105, 110, 105, 116)
  pure val itemsName: Text = List(105, 116, 101, 109, 115)
  pure val usedName: Text = List(117, 115, 101, 100)
  pure val nestedName: Text = List(110, 101, 115, 116, 101, 100)
  pure val innerName: Text = List(105, 110, 110, 101, 114)
  pure val lookalikeName: Text = List(108, 111, 111, 107, 97, 108, 105, 107, 101)
  pure val recordedInitName: Text = List(114, 101, 99, 111, 114, 100, 101, 100, 73, 110, 105, 116)
  pure val explicitInitName: Text = List(101, 120, 112, 108, 105, 99, 105, 116, 73, 110, 105, 116)
  pure val dispatchName: Text = List(100, 105, 115, 112, 97, 116, 99, 104)

  pure val richTrace: ItfDocument = {
    root: 30,
    nodes: List(
      RawText(stateName), // 0
      RawText(mbtAction), // 1
      RawArray(List(0, 1, 1)), // 2
      RawNumber, // 3
      RawObject(List((List(105, 110, 100, 101, 120), 3))), // 4
      RawText(recordedInitName), // 5
      RawText(someTag), // 6
      RawText(List(55)), // 7
      RawObject(List((bigintKey, 7))), // 8
      RawObject(List((tagKey, 6), (valueKey, 8))), // 9
      RawText(noneTag), // 10
      RawArray(List()), // 11
      RawObject(List((tupleKey, 11))), // 12
      RawObject(List((tagKey, 10), (valueKey, 12))), // 13
      RawObject(List((innerName, 13))), // 14
      RawBoolean(true), // 15
      RawObject(List((tagKey, 6), (valueKey, 8), (List(101, 120, 116, 114, 97), 15))), // 16
      RawObject(List((usedName, 9), (List(97, 98, 115, 101, 110, 116), 13), (nestedName, 14), (lookalikeName, 16))), // 17
      RawText(List(49)), // 18
      RawObject(List((bigintKey, 18))), // 19
      RawArray(List(19, 15)), // 20
      RawObject(List((setKey, 20))), // 21
      RawObject(List((subName, 21))), // 22
      RawText(explicitInitName), // 23
      RawObject(List((tagKey, 23), (valueKey, 12))), // 24
      RawObject(List((opName, 24))), // 25
      RawText(List(78, 97, 116)), // 26
      RawObject(List((unserializableKey, 26))), // 27
      RawObject(List((metadataKey, 4), (mbtAction, 5), (mbtPicks, 17), (stateName, 22), (callName, 25), (List(105, 103, 110, 111, 114, 101, 100), 27))), // 28
      RawArray(List(28)), // 29
      RawObject(List((varsKey, 2), (statesKey, 29))), // 30
    ),
  }

  pure val laterError: ItfDocument = {
    root: 19,
    nodes: List(
      RawText(countName), // 0
      RawArray(List(0)), // 1
      RawText(List(48)), // 2
      RawObject(List((bigintKey, 2))), // 3
      RawText(initName), // 4
      RawObject(List()), // 5
      RawObject(List((countName, 3), (mbtAction, 4), (mbtPicks, 5))), // 6
      RawText(List(49)), // 7
      RawObject(List((bigintKey, 7))), // 8
      RawText(List()), // 9
      RawObject(List((countName, 8), (mbtAction, 9), (mbtPicks, 5))), // 10
      RawText(List(50)), // 11
      RawObject(List((bigintKey, 11))), // 12
      RawText(List(108, 97, 116, 101, 114)), // 13
      RawText(List(78, 97, 116)), // 14
      RawObject(List((unserializableKey, 14))), // 15
      RawObject(List((List(98, 97, 100), 15))), // 16
      RawObject(List((countName, 12), (mbtAction, 13), (mbtPicks, 16))), // 17
      RawArray(List(6, 10, 17)), // 18
      RawObject(List((varsKey, 1), (statesKey, 18))), // 19
    ),
  }

  pure val plainTrace: ItfDocument = {
    root: 10,
    nodes: List(
      RawText(countName), // 0
      RawArray(List(0)), // 1
      RawText(List(48)), // 2
      RawObject(List((bigintKey, 2))), // 3
      RawText(initName), // 4
      RawObject(List()), // 5
      RawNumber, // 6
      RawObject(List((List(105, 110, 100, 101, 120), 6))), // 7
      RawObject(List((countName, 3), (mbtAction, 4), (mbtPicks, 5), (metadataKey, 7))), // 8
      RawArray(List(8)), // 9
      RawObject(List((varsKey, 1), (statesKey, 9))), // 10
    ),
  }

  pure val mapPayloadTrace: ItfDocument = {
    root: 10,
    nodes: List(
      RawText(countName), // 0
      RawArray(List(0)), // 1
      RawText(List(48)), // 2
      RawObject(List((bigintKey, 2))), // 3
      RawText(List(115, 116, 97, 114, 116)), // 4
      RawArray(List()), // 5
      RawObject(List((mapKey, 5))), // 6
      RawObject(List((tagKey, 4), (valueKey, 6))), // 7
      RawObject(List((countName, 3), (dispatchName, 7))), // 8
      RawArray(List(8)), // 9
      RawObject(List((varsKey, 1), (statesKey, 9))), // 10
    ),
  }

  pure val badArgumentTrace: ItfDocument = {
    root: 12,
    nodes: List(
      RawText(countName), // 0
      RawArray(List(0)), // 1
      RawText(List(48)), // 2
      RawObject(List((bigintKey, 2))), // 3
      RawText(initName), // 4
      RawText(someTag), // 5
      RawText(List(78, 97, 116)), // 6
      RawObject(List((unserializableKey, 6))), // 7
      RawObject(List((tagKey, 5), (valueKey, 7))), // 8
      RawObject(List((List(98, 97, 100), 8))), // 9
      RawObject(List((countName, 3), (mbtAction, 4), (mbtPicks, 9))), // 10
      RawArray(List(10)), // 11
      RawObject(List((varsKey, 1), (statesKey, 11))), // 12
    ),
  }

  pure val mbtSelection: Selection = { actionPath: List(), statePath: List(stateName, subName) }
  pure val explicitSelection: Selection = { actionPath: List(callName, opName), statePath: List(stateName, subName) }
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
    nodes: List(TextNode(noneTag), TupleNode(List()), RecordNode(Map(tagKey -> 0, valueKey -> 1)),
      RecordNode(Map(innerName -> 2))),
    root: 3,
  }

  pure val lookalikeValue: ItfValue = {
    nodes: List(TextNode(someTag), IntegerNode({ negative: false, digits: List(7) }), BooleanNode(true),
      RecordNode(Map(tagKey -> 0, valueKey -> 1, List(101, 120, 116, 114, 97) -> 2))),
    root: 3,
  }

  pure def validMbtStep(stepData: DecodedStep): bool =
    if (stepData.arguments.keys() == Set(usedName, nestedName, lookalikeName))
      stepData.name == recordedInitName and equalValues(stepData.expected, reversedSet) and
        equalValues(stepData.arguments.get(usedName), sevenValue) and
        equalValues(stepData.arguments.get(nestedName), innerNone) and
        equalValues(stepData.arguments.get(lookalikeName), lookalikeValue)
    else false

  run mbtOptionsAffectOnlyImmediateNamedArgumentsTest =
    assert(oneStepMatches(decodeItf(richTrace, mbtSelection), validMbtStep))

  run explicitPathWinsAndEmptyTupleMeansNoArgumentsTest =
    assert(oneStepMatches(decodeItf(richTrace, explicitSelection), stepData =>
      stepData.name == explicitInitName and stepData.arguments.keys().size() == 0 and
        equalValues(stepData.expected, reversedSet)
    ))

  run projectedValueIgnoresUnselectedUnserializableTest =
    assert(and {
      oneStepMatches(decodeItf(richTrace, mbtSelection), _ => true),
      decodeItf(richTrace, defaults) == InvalidTrace(AtState({ index: 0, problem: InvalidExpectedValue })),
      decodeItf(richTrace, { ...mbtSelection, statePath: List(List(97, 98, 115, 101, 110, 116)) }) ==
        InvalidTrace(AtState({ index: 0, problem: InvalidExpectedValue })),
      decodeItf(richTrace, { ...mbtSelection, statePath: List(stateName, subName, setKey) }) ==
        InvalidTrace(AtState({ index: 0, problem: InvalidExpectedValue })),
    })

  run defaultExpectedValueExcludesOnlyRuntimeMetadataTest =
    assert(oneStepMatches(decodeItf(plainTrace, defaults), stepData =>
      equalValues(stepData.expected, {
        nodes: List(IntegerNode({ negative: false, digits: List(0) }), RecordNode(Map(countName -> 0))),
        root: 1,
      })
    ))

  run firstBadStateIsReportedBeforeAnyStepsAreReturnedTest =
    assert(decodeItf(laterError, defaults) == InvalidTrace(AtState({ index: 1, problem: InvalidOperation })))

  run mapPayloadAndUnserializableArgumentAreInvalidTest =
    assert(and {
      decodeItf(mapPayloadTrace, { ...defaults, actionPath: List(dispatchName) }) ==
        InvalidTrace(AtState({ index: 0, problem: InvalidOperation })),
      decodeItf(badArgumentTrace, defaults) == InvalidTrace(AtState({ index: 0, problem: InvalidArgument })),
    })

  run envelopeSeparatesEmptyStatesMissingVarsAndLoopsTest =
    assert(and {
      decodeItf({ nodes: List(RawArray(List()), RawObject(List((varsKey, 0), (statesKey, 0)))), root: 1 }, defaults)
        == NoStates,
      decodeItf({ nodes: List(RawArray(List()), RawObject(List((statesKey, 0)))), root: 1 }, defaults)
        == InvalidTrace(InvalidEnvelope),
      decodeItf({ nodes: List(RawArray(List()), RawNumber,
        RawObject(List((varsKey, 0), (statesKey, 0), (loopKey, 1)))), root: 2 }, defaults)
        == InvalidTrace(InvalidEnvelope),
    })

  run malformedJsonTreeAndMissingDeclaredVariableAreDistinctTest =
    assert(and {
      decodeItf({ nodes: List(RawArray(List(0))), root: 0 }, defaults) == InvalidTrace(InvalidJsonTree),
      decodeItf({ nodes: List(RawArray(List()), RawObject(List((statesKey, 0), (statesKey, 0)))), root: 1 }, defaults)
        == InvalidTrace(InvalidJsonTree),
      decodeItf({
        nodes: List(RawText(List(109, 105, 115, 115, 105, 110, 103)), RawArray(List(0)), RawObject(List()),
          RawArray(List(2)), RawObject(List((varsKey, 1), (statesKey, 3)))),
        root: 4,
      }, defaults)
        == InvalidTrace(AtState({ index: 0, problem: MissingDeclaredVariable })),
    })

  run rawTreeRejectsNonScalarTextAndObjectNamesTest =
    assert(and {
      decodeItf({ nodes: List(RawText(List(0xD800))), root: 0 }, defaults) ==
        InvalidTrace(InvalidJsonTree),
      decodeItf({ nodes: List(RawNull, RawObject(List((List(0xDFFF), 0)))), root: 1 }, defaults) ==
        InvalidTrace(InvalidJsonTree),
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
    nodes: List(TextNode(List(128578)), IntegerNode({ negative: false, digits: List(1) }), TupleNode(List(0, 1))),
    root: 2,
  }

  pure def bytesDecodeToSameTuple(bytes: List[int]): bool =
    match parseItfBytes(bytes) {
      | ByteInputParsed(document) =>
        oneStepMatches(decodeItf(document, { ...defaults, statePath: List(itemsName) }), stepData =>
          stepData.name == initName and equalValues(stepData.expected, tupleFromBytes)
        )
      | _ => false
    }

  run rawAndEscapedUnicodeBytesGiveTheSameItfValueTest =
    assert(bytesDecodeToSameTuple(rawUnicodeItf) and bytesDecodeToSameTuple(escapedUnicodeItf))

  run escapedDuplicateIsDetectedAtTheItfBoundaryTest =
    assert(match parseItfBytes(duplicateKeyItf) {
      | ByteInputParsed(document) => decodeItf(document, defaults) == InvalidTrace(InvalidJsonTree)
      | _ => false
    })

  run numberGrammarAndItfNumberEncodingAreBothCheckedTest =
    assert(match parseItfBytes(rawNumberItf) {
      | ByteInputParsed(document) => decodeItf(document, { ...defaults, statePath: List(itemsName) }) ==
        InvalidTrace(AtState({ index: 0, problem: InvalidExpectedValue }))
      | _ => false
    })

  run largeJsonNumberInUnselectedMetadataIsAcceptedTest = {
    // Add "#meta":{"index":1e100000000000000000000} to the state.
    val metadata = List(
      44, 34, 35, 109, 101, 116, 97, 34, 58, 123, 34, 105, 110, 100, 101, 120, 34,
      58, 49, 101, 49, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48,
      48, 48, 48, 48, 48, 48, 48, 125,
    )
    val stateEnd = rawUnicodeItf.length() - 3
    val withMetadata = rawUnicodeItf.slice(0, stateEnd).concat(metadata)
      .concat(rawUnicodeItf.slice(stateEnd, rawUnicodeItf.length()))
    assert(bytesDecodeToSameTuple(withMetadata))
  }

  run invalidUtf8AndJsonSyntaxAreDistinguishedTest =
    assert(and {
      parseItfBytes(List(192, 175)) == ByteInputInvalidUtf8,
      parseItfBytes(List(123)) == ByteInputInvalidJson,
    })

  // {"vars":["\u00E9","é"],"states":[{"é":"é","e\u0301":"é","命令":{"tag":"実行","value":{"値":"🙂"}}}]}
  pure val unicodeSelectionItf: List[int] = List(
    123, 34, 118, 97, 114, 115, 34, 58, 91, 34, 92, 117, 48, 48, 69, 57,
    34, 44, 34, 101, 204, 129, 34, 93, 44, 34, 115, 116, 97, 116, 101, 115,
    34, 58, 91, 123, 34, 195, 169, 34, 58, 34, 195, 169, 34, 44, 34, 101,
    92, 117, 48, 51, 48, 49, 34, 58, 34, 101, 204, 129, 34, 44, 34, 229,
    145, 189, 228, 187, 164, 34, 58, 123, 34, 116, 97, 103, 34, 58, 34, 229,
    174, 159, 232, 161, 140, 34, 44, 34, 118, 97, 108, 117, 101, 34, 58, 123,
    34, 229, 128, 164, 34, 58, 34, 240, 159, 153, 130, 34, 125, 125, 125, 93,
    125,
  )

  run unicodeSelectionPreservesKeySpellingAndOperationNameTest =
    assert(match parseItfBytes(unicodeSelectionItf) {
      | ByteInputParsed(document) => {
        val composed = { actionPath: List(List(0x547D, 0x4EE4)), statePath: List(List(0xE9)) }
        val decomposed = { ...composed, statePath: List(List(0x65, 0x301)) }
        val composedValue = { nodes: List(TextNode(List(0xE9))), root: 0 }
        val decomposedValue = { nodes: List(TextNode(List(0x65, 0x301))), root: 0 }
        val argumentValue = { nodes: List(TextNode(List(0x1F642))), root: 0 }
        and {
          oneStepMatches(decodeItf(document, composed), stepData =>
            stepData.name == List(0x5B9F, 0x884C) and
              stepData.arguments.keys() == Set(List(0x5024)) and
              equalValues(stepData.arguments.get(List(0x5024)), argumentValue) and
              equalValues(stepData.expected, composedValue)
          ),
          oneStepMatches(decodeItf(document, decomposed), stepData =>
            stepData.name == List(0x5B9F, 0x884C) and equalValues(stepData.expected, decomposedValue)
          ),
          not(equalValues(composedValue, decomposedValue)),
        }
      }
      | _ => false
    })
}
