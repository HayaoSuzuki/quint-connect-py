module quint_executor_test {
  import quint_cli as cli from "./quint_cli"
  import quint_path_search as path from "./quint_path_search"
  import quint_connect_documents.* from "./quint_connect"
  import quint_connect(CALL_IDS = Set(1), WORKSPACE_IDS = Set(7), DRIVER_IDS = Set(1),
    GENERATED_INPUTS = generatedInputs, SAVED_INPUTS = Map(), SAVED_ALIASES = Map(), EXISTING_ARTIFACTS = Map()).* from "./quint_connect"

  pure val request: cli::CliRequest = {
    ...simulatorRequest(7, simulationWithCount(1)), callerDirectory: "/caller", executable: cli::BareCommand("quint"),
  }

  pure val firstDirectory = cli::RelativePath("tools")
  pure val fallbackDirectory = cli::AbsolutePath("/bin")
  pure val first = path::pathCandidate("/caller", "quint", firstDirectory)
  pure val fallback = path::pathCandidate("/caller", "quint", fallbackDirectory)

  pure def searchInputs(firstResult: path::Observation, secondResult: path::Observation): PathEnvironment =
    { directories: List(firstDirectory, fallbackDirectory), observations: Map(first -> firstResult, fallback -> secondResult) }

  run bareCommandUsesFirstRunnableTargetInPrivateWorkspaceTest =
    init
      .then(startRequestedRunWithPath(1, request, sampleSeed, defaultArtifactRoot, itemsSelection,
        searchInputs(path::Unusable("permission denied"), path::Runnable)))
      .expect(hasEvent(calls.get(1).history, event =>
        match event {
          | CommandPrepared(plan) => plan.target == ExecutableOnPath(fallback) and plan.command.workspace == 7
          | _ => false
        }) and filesystem.workspaces.get(7).owner == 1 and safety)
      .then(failSpawn(1, "launch failed after selection"))
      .then(cleanWorkspace(1, StorageSucceeded))
      .expect(calls.get(1).phase == Finished(failed(QuintFailed({
        seed: sampleSeed, problem: SpawnFailure("launch failed after selection"),
      }))) and safety)

  run pathLookupFailurePreservesFirstCauseWithoutWorkDirectoryTest =
    init
      .then(startRequestedRunWithPath(1, request, sampleSeed, defaultArtifactRoot, itemsSelection,
        searchInputs(path::Unusable("first is not executable"), path::Unusable("second is not executable"))))
      .expect(calls.get(1).phase == Finished(failed(ExecutableLookupFailed({
        seed: sampleSeed, problem: path::Rejected({ candidate: first, cause: "first is not executable" }),
      }))) and filesystem.workspaces.keys().size() == 0 and safety)

  run missingCommandIsDistinguishedFromUnusableCandidateTest =
    init
      .then(startRequestedRun(1, request, sampleSeed, defaultArtifactRoot, itemsSelection))
      .expect(calls.get(1).phase == Finished(failed(ExecutableLookupFailed({
        seed: sampleSeed, problem: path::CommandNotFound("quint"),
      }))) and filesystem == initialFilesystem and safety)
}
