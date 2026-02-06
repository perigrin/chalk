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

# ===== Optimizer orchestrator tests =====

use_ok('Chalk::Bootstrap::Optimizer');

# Construction with no passes
{
    my $opt = Chalk::Bootstrap::Optimizer->new();
    isa_ok($opt, 'Chalk::Bootstrap::Optimizer', 'Optimizer constructs');
    is($opt->pass_count(), 0, 'pass_count() is 0 initially');
}

# add_pass() increments count and returns $self for chaining
{
    my $opt = Chalk::Bootstrap::Optimizer->new();
    my $pass = Chalk::Bootstrap::Optimizer::Pass->new();
    my $ret = $opt->add_pass($pass);
    is($opt->pass_count(), 1, 'pass_count() is 1 after add_pass()');
    is($ret, $opt, 'add_pass() returns $self for chaining');
}

# optimize() with no passes returns IR unchanged
{
    my $opt = Chalk::Bootstrap::Optimizer->new();
    my $ir = ['rule1', 'rule2'];
    my $result = $opt->optimize($ir);
    is($result, $ir, 'optimize() with no passes returns same IR reference');
}

# optimize() calls run() on each pass in order
{
    # Build a concrete TestPass that records calls
    my @call_log;

    package TestPass1 {
        use 5.42.0;
        use feature 'class';
        no warnings 'experimental::class';

        class TestPass1 :isa(Chalk::Bootstrap::Optimizer::Pass) {
            method name() { return 'TestPass1' }
            method run($ir) {
                push @call_log, 'pass1';
                return $ir;
            }
        }
    }

    package TestPass2 {
        use 5.42.0;
        use feature 'class';
        no warnings 'experimental::class';

        class TestPass2 :isa(Chalk::Bootstrap::Optimizer::Pass) {
            method name() { return 'TestPass2' }
            method run($ir) {
                push @call_log, 'pass2';
                return $ir;
            }
        }
    }

    my $opt = Chalk::Bootstrap::Optimizer->new();
    $opt->add_pass(TestPass1->new());
    $opt->add_pass(TestPass2->new());

    my $ir = ['some_ir'];
    $opt->optimize($ir);

    is_deeply(\@call_log, ['pass1', 'pass2'],
        'optimize() calls passes in order');
}

# optimize(undef) dies with useful error
{
    my $opt = Chalk::Bootstrap::Optimizer->new();
    eval { $opt->optimize(undef) };
    like($@, qr/requires.*arrayref/i, 'optimize(undef) dies with useful error');
}

done_testing();
