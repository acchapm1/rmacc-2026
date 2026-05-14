---
marp: true
theme: default
class: invert
paginate: true
size: 16:9
style: |
  section {
    font-size: 22px;
  }
  h1 {
    font-size: 40px;
  }
  h2 {
    font-size: 32px;
  }
  pre, code {
    font-size: 18px;
  }
  table {
    font-size: 22px;
  }
  section.lead h1 {
    font-size: 52px;
  }
---

<!-- _class: lead invert -->

# Updating and Optimizing Mutation Detection Pipeline

## Snakemake 7 → 9 on SLURM

Alan Chapman — HPC Systems Analyst
Arizona State University Research Computing

RMACC HPC Symposium 2026 · Boise, ID

`github.com/acchapm1/rmacc-2026`
`acchapm1.github.io/rmacc-2026`

<!--
PRESENTER NOTES

Welcome — I'm Alan Chapman, HPC Systems Analyst at ASU Research Computing.

Quick orientation up front: this is a technical talk. I'm going to spend most of the next 25 minutes showing you actual code — Snakefile snippets, YAML profiles, command lines — from a real workflow we migrated from Snakemake 7 to Snakemake 9 over the second half of last year. If you operate or support Snakemake workflows on a SLURM cluster, this should be directly applicable.

Quick show of hands: who has a Snakemake workflow running on SLURM today? … And who's already on Snakemake 9? OK — that's roughly the gap I'm hoping this talk closes.

Time check: 25 minutes plus Q&A. I'll try to leave ~5 minutes at the end.
-->

---

# DETECT in 30 Seconds

**DNM Extraction Through Empirical Cutoff Thresholds**

- Pfeifer Lab, Arizona State University
- Identifies *de novo* mutations (new in a child, absent in either parent) in **simulated** trio sequencing data
- Workflow: simulate trio reads → inject known DNMs → align (BWA) → variant call (GATK) → recommend filter thresholds
- Output is a set of **summary statistics / empirical thresholds** that downstream users then apply to **real** trio sequencing data

**Why HPC matters:** a single production run is hundreds of jobs and ~20–26 hours wall time on SLURM. Reliability at that scale is the whole game.

**Talk scope:** the *migration mechanics* — how the SLURM integration changed between Snakemake 7 and 9, with the actual code.

<!--
PRESENTER NOTES

DETECT stands for DNM Extraction Through Empirical Cutoff Thresholds. It's the workflow we'll use as our running example.

The science in one sentence: it identifies de novo mutations in *simulated* sequencing data — where the truth is known because the mutations were injected — and collects summary statistics on what filter thresholds best separate signal from noise. Those empirical thresholds are the deliverable: downstream users apply them to *real* trio sequencing data, where the truth isn't known, to tell real de novo mutations from sequencing artifacts.

The reason this matters for this talk is the *shape* of the workload, not the biology. Hundreds of jobs per run. Twenty-plus hours of wall time. Lots of fan-out, lots of GATK and BWA invocations. That shape is common — if you're running variant-calling, RNA-seq, or any DAG-driven bioinformatics workflow, you're operating in this regime, and the lessons transfer directly.

I want to be explicit about scope: I'm not going to talk about the science. I'm not going to talk about why we picked this lab to work with. This is a talk about the migration mechanics.
-->

---

# Why Bother — Results First

| Dataset       | Snakemake 7 | Snakemake 9          | Δ          |
|---------------|-------------|----------------------|------------|
| Demo          | 31m 52s     | **24m 29s**          | 23% faster |
| Production    | 26h 4m      | **19h 41m** (avg/3)  | 24% faster |

**Stability — three production runs, Sol cluster, Feb 2026**

| Run     | Jobs | Completed | Failed |
|---------|------|-----------|--------|
| 5DETECT | 183  | 183       | 0      |
| 6DETECT | 362  | 362       | 0      |
| 7DETECT | 362  | 362       | 0      |
| **Total** | **907** | **907** | **0** |

The 24% isn't faster code. It's better scheduling, retry recovery, and right-sized resources. The rest of the talk is *how*.

<!--
PRESENTER NOTES

Results up front so you know whether to keep listening.

Top table: same code, same data, same cluster, same day — Snakemake 7 vs. Snakemake 9. 23% faster on the demo dataset, 24% faster on a production-scale dataset. Production-side is averaged over three Snakemake 9 runs to smooth out cluster variance.

Bottom table: 907 SLURM jobs across three production runs in February. Zero failures. There were four transient OOM and walltime hits along the way — all auto-retried and recovered without human intervention. We'll come back to how that works.

The point I want to plant now and revisit at the end: that 24% speedup did not come from making the code faster. The Snakefile rules are essentially the same. What changed was the workflow's relationship with SLURM — and the rest of this talk is about the specific knobs that made that happen.
-->

---

# What `--cluster` Actually Was

In Snakemake 7, `--cluster` took a **shell string** that Snakemake would interpolate per job and hand to your scheduler.

```bash
snakemake --cluster "sbatch -n {threads} --mem={resources.mem_mb} \
                            -t 01:00:00 \
                            -o logs/{rulename}.{jobid}.out \
                            -e logs/{rulename}.{jobid}.err"
```

**Mental model:** Snakemake renders that string, calls `sbatch`, parses the returned job ID, then **polls `squeue` / `sacct`** to track state. No real SLURM awareness — just shell-out and string-match.

That worked. But it was the source of every operational pain that follows.

<!--
PRESENTER NOTES

OK — Snakemake 7's SLURM story.

