// Select a bare command from the PATH captured at the call site.
module quint_path_search {
  import quint_cli as cli from "./quint_cli"

  type Candidate = { directory: cli::ResolvedPath, name: str }
  type Observation = Absent | Unusable(str) | Runnable
  type Resolution =
    | Found(Candidate)
    | Rejected({ candidate: Candidate, cause: str })
    | CommandNotFound(str)
  type SearchResult = { resolution: Resolution, attempted: List[Candidate] }

  // An empty entry uses the captured directory itself. The OS adapter joins the name.
  pure def pathCandidate(directory: str, name: str, entry: cli::InputPath): Candidate = {
    directory: if (entry == cli::RelativePath("")) cli::AbsoluteTarget(directory)
      else cli::resolvePath(directory, entry),
    name: name,
  }

  // The adapter supplies observations for candidate locations. An omitted location is absent.
  pure def searchPath(
    directory: str,
    name: str,
    entries: List[cli::InputPath],
    observations: Candidate -> Observation,
  ): SearchResult = {
    val initial: SearchResult = { resolution: CommandNotFound(name), attempted: List() }
    entries.foldl(initial, (search, entry) =>
      match search.resolution {
        | Found(_) => search
        | _ => {
          val candidate = pathCandidate(directory, name, entry)
          val observation = if (observations.keys().contains(candidate)) observations.get(candidate) else Absent
          val resolution = match observation {
            | Absent => search.resolution
            | Unusable(cause) =>
              if (search.resolution == CommandNotFound(name)) Rejected({ candidate: candidate, cause: cause })
              else search.resolution
            | Runnable => Found(candidate)
          }
          { resolution: resolution, attempted: search.attempted.append(candidate) }
        }
      }
    )
  }
}
