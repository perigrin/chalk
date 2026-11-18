#!/usr/bin/env perl
# ABOUTME: The census's declared deviations (t/data/census-deviations.tsv): a case declared
# ABOUTME: there passes only on its declared output, exactly, and is counted DEVIATES, never SAME.

use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempdir);

use Chalk::CodeGen::Harness::Deviation qw(ground_of read_declared judge declared_path);

# ---------------------------------------------------------------------------
# The census compared each case against perl alone. A case whose output is a
# legitimate deviation (the rule: Chalk::CodeGen::Harness::Deviation, and
# docs/plans/2026-09-04-legal-deviation-a-third-verdict.md) has no way to pass
# but to match perl -- so it either stays DIFFERS or someone "fixes" chalk to
# be less exact. The corpus's `L: DEVIATES` already answers this; the census
# gets the same mechanism, in a file in this repo: case, ground, reason, and
# the output chalk must print.
# ---------------------------------------------------------------------------

sub dies_like ($code, $re, $name) {
    my $err = do { local $@; eval { $code->(); 1 } ? '' : $@ };
    like $err, $re, $name;
}

sub tsv (@lines) {
    my $dir = tempdir(CLEANUP => 1);
    open my $f, '>:utf8', "$dir/d.tsv" or die $!;
    print $f map { "$_\n" } @lines;
    close $f;
    return "$dir/d.tsv";
}

subtest 'a reason names its ground' => sub {
    is_deeply [ ground_of('correct: the exact value; perl prints a rounded double') ],
        [ 'correct', 'the exact value; perl prints a rounded double' ], 'correct: is ground (b)';
    is_deeply [ ground_of('cannot: hash order is randomised per process') ],
        [ 'cannot', 'hash order is randomised per process' ], 'cannot: is ground (a)';
    dies_like sub { ground_of('perl does not specify IV vs NV') }, qr/ground.*cannot:.*correct:/s,
        'a reason with no ground is rejected';
    dies_like sub { ground_of('later: chalk has not yet') }, qr/ground/, 'an unknown ground is rejected';
    dies_like sub { ground_of('correct:   ') }, qr/proof|reason/i, 'a ground with nothing stated is rejected';
};

subtest 'the declared-deviations file' => sub {
    my $d = read_declared( tsv(
        '# id	ground	reason	expected',
        '',
        "arithmetic:9\tcorrect\tthe exact value; perl prints a rounded double\t1000000000000000\\n",
        "hashes:2\tcannot\thash order is randomised per process\tb a\\tc\\\\d\\n",
    ) );
    is_deeply [ sort keys $d->%* ], [ 'arithmetic:9', 'hashes:2' ], 'one entry per case, comments and blanks skipped';
    is $d->{'arithmetic:9'}{ground}, 'correct', 'the ground';
    like $d->{'arithmetic:9'}{reason}, qr/exact value/, 'the reason';
    is $d->{'arithmetic:9'}{expected}, "1000000000000000\n", 'expected is the whole output, \n decoded';
    is $d->{'hashes:2'}{expected}, "b a\tc\\d\n", '\t and \\\\ decoded';

    dies_like sub { read_declared( tsv("arithmetic:9\tlater\tbecause\tx\\n") ) }, qr/line 1.*ground/s,
        'an unknown ground dies, naming the line';
    dies_like sub { read_declared( tsv("arithmetic:9\tcorrect\t\tx\\n") ) }, qr/reason/,
        'an empty reason dies';
    dies_like sub { read_declared( tsv("arithmetic:9\tcorrect\tthe exact value") ) }, qr/expected/,
        'a row with no expected output dies';
    dies_like sub { read_declared( tsv("arithmetic:9\tcorrect\tthe exact value\t") ) }, qr/expected/,
        'an empty expected output dies: it would accept nothing checkable';
    dies_like sub { read_declared( tsv("c123\tcorrect\tthe exact value\tx\\n") ) }, qr/file:N/,
        'a case is named file:N (stable), not the census number (which moves)';
    dies_like sub { read_declared( tsv(map { "a:1\tcorrect\tr\tx\\n" } 1, 2) ) }, qr/twice/,
        'a case declared twice dies';
};

subtest 'judging a case' => sub {
    my $decl = { ground => 'correct', reason => 'r', expected => "1000000000000000\n" };
    is judge( "1\n", "1\n", undef )->{verdict}, 'SAME', 'undeclared, perl\'s output: SAME';
    is judge( "2\n", "1\n", undef )->{verdict}, 'DIFFERS', 'undeclared, other output: DIFFERS';
    is judge( "1000000000000000\n", "1e+15\n", $decl )->{verdict}, 'DEVIATES',
        'declared, the declared output: DEVIATES -- never SAME';
    my $r = judge( "1e+15\n", "1e+15\n", $decl );
    is $r->{verdict}, 'DIFFERS', 'declared, perl\'s output: not a pass (the declaration is stale)';
    like $r->{why}, qr/declared/, '... and says why';
    is judge( "999\n", "1e+15\n", $decl )->{verdict}, 'DIFFERS', 'declared, any third output: DIFFERS';
    dies_like sub { judge( "1\n", "1\n", { $decl->%*, expected => "1\n" } ) }, qr/perl's own/,
        'a declaration of perl\'s own output is no deviation: an error, not a pass';
};

subtest 'the repo\'s file loads, every entry with a ground' => sub {
    ok -f declared_path(), 'it is t/data/census-deviations.tsv';
    my $d = read_declared( declared_path() );
    for my $id ( sort keys $d->%* ) {
        like $d->{$id}{ground}, qr/\A(?:cannot|correct)\z/, "$id: a ground";
        ok length $d->{$id}{expected}, "$id: an expected output";
    }
    pass 'loaded';
    my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
    SKIP: {
        skip "perl5-son not found at $SON (set PERL5_SON_LIB): declared cases not checked", 1
            unless -f "$SON/B/SoN.pm";
        require Chalk::CodeGen::Harness::T2Case;
        my %case = map { ( $_->{id} => 1 ) } Chalk::CodeGen::Harness::T2Case::cases();
        is_deeply [ grep { !$case{$_} } sort keys $d->%* ], [], 'every declared case is a census case';
    }
};

done_testing;
