# srun

`srun` runs Crystal specs and standalone Crystal acceptance scenarios in
separate processes, with a timeout and a full output log for every target.

## Commands

```sh
srun                 # scenarios if ./scen exists; otherwise specs
srun specs           # spec/**/*_spec.cr, one `crystal spec` process per file
srun scenarios       # scen/**/*.scen.cr, one `crystal run` process per file
srun scenarios -t 60 # 60-second timeout for each scenario
```

The `specs` command always preserves per-file process isolation. There is no
suite-wide Crystal spec process. Explicit subcommands override automatic
selection: `srun specs` still runs specs when `./scen` exists, and
`srun scenarios` always selects scenarios.

A scenario is an ordinary Crystal source file. It should return exit status 0
when its acceptance checks pass and a non-zero exit status when they fail. Each
scenario is executed from the current project directory with `crystal run`, so
it can load dependencies installed by Shards and use project-local resources.

## Results

Every invocation creates a timestamped `*.srun.*` directory in the current
working directory:

- `passing/`: complete output from successful targets.
- `failing/`: complete output from failed, timed-out or unlaunchable targets.
- `report.txt`: summary listing every discovered spec or scenario, its result,
  elapsed time, exit status and full log path.

`SRUN_TIMEOUT` sets the default per-target timeout in seconds. `--timeout`
(and `-t`) overrides it for one invocation. The default is 10 seconds.

See [the execution flow](docs/design/execution-flow.md) for the method and
component dependency map.

## Development

```sh
bundle install
shards install
bundle exec rake
bundle exec rspec
```