The `--cluster` flag has been around since the early days. It accepts a shell string. Snakemake substitutes the curly-brace placeholders — threads, memory, rule name, job ID — and runs that as a shell command for every job that's ready in the DAG.

Mental model: Snakemake is shelling out to sbatch, capturing the job ID it gets back, then in a separate loop calling squeue or sacct to figure out whether that job is done, running, or failed. The integration is at the level of *string interpolation and process exit codes*. Snakemake doesn't actually understand SLURM. It understands shell.

That worked fine for years. Lots of papers were written on top of this. But it has structural limits — and once you hit them at scale, you hit them hard. That's the next slide.
-->

---

# The Real DETECT Snakemake 7 Invocation

```bash
sbatch -n1 --job-name demo_detect_superjob \
  -o logs/demo_detect.out -e logs/demo_detect.err \
  --wrap "snakemake -p --configfile config.json -s Snakefile \
    --default-resources mem_mb=8000 \
    --scheduler greedy -j 100 --latency-wait 60 \
    --keep-target-files --rerun-incomplete \
    --cluster 'sbatch -n {threads} --mem={resources.mem_mb} -t 01:00:00 \
      -o logs/{rulename}.{jobid}.out \
      -e logs/{rulename}.{jobid}.err'"
```

- An outer `sbatch --wrap` that runs `snakemake`…
- …which runs an inner `sbatch …` for every rule invocation.
- Resources are pasted into a string. Times are hardcoded (`-t 01:00:00`). Partition? Whatever the cluster defaults to.

<!--
PRESENTER NOTES

This is the real submission command from DETECT's Snakemake 7 README. Not a strawman — this is what the lab was actually running.

Read it from the outside in. There's an outer sbatch that wraps the whole thing — that's because snakemake itself is long-running, and you don't want it sitting on a login node for 26 hours. So the snakemake driver itself is a SLURM job.

Inside the wrap, you have snakemake invoking another sbatch — that's the --cluster string — for every rule that fires. So the outer sbatch is the orchestrator, and it spawns hundreds of inner sbatches over the run.

Things to call out:
  - "-t 01:00:00" — every single job gets a one-hour walltime. Doesn't matter if it's a 30-second sed or an 8-hour assembly.
  - No -p flag. Whatever queue the cluster defaults you into, that's where every job goes.
  - mem_mb is whatever the rule declared in the Snakefile, pasted in. No retry, no backoff.

This worked. People built careers on this. But it doesn't scale gracefully — and "doesn't scale gracefully" is what the next slide is about.
-->

---

# The Real DETECT Snakemake 7 Invocation

<img src="img/nestingdolls.png" style="position: absolute; top: 50px; left: 903px; width: 278px; height: 242px; opacity: 0.5;" />

```bash
sbatch -n1 --job-name demo_detect_superjob \
  -o logs/demo_detect.out -e logs/demo_detect.err \
  --wrap "snakemake -p --configfile config.json -s Snakefile \
    --default-resources mem_mb=8000 \
    --scheduler greedy -j 100 --latency-wait 60 \
    --keep-target-files --rerun-incomplete \
    --cluster 'sbatch -n {threads} --mem={resources.mem_mb} -t 01:00:00 \
      -o logs/{rulename}.{jobid}.out \
      -e logs/{rulename}.{jobid}.err'"
```

- An outer `sbatch --wrap` that runs `snakemake`…
- …which runs an inner `sbatch …` for every rule invocation.
- Resources are pasted into a string. Times are hardcoded (`-t 01:00:00`). Partition? Whatever the cluster defaults to.

<!--
PRESENTER NOTES

This is the real submission command from DETECT's Snakemake 7 README. Not a strawman — this is what the lab was actually running.

Read it from the outside in. There's an outer sbatch that wraps the whole thing — that's because snakemake itself is long-running, and you don't want it sitting on a login node for 26 hours. So the snakemake driver itself is a SLURM job.

Inside the wrap, you have snakemake invoking another sbatch — that's the --cluster string — for every rule that fires. So the outer sbatch is the orchestrator, and it spawns hundreds of inner sbatches over the run.

Things to call out:
  - "-t 01:00:00" — every single job gets a one-hour walltime. Doesn't matter if it's a 30-second sed or an 8-hour assembly.
  - No -p flag. Whatever queue the cluster defaults you into, that's where every job goes.
  - mem_mb is whatever the rule declared in the Snakefile, pasted in. No retry, no backoff.

This worked. People built careers on this. But it doesn't scale gracefully — and "doesn't scale gracefully" is what the next slide is about.
-->

---

# Why It Hurt at Scale

- **No rate limiting** — Snakemake fires `sbatch` and `squeue` as fast as the DAG allows. SLURM's slurmctld socket → timeouts and `slurm_load_jobs error: Socket timed out` failures. Random rules die.
- **Hardcoded walltime** — `-t 01:00:00` for *every* rule. The 4-hour assembly-depth job needed its own one-off submission.
- **String-typed resources** in the Snakefile — `runtime='15m'`, `runtime='4d'`, `runtime='8h'`. No retry backoff.
- **No partition intelligence** — every job goes to the default queue, regardless of fit.
- **Bare `python` in shell rules** — picks up whatever's first on `$PATH` inside the SLURM job. Worked on the login node, broke on compute nodes.
- **Failure diagnosis = `grep` archaeology** across 800 log files.

<!--
PRESENTER NOTES

Six things that hurt. Number one is the killer.

