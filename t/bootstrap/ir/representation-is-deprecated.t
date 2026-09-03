# ABOUTME: representation/set_representation are a deprecated alias for stamp/set_stamp.
# ABOUTME: The warning is opt-in, so 1400+ existing call sites stay silent until migrated.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;

# `representation` NAMES THE WRONG AXIS. A stamp is a TYPE (`Unknown` is a
# legitimate value, `None` is the lattice bottom); a representation is a MACHINE
# ENCODING (`Unknown` has none, and `None` cannot have one -- it is the empty
# type). Calling the type axis by the encoding axis's name is what lets a value
# that is correct on one axis be read as poison on the other.
#
# Both methods are a straight alias for the same storage, so this is a rename
# with a long tail, not a semantic change. Measured at the time of writing:
#
#     lib/   113 reads    34 writes
#     t/     150 reads  1416 writes
#
# THE WARNING IS OPT-IN, and that is the whole design. A default-on warning
# across ~1700 call sites floods every test run, and this project treats
# non-pristine test output as a failure rather than as noise to skim -- so
# turning it on by default would either bury a real diagnostic or force the
# entire migration into one commit. `warnings::register` gives a category that
# is silent unless a scope asks for it, which lets the migration proceed file by
# file with the warning enabled only where the work is happening.

# THE ENV GATE IS READ AT LOAD TIME, deliberately -- these methods sit on a hot
# path (every stamp read in the compiler) and a per-call %ENV lookup would cost
# real time for a diagnostic that is off in every normal run. So a single
# process cannot exercise both states, and each case runs in its own child.

my $PERL = $^X;

sub run_child ($env_on, $body) {
    my $prelude = 'use 5.42.0; use lib q{lib}; use Chalk::IR::NodeFactory; '
                . 'my $n = Chalk::IR::NodeFactory->new->make(q{Constant}, '
                . 'value => 1, const_type => q{integer}); ';
    my $env = $env_on ? 'CHALK_WARN_DEPRECATED_REPR=1 ' : '';
    return scalar qx($env$PERL -Ilib -e '$prelude$body' 2>&1);
}

subtest 'the alias is silent by default' => sub {
    # THE LOAD-BEARING PROPERTY. Measured before this gate existed: ONE
    # ordinary test file emitted 1438 deprecation lines. A warning nobody can
    # read is a wall that hides the diagnostics underneath it.
    my $out = run_child(0,
        '$n->set_representation(q{Int}); my $g = $n->representation; '
      . 'print qq{VALUE=$g\n};');

    like $out, qr/VALUE=Int/, 'the alias still works -- read and write reach the stamp';
    unlike $out, qr/deprecated/, 'and neither direction warns by default'
        or diag("  got: $out");
};

subtest 'both directions warn when the env gate is set' => sub {
    my $out = run_child(1,
        '$n->set_representation(q{Str}); my $g = $n->representation;');

    # ASSERTED PER DIRECTION: "some warning fired" would pass with only one
    # wired up, and the WRITE is the more dangerous one -- it overwrites the
    # type rather than naming it.
    like $out, qr/set_representation\(\) is deprecated/,
        'the WRITE warns -- the destructive direction';
    like $out, qr/(?<!set_)representation\(\) is deprecated/,
        'and the READ warns too';
};

subtest 'the warning names what to use instead' => sub {
    my $out = run_child(1, 'my $g = $n->representation;');
    like $out, qr/stamp\(\)/,
        'the message points at stamp, so a reader knows the migration target';
};

# THE CONTROL. The migration TARGET must stay silent even with the gate on --
# otherwise there is nowhere to migrate to.
subtest 'stamp and set_stamp never warn' => sub {
    my $out = run_child(1,
        '$n->set_stamp(q{Num}); my $g = $n->stamp; print qq{VALUE=$g\n};');

    like $out, qr/VALUE=Num/, 'the real axis works';
    unlike $out, qr/deprecated/, 'and is silent even with the gate on'
        or diag("  got: $out");
};

# THE SECOND CONTROL. `no warnings` must still suppress it when the gate is on,
# so a file mid-migration can silence the part it has not reached yet.
subtest 'the warnings category still suppresses' => sub {
    my $out = run_child(1,
        'no warnings q{Chalk::IR::Node}; $n->set_representation(q{Int});');

    unlike $out, qr/deprecated/,
        'no warnings Chalk::IR::Node silences it even with the gate set'
        or diag("  got: $out");
};

done_testing;
