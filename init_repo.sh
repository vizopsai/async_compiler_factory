#!/bin/bash
# =============================================================================
# Initialize the bare upstream repository with seed content
# =============================================================================
# Run this once before launching agents. Creates the shared bare repo
# and seeds it with the initial Rust project skeleton.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPSTREAM_DIR="$SCRIPT_DIR/upstream.git"
TEMP_CLONE="$(mktemp -d)"

if [ -d "$UPSTREAM_DIR" ]; then
    echo "upstream.git already exists. Delete it first to re-initialize."
    echo "  rm -rf $UPSTREAM_DIR"
    exit 1
fi

echo "Creating bare repo at $UPSTREAM_DIR..."
git init --bare "$UPSTREAM_DIR"

echo "Seeding initial project structure..."
git clone "$UPSTREAM_DIR" "$TEMP_CLONE/code"
cd "$TEMP_CLONE/code"

git config user.name "Claude Opus 4.6"
git config user.email "noreply@anthropic.com"

# ---- Directory structure ----
mkdir -p src current_tasks ideas projects
touch current_tasks/.gitkeep
touch projects/.gitkeep

# ---- Copy CLAUDE.md from scaffolding ----
cp "$SCRIPT_DIR/CLAUDE.md" CLAUDE.md

# ---- Cargo.toml ----
cat > Cargo.toml << 'EOF'
[package]
name = "ccc"
version = "0.1.0"
edition = "2021"
description = "Claude's C Compiler - a Rust-based C compiler targeting x86-64, i686, AArch64, and RISC-V 64"

[[bin]]
name = "ccc"
path = "src/main.rs"
EOF

# ---- src/main.rs ----
cat > src/main.rs << 'EOF'
use std::env;
use std::fs;
use std::process;

fn main() {
    let args: Vec<String> = env::args().collect();

    let mut input_file = None;
    let mut output_file = String::from("a.out");
    let mut i = 1;

    while i < args.len() {
        match args[i].as_str() {
            "-o" => {
                i += 1;
                if i < args.len() {
                    output_file = args[i].clone();
                }
            }
            "-c" => {
                // Compile only, don't link - TODO
            }
            "-S" => {
                // Output assembly - TODO
            }
            arg if !arg.starts_with('-') => {
                input_file = Some(arg.to_string());
            }
            _ => {
                // Ignore unknown flags for now
            }
        }
        i += 1;
    }

    let input_file = match input_file {
        Some(f) => f,
        None => {
            eprintln!("ccc: error: no input files");
            process::exit(1);
        }
    };

    let _source = match fs::read_to_string(&input_file) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("ccc: error: {}: {}", input_file, e);
            process::exit(1);
        }
    };

    // TODO: Implement the compilation pipeline:
    // 1. Lexer: tokenize source
    // 2. Parser: parse tokens into AST
    // 3. Type checker: semantic analysis
    // 4. IR generation: lower AST to SSA IR
    // 5. Optimizer: optimization passes
    // 6. Code generation: emit x86-64 assembly
    // 7. Assemble and link (call system as/ld)

    eprintln!("ccc: error: compilation not yet implemented");
    eprintln!("  input: {} ({} bytes)", input_file, _source.len());
    eprintln!("  output: {}", output_file);
    process::exit(1);
}
EOF

# ---- README.md ----
cat > README.md << 'EOF'
# CCC - Claude's C Compiler

A Rust-based C compiler targeting x86-64, i686, AArch64, and RISC-V 64.
Written from scratch with no dependencies beyond the Rust standard library.

## Building

```
cargo build --release
```

The compiler binary will be at `target/release/ccc`.

## Usage

```
./target/release/ccc input.c -o output
```

## Testing

```
./run_tests.sh --fast    # Quick 1% sample (~30 seconds)
./run_tests.sh           # Full test suite
```

Test suites are located at `/test-suites/` inside the Docker container.

## Project Status

The compiler is under active development by autonomous Claude agents.
Check `current_tasks/` for ongoing work and `ideas/` for planned improvements.

## Architecture

See `DESIGN_DOC.md` for the compilation pipeline design.
EOF

# ---- DESIGN_DOC.md ----
cat > DESIGN_DOC.md << 'EOF'
# CCC Design Document

## Overview

CCC is a C compiler written in Rust. It targets multiple architectures:
- x86-64 (primary target)
- i686 (32-bit x86)
- AArch64 (ARM 64-bit)
- RISC-V 64

The compiler is a clean-room implementation with no external dependencies
beyond the Rust standard library.

## Compilation Pipeline

