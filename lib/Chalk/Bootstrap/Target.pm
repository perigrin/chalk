# ABOUTME: Base class for code generation targets (abstract interface).
# ABOUTME: Subclasses implement generate() to emit code from IR nodes.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class Chalk::Bootstrap::Target {
    method generate($ir) {
        die "Subclass must implement generate()";
    }
}
