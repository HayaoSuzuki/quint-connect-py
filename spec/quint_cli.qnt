// Command and output-name contract for Quint 0.34.0.
module quint_cli {
  type CliOption[a] = CliDefault | CliSpecified(a)
  type CliBackend = RustBackend | TypeScriptBackend

  // Canonical ASCII decimal digits represent the full unsigned 64-bit range.
  type SeedDigits = List[str]

  type SimulationOptions = {
    init: CliOption[str],
    step: CliOption[str],
    nTraces: CliOption[int],
    maxSamples: CliOption[int],
    maxSteps: CliOption[int],
  }

  type NamedTestOptions = {
    // Each integer is one Unicode code point in the requested test name.
    name: List[int],
    maxSamples: CliOption[int],
  }

  type QuintConfig = Simulation(SimulationOptions) | NamedTestMode(NamedTestOptions)

  type CliRequest = {
    executable: str,
    model: str,
    workspace: int,
    main: CliOption[str],
    backend: CliOption[CliBackend],
    seed: CliOption[SeedDigits],
    config: QuintConfig,
  }

  // Each variant represents one OS argument. Options use flag=value.
  type CliArgument =
    | LiteralArgument(str)
    | StringOption({ flag: str, value: str })
    | IntegerOption({ flag: str, value: int })
    | SeedOption(SeedDigits) // --seed= followed by the joined ASCII digits
    | MatchOption(List[int]) // --match= followed by the encoded pattern

  type QuintCommand = {
    executable: str,
    workspace: int,
    seed: SeedDigits,
    argv: List[CliArgument],
  }

  type CommandResult =
    | CommandReady(QuintCommand)
    | InvalidSeed
    | InvalidTraceCount
    | InvalidSampleLimit
    | InvalidStepLimit

  pure val decimalDigitValues: str -> int = Map(
    "0" -> 0, "1" -> 1, "2" -> 2, "3" -> 3, "4" -> 4,
    "5" -> 5, "6" -> 6, "7" -> 7, "8" -> 8, "9" -> 9,
  )

  pure val maxSeed: SeedDigits = List(
    "1", "8", "4", "4", "6", "7", "4", "4", "0", "7",
    "3", "7", "0", "9", "5", "5", "1", "6", "1", "5",
  )

  pure def canonicalDecimal(digits: List[str]): bool =
    if (digits.length() == 0) false
    else
      (digits.length() == 1 or digits.head() != "0") and
        digits.indices().forall(index => decimalDigitValues.keys().contains(digits.nth(index)))

  pure def decimalLess(left: List[str], right: List[str]): bool =
    if (left.length() != right.length()) left.length() < right.length()
    else
      range(0, left.length()).foldl(0, (comparison, index) =>
        if (comparison != 0) comparison
        else decimalDigitValues.get(left.nth(index)) - decimalDigitValues.get(right.nth(index))
      ) < 0

  pure def validSeed(seed: SeedDigits): bool =
    if (canonicalDecimal(seed)) not(decimalLess(maxSeed, seed))
    else false

  // Quint passes --match to JavaScript's RegExp constructor without flags.
  // Escape ^ $ \ . * + ? ( ) [ ] { } | and add start and end anchors.
  pure val regexMetacharacters: Set[int] =
    Set(94, 36, 92, 46, 42, 43, 63, 40, 41, 91, 93, 123, 125, 124)

  pure def exactTestPattern(name: List[int]): List[int] =
    name.foldl(List(94), (pattern, codePoint) =>
      if (regexMetacharacters.contains(codePoint)) pattern.append(92).append(codePoint)
      else pattern.append(codePoint)
    ).append(36)

  pure def optionOr(option: CliOption[a], fallback: a): a =
    match option {
      | CliDefault => fallback
      | CliSpecified(value) => value
    }

  pure def limitAtLeast(option: CliOption[int], minimum: int): bool =
    match option {
      | CliDefault => true
      | CliSpecified(value) => value >= minimum
    }

  pure def optionArgument(option: CliOption[a], encode: (a) => CliArgument): List[CliArgument] =
    match option {
      | CliDefault => List()
      | CliSpecified(value) => List(encode(value))
    }

  pure def backendName(backend: CliBackend): str =
    match backend {
      | RustBackend => "rust"
      | TypeScriptBackend => "typescript"
    }

