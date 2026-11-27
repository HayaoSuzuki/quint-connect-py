module quint_path_search_test {
  import quint_cli as cli from "./quint_cli"
  import quint_path_search.* from "./quint_path_search"

  pure val caller = "/project"
  pure val name = "quint"
  pure val callerCandidate: Candidate = { directory: cli::AbsoluteTarget("/project"), name: "quint" }
  pure val relativeCandidate: Candidate = {
    directory: cli::AnchoredPath({ directory: "/project", path: "link/../bin" }),
    name: "quint",
  }
  pure val absoluteCandidate: Candidate = { directory: cli::AbsoluteTarget("/usr/bin"), name: "quint" }
  pure val fallbackCandidate: Candidate = { directory: cli::AbsoluteTarget("/fallback"), name: "quint" }

  run firstRunnableEndsSearchTest =
    searchPath(
      caller,
      name,
      List(cli::RelativePath(""), cli::RelativePath("link/../bin"), cli::AbsolutePath("/usr/bin"),
        cli::AbsolutePath("/fallback")),
      Map(relativeCandidate -> Unusable("permission denied"), absoluteCandidate -> Runnable,
        fallbackCandidate -> Runnable),
    ) == {
      resolution: Found(absoluteCandidate),
      attempted: List(callerCandidate, relativeCandidate, absoluteCandidate),
    }

  run firstRejectionSurvivesLaterFailuresTest =
    searchPath(
      caller,
      name,
      List(cli::RelativePath(""), cli::RelativePath("link/../bin"), cli::AbsolutePath("/usr/bin")),
      Map(callerCandidate -> Absent, relativeCandidate -> Unusable("permission denied"),
        absoluteCandidate -> Unusable("not an executable file")),
    ) == {
      resolution: Rejected({ candidate: relativeCandidate, cause: "permission denied" }),
      attempted: List(callerCandidate, relativeCandidate, absoluteCandidate),
    }

  run emptyEntriesUseTheCapturedDirectoryTest =
    searchPath(
      caller,
      name,
      List(cli::RelativePath(""), cli::AbsolutePath("/usr/bin")),
      Map(callerCandidate -> Runnable, absoluteCandidate -> Runnable),
    ) == { resolution: Found(callerCandidate), attempted: List(callerCandidate) }

  run allAbsentReportsCommandNameTest =
    searchPath(
      caller,
      name,
      List(cli::AbsolutePath("/usr/bin"), cli::AbsolutePath("/fallback")),
      Map(absoluteCandidate -> Absent),
    ) == {
      resolution: CommandNotFound("quint"),
      attempted: List(absoluteCandidate, fallbackCandidate),
    }

  run emptyPathHasNoCandidatesTest =
    searchPath(caller, name, List(), Map()) == {
      resolution: CommandNotFound("quint"),
      attempted: List(),
    }

  run duplicateEntriesKeepTheirPositionAndObservationTest =
    searchPath(
      caller,
      name,
      List(cli::RelativePath(""), cli::AbsolutePath("/project"), cli::RelativePath(""), cli::AbsolutePath("/usr/bin")),
      Map(callerCandidate -> Unusable("permission denied")),
    ) == {
      resolution: Rejected({ candidate: callerCandidate, cause: "permission denied" }),
      attempted: List(callerCandidate, callerCandidate, callerCandidate, absoluteCandidate),
    }
}
