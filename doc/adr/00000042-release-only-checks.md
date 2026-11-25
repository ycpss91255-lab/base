# Release-only checks: which CI jobs gate a release and not a change

> Serves: PRD invariant 7 (rigorous test bar) -- which CI run a check
> belongs to; a swappable mechanism, not the invariant.

- **Date:** 2026-11-26
- **Status:** Accepted
- **Relates to:** #1592 (the owner's decision), #2177 (`mutation-roster`),
  #2176 (`config-gen-redpath`), #1461 (the required-kill roster), #1547 (the
  redpath's shards), #1584 and #1587 (per-job selection, the merge queue),
  ADR-00000017 (CI throughput), ADR-00000027 (release cadence),
  ADR-00000039 (the config generator's gates)

## Context

The required-kill roster (#1461) proves that a test notices when the guard
it covers is removed. Its hosted job, `mutation-roster`, ran for every code
change three times on the way to `main`: on the pull request, on the merge
group and on the push. No ADR recorded that it must pass; the rule lived in
`self-test.yaml` and in the specs that hold it, so this record is the first
one and amends none.

#1592 asked whether it should keep blocking every merge, and deferred the
answer until #1584 merged and the cost could be measured. Measured over the
jobs API on 2026-11-25:

| run | event | all jobs, machine minutes | `mutation-roster` (21 legs) | slowest leg |
|---|---|---:|---:|---:|
| 45515901069 | `pull_request` | 240 | 86 | 306 s |
| 45519875638 | `merge_group` | 243 | 79 | 292 s |
| 45522285796 | `push` (`main`) | 262 | 85 | 294 s |

It is about a third of every run, and 21 jobs of a 20-job concurrency cap
(ADR-00000017). Its slowest leg is about five minutes, so it was not what a
pull request waits for. Of its 354 rows, 46 mutate what base ships
(`dist/`); 180 mutate the test tooling and 107 the version watch.

The config generator's redpath plants one defect per Go gate in a scratch
copy and requires each to go red on its own gate. Its hosted job,
`config-gen-redpath`, ran on the same three runs, as 46, 49 and 56 machine
minutes over 5 shards. Its slowest shard, 742 s, 967 s and 984 s, was the
longest job of each run; the next was a coverage shard at 655 to 667 s.

## Decision

The owner decided on 2026-11-26 (#1592) that the roster and the redpath no
longer block every change and block a release instead.

1. **A release-only check** is a hosted job of `self-test.yaml` that a tag
   push and a `workflow_dispatch` run select, and that a pull request, a
   merge group and a push to a branch skip. The set is:

   | job | since | before a release, locally |
   |---|---|---|
   | `mutation-roster` | #2177 | `just test mutation-required` |
   | `config-gen-redpath` | #2176 | `just test go-redpath` |

2. **The event alone decides.** The `classify` job's diff step writes the
   `select_<job>` key of each release-only job from the event and the ref,
   in one place, before it looks at the diff. The map of which job a diff
   can affect (`script/ci/check_selection.sh`) does not name them. It fails
   closed: an event or a ref the step has no case for runs them.
3. **One gate shape.** A release-only job keeps the `if:` every gated job
   has, on its own key, and stays in `needs:` of `ci-rollup` and of
   `release`. So `ci-rollup` passes its skip only where `classify` wrote
   `false`, and names it in its notice; `release` runs only when it
   succeeded, not when it skipped.
4. **Local matches hosted.** The no-flag `just test` and the pre-PR mirror
   stand for the pull request gate, so they do not run it either. The mirror
   lists it as excluded, with the recipe to run. For the config generator the
   mirror runs `just test go-gates`, the recipe of the hosted gates job;
   `just test go` stays the gates and then the redpath, all that a tag runs
   for it.
5. **Before a release**, run it on the commit to be tagged: `gh workflow run
   self-test.yaml --ref main`, or the local command in the table.
   `workflow_dispatch` is kept for this.

No roster row is removed or changed, and the specs that read the roster as
data (every row still applies to its subject, has a witness, and fits its
leg) still run on every pull request. No redpath case is removed or changed
either, and `config_gen_gates_spec.bats` still runs the redpath against a
stub runner on every pull request that selects coverage. `config-gen-gates`
keeps its own selection, and ADR-00000039's rule that one recipe runs the Go
gates in every environment stands: that recipe is `just test go-gates`.

## Consequences

- About a third of the machine time of every pull request, merge group and
  push to `main` goes away with the roster, and 21 jobs of each. The wait for
  one pull request does not get visibly shorter by that.
- About another fifth goes away with the redpath, and 5 jobs of each. The
  longest job of a run is then a coverage shard, about 11 minutes.
- **A test that stops killing its mutant, or a Go gate that can no longer go
  red, can reach `main`** and is found only at the next release or dispatch,
  after later changes have landed on top of it.
- **A red release-only check on a tag comes after the tag exists.** The tag
  also starts `release-test-tools.yaml`, which publishes the test-tools
  images without waiting for it. Only the GitHub Release is withheld. Running
  the checks before tagging is what avoids this.
- A run whose `ci-rollup` is green no longer says the release-only checks
  passed. The rollup's notice names the jobs that did not run.

## Alternatives

- **Keep blocking every merge.** Rejected by the owner on the figures above.
- **Run only the rows a diff can affect (#1604).** Still open: every way
  found so far to derive the files a row's spec reads has failed open. It
  would shrink the cost of the rows that run, and can be added later.
- **A non-blocking tier that opens an issue on a red roster (#1592's first
  form).** Not taken: it needs someone to triage the issues, and a release
  could still be published over a red roster.
- **Delete rows until it is cheap.** Out of scope: the decision moves when
  the roster runs, not what it checks.
