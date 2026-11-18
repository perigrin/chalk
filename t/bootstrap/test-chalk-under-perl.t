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
    my $head = $module =~ /\n/ ? $module : "use $module;\n";
    print $fh "use lib 't/lib';\n$head$body";
    close $fh;
    my ( undef, $err ) = tempfile( UNLINK => 1 );
    my $out  = qx($^X $file 2>$err);
    my $exit = $? & 127 ? 128 + ( $? & 127 ) : $? >> 8;
    open my $eh, '<', $err or die "$err: $!";
    my $stderr = do { local $/; <$eh> } // '';
    # (the file names differ: each is written as FILE; so do the counts of
    # string evals each module made before the probe's, and addresses)
    s/\Q$file\E/FILE/g, s/\(eval \d+\)/(eval N)/g, s/\(0x[0-9a-f]+\)/(0xADDR)/g for $out, $stderr;
    return { out => $out, err => $stderr, exit => $exit };
}

sub same_as_test_more ($body, $name) {
    my $want = run_probe( 'Test::More', $body );
    my $got  = run_probe( 'Test::Chalk', $body );
    is $got->{out},  $want->{out},  "$name: stdout";
    is $got->{err},  $want->{err},  "$name: stderr";
    is $got->{exit}, $want->{exit}, "$name: exit status";
}

# WHAT ONLY TEST2 HAS (ref_ok, dies, lives, isa_ok of a list of classes):
# the oracle is Test::More with Test2's own tools for those -- Test::Chalk is
# Test::More, plus Test2's functions Test::More lacks. Test2's isa_ok takes
# [classes] (and a name) where Test::More's takes a class: Test::Chalk's is
# Test2's when its second argument is a list of classes.
# (one line, as Test::Chalk's: the probe's line numbers are the same)
my $WITH_TEST2 = "use Test::More; use Test2::Tools::Ref qw(ref_ok); use Test2::Tools::Exception qw(dies lives); use Test2::Tools::Class ();"
  . " BEGIN { no warnings 'redefine'; *main::isa_ok = sub (\$\$;\$) { goto &Test2::Tools::Class::isa_ok if ref \$_[1] eq 'ARRAY'; goto &Test::More::isa_ok } }\n";
sub same_as_test2 ($body, $name) {
    my $want = run_probe( $WITH_TEST2, $body );
    my $got  = run_probe( 'Test::Chalk', $body );
    is $got->{out},  $want->{out},  "$name: stdout";
    is $got->{err},  $want->{err},  "$name: stderr";
    is $got->{exit}, $want->{exit}, "$name: exit status";
}
my $classes = qq{package Foo;\nsub new { my (\$c) = \@_; return bless {}, \$c }\npackage Bar;\nour \@ISA = ('Foo');\npackage main;\n};

# ref_ok($thing, $type, $name): a reference (of that type, by what it is
# underneath), Test2's diagnostics.
same_as_test2( $classes . qq{ref_ok([], 'ARRAY', 'an array');\nref_ok({}, 'ARRAY', 'not an array');\nref_ok({}, 'HASH');\nref_ok({});\nref_ok('x', 'HASH', 'plain');\nref_ok('y');\nref_ok(undef, undef, 'undef');\nref_ok(Foo->new, 'HASH', 'an object');\nref_ok(Foo->new, 'Foo', 'not its class');\nref_ok(\\1, 'SCALAR');\nok(ref_ok([]), 'returns true');\ndone_testing;\n}, 'ref_ok' );

# dies { ... }: the exception, or undef; lives { ... }: true, or false with
# the exception shown when the next test fails, and left in $@.
same_as_test2( qq{is(dies { die "boom\\n" }, "boom\\n", 'dies gives the exception');\nok(!defined(dies { 1 }), 'no die: undef');\nlike(dies { die "x" }, qr/^x at /, 'with where');\neval { die "outer\\n" };\nmy \$e = dies { die "in\\n" };\nis(\$@, "outer\\n", 'dies leaves the error as it was');\nok(lives { 1 }, 'lives');\nok(lives { die "x\\n" }, 'lives fails');\nok(lives { die "y" });\nok(!lives { die "z\\n" }, 'negated');\nok(0, 'no exception shown');\nmy \$l = lives { die "w\\n" };\nis(\$@, "w\\n", 'lives leaves its exception as the error');\nmy \$m = lives { die "v\\n" };\ndiag('a diag drops it');\nok(0, 'later');\nmy \$q = lives { die "u\\n" };\nis(1, 2, 'after is');\npass('p');\ndone_testing;\n}, 'dies and lives' );

