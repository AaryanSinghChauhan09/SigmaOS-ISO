# SigmaOS-ISO

Build the SigmaOS live ISO from a manifest

- **Category:** Utilities
- **Engine:** iso_builder
- **Language:** Rust

## Build & Test

```sh
cargo build
cargo test
```

Part of the SigmaOS multi-repository component ecosystem.

## Live session

The live ISO autologins `liveuser` on tty1 into Hyprland. For manual
login (serial console, TTY switch):

- **user:** `liveuser`
- **password:** `sigmaos`

`liveuser` is in `wheel` — `sudo` works with the same password. The `root`
account is locked in the live image. These credentials apply to the live
environment only; `sigmaos-install` prompts for new credentials on install.
