module quint_cli_test {
  import quint_cli.* from "./quint_cli"

  pure val defaultSimulation: SimulationOptions = {
    init: CliDefault,
    step: CliDefault,
    nTraces: CliDefault,
    maxSamples: CliDefault,
    maxSteps: CliDefault,
  }

  pure val baseRequest: CliRequest = {
    executable: "/chosen bin/quint",
    model: "/project/models/counter test.qnt",
    workspace: 1,
    main: CliDefault,
    backend: CliDefault,
    seed: CliDefault,
    config: Simulation(defaultSimulation),
  }

  run simulationDefaultsTest =
    quintCommand(baseRequest, List("0")) == CommandReady({
      executable: "/chosen bin/quint",
      workspace: 1,
      seed: List("0"),
      argv: List(
        LiteralArgument("run"),
        LiteralArgument("/project/models/counter test.qnt"),
        LiteralArgument("--mbt"),
        StringOption({ flag: "--out-itf", value: "trace_{seq}.itf.json" }),
        SeedOption(List("0")),
        IntegerOption({ flag: "--n-traces", value: 1 }),
        IntegerOption({ flag: "--max-samples", value: 1 }),
      ),
    })

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
      executable: baseRequest.executable,
      workspace: baseRequest.workspace,
      seed: List("4", "2"),
      argv: List(
        LiteralArgument("run"),
        LiteralArgument(baseRequest.model),
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
      executable: baseRequest.executable,
      workspace: baseRequest.workspace,
      seed: List("5"),
      argv: List(
        LiteralArgument("test"),
        LiteralArgument(baseRequest.model),
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
      executable: baseRequest.executable,
      workspace: baseRequest.workspace,
      seed: List("0"),
      argv: List(
        LiteralArgument("test"),
        LiteralArgument(baseRequest.model),
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

  run veryLongFileSequencesSortWithoutIntegerConversionTest = {
    val digits = range(0, 21).foldl(List(), (acc, _) => acc.append("9"))
    val large = { name: generatedFilename(digits), trace: 1 }
    val larger = { name: generatedFilename(List("1").concat(digits)), trace: 2 }
    orderedGeneratedTraces(List(larger, large)) == List(1, 2)
  }
}
