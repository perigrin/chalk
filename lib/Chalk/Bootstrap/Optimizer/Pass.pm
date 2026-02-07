# ABOUTME: Abstract base class for optimizer passes.
# ABOUTME: Subclasses implement name() and run($ir) to perform a specific optimization.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Optimizer::Pass {
    method name() {
        die "Subclass must implement name()";
    }

    method run($ir) {
        die "Subclass must implement run()";
    }
}
