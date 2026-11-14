# ABOUTME: The pvm-corpus cases T2 lowers alone (no Context fallback) and prints as
# ABOUTME: perl does. A ratchet: a slice adds the cases it closes; none is ever removed.
use 5.42.0;
use Test::More;
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::T2Case;

# Cases by file:N (script/t2-case runs one). Retiring Context.pm needs every
# census case here (docs/plans/2026-11-14-context-only-census.tsv lists the rest).
my @CASES = qw(
    adjacency-01_literals:1 adjacency-05_scoping:1 adjacency-06_control:2
    adjacency-09_regex:1 aggregate-operators:1 aggregate-operators:2
    aggregate-operators:3 aggregate-operators:4 aggregate-operators:5
    aggregates-in-context:1 aggregates-in-context:2 aggregates-in-context:3
    argument-extent:1 argument-extent:2 arguments:1 arguments:4 arguments:5
    arguments:6 arguments:7 arguments:9 arithmetic:3 arrays:1 arrays:2
    arrays:3 bless-dispatch:1 bless-dispatch:2 bless-dispatch:3
    bless-dispatch:5 bless-dispatch:6 bless-dispatch:8
    blocks-and-terminations:1 blocks-and-terminations:2 chalk-found-gaps:1
    chalk-found-gaps:5 chalk-found-gaps:6 chalk-found-gaps:7
    chalk-found-gaps:9 chalk-found-gaps:14 chalk-found-gaps:17
    chalk-found-gaps:18 chalk-found-gaps:19 chalk-found-gaps:28
    chalk-found-gaps:30 chalk-found-gaps:33 chalk-found-gaps:34
    chalk-found-gaps:39 chalk-found-gaps:40 chalk-found-gaps:41
    chalk-found-gaps:42 chalk-found-gaps:44 chalk-found-gaps:45
    chalk-found-gaps:46 chalk-found-gaps:48 chalk-found-gaps:51
    chalk-found-gaps:52 chalk-found-gaps:55 chalk-found-gaps:56
    chalk-found-gaps:57 chalk-found-gaps:60 chalk-found-gaps:62
    chalk-found-gaps:69 chalk-found-gaps:87 chalk-found-gaps:89
    chalk-found-gaps:91 chalk-found-gaps:92 chalk-found-gaps:97
    chalk-found-gaps:100 chalk-found-gaps:102 chalk-found-gaps:103
    chalk-found-gaps:105 chalk-found-gaps:114 chalk-found-gaps:117
    chalk-found-gaps:133 chalk-found-gaps:140 chalk-found-gaps:142
    chalk-found-gaps:143 chalk-found-gaps:149 chalk-found-gaps:157
    chalk-found-gaps:161 chalk-found-gaps:162 chalk-found-gaps:165
    chalk-found-gaps:169 chalk-found-gaps:171 class-feature:1
    class-feature:2 class-feature:3 class-feature:4 class-feature:9
    class-feature:11 comparison:1 comparison:2 comparison:4 comparison:5
    comparison:6 compile-phase:1 compile-phase:2 compile-phase:3
    compile-phase:4 compound-assignment:1 compound-assignment:2
    compound-assignment:4 conditionals:1 conditionals:2 conditionals:3
    conditionals:4 context-from-inside:2 declarations:1 declarations:2
    declarations:3 dereferencing:1 dereferencing:2 dereferencing:3
    dereferencing:4 dereferencing:5 dereferencing:6 dereferencing:7
    dereferencing:8 dynamic-scope:1 dynamic-scope:2 embedded-code:1
    embedded-code:2 embedded-code:3 eval-replacement:1 hashes:1 hashes:2
    hashes:3 hashes:4 heredocs:1 heredocs:2 heredocs:3
    list-operators-in-context:2 list-operators-in-context:4
    list-operators-in-context:5 loading:1 loading:6 loops:1 loops:2 loops:3
    loops:4 loops:5 loops:6 loops:7 loops:9 named-operators:1
    named-operators:2 named-operators:4 named-operators:6 named-operators:7
    named-operators:8 named-operators:9 names:1 names:3 names:4 names:5
    numeric-point:1 numeric-point:2 numeric-point:3 numeric-point:4
    numeric-point:5 numeric-radix:1 numeric-radix:2 numeric-radix:3
    numeric-radix:4 numeric-radix:5 numeric-radix:6 packages:1 packages:2
    packages:3 pod-and-data:1 pod-and-data:2 quote-like-terms:5 range:3
    read-position:1 read-position:2 read-position:3 regex-delimiters:1
    regex-delimiters:2 regex-delimiters:3 regex-matching:1 regex-matching:2
    regex-matching:3 regex-matching:4 regex-matching:5
    regex-pattern-positions:1 regex-pattern-positions:2 regex-quote-likes:1
    regex-quote-likes:2 strings:1 strings:2 strings:3 subroutines:1
    subroutines:7 subroutines:8 subroutines:9 subroutines:10 subroutines:11
    symbol-table:4 taking-references:1 taking-references:3
    taking-references:4 unary:1 unary:2 unary:3 unary:5 ungated:1 ungated:2
    ungated:4 vstrings:1 vstrings:2 writing:2
);

my %case = map { ( $_->{id} => $_ ) } Chalk::CodeGen::Harness::T2Case::cases();
for my $id (@CASES) {
    my $c = $case{$id} or do { fail("$id: no such case"); next };
    my $r = Chalk::CodeGen::Harness::T2Case::run_case($c);
    is($r->{verdict}, 'SAME', "$id ($c->{cid})") or diag($r->{why} // "got: $r->{got}");
}

done_testing;
