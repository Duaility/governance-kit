# reconstructable-repo

Repo with `.governance/install.yaml` deleted (somebody hand-removed it),
but every kit-owned runtime file still carries the versioned
`# governance-kit:managed kit-version=0.1` marker. `kit update` should
reconstruct the version pin from the markers (taking the min
`kit-version=`), proceed through the forward-update flow, and rewrite a
fresh `install.yaml` with the new pin. The marker is the source of
truth; the manifest is a cache.