Quick aside on terminology before I dive in — I'll say "DAG" a few times in this talk. DAG stands for **directed acyclic graph**: a set of nodes with one-way edges and no cycles. In Snakemake, every rule's outputs become the inputs to other rules, and Snakemake walks those input/output declarations to build a DAG of jobs — nodes are the jobs, edges are the file dependencies, "acyclic" because nothing can depend on its own output. That graph is what Snakemake schedules against. When I say "as fast as the DAG allows," I mean: any rule whose inputs are ready can run in parallel with any other ready rule, and Snakemake will try to launch all of them at once. That's exactly what makes the rate-limiting problem on the next bullet so dangerous.

No rate limiting. When a wide rule fans out — say, you've got a hundred chromosomes to process — Snakemake will fire a hundred sbatch calls back-to-back. Then it polls squeue or sacct in tight loops. slurmctld is the SLURM controller daemon, and it has a finite socket. When you hammer it, calls start timing out. When sbatch times out, Snakemake interprets that as a failed job. Random rules in your DAG silently don't run, and you don't find out until much later.

This was the dominant failure mode for DETECT on Sol. Anyone here who runs SLURM clusters: you've seen this from the *other* side, in your slurmctld logs.

Hardcoded walltime — every rule got 1 hour. Some needed 15 minutes; one needed 8 hours. The 8-hour one couldn't go through this driver at all; the lab ran it as a separate manual sbatch.

String-typed resources — Snakemake 7 lets you write runtime='15m' or '4d'. Cute, but no math. No retry-with-more-resources.

No partition intelligence — every job lands in the same queue. Even the ones that would obviously fit on a faster, smaller partition.

Bare `python` in the shell rules — sounds trivial. Wasn't. The login node has one PATH; the compute node inside an sbatch job has a different one. You'd run on the login node, it'd work. You'd submit, half the rules would crash with ModuleNotFoundError. Took a while to track down.

And when something failed at 3 AM during a 26-hour run, you got to grep through 800 log files to figure out which one. There's no log analysis built in.

That's where we started. Now the question — what changed?

---

**Q&A backup — explaining DAG to a non-technical audience:**

Think of baking a birthday cake. The recipe has steps: crack the eggs, mix the batter, bake the cake, let it cool, make the frosting, frost it, add sprinkles. Some steps have to happen in order — you can't frost before you bake, can't bake before you mix. That's the "directed" part: arrows pointing one way, like a one-way street, showing what has to come first.

But some steps *don't* depend on each other. While the cake is baking, you can be making the frosting at the same time — two things at once, no waiting. And "acyclic" just means no loops: once you've baked the cake, you don't go back and crack more eggs. You always move forward.

A DAG — Directed Acyclic Graph — is just that picture: boxes for each step, arrows showing what has to come before what, and no going backward.

How it applies to Snakemake: scientists describe their recipe in terms of files — "to make file B, I need file A first." Snakemake reads all those input/output declarations and draws the whole DAG itself. Then it looks at the picture and says: "These 50 steps don't depend on each other, so I'll run them all at once on 50 different computers. When those finish, the next batch starts." That's how a job that would take a month on one computer finishes overnight on a cluster — the DAG tells Snakemake what's safe to do in parallel and what has to wait its turn.
-->

---

# The Breaking Change

- **Snakemake 8 (Feb 2024):** `--cluster` deprecated. Executor plugin interface introduced.
- **Snakemake 9 (Sep 2024):** `--cluster` **removed**.
- Every HPC-bound Snakemake 7 workflow needs migration. There is no `--cluster` shim.

**The new model:** scheduler integration moves out of the CLI flag and into a **plugin** that Snakemake loads.

```bash
pip install snakemake-executor-plugin-slurm
snakemake --executor slurm ...
```

The plugin speaks SLURM natively — submits via `sbatch`, tracks state via `sacct`, handles retries, applies rate limits, picks partitions. It's not just a different flag; it's a different relationship with the scheduler.

<!--
PRESENTER NOTES

What actually happened in the Snakemake project.

Snakemake 8 came out in February 2024. The big change was: --cluster is deprecated. We're moving to an executor plugin interface instead. You'll get a deprecation warning if you use the old flag, but it still works.

Snakemake 9 came out in September 2024 and removed --cluster entirely. If you upgrade to Snakemake 9 with a workflow that depends on --cluster, your workflow stops working. There is no compatibility shim. There is no --legacy-cluster flag. It's gone.

So if you're running Snakemake 7 today and you're on a SLURM cluster, you have a deadline. It's not "this year"; it's "the next time you do a major upgrade." The migration isn't optional, and there's no half-step.

The new model: instead of a flag that takes a string, scheduler integration is a *plugin* that Snakemake loads at runtime. You pip install it, you tell snakemake which executor to use, and the plugin owns the integration.

The plugin uses SLURM properly — it submits with sbatch but it polls with sacct, with sensible backoff. It implements rate limiting. It handles automatic retries. It picks partitions. It's not just a refactor of --cluster; it's a different *architecture* for how Snakemake talks to your scheduler.
-->

---

# The Breaking Change

<img src="img/easybutton-transparent.png" style="position: absolute; top: 50px; left: 850px; width: 324px; height: 324px; opacity: 0.5;" />

- **Snakemake 8 (Feb 2024):** `--cluster` deprecated. Executor plugin interface introduced.
- **Snakemake 9 (Sep 2024):** `--cluster` **removed**.
- Every HPC-bound Snakemake 7 workflow needs migration. There is no `--cluster` shim.

**The new model:** scheduler integration moves out of the CLI flag and into a **plugin** that Snakemake loads.

```bash
pip install snakemake-executor-plugin-slurm
snakemake --executor slurm ...
```

The plugin speaks SLURM natively — submits via `sbatch`, tracks state via `sacct`, handles retries, applies rate limits, picks partitions. It's not just a different flag; it's a different relationship with the scheduler.

