# future-kit-repo

Bootstrapped at a kit version newer than the one currently on PATH
(`kit_version: "9.9"` against the kit's `KIT_VERSION = "0.2"`). `kit
update` should refuse — silently rolling a runtime file backwards under
a manifest stamp the user already trusts is the exact failure mode this
verb exists to prevent. Recovery: upgrade the kit on PATH.
