# CCC Agent Teams — Scaffolding

Scaffolding to reproduce the results from [Building a C Compiler with Claude Agent Teams](https://www.anthropic.com/engineering/building-c-compiler). Spawns parallel Claude Code agents in Docker containers that coordinate via git to build a C compiler from scratch.

## Quick Start

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
./run.sh              # 2 agents, 60 minutes
```

## Usage

```bash
./run.sh [NUM_AGENTS] [DURATION_MINUTES]
```

Builds the Docker image, initializes the repo, launches agents, prints progress every 5 minutes, and stops when time is up. All state lives in `upstream.git/` — delete it to start fresh, keep it to resume.

```bash
./run.sh 1 10         # 1 agent, 10 minutes (test run, ~$5-15)
./run.sh 2 60         # 2 agents, 1 hour (~$100-300)
./run.sh 4 120        # 4 agents, 2 hours
```

## Checking Progress

```bash
./status.sh           # full snapshot: commits, source stats, live agent work
./status.sh --short   # just commit count + lines of code
```

## Prerequisites

- Docker Desktop installed and running
- `ANTHROPIC_API_KEY` with access to `claude-opus-4-6`