<!--
PRESENTER NOTES

What actually happened in the Snakemake project.

Snakemake 8 came out in February 2024. The big change was: --cluster is deprecated. We're moving to an executor plugin interface instead. You'll get a deprecation warning if you use the old flag, but it still works.

Snakemake 9 came out in September 2024 and removed --cluster entirely. If you upgrade to Snakemake 9 with a workflow that depends on --cluster, your workflow stops working. There is no compatibility shim. There is no --legacy-cluster flag. It's gone.

So if you're running Snakemake 7 today and you're on a SLURM cluster, you have a deadline. It's not "this year"; it's "the next time you do a major upgrade." The migration isn't optional, and there's no half-step.

The new model: instead of a flag that takes a string, scheduler integration is a *plugin* that Snakemake loads at runtime. You pip install it, you tell snakemake which executor to use, and the plugin owns the integration.

The plugin uses SLURM properly — it submits with sbatch but it polls with sacct, with sensible backoff. It implements rate limiting. It handles automatic retries. It picks partitions. It's not just a refactor of --cluster; it's a different *architecture* for how Snakemake talks to your scheduler.
-->

---

# What the Plugin Gives You for Free

- **Native job submission** — no template string. Resources go through the plugin's typed interface.
- **Native status polling** — proper `sacct` queries with backoff, not hammering `squeue` in a loop.
- **Rate limiting** as a first-class config knob.
- **Automatic partition selection** when given a partitions YAML.
- **Retry semantics** wired into Snakemake's own attempt counter.
- **Profile-based config** — submission settings live in YAML, not in your shell history.

There's also `snakemake-executor-plugin-cluster-generic` (a `--cluster` workalike). **Don't use it for new work.** It exists for the migration off-ramp; the SLURM plugin is the destination.

<!--
PRESENTER NOTES

Walk through what you get for free once you install the SLURM plugin.

Native submission — no shell template. Resources are passed through a typed Python interface. Type errors get caught at submission time, not deep inside a job.

Native status polling — uses sacct, backs off appropriately, doesn't hammer the scheduler.

Rate limiting — first-class config option. We'll spend a slide on this; it's the most important single setting.

Automatic partition selection — give the plugin a YAML file describing your partitions, and it'll match each job's resource ask to the smallest partition that can satisfy it. No more hardcoded -p flag.

Retry semantics — the `attempt` variable gets wired into Snakemake's own retry machinery. We'll see in a few slides how that lets you do memory backoff: first attempt 32 GB, second attempt 48, third attempt 64.

Profile-based configuration — instead of a shell command with twelve flags, you have a YAML file checked into your repo. Reproducible. Diffable. Reviewable.

Quick aside: there's a *second* plugin called cluster-generic. It's basically a --cluster workalike that lets you keep using your old shell template under the new executor interface. Don't use it for new work. It exists for people who need a shortest-path migration off Snakemake 7 without rethinking anything. The SLURM plugin is the actual destination.
-->

---

# Invocation: Before and After

**Snakemake 7**

```bash
sbatch --wrap "snakemake --configfile config.json \
  --cluster 'sbatch -n {threads} --mem={resources.mem_mb} -t 01:00:00 ...' \
  -j 100 --latency-wait 60 --rerun-incomplete"
```

**Snakemake 9**

```bash
snakemake -p --snakefile Snakefile \
    --configfile work/config/config.json \
    --executor slurm \
    --workflow-profile profiles/slurm \
    --slurm-partition-config profiles/slurm/public.yaml \
    --scheduler greedy -j 100 --cores 100 \
    --latency-wait 30 --retries 3 --rerun-incomplete
```

Two new flags carry most of the meaning: `--workflow-profile` and `--slurm-partition-config`. Everything else lives in YAML now.

<!--
PRESENTER NOTES

Side-by-side. This is the visual takeaway of the whole migration.

Top: the Snakemake 7 invocation — abbreviated for slide-fit. Notice the --cluster flag with its embedded sbatch template. That string is doing all the work.

Bottom: the Snakemake 9 invocation. Notice what's *not* there. No --cluster string. No embedded sbatch template. Walltimes? Gone. Memory specs? Gone. Output paths? Gone.

Two new flags carry the meaning:
  - --workflow-profile points at a directory containing config.yaml — that's where executor settings, defaults, and per-rule resources live.
  - --slurm-partition-config points at a YAML describing the partitions on this cluster.

Everything that used to live in that shell string now lives in checked-in YAML. Which means you can review it. You can diff it. You can roll it back. You can have one profile per cluster — Sol gets one config, Phoenix gets another, and the snakemake invocation itself is identical.

We're going to spend the next few slides walking through what's *in* those YAML files.
-->

---

# `profiles/slurm/config.yaml` — Core

```yaml
executor: slurm
jobs: 150
cores: 150
retries: 1
latency-wait: 30
rerun-incomplete: true
scheduler: greedy
slurm-logdir: logs

# rate limiting — the cure for socket timeouts
max-jobs-per-timespan: 9/1s
max-status-checks-per-second: 2

# defaults for any rule that doesn't override them
default-resources:
  - mem_mb=8000
  - runtime=30
  - cpus_per_task=8
```

The whole `--cluster` template string is now declarative. `slurm-logdir` replaces every per-rule `-o`/`-e` argument you used to hand-write.

<!--
PRESENTER NOTES

This is the top half of the profile. Walk through it block by block.

