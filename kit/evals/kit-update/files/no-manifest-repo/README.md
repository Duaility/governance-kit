# no-manifest-repo

Repo with `.governance/` artifacts but `.governance/install.yaml` deleted
(somebody hand-removed it). `kit update` should refuse to run — the
manifest is the version pin this verb writes through, and there is no
safe heuristic for "what kit version did this install" after the fact.
The recovery path is `governance uninstall` + `governance init`.