```
Source Code (.c)
    |
    v
+----------+
|  Lexer   |  Tokenize source into token stream
+----------+
    |
    v
+----------+
|  Parser  |  Parse tokens into AST
+----------+
    |
    v
+--------------+
|  Type Check  |  Semantic analysis, type checking, symbol resolution
+--------------+
    |
    v
+----------+
|  IR Gen  |  Lower AST to SSA-based intermediate representation
+----------+
    |
    v
+--------------+
|  Optimizer   |  Optimization passes on SSA IR
+--------------+
    |
    v
+--------------+
|  Code Gen    |  Architecture-specific code generation
+--------------+
    |
    v
Assembly (.s) --> as --> Object (.o) --> ld --> Executable
```

## Module Structure

- `src/main.rs` - Entry point, argument parsing, driver
- `src/lexer/` - Tokenizer (keywords, identifiers, literals, operators)
- `src/parser/` - C parser producing AST
- `src/ast/` - AST type definitions
- `src/types/` - Type system and type checking
- `src/ir/` - SSA-based intermediate representation
- `src/optimizer/` - Optimization passes (constant folding, DCE, etc.)
- `src/codegen/` - Code generation backends
  - `src/codegen/x86_64/` - x86-64 code generator
  - `src/codegen/i686/` - i686 code generator
  - `src/codegen/aarch64/` - AArch64 code generator
  - `src/codegen/riscv64/` - RISC-V 64 code generator

## Key Design Decisions

1. **SSA-based IR**: Enables powerful optimization passes. All values are
   assigned exactly once, making dataflow analysis straightforward.

2. **No dependencies**: Only uses the Rust standard library. The compiler
   should be fully self-contained.

3. **Multi-backend**: Shared frontend (lexer, parser, type checker, IR)
   with architecture-specific code generation backends.

4. **GCC compatibility**: Aims to accept the same command-line flags and
   produce compatible output. Uses the system assembler (as) and linker (ld).

5. **Incremental development**: Start with the simplest possible programs
   (return constants) and progressively add features.
EOF

# ---- run_tests.sh ----
cat > run_tests.sh << 'RUNTEST_EOF'
#!/bin/bash
# =============================================================================
# CCC Test Runner
# =============================================================================
# Usage:
#   ./run_tests.sh                 # Full test suite
#   ./run_tests.sh --fast          # 1% sample (~30 seconds)
#   ./run_tests.sh --ratio 10     # 10% sample
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPILER="${COMPILER:-$SCRIPT_DIR/target/release/ccc}"
TEST_SUITES_DIR="${TEST_SUITES_DIR:-/test-suites}"
RATIO=100
SEED="${AGENT_ID:-default}"
LOG_DIR="/workspace/test_logs"

mkdir -p "$LOG_DIR"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --fast)
            RATIO=1
            shift
            ;;
        --ratio)
            RATIO="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

echo "CCC Test Runner"
echo "  Compiler: $COMPILER"
echo "  Ratio: ${RATIO}%"
echo "  Seed: $SEED"
echo ""

# Ensure compiler is built
if [ ! -f "$COMPILER" ]; then
    echo "ERROR: Compiler not found at $COMPILER"
    echo "Run: cargo build --release"
    exit 1
fi

PASS=0
FAIL=0
TOTAL=0
FAIL_LOG="$LOG_DIR/failures.log"
> "$FAIL_LOG"

