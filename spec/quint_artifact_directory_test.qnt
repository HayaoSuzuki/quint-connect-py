module quint_artifact_directory_test {
  import quint_cli as cli from "./quint_cli"
  import quint_filesystem as fs from "./quint_filesystem"
  import quint_connect_documents.* from "./quint_connect"
  pure val occupiedRoot = "prior artifacts"
  pure val firstDirectory = 50
  pure val earlierArtifacts: fs::ArtifactDirectory -> fs::TraceFiles =
    Map({ root: occupiedRoot, directory: firstDirectory } -> Map(2 -> otherBytes))
  import quint_connect(CALL_IDS = Set(1, 2), WORKSPACE_IDS = Set(1, 2), DRIVER_IDS = Set(1, 2),
    GENERATED_INPUTS = generatedInputs, SAVED_INPUTS = Map(), SAVED_ALIASES = Map(),
    EXISTING_ARTIFACTS = earlierArtifacts).* from "./quint_connect"

  pure val root = "shared artifacts"
  pure val secondDirectory = 51
  pure val firstPath = fs::evidencePath(root, firstDirectory, 2)
  pure val secondPath = fs::evidencePath(root, secondDirectory, 2)
  pure val secondBytes = originalBytes.append(32)

  action findMismatch(id: int, bytes: fs::Bytes, saveRoot: str): bool =
    startRequestedRun(id, simulatorRequest(id, simulationWithCount(1)), sampleSeed, saveRoot, itemsSelection)
      .then(startProcess(id))
      .then(completeProcessSuccess(id, List({
        name: cli::generatedFilename(List("2")), trace: 2, bytes: bytes,
      })))
      .then(listGeneratedOutput(id, ListingSucceeded))
      .then(readGeneratedInput(id, ReadSucceeded))
      .then(createDriver(id, FactorySucceeded(id)))
      .then(applyOperation(id, OperationApplied))
      .then(observeState(id, Observed(integerDigit(1))))

  def lookupSave(id: int, expected: SaveResult): bool =
    hasEvent(calls.get(id).history, event =>
      match event {
        | FailureRecognized(error) =>
          match error {
            | StatesDiffer(mismatch) =>
              mismatch.detail.actual == integerDigit(1) and
                mismatch.artifacts == FromGeneration({ seed: sampleSeed, save: expected })
            | _ => false
          }
        | _ => false
      }
    )

  run artifactParentUsesCallerDirectoryOrSystemDefaultTest = {
    val explicit = cli::CliSpecified(cli::RelativePath("../artifacts"))
    val configured = cli::AnchoredPath({ directory: "/caller", path: "../artifacts" })
    val fallback = cli::AbsoluteTarget("/system-temp")
    val folders = Map(configured -> root, fallback -> occupiedRoot)
    val first = { ...simulatorRequest(1, simulationWithCount(1)), callerDirectory: "/caller" }
    val second = { ...simulatorRequest(2, simulationWithCount(1)), callerDirectory: "/other" }
    init
      .then(startRunWithArtifactParent(1, first, sampleSeed, explicit, "/system-temp", folders, itemsSelection))
      .then(startRunWithArtifactParent(2, second, sampleSeed, cli::CliDefault, "/system-temp", folders, itemsSelection))
      .expect(filesystem.workspaces.get(1).root == root and filesystem.workspaces.get(2).root == occupiedRoot and safety)
  }

  run preexistingArtifactSurvivesReservationCollisionTest = {
    val earlier = fs::evidencePath(occupiedRoot, firstDirectory, 2)
    val later = fs::evidencePath(occupiedRoot, secondDirectory, 2)
    init
      .then(findMismatch(1, originalBytes, occupiedRoot))
      .then(planArtifactDirectories(1, List(firstDirectory, secondDirectory)))
      .then(tryArtifactDirectory(1, StorageSucceeded))
      .expect(filesystem.files.get(earlier) == otherBytes and safety)
      .then(tryArtifactDirectory(1, StorageSucceeded))
      .then(beginArtifactCopy(1))
      .then(writeArtifactCopy(1, originalBytes.length()))
      .then(completeArtifactCopy(1, StorageSucceeded))
      .then(cleanWorkspace(1, StorageSucceeded))
      .expect(filesystem.files.get(earlier) == otherBytes and
        filesystem.files.get(later) == originalBytes and lookupSave(1, ArtifactSaved(later)) and safety)
  }

  run collidingCallRetriesWithoutReplacingPublishedBytesTest =
    init
      .then(findMismatch(1, originalBytes, root))
      .then(findMismatch(2, secondBytes, root))
      .then(planArtifactDirectories(1, List(firstDirectory)))
      .then(tryArtifactDirectory(1, StorageSucceeded))
      .then(beginArtifactCopy(1))
      .then(writeArtifactCopy(1, originalBytes.length()))
      .then(completeArtifactCopy(1, StorageSucceeded))
      .then(planArtifactDirectories(2, List(firstDirectory, secondDirectory)))
      .then(tryArtifactDirectory(2, StorageSucceeded))
      .expect(filesystem.files.get(firstPath) == originalBytes and
        filesystem.workspaces.get(2).artifactDirectory == fs::NoArtifactDirectory and safety)
      .then(tryArtifactDirectory(2, StorageSucceeded))
      .then(beginArtifactCopy(2))
      .then(writeArtifactCopy(2, secondBytes.length()))
      .then(completeArtifactCopy(2, StorageSucceeded))
      .then(cleanWorkspace(1, StorageSucceeded))
      .then(cleanWorkspace(2, StorageSucceeded))
      .expect(lookupSave(1, ArtifactSaved(firstPath)) and lookupSave(2, ArtifactSaved(secondPath)) and
        filesystem.files.get(firstPath) == originalBytes and filesystem.files.get(secondPath) == secondBytes and safety)

  run directoryIoFailureKeepsOriginalMismatchAndCleanupNoteTest =
    init
      .then(findMismatch(1, originalBytes, root))
      .then(planArtifactDirectories(1, List(firstDirectory)))
      .then(tryArtifactDirectory(1, StorageFailed("directory permission denied")))
      .then(cleanWorkspace(1, StorageFailed("cleanup failed")))
      .expect(lookupSave(1, ArtifactDirectoryFailed({
        root: root, directory: firstDirectory, cause: "directory permission denied",
      })) and not(filesystem.files.keys().contains(firstPath)) and
        fs::artifactDirectoryAvailable(filesystem, root, firstDirectory) and
        (match calls.get(1).phase {
          | Finished(outcome) =>
            match outcome {
              | Failed(failure) => failure.cleanup == CleanupAlsoFailed("cleanup failed")
              | _ => false
            }
          | _ => false
        }) and safety)

  run exhaustingCollidingCandidatesDoesNotTouchOwnedDirectoryTest =
    init
      .then(findMismatch(1, originalBytes, root))
      .then(findMismatch(2, secondBytes, root))
      .then(planArtifactDirectories(1, List(firstDirectory)))
      .then(tryArtifactDirectory(1, StorageSucceeded))
      .then(planArtifactDirectories(2, List(firstDirectory)))
      .then(tryArtifactDirectory(2, StorageSucceeded))
      .expect(filesystem.artifactDirectories.get({ root: root, directory: firstDirectory }) ==
        fs::OwnedArtifactDirectory(1) and lookupSave(2, ArtifactDirectoryFailed({
          root: root, directory: firstDirectory, cause: "artifact directory already exists",
        })) and safety)
      .then(cleanWorkspace(2, StorageSucceeded))
      .then(beginArtifactCopy(1))
      .then(writeArtifactCopy(1, originalBytes.length()))
      .then(completeArtifactCopy(1, StorageSucceeded))
      .then(cleanWorkspace(1, StorageSucceeded))
      .expect(filesystem.files.get(firstPath) == originalBytes and safety)
}
