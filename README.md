# SigmaOS ISO

This Rust crate exports `DistroIsoBuilder` and `IsoBuildConfig` from its `iso`
module, plus installer modules. The package describes an ISO builder, but this
README does not yet document a supported build command, input layout, output
contract, or a verified bootable image workflow. Treat the exported API and
installer modules as code surfaces, not as release evidence for a bootable ISO.

The crate depends on the sibling `SigmaOS-kernel` checkout through a local path.
Build and release instructions should be added after a reproducible image build
and boot check are documented.

## License

GPL-3.0-or-later. See [`LICENSE`](LICENSE) and [`Cargo.toml`](Cargo.toml).
