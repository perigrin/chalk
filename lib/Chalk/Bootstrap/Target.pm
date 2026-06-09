# ABOUTME: Compat alias for Chalk::Target — the abstract base for code generation targets.
# ABOUTME: The ~153 Bootstrap consumers that use :isa(Chalk::Bootstrap::Target) continue to work unchanged.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::Target;

# Chalk::Bootstrap::Target is a compat alias for Chalk::Target.
# The canonical base is now Chalk::Target; this class extends it under the
# legacy name so existing consumers doing :isa(Chalk::Bootstrap::Target) need
# not change. The full Bootstrap-target family rename is tracked separately.
class Chalk::Bootstrap::Target :isa(Chalk::Target) {
}