for SUITE_DIR in "$TEST_SUITES_DIR"/*/; do
    [ -d "$SUITE_DIR" ] || continue
    SUITE_NAME=$(basename "$SUITE_DIR")

    while IFS= read -r -d '' test_file; do
        TOTAL=$((TOTAL + 1))

        # Deterministic sampling: hash(seed + test_path) mod 100 < ratio
        HASH=$(echo "${SEED}${test_file}" | md5sum | cut -c1-8)
        HASH_NUM=$((16#$HASH % 100))
        if [ "$HASH_NUM" -ge "$RATIO" ]; then
            continue
        fi

        BASENAME=$(basename "$test_file" .c)
        OUTPUT="/tmp/ccc_test_${BASENAME}"

        # Try to compile
        if $COMPILER -o "$OUTPUT" "$test_file" 2>/dev/null; then
            # Try to run
            RESULT=$("$OUTPUT" 2>/dev/null) || true
            EXIT_CODE=${PIPESTATUS[0]:-$?}

            # Re-run to capture exit code properly
            "$OUTPUT" > /tmp/ccc_test_stdout 2>/dev/null
            EXIT_CODE=$?
            RESULT=$(cat /tmp/ccc_test_stdout)

            EXPECTED_FILE="${test_file%.c}.expected"
            if [ -f "$EXPECTED_FILE" ]; then
                EXPECTED=$(cat "$EXPECTED_FILE")
                if [ "$RESULT" = "$EXPECTED" ] && [ "$EXIT_CODE" -eq 0 ]; then
                    PASS=$((PASS + 1))
                else
                    FAIL=$((FAIL + 1))
                    echo "ERROR $SUITE_NAME/$BASENAME: expected='$(head -c 80 "$EXPECTED_FILE")' got='$(echo "$RESULT" | head -c 80)' exit=$EXIT_CODE" >> "$FAIL_LOG"
                fi
            else
                if [ "$EXIT_CODE" -eq 0 ]; then
                    PASS=$((PASS + 1))
                else
                    FAIL=$((FAIL + 1))
                    echo "ERROR $SUITE_NAME/$BASENAME: crash exit=$EXIT_CODE" >> "$FAIL_LOG"
                fi
            fi
        else
            FAIL=$((FAIL + 1))
            echo "ERROR $SUITE_NAME/$BASENAME: compilation failed" >> "$FAIL_LOG"
        fi

        rm -f "$OUTPUT" /tmp/ccc_test_stdout
    done < <(find "$SUITE_DIR" -name "*.c" -print0 | sort -z)
done

TESTED=$((PASS + FAIL))
if [ "$TESTED" -gt 0 ]; then
    PCT=$(echo "scale=1; $PASS * 100 / $TESTED" | bc)
    echo "Results: $PASS/$TESTED ($PCT%) [from $TOTAL total tests]"
else
    echo "Results: no tests run (0 total test files found)"
fi

if [ -s "$FAIL_LOG" ]; then
    FAIL_COUNT=$(wc -l < "$FAIL_LOG")
    echo "$FAIL_COUNT failures logged to $FAIL_LOG"
    head -5 "$FAIL_LOG" | sed 's/^/  /'
    if [ "$FAIL_COUNT" -gt 5 ]; then
        echo "  ... and $((FAIL_COUNT - 5)) more (see $FAIL_LOG)"
    fi
fi
RUNTEST_EOF
chmod +x run_tests.sh

# ---- ideas/initial_tasks.txt ----
cat > ideas/initial_tasks.txt << 'EOF'
Initial Implementation Roadmap
==============================
Priority: HIGH

Build the compiler from scratch in this order:

1. Lexer (src/lexer.rs or src/lexer/)
   - Tokenize C source code
   - Handle keywords, identifiers, integer/string/char literals
   - Handle operators and punctuation
   - Handle comments (// and /* */)

2. Parser (src/parser.rs or src/parser/)
   - Parse token stream into AST
   - Start with: function definitions, return statements, integer literals
   - Then: local variables, arithmetic expressions, if/else, while/for
   - Then: pointers, arrays, structs, function calls

3. Code Generation (src/codegen/ or src/codegen.rs)
   - Start with x86-64 assembly output (AT&T syntax)
   - Use system assembler (as) and linker (gcc -o) to produce executables
   - First milestone: compile "int main() { return 0; }" to working binary

4. Progressive testing against /test-suites/basic/
   - 001_return_zero.c is the first milestone
   - Work through tests in numerical order (increasing difficulty)
   - Tests 001-003: just return values (need: functions, return, literals)
   - Tests 004-007: arithmetic and control flow (need: operators, if, loops)
   - Tests 008-009: function calls and recursion
   - Tests 010-014: pointers, arrays, globals, structs
   - Tests 050+: printf (need: #include, linking with libc)
EOF

# ---- Commit and push ----
git add -A
git commit -m "Initial commit: project skeleton

Seeded with:
- Cargo.toml and src/main.rs (stub compiler that parses args)
- README.md, DESIGN_DOC.md (architecture reference)
- CLAUDE.md (agent instructions)
- run_tests.sh (test runner)
- ideas/initial_tasks.txt (implementation roadmap)

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"

git push origin main 2>/dev/null || git push origin master

# Clean up
rm -rf "$TEMP_CLONE"

echo ""
echo "Upstream repo initialized at: $UPSTREAM_DIR"
echo "Seed content:"
echo "  - Cargo.toml + src/main.rs (compilable stub)"
echo "  - README.md, DESIGN_DOC.md, CLAUDE.md"
echo "  - run_tests.sh (test runner)"
echo "  - ideas/initial_tasks.txt (implementation roadmap)"
echo ""
echo "Ready to run: ./run.sh"
