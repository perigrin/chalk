# ABOUTME: Basic comonad implementing extract operation for threading context through parser.
# ABOUTME: Phase 1a: extract only; extend and duplicate deferred to Phase 2b.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class Chalk::Bootstrap::Context {
    field $focus :param :reader;

    # Extract the current focus value from the context
    method extract() {
        return $focus;
    }

    # Placeholder for Phase 2b: extend
    # method extend($f) { ... }

    # Placeholder for Phase 2b: duplicate
    # method duplicate() { ... }
}