Top block: executor settings. `executor: slurm` is what activates the plugin. jobs and cores cap parallelism. retries — Snakemake-level retries on top of any per-rule attempt logic. latency-wait gives the filesystem a moment to settle on networked storage. scheduler: greedy is the DAG scheduler. slurm-logdir replaces every -o and -e flag from the Snakemake 7 cluster string — all SLURM stdout and stderr lands in one directory.

Middle block: rate limiting. We're going to come back to this on its own slide because it's the single most important change. For now: 9 submissions per second max, 2 status checks per second max. Two lines. They eliminated the dominant failure mode.

Bottom block: default resources. If a rule doesn't say otherwise, it gets 8 GB of memory, 30 minutes of walltime, and 8 CPUs. The plugin uses these defaults to pick a partition, which we'll see shortly.

The whole shell-string approach is gone. Everything's declarative. And one consequence — small but real — is that you can no longer accidentally have a typo in your sbatch flags that only fires for one specific rule six hours into a run. The validation happens up front.
-->

---

# `profiles/slurm/config.yaml` — Per-Rule Resources

```yaml
set-resources:
  SplitFasta:
    mem_mb: 4000
    runtime: 10
    cpus_per_task: 1

  ReformatMutations:
    mem_mb: 8000
    runtime: 20
    cpus_per_task: 1

  AssemblyDepth:
    mem_mb: 64000
    runtime: 480
    cpus_per_task: 16
```

Right-sizing in YAML, not in the Snakefile. Means the workflow author and the cluster operator can tune resources independently — and rolling back a bad tuning is a `git revert` on one file.

<!--
PRESENTER NOTES

Bottom half of the profile: per-rule resource overrides. This is the `set-resources` block.

Three real rules from DETECT. SplitFasta is trivial — 4 GB, 10 minutes, 1 CPU. ReformatMutations is small — 8 GB, 20 minutes. AssemblyDepth is the heavyweight — 64 GB, 8 hours, 16 CPUs.

Why is this nice? Because in Snakemake 7, all of this lived in the Snakefile in `resources:` blocks. Which meant tuning resources required editing workflow code — and that meant the workflow author and the cluster operator were the same person. Or, more realistically, the workflow author had to negotiate every change.

In Snakemake 9, the workflow author writes the Snakefile and ships it. The cluster operator — that's me, that's many of you — owns the profile. We tune resources for our cluster's queue policy, our memory layout, our user community. If a tuning is bad, we git revert one file. The Snakefile is untouched.

This separation also means the *same Snakefile* can run on multiple clusters with different profiles. DETECT runs on both Sol and Phoenix at ASU. Same Snakefile, different profile per cluster.
-->

---

# Automatic Partition Selection

```yaml
# profiles/slurm/public.yaml
partitions:
  public:
    max_runtime: 10080       # 7 days
    max_mem_mb: 500000       # 500 GB
    max_cpus_per_task: 120
    max_nodes: 24
  htc:
    max_runtime: 240         # 4 hours
    max_mem_mb: 256000
    max_cpus_per_task: 120
    max_nodes: 24
```

Pass with `--slurm-partition-config public.yaml`. The plugin matches each job's resource request against the table and picks the smallest partition that fits — the 10-minute `SplitFasta` job lands on `htc`, the 8-hour `AssemblyDepth` job lands on `public`. **No more hardcoded `-p` flag; no more rule-by-rule partition logic.**

<!--
PRESENTER NOTES

Automatic partition selection. This was a big win.

The file describes the partitions on the cluster — at ASU we have `public` for long-running heavy jobs, and `htc` for short throughput-style jobs. Each entry has max walltime, max memory, max CPUs, max nodes.

Pass it on the command line with --slurm-partition-config. The plugin then looks at each job's resource ask — from set-resources or default-resources — and picks the smallest partition that can actually satisfy it.

So the SplitFasta job at 4 GB and 10 minutes lands on htc. It clears immediately because htc has short queue waits. The AssemblyDepth job at 64 GB for 8 hours can only fit on public. It goes there.

In Snakemake 7, every job went to the cluster default. Often that was a long-job partition with deep queue waits — even for jobs that should have cleared in 30 seconds on htc. That's a chunk of the speedup we'll attribute later. Better partition fit = shorter queue waits = lower wall time.

If your cluster has a single partition this slide is less relevant. If it has two or more, this is the main benefit you're not getting today.
-->

---

# Resources: From Strings to Lambdas

**Snakemake 7** — string-typed, fixed

```python
rule MutateOffspring:
    resources:
        mem_mb = 8000,
        runtime = '15m'         # string format
```

**Snakemake 9** — integer minutes, with `attempt`-based backoff

```python
rule callHaplotypeCaller:
    resources:
        mem_mb  = lambda wildcards, attempt: 32000 + (16000 * (attempt - 1)),
        runtime = lambda wildcards, attempt: 60    + (30    * (attempt - 1))
```

- Attempt 1: 32 GB / 60 min  → OOM kill, SLURM exits with retry-eligible code
- Attempt 2: 48 GB / 90 min  → likely succeeds
- Attempt 3: 64 GB / 120 min → upper bound

**Result on DETECT:** four transient OOM/walltime failures across 907 jobs, all auto-recovered. Zero manual intervention.

<!--
PRESENTER NOTES

This is one of my favorite changes.

Top: Snakemake 7. mem_mb is a fixed integer. runtime is a string with a unit suffix. Cute, but if your job OOMs, you fix the number, you re-run from scratch. There's no graceful degradation.

Bottom: Snakemake 9. Let me decode that lambda line in plain English first, because it's the densest one in the deck.

  `mem_mb = lambda wildcards, attempt: 32000 + (16000 * (attempt - 1))`

