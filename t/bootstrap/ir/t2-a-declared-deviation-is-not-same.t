# ABOUTME: script/t2-case judges a case declared in t/data/census-deviations.tsv by its
# ABOUTME: declared output alone, and calls it DEVIATES -- never SAME (Harness::Deviation).
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
use Chalk::CodeGen::Harness::LLI;
Chalk::CodeGen::Harness::LLI->lli;
require Chalk::CodeGen::Harness::T2Case;

# A census case perl and chalk agree on; the declarations below are made up
# for the test, the case's own output is not.
my $c = Chalk::CodeGen::Harness::T2Case::case_by_id('arithmetic:1') or BAIL_OUT('no arithmetic:1');
my $plain = Chalk::CodeGen::Harness::T2Case::run_case($c);
is $plain->{verdict}, 'SAME', 'undeclared, it is SAME (the repo declares no deviation for it)';
my $out = $plain->{got};

my %decl = ( ground => 'correct', reason => 'a test of the mechanism' );

# Declared, printing its declared output where perl prints something else:
# DEVIATES, with the declaration's ground and reason.
my $r = Chalk::CodeGen::Harness::T2Case::run_case( { $c->%*, want => "perl's other rendering\n" },
    { $c->{id} => { %decl, id => $c->{id}, expected => $out } } );
is $r->{verdict}, 'DEVIATES', 'declared, the declared output: DEVIATES, not SAME';
like $r->{why}, qr/\Acorrect: a test of the mechanism/, 'its why is the ground and reason';

# Declared, printing perl's output: the declaration is stale -- not a pass.
$r = Chalk::CodeGen::Harness::T2Case::run_case( $c, { $c->{id} => { %decl, id => $c->{id}, expected => "something else\n" } } );
is $r->{verdict}, 'DIFFERS', "declared, perl's output: DIFFERS";
like $r->{why}, qr/stale/, '... the declaration is stale';

# A declaration of perl's own output is no deviation: refused, never a pass.
$r = Chalk::CodeGen::Harness::T2Case::run_case( $c, { $c->{id} => { %decl, id => $c->{id}, expected => $out } } );
is $r->{verdict}, 'DIFFERS', "a declaration of perl's own output: DIFFERS";
like $r->{why}, qr/perl's own/, '... naming why';

done_testing;
