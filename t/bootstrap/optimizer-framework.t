# ABOUTME: Tests for the optimizer framework: Pass base class and Optimizer orchestrator.
# ABOUTME: Verifies abstract interface, pass chaining, and correct execution order.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

# ===== Pass base class tests =====

use_ok('Chalk::Bootstrap::Optimizer::Pass');

# Construction
{
    my $pass = Chalk::Bootstrap::Optimizer::Pass->new();
    isa_ok($pass, 'Chalk::Bootstrap::Optimizer::Pass', 'Pass constructs');
}

# Abstract name() dies
{
    my $pass = Chalk::Bootstrap::Optimizer::Pass->new();
    eval { $pass->name() };
    like($@, qr/Subclass must implement/, 'name() dies with "Subclass must implement"');
}

# Abstract run() dies
{
    my $pass = Chalk::Bootstrap::Optimizer::Pass->new();
    eval { $pass->run([]) };
    like($@, qr/Subclass must implement/, 'run() dies with "Subclass must implement"');
}

done_testing();
