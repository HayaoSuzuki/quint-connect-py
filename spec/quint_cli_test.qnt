module quint_cli_test {
  import quint_cli.* from "./quint_cli"

  pure val defaultSimulation: SimulationOptions = {
    init: CliDefault,
    step: CliDefault,
    nTraces: CliDefault,
    maxSamples: CliDefault,
    maxSteps: CliDefault,
  }

  pure val executablePath = "/chosen bin/quint"
  pure val modelPath = "/project/models/counter test.qnt"

  pure val baseRequest: CliRequest = {
    callerDirectory: "/caller",
    executable: ExecutablePath(AbsolutePath(executablePath)),
    model: AbsolutePath(modelPath),
    workspace: 1,
    main: CliDefault,
    backend: CliDefault,
    seed: CliDefault,
    config: Simulation(defaultSimulation),
  }

  run simulationDefaultsTest =
    quintCommand(baseRequest, List("0")) == CommandReady({
      executable: DirectExecutable(AbsoluteTarget(executablePath)),
      workspace: 1,
      seed: List("0"),
      argv: List(
        LiteralArgument("run"),
        ModelArgument(AbsoluteTarget(modelPath)),
        LiteralArgument("--mbt"),
        StringOption({ flag: "--out-itf", value: "trace_{seq}.itf.json" }),
        SeedOption(List("0")),
        IntegerOption({ flag: "--n-traces", value: 1 }),
        IntegerOption({ flag: "--max-samples", value: 1 }),
      ),
    })

  run relativePathsAreAnchoredIndependentlyOfWorkspaceTest =
    Set("/project A", "/project B").forall(directory =>
      Set(1, 2).forall(workspace => {
        val request = {
          ...baseRequest,
          callerDirectory: directory,
          executable: ExecutablePath(RelativePath("../tools/quint")),
          model: RelativePath("counter test.qnt"),
          workspace: workspace,
        }
        match quintCommand(request, List("0")) {
          | CommandReady(command) => and {
            command.workspace == workspace,
            command.executable ==
              DirectExecutable(AnchoredPath({ directory: directory, path: "../tools/quint" })),
            command.argv.nth(1) ==
              ModelArgument(AnchoredPath({ directory: directory, path: "counter test.qnt" })),
          }
          | _ => false
        }
      })
    )

  run bareCommandUsesCallerPathTest = {
    val request = {
      ...baseRequest,
      callerDirectory: "/named tests",
      executable: BareCommand("quint"),
      model: RelativePath("models/sample.qnt"),
      config: NamedTestMode({ name: List(65), maxSamples: CliDefault }),
    }
    match quintCommand(request, List("0")) {
      | CommandReady(command) => and {
        command.executable == SearchCallerPath({ directory: "/named tests", name: "quint" }),
        command.argv.nth(1) == ModelArgument(AnchoredPath({ directory: "/named tests", path: "models/sample.qnt" })),
      }
      | _ => false
    }
  }

  run configuredSimulationTest = {
    val options = {
      init: CliSpecified("open"),
      step: CliSpecified("advance"),
      nTraces: CliSpecified(10),
      maxSamples: CliSpecified(40),
      maxSteps: CliSpecified(0),
    }
    val request = {
      ...baseRequest,
      config: Simulation(options),
      main: CliSpecified("entry"),
      backend: CliSpecified(TypeScriptBackend),
      seed: CliSpecified(List("4", "2")),
    }
    quintCommand(request, List("invalid")) == CommandReady({
      executable: DirectExecutable(AbsoluteTarget(executablePath)),
      workspace: baseRequest.workspace,
      seed: List("4", "2"),
      argv: List(
        LiteralArgument("run"),
        ModelArgument(AbsoluteTarget(modelPath)),
        LiteralArgument("--mbt"),
        StringOption({ flag: "--out-itf", value: "trace_{seq}.itf.json" }),
        SeedOption(List("4", "2")),
        StringOption({ flag: "--main", value: "entry" }),
        StringOption({ flag: "--backend", value: "typescript" }),
        IntegerOption({ flag: "--n-traces", value: 10 }),
        IntegerOption({ flag: "--max-samples", value: 40 }),
        StringOption({ flag: "--init", value: "open" }),
        StringOption({ flag: "--step", value: "advance" }),
        IntegerOption({ flag: "--max-steps", value: 0 }),
      ),
    })
  }

  run simulationUsesTraceCountForOmittedSampleLimitTest = {
    val request = {
      ...baseRequest,
      config: Simulation({ ...defaultSimulation, nTraces: CliSpecified(6) }),
    }
    match quintCommand(request, List("7")) {
      | CommandReady(command) =>
        command.argv.slice(5, 7) == List(
          IntegerOption({ flag: "--n-traces", value: 6 }),
          IntegerOption({ flag: "--max-samples", value: 6 }),
        )
      | _ => false
    }
  }

  run namedTestFlagsAndExactPatternTest = {
    // A.[b] is a representative input containing regex metacharacters.
    val request = {
      ...baseRequest,
      backend: CliSpecified(RustBackend),
      config: NamedTestMode({ name: List(65, 46, 91, 98, 93), maxSamples: CliSpecified(1) }),
    }
    quintCommand(request, List("5")) == CommandReady({
      executable: DirectExecutable(AbsoluteTarget(executablePath)),
      workspace: baseRequest.workspace,
      seed: List("5"),
      argv: List(
        LiteralArgument("test"),
        ModelArgument(AbsoluteTarget(modelPath)),
        StringOption({ flag: "--out-itf", value: "trace_{seq}.itf.json" }),
        SeedOption(List("5")),
        StringOption({ flag: "--backend", value: "rust" }),
        MatchOption(List(94, 65, 92, 46, 92, 91, 98, 92, 93, 36)),
        IntegerOption({ flag: "--max-samples", value: 1 }),
      ),
    })
  }

  run namedTestUsesQuintDefaultSampleLimitTest = {
    val request = {
      ...baseRequest,
      config: NamedTestMode({ name: List(65), maxSamples: CliDefault }),
    }
    quintCommand(request, List("0")) == CommandReady({
      executable: DirectExecutable(AbsoluteTarget(executablePath)),
      workspace: baseRequest.workspace,
      seed: List("0"),
      argv: List(
        LiteralArgument("test"),
        ModelArgument(AbsoluteTarget(modelPath)),
        StringOption({ flag: "--out-itf", value: "trace_{seq}.itf.json" }),
        SeedOption(List("0")),
        MatchOption(List(94, 65, 36)),
      ),
    })
  }

  run regexSyntaxCharactersAreAllEscapedTest =
    exactTestPattern(List(94, 36, 92, 46, 42, 43, 63, 40, 41, 91, 93, 123, 125, 124, 47, 233)) ==
      List(94, 92, 94, 92, 36, 92, 92, 92, 46, 92, 42, 92, 43, 92, 63, 92, 40, 92,
        41, 92, 91, 92, 93, 92, 123, 92, 125, 92, 124, 47, 233, 36)

  // Quint strings are opaque. This fixture supplies their code points at the adapter boundary.
  pure val argumentText: str -> List[int] = Map(
    "run" -> List(114, 117, 110),
    "test" -> List(116, 101, 115, 116),
    "--mbt" -> List(45, 45, 109, 98, 116),
    "--out-itf" -> List(45, 45, 111, 117, 116, 45, 105, 116, 102),
    "trace_{seq}.itf.json" -> List(116, 114, 97, 99, 101, 95, 123, 115, 101, 113, 125, 46, 105, 116, 102, 46, 106, 115, 111, 110),
    "--seed" -> List(45, 45, 115, 101, 101, 100),
    "--n-traces" -> List(45, 45, 110, 45, 116, 114, 97, 99, 101, 115),
    "--max-samples" -> List(45, 45, 109, 97, 120, 45, 115, 97, 109, 112, 108, 101, 115),
    "--max-steps" -> List(45, 45, 109, 97, 120, 45, 115, 116, 101, 112, 115),
    "--main" -> List(45, 45, 109, 97, 105, 110),
    "--backend" -> List(45, 45, 98, 97, 99, 107, 101, 110, 100),
    "typescript" -> List(116, 121, 112, 101, 115, 99, 114, 105, 112, 116),
    "--init" -> List(45, 45, 105, 110, 105, 116),
    "--step" -> List(45, 45, 115, 116, 101, 112),
    "--match" -> List(45, 45, 109, 97, 116, 99, 104),
    "--scope=é 🙂" -> List(45, 45, 115, 99, 111, 112, 101, 61, 233, 32, 128578),
    "with spaces" -> List(119, 105, 116, 104, 32, 115, 112, 97, 99, 101, 115),
    "" -> List(),
  )

  run simulationSerializesExactArgvTest = {
    val largest = 9007199254740991
    val request = {
      ...baseRequest,
      main: CliSpecified("--scope=é 🙂"),
      backend: CliSpecified(TypeScriptBackend),
      seed: CliSpecified(maxSeed),
      config: Simulation({
        ...defaultSimulation,
        init: CliSpecified("with spaces"),
        step: CliSpecified(""),
        nTraces: CliSpecified(largest),
        maxSteps: CliSpecified(0),
      }),
    }
    match quintCommand(request, List()) {
      | CommandReady(command) => osArgv(command, word => argumentText.get(word)) == List(
        OsText(List(114, 117, 110)),
        OsPath(AbsoluteTarget(modelPath)),
        OsText(List(45, 45, 109, 98, 116)),
        // --out-itf=trace_{seq}.itf.json
        OsText(List(45, 45, 111, 117, 116, 45, 105, 116, 102, 61, 116, 114, 97, 99, 101, 95, 123, 115, 101, 113, 125, 46, 105, 116, 102, 46, 106, 115, 111, 110)),
        // --seed=18446744073709551615
        OsText(List(45, 45, 115, 101, 101, 100, 61, 49, 56, 52, 52, 54, 55, 52, 52, 48, 55, 51, 55, 48, 57, 53, 53, 49, 54, 49, 53)),
        // --main=--scope=é 🙂
        OsText(List(45, 45, 109, 97, 105, 110, 61, 45, 45, 115, 99, 111, 112, 101, 61, 233, 32, 128578)),
        OsText(List(45, 45, 98, 97, 99, 107, 101, 110, 100, 61, 116, 121, 112, 101, 115, 99, 114, 105, 112, 116)),
        // Both counts are 9007199254740991.
        OsText(List(45, 45, 110, 45, 116, 114, 97, 99, 101, 115, 61, 57, 48, 48, 55, 49, 57, 57, 50, 53, 52, 55, 52, 48, 57, 57, 49)),
        OsText(List(45, 45, 109, 97, 120, 45, 115, 97, 109, 112, 108, 101, 115, 61, 57, 48, 48, 55, 49, 57, 57, 50, 53, 52, 55, 52, 48, 57, 57, 49)),
        OsText(List(45, 45, 105, 110, 105, 116, 61, 119, 105, 116, 104, 32, 115, 112, 97, 99, 101, 115)),
        OsText(List(45, 45, 115, 116, 101, 112, 61)),
        OsText(List(45, 45, 109, 97, 120, 45, 115, 116, 101, 112, 115, 61, 48)),
      )
      | _ => false
    }
  }

  run namedTestSerializesOneExactUnicodePatternArgumentTest = {
    val request = {
      ...baseRequest,
      model: RelativePath("-models/../counter = test.qnt"),
      config: NamedTestMode({ name: List(45, 45, 61, 32, 233, 46, 128578), maxSamples: CliDefault }),
    }
    match quintCommand(request, List("0")) {
      | CommandReady(command) => osArgv(command, word => argumentText.get(word)) == List(
        OsText(List(116, 101, 115, 116)),
        OsPath(AnchoredPath({ directory: "/caller", path: "-models/../counter = test.qnt" })),
        OsText(List(45, 45, 111, 117, 116, 45, 105, 116, 102, 61, 116, 114, 97, 99, 101, 95, 123, 115, 101, 113, 125, 46, 105, 116, 102, 46, 106, 115, 111, 110)),
        OsText(List(45, 45, 115, 101, 101, 100, 61, 48)),
        // --match=^--= é\.🙂$
        OsText(List(45, 45, 109, 97, 116, 99, 104, 61, 94, 45, 45, 61, 32, 233, 92, 46, 128578, 36)),
      )
      | _ => false
    }
  }

  run unsignedSeedBoundsTest = {
    val highestSeed = List(
      "1", "8", "4", "4", "6", "7", "4", "4", "0", "7", "3", "7", "0", "9", "5", "5", "1", "6", "1", "5"
    )
    val highestPlusOne = highestSeed.replaceAt(19, "6")
    and {
      validSeed(List("0")),
      validSeed(highestSeed),
      not(validSeed(highestPlusOne)),
      not(validSeed(highestSeed.append("0"))),
      not(validSeed(List())),
      not(validSeed(List("-", "1"))),
      not(validSeed(List("0", "1"))),
      not(validSeed(List("true"))),
      quintCommand({ ...baseRequest, seed: CliSpecified(highestPlusOne) }, List("5")) == InvalidSeed,
      quintCommand(baseRequest, highestPlusOne) == InvalidSeed,
      match quintCommand({ ...baseRequest, seed: CliSpecified(highestSeed) }, List()) {
        | CommandReady(command) =>
          command.seed == highestSeed and command.argv.nth(4) == SeedOption(highestSeed)
        | _ => false
      },
    }
  }

  run nonPositiveTraceCountIsInvalidTest =
    Set(-1, 0).forall(count =>
      quintCommand({
        ...baseRequest,
        config: Simulation({ ...defaultSimulation, nTraces: CliSpecified(count) }),
      }, List("0")) == InvalidTraceCount
    )

  run simulationRejectsSampleLimitBelowTraceCountTest =
    Set(-1, 0, 1).forall(limit =>
      quintCommand({
        ...baseRequest,
        config: Simulation({ ...defaultSimulation, nTraces: CliSpecified(2), maxSamples: CliSpecified(limit) }),
      }, List("0")) == InvalidSampleLimit
    )

  run simulationAcceptsSampleLimitEqualToTraceCountTest = {
    val options = {
      ...defaultSimulation,
      nTraces: CliSpecified(2),
      maxSamples: CliSpecified(2),
      maxSteps: CliSpecified(1),
    }
    match quintCommand({ ...baseRequest, config: Simulation(options) }, List("0")) {
      | CommandReady(command) =>
        command.argv.slice(5, command.argv.length()) == List(
          IntegerOption({ flag: "--n-traces", value: 2 }),
          IntegerOption({ flag: "--max-samples", value: 2 }),
          IntegerOption({ flag: "--max-steps", value: 1 }),
        )
      | _ => false
    }
  }

  run namedTestRejectsNonPositiveSampleLimitTest =
    Set(-1, 0).forall(limit =>
      quintCommand({
        ...baseRequest,
        config: NamedTestMode({ name: List(65), maxSamples: CliSpecified(limit) }),
      }, List("0")) == InvalidSampleLimit
    )

  run simulationRejectsNegativeStepLimitTest =
    quintCommand({
      ...baseRequest,
      config: Simulation({ ...defaultSimulation, maxSteps: CliSpecified(-1) }),
    }, List("0")) == InvalidStepLimit

  run generationLimitsRejectUnrepresentableCliIntegersTest =
    Set(9007199254740992, 9007199254740993).forall(limit => all {
      quintCommand({ ...baseRequest,
        config: Simulation({ ...defaultSimulation, nTraces: CliSpecified(limit) }),
      }, List("0")) == InvalidTraceCount,
      quintCommand({ ...baseRequest,
        config: Simulation({ ...defaultSimulation, maxSamples: CliSpecified(limit) }),
      }, List("0")) == InvalidSampleLimit,
      quintCommand({ ...baseRequest,
        config: Simulation({ ...defaultSimulation, maxSteps: CliSpecified(limit) }),
      }, List("0")) == InvalidStepLimit,
      quintCommand({ ...baseRequest,
        config: NamedTestMode({ name: List(65), maxSamples: CliSpecified(limit) }),
      }, List("0")) == InvalidSampleLimit,
    })

  run generationLimitsPreserveLargestSafeCliIntegerTest = {
    val largest = 9007199254740991
    val options = {
      ...defaultSimulation,
      nTraces: CliSpecified(largest),
      maxSteps: CliSpecified(largest),
    }
    all {
      match quintCommand({ ...baseRequest, config: Simulation(options) }, List("0")) {
        | CommandReady(command) =>
          command.argv.slice(5, command.argv.length()) == List(
            IntegerOption({ flag: "--n-traces", value: largest }),
            IntegerOption({ flag: "--max-samples", value: largest }),
            IntegerOption({ flag: "--max-steps", value: largest }),
          )
        | _ => false
      },
      match quintCommand({ ...baseRequest,
        config: NamedTestMode({ name: List(65), maxSamples: CliSpecified(largest) }),
      }, List("0")) {
        | CommandReady(command) =>
          command.argv.nth(command.argv.length() - 1) ==
            IntegerOption({ flag: "--max-samples", value: largest })
        | _ => false
      },
    }
  }

  run simulationValidatesSeedAndLimitsInOrderTest = {
    val options = {
      ...defaultSimulation,
      nTraces: CliSpecified(0),
      maxSamples: CliSpecified(-1),
      maxSteps: CliSpecified(-1),
    }
    val request = { ...baseRequest, config: Simulation(options) }
    and {
      quintCommand(request, List()) == InvalidSeed,
      quintCommand(request, List("0")) == InvalidTraceCount,
      quintCommand({
        ...request,
        config: Simulation({ ...options, nTraces: CliSpecified(2) }),
      }, List("0")) == InvalidSampleLimit,
    }
  }

  run generatedFilesAreFilteredAndNumericallyOrderedTest = {
    val zero = { name: generatedFilename(List("0")), trace: 42 }
    val two = { name: generatedFilename(List("2")), trace: 78 }
    val ten = { name: generatedFilename(List("1", "0")), trace: 91 }
    val eleven = { name: generatedFilename(List("1", "1")), trace: 40 }
    val leadingZero = { name: generatedFilename(List("0", "2")), trace: 1 }
    val nondigit = { name: generatedFilename(List("a")), trace: 2 }
    val noDigits = { name: generatedFilename(List()), trace: 3 }
    val signed = { name: generatedFilename(List("-", "2")), trace: 4 }
    val otherBasename = { name: List("unrelated.itf.json"), trace: 5 }
    val badExtension = { name: two.name.append("x"), trace: 6 }
    val wrongPrefix = { name: two.name.replaceAt(0, "x"), trace: 7 }
    and {
      orderedGeneratedTraces(List()) == List(),
      orderedGeneratedTraces(List(ten, leadingZero, two, nondigit, noDigits, signed,
        zero, otherBasename, eleven, badExtension, wrongPrefix)) == List(42, 78, 91, 40),
      orderedGeneratedTraces(List(two, zero, ten)) == List(42, 78, 91),
    }
  }

  run generatedTraceCandidatesRequireRegularEntriesAndCanonicalBasenamesTest = {
    val first = { name: generatedFilename(List("0")), trace: 42, kind: RegularFile }
    val later = { name: generatedFilename(List("1", "0")), trace: 91, kind: RegularFile }
    val directory = { name: generatedFilename(List("1")), trace: 1, kind: Directory }
    val symlink = { name: generatedFilename(List("2")), trace: 2, kind: Symlink }
    val special = { name: generatedFilename(List("3")), trace: 3, kind: Other }
    val leadingZero = { name: generatedFilename(List("0", "4")), trace: 4, kind: RegularFile }
    and {
      orderedGeneratedEntries(List(later, directory, symlink, special, leadingZero, first)) == List(42, 91),
      orderedGeneratedEntries(List(directory, symlink, special, leadingZero)) == List(),
    }
  }

  run veryLongFileSequencesSortWithoutIntegerConversionTest = {
    val digits = range(0, 21).foldl(List(), (acc, _) => acc.append("9"))
    val large = { name: generatedFilename(digits), trace: 1 }
    val larger = { name: generatedFilename(List("1").concat(digits)), trace: 2 }
    orderedGeneratedTraces(List(larger, large)) == List(1, 2)
  }
}