Read it as a tiny recipe: "to figure out the memory for this job, take the attempt number, subtract 1, multiply by 16 GB, and add 32 GB." The word `lambda` just means "this isn't a fixed number — call this little function each time you need the value." `wildcards` and `attempt` are the inputs Snakemake hands in; we only use `attempt` here. So:

  - Attempt 1 → 32000 + (16000 × 0) = 32 GB
  - Attempt 2 → 32000 + (16000 × 1) = 48 GB
  - Attempt 3 → 32000 + (16000 × 2) = 64 GB

If SLURM kills the job for memory or walltime, Snakemake gets a retry-eligible exit code and re-submits with attempt incremented. The same idea applies to the runtime line right below it.

Why is this good? Most jobs succeed at attempt 1, so you don't over-allocate up front — your cluster's queue policy will hate you if you do. But for the tail of jobs that need more, you don't need a manual rerun. Low default ask, automatic backoff for the outliers.

Real numbers from DETECT in February: across three production runs totaling 907 jobs, four jobs hit transient failures. All four auto-recovered on attempt 2. Zero manual intervention. That's the operational improvement that doesn't show up in a benchmark table but matters more than the speedup does.

**Honest caveat — same flavor as the bare-`python` slide:** the lambda-with-`attempt` pattern is *not* new in Snakemake 9. It's been valid since Snakemake 5, and `--retries` (formerly `--restart-times`) was already in Snakemake 7. The DETECT Sn7 Snakefile could have used this exact pattern and gotten the same auto-recovery. It didn't — fixed integers and string runtimes were simpler to type, and the cost only shows up at production scale when something OOMs at 3 AM.

There *is* one real Sn9 difference worth knowing: in Sn7 under `--cluster`, you had to manually wire `{resources.runtime}` into your sbatch template string for it to do anything — the lambda would evaluate, but if your template didn't reference the value, SLURM never saw it. In Sn9 the SLURM plugin consumes `runtime` natively and passes it as `--time`. So the pattern is older than the migration; what Sn9 added is making it *harder to forget to wire up*.

Same lesson as slide 15: the migration is a forcing function for the discipline, not the source of the capability.
-->

---

# Containers: Per-Rule → Global

**Snakemake 7** — repeat the directive on every GATK rule

```python
rule MarkDuplicates:
    singularity: "container/gatk4.6.2.sif"
    shell: "gatk MarkDuplicates ..."

rule BQSR:
    singularity: "container/gatk4.6.2.sif"
    shell: "gatk BaseRecalibrator ..."
```

**Snakemake 9** — global directive at the top of the Snakefile

```python
GATK_CONTAINER = "container/gatk4.6.2.sif"
container: GATK_CONTAINER

rule MarkDuplicates:
    shell: "gatk MarkDuplicates ..."
```

Drives consistency. Adding a new GATK rule is no longer a chance to forget the directive and have it silently use whatever GATK happens to be on `$PATH`.

<!--
PRESENTER NOTES

Quick one. Containers.

In Snakemake 7, if you wanted GATK to run inside an Apptainer container — and you should, because GATK pulls in a Java runtime that fights with your conda environment — you put a `singularity:` directive on every rule that uses GATK. DETECT has roughly a dozen such rules. That's a dozen places where someone could add a new rule and *forget* to add the directive. And if they forget, the rule silently falls back to whatever gatk binary is first on PATH on the compute node. That might be the right version. Probably isn't.

In Snakemake 9, you set a global `container:` directive at the top of the Snakefile. Every rule inherits it. New rule? It's automatically containerized. No way to forget. Less code. More consistent.

You can still override per-rule if you need to. But the default is now sensible.

If your workflow uses singularity or apptainer at all, hoist it to global. It's a one-day refactor that pays back forever.
-->

---

# The Python-Path Gotcha

Not a Snakemake-version issue — a discipline issue. The migration was the forcing function.

**Symptom:** `python scripts/mutator.py` works on the login node, fails inside a SLURM job with `ModuleNotFoundError`. The compute node has a different `$PATH`.

**Before — bare `python`** (what the Sn7 Snakefile actually shipped)

```python
shell: "python {snakedir}/scripts/mutator.py -i {input} ..."
```

**After — resolve from `$CONDA_PREFIX` at workflow load**

```python
def get_python_executable():
    conda_prefix = os.environ.get("CONDA_PREFIX", "")
    if conda_prefix:
        candidate = os.path.join(conda_prefix, "bin", "python3")
        if os.path.exists(candidate):
            return candidate
    return "python3"

python_exec = get_python_executable()

rule MutateOffspring:
    params: python_exec = python_exec
    shell: "{params.python_exec} {snakedir}/scripts/mutator.py ..."
```

`params:` + top-level Python work in Snakemake 7 too — this pattern was always available. We just hadn't written it that way until the migration prompted the cleanup.

<!--
PRESENTER NOTES

I want to be honest about this one: it's the slide where I out myself as having shipped a bug.

The symptom: you run snakemake on the login node, it works. You submit it as a SLURM job, half the rules fail with ModuleNotFoundError. The Python scripts can't find their imports.

Why? The compute node has a different PATH than the login node. Whatever Python is first on PATH at the compute node is *not* the conda environment Python you set up. So the scripts run, but they're using the wrong interpreter — one that doesn't have biopython, doesn't have your other deps.

The fix is small: at workflow load time, resolve the Python path from $CONDA_PREFIX. Stash it in a module-level variable. Pass it through `params:` to every rule. Use `{params.python_exec}` in the shell command instead of bare `python`.

