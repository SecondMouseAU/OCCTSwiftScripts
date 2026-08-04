# Decisions

Recorded engineering decisions and their rationale. Add an entry here when a choice needs its
reasoning preserved beyond the commit message, so the next person does not re-litigate it.

Decisions to date are captured in `CLAUDE.md` and the git log; this directory holds the ones
that need standalone rationale.

* [Single-source verb inventory](single-source-verb-inventory.md): `Registry.all` is the only
  verb list; `occtkit --verbs` feeds the Makefile and the docs point at the reference page.
