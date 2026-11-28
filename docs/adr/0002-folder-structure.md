# 2. Folder structure

**Status:** Accepted

**Date:** 2026-11-28

## Context

Weather has two parts with different stacks: a Spring Boot API and an Angular web page. Each part should build,
test and be checked on its own, and the factory needs clear zones to fence what each station may change.

## Decision

Both parts sit at the top of the repo, each in its own folder with its own build:

- `api/`: the Spring Boot app that takes in public weather data, works out the averages and serves them through the
  API. Standard Maven layout: source in `api/src/main/`, tests in `api/src/test/`, dependencies in `api/pom.xml`.
  Code lives under the `com.example.weather` package; HTTP controllers live in `com.example.weather.web`, and no
  other package depends on it.
- `ui/`: the Angular web page where a user types in a zip code and a number of days and sees the averages. Standard
  Angular CLI layout: source in `ui/src/`, tests next to the code as `*.spec.ts`, dependencies in `ui/package.json`
  and `ui/package-lock.json`.
- `docs/adr/`: architecture decision records.
- `.factory-manager/`: the factory definition, its role files and check scripts.

## Consequences

- The factory's zones follow these folders (`api-source`, `api-tests`, `api-dependencies`, `ui-source`, `ui-tests`,
  `ui-dependencies`).
- Because Angular keeps specs beside the code, the `ui-source` zone (`ui/src/**`, `ui/public/**`) excludes
  `*.spec.ts` files, which form the `ui-tests` zone, so no path is in two zones.
- The parts talk only over HTTP; neither imports code from the other.