# isa_ok($thing, [classes], $name): Test2's -- each class by ->isa, the
# thing named as Test2 names it, every class it is not listed.
same_as_test2( $classes . qq{isa_ok(Bar->new, ['Foo']);\nisa_ok(Bar->new, ['Foo'], 'named');\nisa_ok(Bar->new, ['Foo', 'Bar'], 'two');\nisa_ok(Bar->new, ['Baz'], 'bad');\nisa_ok(Bar->new, ['Baz', 'Foo', 'Qux']);\nisa_ok('Bar', ['Foo']);\nisa_ok('Bar', ['Baz']);\nisa_ok(undef, ['Foo']);\nisa_ok([], ['ARRAY'], 'a plain reference');\nisa_ok('', ['Foo']);\nok(isa_ok(Bar->new, ['Foo']), 'returns true');\nisa_ok(Bar->new, 'Foo');\nisa_ok(Bar->new, 'Baz', 'Test::More\\'s still');\ndone_testing;\n}, 'isa_ok of a list of classes' );
{
    local $ENV{HARNESS_ACTIVE} = 1;
    same_as_test2( qq{ok(1);\nref_ok('x');\nok(lives { die "h\\n" }, 'h');\nisa_ok(undef, ['Foo']);\ndone_testing;\n}, 'Test2\'s functions under a harness' );
}

# Test::More's prototypes: an argument is in scalar context (a grep is its
# count, an array its length).
same_as_test_more( qq{my \@a = (5, 6);\nok((grep { \$_ == 0 } (0, 1)), 'a grep counts');\nis(\@a, 2, 'an array is its length');\nisnt(\@a, 3, 'isnt');\nlike(\@a, qr/^2\$/, 'like');\nunlike(\@a, qr/^5/, 'unlike');\ncmp_ok(\@a, '==', 2, 'cmp_ok');\ndone_testing;\n}, 'prototypes' );

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

# is_deeply walks an object by what it is underneath, ignoring its class.
same_as_test_more( qq{my \$a = bless { t => 'x', k => [1, 2] }, 'Foo';\nis_deeply(\$a, bless({ t => 'x', k => [1, 2] }, 'Foo'), 'same object');\nis_deeply(\$a, bless({ t => 'x', k => [1, 3] }, 'Foo'), 'differs inside');\nis_deeply(\$a, { t => 'x', k => [1, 2] }, 'blessed or not');\nis_deeply([bless([1], 'Bar')], [bless([1], 'Baz')], 'two classes, one shape');\nis_deeply(bless([1], 'Bar'), bless({}, 'Bar'), 'array and hash');\ndone_testing;\n}, 'is_deeply of objects' );

# A subtest's plan is checked: one that runs other than it planned fails.
same_as_test_more( qq{subtest 'short' => sub {\n    plan tests => 2;\n    ok(1);\n};\nsubtest 'long' => sub {\n    plan tests => 1;\n    ok(1);\n    ok(1);\n};\nsubtest 'right' => sub {\n    plan tests => 1;\n    ok(1);\n};\ndone_testing;\n}, 'a subtest runs what it planned' );

# A VALUE OF SEVERAL LINES in a failure's diagnostics: each line "# "-prefixed.
same_as_test_more( qq{is("a\\nb", "c", 'is');\nisnt("x\\ny", "x\\ny", 'isnt');\nlike("a\\nb", qr/z/, 'like');\nunlike("a\\nb", qr/b/, 'unlike');\ncmp_ok("a\\nb", 'eq', "c", 'cmp_ok eq');\nis_deeply(["a\\nb"], ["c"], 'is_deeply');\nsubtest 's' => sub { is("p\\nq", "r", 'in a subtest') };\ndone_testing;\n}, 'a value of several lines' );

# plan skip_all IN A SUBTEST skips that subtest, not the program: its
# "1..0 # SKIP why", then "ok N # skip why" for it. A test it failed before
# is reported on stderr, and hidden: the subtest is ok, the program passes.
same_as_test_more( qq{ok(1, 'before');\nsubtest 'skipped' => sub {\n    plan skip_all => 'not here';\n    ok(1, 'never');\n};\nsubtest 'some then skip' => sub {\n    ok(1, 'one');\n    plan skip_all => 'later';\n    ok(1, 'never');\n};\nsubtest 'fail then skip' => sub {\n    ok(0, 'lower() does not die');\n    ok(1, 'two');\n    ok(0);\n    plan skip_all => 'lowering failed';\n};\nsubtest 'nested' => sub {\n    ok(1, 'n1');\n    subtest 'inner' => sub { diag('dd'); note('nn'); plan skip_all => 'deep'; };\n    ok(1, 'n2');\n};\nok(1, 'after');\ndone_testing;\n}, 'skip_all in a subtest' );
{
    local $ENV{HARNESS_ACTIVE} = 1;
    same_as_test_more( qq{subtest 'fail then skip' => sub {\n    ok(0, 'x');\n    plan skip_all => 'y';\n};\nok(0, 'z');\ndone_testing;\n}, 'skip_all in a subtest, under a harness' );
}
# A DIE IN A SUBTEST finishes it (its plan, and its test, from what ran),
# then goes on dying. (Compared on stdout: Test::More's END says more on
# stderr.)
{
    my $want = run_probe( 'Test::More', qq{subtest 'dies' => sub {\n    ok(1, 'one');\n    die "boom\\n";\n};\nok(1, 'never');\ndone_testing;\n} );
    my $got  = run_probe( 'Test::Chalk', qq{subtest 'dies' => sub {\n    ok(1, 'one');\n    die "boom\\n";\n};\nok(1, 'never');\ndone_testing;\n} );
    is $got->{out}, $want->{out}, 'a die in a subtest: stdout';
    like $got->{err}, qr/\Aboom\n/, '... and it dies with its error';
    is $got->{exit}, $want->{exit}, '... and its exit status';
}

# Output written before a fork is written once. (perl flushes every handle
# before it forks, so the child has no buffer to write again.)
same_as_test_more( qq{ok(1, 'before');\nmy \$pid = fork();\nexit 0 if defined \$pid && \$pid == 0;\nwaitpid(\$pid, 0);\nok(1, 'after');\ndone_testing;\n}, 'a fork' );

done_testing;
