# ABOUTME: Orchestrator that runs optimizer passes in sequence over IR graphs.
# ABOUTME: Passes are added via add_pass() and executed in order by optimize().
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class Chalk::Bootstrap::Optimizer {
    field $passes = [];

    # Return the number of registered passes
    method pass_count() {
        return scalar $passes->@*;
    }

    # Register an optimizer pass; returns $self for chaining
    method add_pass($pass) {
        push $passes->@*, $pass;
        return $self;
    }

    # Run all passes in sequence over the IR; returns the (possibly modified) IR
    method optimize($ir) {
        die "optimize() requires an arrayref of IR roots"
            unless defined($ir) && ref($ir) eq 'ARRAY';

        for my $pass ($passes->@*) {
            $ir = $pass->run($ir);
        }

        return $ir;
    }
}
