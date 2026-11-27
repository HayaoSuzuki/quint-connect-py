module quint_parallel_test {
  import quint_connect_documents.* from "./quint_connect"
  import quint_parallel_inputs.* from "./quint_parallel"
  import quint_cli as cli from "./quint_cli"
  import quint_filesystem as fs from "./quint_filesystem"
  import quint_connect(
    CALL_IDS = parallelCallIds, WORKSPACE_IDS = parallelCallIds, DRIVER_IDS = parallelDriverIds,
    GENERATED_INPUTS = parallelGeneratedInputs, SAVED_INPUTS = Map(), SAVED_ALIASES = Map()
  ).* from "./quint_connect"

  pure val sharedRoot = "shared artifacts"
  pure val sharedTrace = 2

  action startCall(id: CallId): bool =
    startRequestedRun(id, simulatorRequest(id, simulationWithCount(1)), sampleSeed, sharedRoot, itemsSelection)

  action emitCallFile(id: CallId): bool =
    startProcess(id).then(completeProcessSuccess(id, List({
      name: cli::generatedFilename(List("2")), trace: sharedTrace, bytes: parallelBytes.get(id),
    }))).then(listGeneratedOutput(id, ListingSucceeded))

  action findMismatch(id: CallId): bool =
    validateGeneratedDocument(id, parallelBytes.get(id))
      .then(createDriver(id, FactorySucceeded(id)))
      .then(applyOperation(id, OperationApplied))
      .then(observeState(id, Observed(integerDigit(1))))

  def hasBytes(path: fs::FilePath, bytes: fs::Bytes): bool =
    if (filesystem.files.keys().contains(path)) filesystem.files.get(path) == bytes
    else false

  run fourCallsWithSameNamesAndSeedAreIsolatedTest =
    init
      .then(startCall(1)).then(startCall(2)).then(startCall(3)).then(startCall(4))
      .expect(filesystem.workspaces.keys() == parallelCallIds and
        parallelCallIds.map(id => parallelBytes.get(id)).size() == 4)
      .then(emitCallFile(4)).then(emitCallFile(2)).then(emitCallFile(1)).then(emitCallFile(3))
      .then(findMismatch(1))
      .then(saveArtifact(1, StorageSucceeded))
      .then(cleanWorkspace(1, StorageSucceeded))
      .expect(Set(2, 3, 4).forall(id => hasBytes(fs::workingPath(id, sharedTrace), parallelBytes.get(id))) and
        hasBytes(fs::evidencePath(sharedRoot, 1, sharedTrace), parallelBytes.get(1)) and
        not(filesystem.files.keys().contains(fs::workingPath(1, sharedTrace))) and safety)
      .then(findMismatch(2))
      .then(saveArtifact(2, StorageSucceeded))
      .then(cleanWorkspaceWithRemoval(2, StorageFailed("partial cleanup"), fs::RemoveInterrupted(Set(sharedTrace))))
      .then(findMismatch(3))
      .then(saveArtifactWithCopy(3, StorageFailed("copy failed"), fs::CopyInterrupted(1)))
      .then(cleanWorkspace(3, StorageSucceeded))
      .then(findMismatch(4))
      .then(saveArtifact(4, StorageSucceeded))
      .then(cleanWorkspace(4, StorageSucceeded))
      .expect(filesystem.files.keys() == Set(
        fs::evidencePath(sharedRoot, 1, sharedTrace), fs::evidencePath(sharedRoot, 2, sharedTrace),
        fs::workingPath(2, sharedTrace), fs::evidencePath(sharedRoot, 4, sharedTrace),
      ) and Set(1, 2, 4).forall(id =>
        hasBytes(fs::evidencePath(sharedRoot, id, sharedTrace), parallelBytes.get(id))
      ) and hasBytes(fs::workingPath(2, sharedTrace), parallelBytes.get(2)) and
        pendingCalls.size() == 0 and safety)
}