Why does this work? $CONDA_PREFIX is set by `conda activate`, and it gets exported into the SLURM job's environment when the snakemake driver itself was activated under the env. The compute node sees the same conda prefix — it just doesn't have it on PATH.

Now the part I want to be honest about: **none of this required Snakemake 9.** The `params:` directive has been in Snakemake since basically forever. Top-level Python in a Snakefile has worked since day one. The DETECT Sn7 Snakefile could have used this exact pattern and dodged the bug. It just didn't — bare `python` was simpler to type, looked fine in testing, and the failure mode only showed up at scale on a node where PATH happened to be wrong.

So the migration didn't *enable* this fix. It was a forcing function. When you're already rewriting the resource declarations and adding the executor plugin and reorganizing the profile, you read every rule, and the bare-`python` smell finally registers.

That's a pattern worth naming explicitly: half of what a big migration delivers isn't the new platform's features — it's the technical-debt cleanup that the rewrite forces you to do. Worth keeping in mind when someone asks you to justify a migration on feature-list grounds.
-->

---

# Rate Limiting in Practice

```yaml
max-jobs-per-timespan: 9/1s
max-status-checks-per-second: 2
```

Two lines in `profiles/slurm/config.yaml`. They eliminated the failure mode that had been the dominant source of run failures.

**Before:** Snakemake fires hundreds of `sbatch` and `squeue` calls when a wide rule fans out. slurmctld saturates. Calls time out. Snakemake interprets the timeout as a failed submission. Random rules silently don't run.

**After:** the plugin enforces ≤9 submissions per second and ≤2 status checks per second cluster-wide. slurmctld never sees a burst. Run failures from this class: zero across 907 jobs.

If you take one thing from this talk, it's **set these two values.**

<!--
PRESENTER NOTES

If you only remember one slide from this talk, this is it.

Two YAML lines. max-jobs-per-timespan: 9 per 1 second. max-status-checks-per-second: 2. They go in your profile config.

Before this, when DETECT hit a wide fan-out rule — say, splitting work across a hundred chromosomes — Snakemake would fire all hundred sbatch calls back to back, then immediately start polling squeue for status. slurmctld is single-threaded for a lot of operations. Its socket saturates. Calls time out. Snakemake sees the timeout as a failure and silently doesn't track those jobs. You only find out later when downstream rules can't find their inputs.

This was the dominant failure mode. Probably accounts for half the production-run failures we'd seen in the year before the migration.

After: the plugin enforces these limits cluster-wide. slurmctld is never under burst load from us. Across 907 jobs in February, zero failures from this class.

For the cluster operators in the room: this is the setting your users *don't know they need*. If you're seeing slurmctld socket pressure from Snakemake users — and you probably are — these two lines are the fix. Send them this slide.

Numbers to tune for your cluster: 9/1s is conservative. Some clusters can handle more, some less. Start there, watch slurmctld load, raise it if you have headroom.
-->

---

# `run.sh` and `sbatch.sh`

Two thin wrappers. The deck doesn't have room for both — the shape is:

```bash
#!/bin/bash
set -euo pipefail
module load mamba/latest
source activate DETECT

snakemake -p --snakefile Snakefile \
    --configfile work/config/config.json \
    --executor slurm \
    --workflow-profile profiles/slurm \
    --slurm-partition-config profiles/slurm/public.yaml \
    --scheduler greedy -j 100 --cores 100 \
    --latency-wait 30 --retries 3 --rerun-incomplete \
    2>&1 | tee logs/output.log
```

- **`run.sh`** — runs on the login node. For testing.
- **`sbatch.sh`** — same body, wrapped for `sbatch`. The `snakemake` driver itself becomes a SLURM job.

Either way, the *contents* of the snakemake call are the same. Configuration lives in the profile.

<!--
PRESENTER NOTES

Quick operational note before we wrap.

The lab runs DETECT through one of two tiny wrapper scripts. Both have basically the body shown here.

run.sh runs the snakemake driver directly on the login node. It tees output to a logfile. Good for testing — you watch the run live.

sbatch.sh wraps that same body in an sbatch — so the snakemake *driver itself* becomes a SLURM job. That's what production runs use, because you don't want a 26-hour driver process sitting on a login node.

Notice what's *not* in either script. No --cluster string. No partition flag. No resource declarations. All of that lives in the profile YAMLs. The snakemake call itself is short and the same in both wrappers.

This separation matters operationally: the lab can change which cluster they're targeting, or tune resources, without touching either run.sh or sbatch.sh. They edit the profile.

(If you're tight on time in your own talk, this slide is the most cuttable. The mechanism is obvious once you've seen the profile.)
-->

---

# Where the 24% Came From

Same code, same data, same cluster — different scheduler behavior.

- **Right-sized resources** — light rules like `SplitFasta` no longer request 64 GB and wait for a fat node. They land on `htc` in seconds.
- **Partition fit** — short jobs go to `htc`, long jobs go to `public`. Queue waits drop because requests match what's available.
- **Retry recovery** — transient OOMs add a few minutes, not a full re-run. Snakemake 7 had no automatic retry on resource failures.
- **No socket-timeout reruns** — every job we submit actually reaches SLURM the first time.

The Snakemake 9 executor plugin is doing what `--cluster` couldn't: behaving like a citizen of the cluster.

<!--
PRESENTER NOTES

Coming back to that 24% from the third slide. Where did it actually come from?

Not from making the workflow code faster. The Snakefile rules execute basically identical shell commands. The biology is the same. The tools are the same.

The 24% comes from four things, in roughly descending order of contribution:

