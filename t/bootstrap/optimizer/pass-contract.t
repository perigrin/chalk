# ABOUTME: Tests the abstract Pass base defines a run($X) -> $X contract.
# ABOUTME: Per Phase 5, every concrete pass must conform to its declared scope level.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib';

use Chalk::Bootstrap::Optimizer::Pass;

# Abstract base must define both name() and run() methods.
ok(Chalk::Bootstrap::Optimizer::Pass->can('name'),
    'Pass abstract has name()');
ok(Chalk::Bootstrap::Optimizer::Pass->can('run'),
    'Pass abstract has run()');

# The base contract: every Pass declares its `scope` level so the
# optimizer pipeline knows what type of input to pass it. Valid levels:
# 'graph' (per-method graph) or 'mop' (whole-program MOP).
ok(Chalk::Bootstrap::Optimizer::Pass->can('scope'),
    'Pass abstract has scope() (returns "graph" or "mop")');

# Calling an abstract method on the base directly should die.
{
    my $base = Chalk::Bootstrap::Optimizer::Pass->new;
    my $err;
    eval { $base->name(); 1 } or $err = $@;
    ok(defined $err, 'Pass::name() on base dies (abstract)');

    $err = undef;
    eval { $base->scope(); 1 } or $err = $@;
    ok(defined $err, 'Pass::scope() on base dies (abstract)');

    $err = undef;
    eval { $base->run({}); 1 } or $err = $@;
    ok(defined $err, 'Pass::run() on base dies (abstract)');
}

done_testing();
