module quint_parallel_inputs {
  import quint_connect_documents.* from "./quint_connect"
  import quint_filesystem as fs from "./quint_filesystem"

  pure val parallelCallIds: Set[int] = Set(1, 2, 3, 4)
  pure val parallelDriverIds: Set[int] = Set(1, 2, 3, 4, 5, 6, 7, 8)

  // All four files have the same decoded content and distinct original bytes.
  pure val parallelBytes: int -> fs::Bytes = Map(
    1 -> originalBytes,
    2 -> List(32).concat(originalBytes),
    3 -> List(9).concat(originalBytes),
    4 -> originalBytes.concat(List(32)),
  )

  pure val parallelGeneratedInputs: Set[fs::Bytes] =
    generatedInputs.union(parallelCallIds.map(id => parallelBytes.get(id)))
}

module quint_parallel_sample {
  import quint_connect_documents.* from "./quint_connect"
  import quint_parallel_inputs.*
  import quint_filesystem as fs from "./quint_filesystem"
  import quint_connect(
    CALL_IDS = parallelCallIds, WORKSPACE_IDS = parallelCallIds, DRIVER_IDS = parallelDriverIds,
    GENERATED_INPUTS = parallelGeneratedInputs, SAVED_INPUTS = savedInputs
  ).* from "./quint_connect"

  // Exercise arbitrary interleavings once all four calls own a workspace.
  action startTogether: bool =
    if (filesystem.workspaces.keys().size() < 4) {
      nondet id = pendingCalls.oneOf()
      startRequestedRun(
        id, simulatorRequest(id, simulationWithCount(1)),
        sampleSeed, defaultArtifactRoot, itemsSelection
      )
    } else step

  observation fourWorkspacesOverlap =
    filesystem.workspaces.keys().filter(id =>
      filesystem.workspaces.get(id).status == fs::WorkspaceActive
    ).size() == 4

  observation anyRetainedEvidence =
    filesystem.files.keys().exists(path =>
      match path {
        | EvidenceFile(_) => true
        | _ => false
      }
    )

  observation allCallsConcluded = pendingCalls.size() == 0
}
