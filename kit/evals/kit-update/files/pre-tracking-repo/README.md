# pre-tracking-repo

Bootstrapped before the `kit_version` field was added to install.yaml v3
(the field is optional within v3 — see [INSTALL_SCHEMA.md](../../../../references/INSTALL_SCHEMA.md)).
`kit update` should detect the absence, treat it as a pre-tracking
install, offer to record the current `KIT_VERSION` on the next run, and
proceed through the normal flow.