One. Right-sized resources. In Snakemake 7, the default ask was generous because nobody wanted to write thirty different resource blocks. So a rule that needed 4 GB might be asking for 64. That meant queueing for a fat node — minutes of wait time per rule, multiplied by hundreds of rules. In Snakemake 9 with set-resources, we right-sized down to what each rule actually needs.

Two. Partition fit. Short jobs land on htc, which has very short queue waits. Long jobs land on public. Stuff stops sitting in queues.

Three. Retry recovery. In Snakemake 7, if a job OOMed, the run failed and you re-ran from the last checkpoint. Maybe an hour lost. In Snakemake 9, the same OOM triggers an automatic retry with more memory, costs a couple of minutes.

Four. No socket-timeout reruns. We're not losing jobs to slurmctld pressure anymore.

Add it up and you get 24%. None of it is faster code. All of it is the workflow behaving like a better citizen of the cluster — and the cluster rewarding that behavior with shorter queues.
-->

---

# Migration Checklist

If you're sitting on a Snakemake 7 workflow today:

1. `pip install snakemake-executor-plugin-slurm`
2. Drop `--cluster '...'`. Add `--executor slurm --workflow-profile profiles/slurm`.
3. Create `profiles/slurm/config.yaml` — start with `executor: slurm`, `jobs:`, `default-resources:`.
4. **Add the two rate-limit lines.** Now, before anything else.
5. Move per-rule resources from Snakefile `resources:` into profile `set-resources:`.
6. Convert `runtime: '4h'` strings to integer minutes. Wrap in `lambda wildcards, attempt: ...` for backoff.
7. Hoist per-rule `singularity:` directives to a global `container:` where appropriate.
8. Replace bare `python` in shell rules with a `get_python_executable()` resolved at load time.
9. Add `--slurm-partition-config partitions.yaml` once you have more than one partition shape.
10. Run a single-chromosome dry-run before a full submission.

<!--
PRESENTER NOTES

This is the takeaway slide. Photograph this one if you only photograph one.

Ten steps to migrate a Snakemake 7 workflow today. They're roughly in order — you can do them mostly independently, but this is the order that minimizes broken intermediate states.

Step 1: install the plugin. One pip install.

Step 2: change the snakemake invocation. Remove --cluster, add --executor slurm and a --workflow-profile pointer.

Step 3: create a starter profile. Three keys gets you working: executor, jobs, default-resources.

Step 4: add the rate limits. Now, not later. This is the cheapest, highest-impact change in the entire list.

Steps 5 and 6 go together: move resources from the Snakefile into the profile, and convert string runtimes to integer minutes with attempt-based backoff lambdas.

Step 7: containers, if you use them. Per-rule to global.

Step 8: the Python path gotcha. Fix it before it bites you.

Step 9: partition config. Skip this if you only have one partition.

Step 10: always test on a single chromosome before submitting a full production run. Same advice applies whether you're on Snakemake 7 or Snakemake 9, but it's especially worth doing the first time after the migration.

If a workflow author in your community wants help with this, this list is the order I'd hand them.

That's the talk. References next, then questions.
-->

---

# References

**This work**
- DETECT — Pfeifer Lab, Arizona State University

**Snakemake**
- Snakemake docs: `snakemake.readthedocs.io`
- SLURM executor plugin: `github.com/snakemake/snakemake-executor-plugin-slurm`
- Plugin interface spec: `github.com/snakemake/snakemake-interface-executor-plugins`

**Migration discussion**
- Snakemake 8 release notes (the `--cluster` deprecation announcement)
- `snakemake --help-all` after installing the SLURM plugin lists every `--slurm-*` flag

<!--
PRESENTER NOTES

Quick reference slide. Three buckets:

DETECT itself, in case you want to look at a real Snakemake 9 + SLURM workflow end to end.

Snakemake official docs and the plugin repos. The SLURM plugin repo's README is genuinely good — the maintainers are responsive.

For the migration story, the Snakemake 8 release notes have the official statement of the --cluster deprecation. And `snakemake --help-all` after installing the plugin will list every --slurm-* flag the plugin exposes — there are more than I covered today. Worth a scroll.
-->

---

<!-- _class: lead invert -->

# Thank You

## Questions?

Alan Chapman — `alan.chapman@asu.edu`
HPC Systems Analyst, ASU Research Computing

DETECT — Pfeifer Lab, Arizona State University

Slides & examples: `github.com/acchapm1/rmacc-2026`
Live deck: `acchapm1.github.io/rmacc-2026`

<!--
PRESENTER NOTES

Thank you. Happy to take questions.

Anticipated questions to be ready for:

  - "Did you write a custom executor plugin?" — yes, there's a small one in plugins/ that does the partition-selection logic, but most people won't need to. The upstream plugin is fine.

  - "What about Nextflow?" — out of scope for this talk, but the operational story is similar; Nextflow has had native SLURM integration for longer.

  - "How long did the migration take?" — six months part-time, but a lot of that was learning the workflow's biology and operationalizing tooling. The pure migration mechanics — the changes on these slides — are roughly two weeks of focused work.

  - "What's the cluster-generic plugin again?" — it's a --cluster workalike. Use it as a stepping stone if you need to ship before doing the full migration. Don't make it your destination.

  - "Did you see any regressions?" — one. Snakemake 9 is stricter about resource validation. A couple of rules that had silently been over-running their declared walltime in Snakemake 7 started getting killed in Snakemake 9. The fix was correct walltime declarations, which is what should have been there all along.

  - "Why ASU and not just upstream into Snakemake?" — the rate-limit values and partition configs are cluster-specific. The pattern is upstream.
-->