  // {seq} works for both commands. Exact selection allows test to use the same template.
  pure val outputTemplate: str = "trace_{seq}.itf.json"

  // Launch in the reserved workspace so Quint only expands placeholders in the basename.
  // The adapter resolves caller-relative model and executable paths before changing cwd.
  pure def quintCommand(request: CliRequest, osSeed: SeedDigits): CommandResult = {
    val seed = optionOr(request.seed, osSeed)
    if (not(validSeed(seed))) InvalidSeed
    else {
      val common = List(
        StringOption({ flag: "--out-itf", value: outputTemplate }),
        SeedOption(seed),
      ).concat(optionArgument(request.main, value => StringOption({ flag: "--main", value: value })))
        .concat(optionArgument(request.backend, value =>
          StringOption({ flag: "--backend", value: backendName(value) })
        ))

      match request.config {
        | Simulation(options) => {
          val nTraces = optionOr(options.nTraces, 1)
          val maxSamples = optionOr(options.maxSamples, nTraces)
          if (nTraces <= 0) InvalidTraceCount
          else if (maxSamples < nTraces) InvalidSampleLimit
          else if (not(limitAtLeast(options.maxSteps, 0))) InvalidStepLimit
          else CommandReady({
            executable: request.executable,
            workspace: request.workspace,
            seed: seed,
            argv: List(LiteralArgument("run"), LiteralArgument(request.model), LiteralArgument("--mbt"))
              .concat(common)
              .append(IntegerOption({ flag: "--n-traces", value: nTraces }))
              .append(IntegerOption({ flag: "--max-samples", value: maxSamples }))
              .concat(optionArgument(options.init, value => StringOption({ flag: "--init", value: value })))
              .concat(optionArgument(options.step, value => StringOption({ flag: "--step", value: value })))
              .concat(optionArgument(options.maxSteps, value =>
                IntegerOption({ flag: "--max-steps", value: value })
              )),
          })
        }
        | NamedTestMode(options) =>
          if (not(limitAtLeast(options.maxSamples, 1))) InvalidSampleLimit
          else CommandReady({
            executable: request.executable,
            workspace: request.workspace,
            seed: seed,
            argv: List(LiteralArgument("test"), LiteralArgument(request.model))
              .concat(common)
              .append(MatchOption(exactTestPattern(options.name)))
              .concat(optionArgument(options.maxSamples, value =>
                IntegerOption({ flag: "--max-samples", value: value })
              )),
          })
      }
    }
  }

  // The filesystem adapter lists files in the workspace and supplies a basename
  // as characters and its associated trace identity.
  type GeneratedFile = { name: List[str], trace: int }
  type OutputSequence = GeneratedSequence(List[str]) | UnrelatedName
  type SequencedFile = { sequence: List[str], trace: int }

  pure val outputPrefix: List[str] = List("t", "r", "a", "c", "e", "_")
  pure val outputSuffix: List[str] = List(".", "i", "t", "f", ".", "j", "s", "o", "n")

  pure def generatedFilename(sequence: List[str]): List[str] =
    outputPrefix.concat(sequence).concat(outputSuffix)

  pure def generatedSequence(name: List[str]): OutputSequence = {
    val start = outputPrefix.length()
    val end = name.length() - outputSuffix.length()
    if (start >= end) UnrelatedName
    else {
      val sequence = name.slice(start, end)
      if (name.slice(0, start) == outputPrefix and
          name.slice(end, name.length()) == outputSuffix and canonicalDecimal(sequence))
        GeneratedSequence(sequence)
      else UnrelatedName
    }
  }

  pure def orderedGeneratedTraces(files: List[GeneratedFile]): List[int] = {
    // A directory has one entry per basename and canonical digits give each sequence one basename.
    val sorted: List[SequencedFile] = files.foldl(List(), (ordered, file) =>
      match generatedSequence(file.name) {
        | UnrelatedName => ordered
        | GeneratedSequence(sequence) => {
          val insertionIndex = ordered.indices().filter(index =>
            not(decimalLess(sequence, ordered.nth(index).sequence))
          ).size()
          ordered.slice(0, insertionIndex)
            .append({ sequence: sequence, trace: file.trace })
            .concat(ordered.slice(insertionIndex, ordered.length()))
        }
      }
    )
    sorted.foldl(List(), (traces, file) => traces.append(file.trace))
  }
}
