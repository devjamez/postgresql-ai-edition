# Publishing plan — and a reality check

## The misconception to clear up first

**This will not be "merged into PostgreSQL" as a core improvement.** That is not how PostgreSQL works, and it's important to be clear:

- PostgreSQL core accepts only **C** patches, reviewed for years on the `pgsql-hackers` mailing list, through CommitFests, requiring a committer to sponsor them and broad consensus. Most patches never land.
- The core team would **not** accept an AI subsystem that calls external APIs from PL/Python. It's out of scope for core by design.
- The successful "PostgreSQL improvements" everyone uses — **pgvector, PostGIS, TimescaleDB, Citus** — are **NOT in core**. They are independent **extensions**. That is the real, proven path, and it reaches millions of users.

So the goal is not "get merged into PostgreSQL." The goal is **become a widely-used PostgreSQL extension**. Same impact, realistic path.

## How we actually publish

1. **GitHub (now).** Public repo, PostgreSQL License, README, issues, discussions. This is the home of the project.
2. **Releases.** Tag versions; ship the Docker image and the `sql/` files. Add a `Makefile`/PGXS packaging when the extension graduates from "thin SQL" to a proper `CREATE EXTENSION pg_ai` package.
3. **PGXN** (PostgreSQL Extension Network) — the registry where people discover extensions. Requires a `META.json` and a proper extension package. Target this once there's a versioned, installable extension (not just init scripts).
4. **Announce** on r/PostgreSQL, Hacker News, the PostgreSQL community Slack/Discord, and a blog post with the demo. Adoption comes from a great README + a 30-second "wow".
5. **Docker Hub** image for one-command trial.

## If you ever want it *in core* (years out, team needed)

Only specific, generic primitives could plausibly go to core — e.g. a planner hook or type that benefits all extensions, written in C, proposed on `pgsql-hackers`. That's a V3+ conversation with a team, not a solo near-term goal. The extension can be hugely successful without ever touching core.
