# ABOUTME: Under perl, Test::Chalk gives the TAP, diagnostics and exit status Test::More
# ABOUTME: gives for what chalk's tests call that T2 does not compile yet (use_ok, $TODO, ...).
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

# THE ORACLE IS TEST::MORE, both under perl: each probe runs once with
# `use Test::More` and once with `use Test::Chalk`; stdout, stderr and the exit
# status must match byte for byte. (Through T2 is
# t/bootstrap/ir/test-chalk-gives-test-more-s-tap.t's job.) Stdout is a pipe,
# as under prove, so it is block-buffered unless the module flushes it.
sub run_probe ($module, $body) {
    my ( $fh, $file ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh "use lib 't/lib';\nuse $module;\n$body";
    close $fh;
    my ( undef, $err ) = tempfile( UNLINK => 1 );
    my $out  = qx($^X $file 2>$err);
    my $exit = $? & 127 ? 128 + ( $? & 127 ) : $? >> 8;
    open my $eh, '<', $err or die "$err: $!";
    my $stderr = do { local $/; <$eh> } // '';
    # (the file names differ: each is written as FILE; so do the counts of
    # string evals each module made before the probe's)
    s/\Q$file\E/FILE/g, s/\(eval \d+\)/(eval N)/g for $out, $stderr;
    return { out => $out, err => $stderr, exit => $exit };
}

sub same_as_test_more ($body, $name) {
    my $want = run_probe( 'Test::More', $body );
    my $got  = run_probe( 'Test::Chalk', $body );
    is $got->{out},  $want->{out},  "$name: stdout";
    is $got->{err},  $want->{err},  "$name: stderr";
    is $got->{exit}, $want->{exit}, "$name: exit status";
}

# use_ok and require_ok: the module loaded at run time, into the caller's
# package; a test named "use Foo;", and on failure the error.
same_as_test_more( qq{use_ok('Text::Wrap');\nok(defined &wrap, 'imported');\nuse_ok('List::Util', 'max');\nis(max(1, 3), 3, 'with an import list');\nuse_ok('No::Such::Module::Here');\ndone_testing;\n}, 'use_ok' );
same_as_test_more( qq{require_ok('Text::Abbrev');\nrequire_ok('No::Such::Module::There');\nok(1) or BAIL_OUT('x');\ndone_testing;\n}, 'require_ok' );

# explain: a reference as Data::Dumper shows it (Indent 1, Terse, sorted keys),
# anything else as itself.
same_as_test_more( qq{diag explain { b => [1, 2], a => undef };\nnote explain [ 'x', { y => 1 } ], 'plain';\nmy \@e = explain('s', 2);\nis(scalar(\@e), 2, 'one per argument');\ndone_testing;\n}, 'explain' );

# $TODO: in a TODO block a failure is "not ok ... # TODO why", its diagnostics
# on stdout, and it is not counted as failed; a pass is "ok ... # TODO why".
same_as_test_more( qq{our \$TODO;\nTODO: {\n    local \$TODO = 'not yet';\n    ok(0, 'a');\n    is(1, 2, 'b');\n    ok(1, 'c');\n    ok(0);\n    diag('inside');\n}\nok(1, 'd');\ndone_testing;\n}, 'TODO' );
same_as_test_more( qq{TODO: {\n    local \$TODO = 'later';\n    ok(0, 'x');\n}\nok(0, 'y');\ndone_testing;\n}, 'TODO, then a real failure' );
same_as_test_more( qq{TODO: {\n    local our \$TODO = 'ours';\n    ok(0, 'x');\n}\ndone_testing;\n}, 'local our $TODO' );
same_as_test_more( qq{subtest 's' => sub {\n    TODO: {\n        local \$TODO = 'inner';\n        ok(0, 'i');\n    }\n    ok(1, 'j');\n};\ndone_testing;\n}, 'TODO in a subtest' );
# Run under a harness: the newline before a failure's diagnostics goes where
# they go.
{
    local $ENV{HARNESS_ACTIVE} = 1;
    same_as_test_more( qq{ok(1);\nTODO: {\n    local \$TODO = 'h';\n    ok(0, 'x');\n}\nok(0, 'y');\ndone_testing;\n}, 'TODO under a harness' );
}

# $Test::Builder::Level: a helper that raises it is looked through, for the
# line a failure is reported at and for the $TODO it is in.
same_as_test_more( qq{package Helper;\nsub check {\n    local \$Test::Builder::Level = \$Test::Builder::Level + 1;\n    main::ok(\$_[0], \$_[1]);\n    main::is(\$_[0], 1, 'is');\n    main::diag('d');\n}\npackage main;\nHelper::check(0, 'here');\nTODO: {\n    local \$TODO = 'via a helper';\n    Helper::check(0, 'todo');\n}\nok(0, 'plain');\ndone_testing;\n}, 'Test::Builder::Level' );

# A subtest's plan is checked: one that runs other than it planned fails.
same_as_test_more( qq{subtest 'short' => sub {\n    plan tests => 2;\n    ok(1);\n};\nsubtest 'long' => sub {\n    plan tests => 1;\n    ok(1);\n    ok(1);\n};\nsubtest 'right' => sub {\n    plan tests => 1;\n    ok(1);\n};\ndone_testing;\n}, 'a subtest runs what it planned' );

# Output written before a fork is written once. (perl flushes every handle
# before it forks, so the child has no buffer to write again.)
same_as_test_more( qq{ok(1, 'before');\nmy \$pid = fork();\nexit 0 if defined \$pid && \$pid == 0;\nwaitpid(\$pid, 0);\nok(1, 'after');\ndone_testing;\n}, 'a fork' );

done_testing;
