# 1. Tech stack

**Status:** Accepted

**Date:** 2026-11-28

## Context

Weather is an API, with a simple web page, that collects public US weather data and serves running averages of
temperature, rainfall, wind and humidity for a zip code over a number of days back from today. It needs a backend
that takes in and processes data and serves it over HTTP, and a small web page that calls that API.

## Decision

- **API (`api/`):** Java 21 with Spring Boot (Spring Web MVC), built with Maven through the committed Maven wrapper
  (`api/mvnw`, `api/.mvn/wrapper/`).
  - Tests: JUnit 5 with Spring's test support; reports in `api/target/surefire-reports/`.
  - Lint: Checkstyle (`api/checkstyle.xml`).
  - Architecture rules: ArchUnit tests under `com.example.weather.architecture`.
  - Mutation testing: PIT (`pitest-maven` with the JUnit 5 plugin), failing under the factory's mutation minimum.
- **Web page (`ui/`):** Angular with TypeScript, built with npm; `ui/package-lock.json` is committed.
  - Tests: the Angular CLI unit-test builder (Vitest with jsdom); JUnit XML in `ui/test-results/junit.xml`.
  - Lint: ESLint with angular-eslint.
  - Architecture rules: dependency-cruiser (`ui/.dependency-cruiser.cjs`).
  - Mutation testing: Stryker, failing under the factory's mutation minimum. The Stryker CLI has no threshold
    flag, so `ui/stryker-run.mjs` takes `--thresholds.break` and starts Stryker through its API.

## Consequences

- Building needs a JDK 21 and Node.js with npm; Maven itself comes from the wrapper.
- The factory's check scripts in `.factory-manager/scripts/` run each check for both parts.
- Changing a major framework or tool in either part needs a new ADR.
