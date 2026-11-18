# ABOUTME: Declared deviations from perl's output: the two legitimate grounds (cannot:,
# ABOUTME: correct:), the census's declared-deviations file, and the verdict a case gets.
package Chalk::CodeGen::Harness::Deviation;
use v5.42.0;
use File::Basename qw(dirname);
use File::Spec;
use Exporter 'import';
our @EXPORT_OK = qw(ground_of read_declared judge declared_path declared);

# THE RULE (perigrin; widened 2026-11-16 -- docs/plans/
# 2026-09-04-legal-deviation-a-third-verdict.md). chalk's output may differ
# from perl's, declared case by case, on one of two grounds:
#
#   cannot:   static compilation CANNOT do what perl does (hash order perl
#             randomises per process, a run-time fact no compiler knows).
#   correct:  chalk's answer is PROVABLY CORRECT where perl's is an artifact
#             of its implementation. perl's IV/UV/NV forms are an
#             implementation detail, not language semantics, and the
#             abstraction leaks: one value prints two ways depending on which
#             form an op happened to leave it in. Three conditions:
#               - the reason STATES THE PROOF: what makes chalk's answer
#                 correct ("the exact value of the expression; perl prints a
#                 rounded double");
#               - the deviation is NEVER LESS EXACT OR LESS CONSISTENT than
#                 perl, only more -- where perl's output is the exact one,
#                 chalk's is a defect, whatever it costs to match;
#               - "chalk HAS NOT YET" is still illegitimate.
#
# Both fields stay mandatory: the reason (naming its ground) and the exact
# output chalk must print. A declared case passes on that output alone and is
# counted DEVIATES -- never SAME, never ROUNDTRIP.
our %GROUND = ( cannot => 'static compilation cannot do what perl does',
                correct => "chalk's answer is provably correct where perl's is an artifact of its implementation" );

# ground_of($reason) -> ($ground, $proof): the ground a reason names, and what
# it states after it. Dies on a reason with no ground, or nothing stated.
sub ground_of ($reason) {
    my ( $g, $rest ) = ( $reason // '' ) =~ /\A\s*(\w+)\s*:\s*(.*?)\s*\z/s
        or die "a deviation's reason names its ground, cannot: or correct: -- got: "
             . ( $reason // '' ) . "\n";
    die "a deviation's ground is cannot: or correct:, not $g: -- got: $reason\n" unless $GROUND{$g};
    die "a deviation's reason states its proof after $g: -- got: $reason\n" unless length $rest;
    return ( $g, $rest );
}

# declared_path() -> this repo's t/data/census-deviations.tsv.
sub declared_path () {
    return File::Spec->catfile( dirname(__FILE__), ( File::Spec->updir ) x 4, 'data', 'census-deviations.tsv' );
}

# read_declared($path) -> { 'file:N' => { id, ground, reason, expected } }.
#
# One case per line, tab-separated: id, ground, reason, expected. id is the
# case's file:N (T2Case's id: stable when other corpus files change, which the
# census's cNNN is not). expected is the case's WHOLE stdout, with \n, \t and
# \\ escaped. '#' lines and blank lines are skipped.
sub read_declared ($path) {
    open my $f, '<:utf8', $path or die "cannot read $path: $!\n";
    my %d;
    while ( my $line = <$f> ) {
        chomp $line;
        next if $line =~ /\A\s*(?:#|\z)/;
        my $at = "$path line $.";
        my ( $id, $ground, $reason, $exp, @more ) = split /\t/, $line, -1;
        die "$at: one case is id, ground, reason, expected -- tab-separated\n" if @more;
        die "$at: a case is named file:N (T2Case's id), got " . ( $id // '' ) . "\n"
            unless defined $id && $id =~ /\A[\w.-]+:\d+\z/;
        die "$at: $id declared twice\n" if $d{$id};
        die "$at: a deviation's ground is cannot: or correct:, got " . ( $ground // '' ) . "\n"
            unless defined $ground && $GROUND{$ground};
        die "$at: a deviation needs its reason (the ground's proof)\n" unless defined $reason && $reason =~ /\S/;
        die "$at: a deviation needs its expected output; without it the case would accept any\n"
            unless defined $exp && length $exp;
        my %esc = ( n => "\n", t => "\t", '\\' => '\\' );
        ( my $want = $exp ) =~ s{\\(.)}{ $esc{$1} // die "$at: unknown escape \\$1\n" }ge;
        $d{$id} = { id => $id, ground => $ground, reason => $reason, expected => $want };
    }
    return \%d;
}

# declared() -> this repo's declared deviations, read once.
my $DECLARED;
sub declared () { return $DECLARED //= read_declared( declared_path() ) }

# judge($got, $want, $decl) -> { verdict => SAME|DIFFERS|DEVIATES, why }: a
# case's verdict from chalk's output, perl's, and its declaration (undef when
# it has none). A declared case is judged against its declared output alone.
sub judge ( $got, $want, $decl ) {
    return { verdict => $got eq $want ? 'SAME' : 'DIFFERS' } unless $decl;
    die( ( $decl->{id} // "a case" ) . ": the declared output is perl's own -- no deviation; drop the declaration\n" )
        if $decl->{expected} eq $want;
    return { verdict => 'DEVIATES', why => "$decl->{ground}: $decl->{reason}" } if $got eq $decl->{expected};
    return { verdict => 'DIFFERS',
             why => $got eq $want ? "declared to deviate, but printed perl's output: the declaration is stale"
                                  : "declared to deviate, but printed neither the declared output nor perl's" };
}

1;
