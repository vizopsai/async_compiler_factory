#!/usr/bin/env python3
"""
Plot test pass rates and lines of code over time from timeseries.csv.

Usage:
    python3 plot_timeseries.py                          # uses results/timeseries.csv
    python3 plot_timeseries.py path/to/timeseries.csv
"""

import csv
import sys
import os
from collections import defaultdict

import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

def load_csv(path):
    repos = defaultdict(lambda: {"time": [], "passed": [], "total": [], "loc": [], "msg": []})
    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            repo = row["repo"]
            repos[repo]["time"].append(int(row["time_offset_min"]))
            repos[repo]["passed"].append(int(row["tests_passed"]))
            repos[repo]["total"].append(int(row["tests_total"]))
            repos[repo]["loc"].append(int(row["loc"]))
            repos[repo]["msg"].append(row["message"])
    return repos

LABELS = {
    "scaffolding_1_120": "1 agent, 120 min",
    "scaffolding_2_60":  "2 agents, 60 min",
}

COLORS = {
    "scaffolding_1_120": "#2563eb",
    "scaffolding_2_60":  "#dc2626",
}

def plot(repos, output_path):
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 7), sharex=True,
                                    gridspec_kw={"hspace": 0.08})

    for repo, data in repos.items():
        label = LABELS.get(repo, repo)
        color = COLORS.get(repo, None)

        # Tests passed
        ax1.step(data["time"], data["passed"], where="post",
                 label=label, color=color, linewidth=2)

        # Lines of code
        ax2.step(data["time"], data["loc"], where="post",
                 label=label, color=color, linewidth=2)

    # --- Tests axis ---
    ax1.set_ylabel("Tests Passing (out of 16)")
    ax1.set_ylim(-0.5, max(d["total"][0] for d in repos.values()) + 1)
    ax1.yaxis.set_major_locator(ticker.MultipleLocator(4))
    ax1.axhline(y=16, color="gray", linestyle=":", linewidth=1, alpha=0.5)
    ax1.legend(loc="center right")
    ax1.grid(axis="y", alpha=0.3)
    ax1.set_title("CCC Agent Teams: Progress Over Time")

    # --- LOC axis ---
    ax2.set_ylabel("Lines of Rust")
    ax2.set_xlabel("Minutes Since Start")
    ax2.xaxis.set_major_locator(ticker.MultipleLocator(10))
    ax2.legend(loc="center right")
    ax2.grid(axis="y", alpha=0.3)

    fig.tight_layout()
    fig.savefig(output_path, dpi=150)
    print(f"Saved plot to {output_path}")


if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    csv_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(script_dir, "results", "timeseries.csv")
    output_path = os.path.splitext(csv_path)[0] + ".png"

    if not os.path.exists(csv_path):
        print(f"ERROR: {csv_path} not found. Run ./timeseries.sh first.")
        sys.exit(1)

    repos = load_csv(csv_path)
    plot(repos, output_path)
