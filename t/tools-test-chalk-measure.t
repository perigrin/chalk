# ABOUTME: tools/test-chalk/measure.pl's pure parts: which test files it measures (Test::Chalk, or
# ABOUTME: Test::More swapped; --easy keeps 11-17's hard-tier filter), and the swap to Test::Chalk.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::More;

require './tools/test-chalk/measure.pl';

# WHAT IS MEASURED: a test that uses Test::Chalk (every chalk test since the
# 11-17 migration), or Test::More, which is swapped. Test2::V0 is not.
ok( TestChalkMeasure::measured("use Test::Chalk;\nok(1);\n"), 'Test::Chalk: measured' );
ok( TestChalkMeasure::measured("use Test::More;\nok(1);\n"), 'Test::More: measured, swapped' );
ok( !TestChalkMeasure::measured("use Test2::V0;\nok(1);\n"), 'Test2::V0: not measured' );

# --easy (docs/plans/2026-11-17-test-chalk-measured.md, Part B): none of the
# hard-tier names, as 11-17 counted.
ok( TestChalkMeasure::is_easy("use Test::Chalk;\nok(1);\nis(1, 1);\ndone_testing;\n"), 'ok/is only: easy' );
ok( !TestChalkMeasure::is_easy("use Test::More;\nlike('a', qr/a/);\n"), 'like: hard tier' );
ok( !TestChalkMeasure::is_easy("use Test::More;\nsubtest x => sub { ok 1 };\n"), 'subtest: hard tier' );
ok( !TestChalkMeasure::is_easy("use Test::More;\nis_deeply([], []);\n"), 'is_deeply: hard tier' );
ok( TestChalkMeasure::is_easy("use Test::More;\n# like() is not called here\nok(1);\n"), 'a hard name in a comment does not count' );

# THE SWAP: `use Test::More` becomes `use Test::Chalk`, and the copy finds lib/
# and t/lib/ itself (the 11-17 run lost two files that relied on `prove -l`).
my $s = TestChalkMeasure::swap("#!perl\nuse strict;\nuse Test::More tests => 2;\nok(1);\n");
like( $s, qr/^use lib 'lib', 't\/lib';$/m, 'the copy finds lib/ and t/lib/' );
like( $s, qr/^use Test::Chalk tests => 2;$/m, 'Test::More becomes Test::Chalk, its import list kept' );
unlike( $s, qr/Test::More/, 'no Test::More left' );
like( $s, qr/\A#!perl\n/, 'the shebang line stays first' );
my $c = "use lib 'lib', 't/lib';\nuse Test::Chalk;\nok(1);\n";
is( TestChalkMeasure::swap($c), $c, 'a Test::Chalk file is run as it is' );

done_testing;
