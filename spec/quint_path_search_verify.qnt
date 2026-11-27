// Exhaust the OS responses for three PATH entries without probing an actual filesystem.
module quint_path_search_verify {
  import quint_cli.* from "./quint_cli"
  import quint_path_search.* from "./quint_path_search"

  pure val directory = "/project"
  pure val command = "quint"
  pure val entries = List(RelativePath(""), RelativePath("bin"), AbsolutePath("/usr/bin"))
  pure val candidates: List[Candidate] = List(
    { directory: AbsoluteTarget("/project"), name: command },
    { directory: AnchoredPath({ directory: "/project", path: "bin" }), name: command },
    { directory: AbsoluteTarget("/usr/bin"), name: command },
  )
  pure val outcomes = Set(Absent, Unusable("permission denied"), Runnable)

  var observations: List[Observation]

  action init: bool = {
    nondet first = outcomes.oneOf()
    nondet second = outcomes.oneOf()
    nondet third = outcomes.oneOf()
    observations' = List(first, second, third)
  }

  action step: bool = observations' = observations

  pure def firstIndex(statuses: List[Observation], condition: (Observation) => bool): int =
    statuses.indices().fold(statuses.length(), (earliest, index) =>
      if (index < earliest and condition(statuses.nth(index))) index else earliest)

  pure def wasRejected(observation: Observation): bool =
    match observation {
      | Unusable(_) => true
      | _ => false
    }

  val searchAgreesWithPathOrder: bool = {
    val end = candidates.length()
    val runnable = firstIndex(observations, observation => observation == Runnable)
    val rejected = firstIndex(observations, wasRejected)
    val resolution =
      if (runnable < end) Found(candidates.nth(runnable))
      else if (rejected < end)
        match observations.nth(rejected) {
          | Unusable(cause) => Rejected({ candidate: candidates.nth(rejected), cause: cause })
          | _ => CommandNotFound(command)
        }
      else CommandNotFound(command)
    val attempted = candidates.slice(0, if (runnable < end) runnable + 1 else end)
    val byCandidate = candidates.indices().fold(Map(), (acc, index) =>
      acc.put(candidates.nth(index), observations.nth(index)))
    searchPath(directory, command, entries, byCandidate) == { resolution: resolution, attempted: attempted }
  }
}
