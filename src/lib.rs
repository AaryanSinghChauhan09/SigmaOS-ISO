//! SigmaOS ISO Builder
//! Multi-architecture ISO image builder with bootloader integration and live session creation
//!
//! Principles:
//! - ZERO-COPY: Efficient file operations
//! - FAIL-FAST: Early validation
//! - LAYERED DESIGN: Separation of mechanism and policy
//! - KISS: Simple, focused implementation

pub mod iso;
pub mod installer;

// Re-export key interfaces
pub use iso::builder::DistroIsoBuilder;
pub use iso::builder::IsoBuildConfig;
