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
    adjacency-01_literals:1 adjacency-12_packages:1 adjacency-05_scoping:1 adjacency-06_control:2
    argument-extent:3
    adjacency-09_regex:1 aggregate-operators:1 aggregate-operators:2
    aggregate-operators:3 aggregate-operators:4 aggregate-operators:5
    aggregate-operators:6 aggregates-in-context:1 aggregates-in-context:2
    aggregates-in-context:3 argument-extent:1 argument-extent:2
    argument-extent:4 arguments:1 arguments:2 arguments:3 arguments:4
    arguments:5 arguments:6 arguments:7 arguments:8 arguments:9 arithmetic:1
    arithmetic:2 arithmetic:3 arithmetic:4 arrays:1 arrays:2 arrays:3
    arrays:4 bitwise:1 bitwise:3 bitwise:4 bitwise:5 bitwise:6
    bless-dispatch:1 bless-dispatch:2 bless-dispatch:3 bless-dispatch:4
    bless-dispatch:5 bless-dispatch:6 bless-dispatch:7 bless-dispatch:8
    bless-dispatch:9 blocks-and-terminations:1 blocks-and-terminations:2
    blocks-and-terminations:3 blocks-and-terminations:4
    blocks-and-terminations:5 chalk-found-gaps:1 chalk-found-gaps:10
    chalk-found-gaps:100 chalk-found-gaps:101 chalk-found-gaps:102
    chalk-found-gaps:103 chalk-found-gaps:105 chalk-found-gaps:11
    chalk-found-gaps:111 chalk-found-gaps:112 chalk-found-gaps:113
    chalk-found-gaps:114 chalk-found-gaps:115 chalk-found-gaps:116
    chalk-found-gaps:117 chalk-found-gaps:118 chalk-found-gaps:119
    chalk-found-gaps:12 chalk-found-gaps:122 chalk-found-gaps:124
    chalk-found-gaps:125 chalk-found-gaps:126 chalk-found-gaps:127
    chalk-found-gaps:128 chalk-found-gaps:13 chalk-found-gaps:131
    chalk-found-gaps:133 chalk-found-gaps:135 chalk-found-gaps:136
    chalk-found-gaps:137 chalk-found-gaps:139 chalk-found-gaps:14
    chalk-found-gaps:140 chalk-found-gaps:142 chalk-found-gaps:143
    chalk-found-gaps:148 chalk-found-gaps:149 chalk-found-gaps:15
    chalk-found-gaps:151 chalk-found-gaps:152 chalk-found-gaps:153
    chalk-found-gaps:155 chalk-found-gaps:157 chalk-found-gaps:158
    chalk-found-gaps:16 chalk-found-gaps:161 chalk-found-gaps:162 chalk-found-gaps:163
    chalk-found-gaps:165 chalk-found-gaps:166 chalk-found-gaps:167
    chalk-found-gaps:168 chalk-found-gaps:169 chalk-found-gaps:17
    chalk-found-gaps:170 chalk-found-gaps:171 chalk-found-gaps:172
    chalk-found-gaps:18 chalk-found-gaps:19 chalk-found-gaps:2
    chalk-found-gaps:20 chalk-found-gaps:21 chalk-found-gaps:22
    chalk-found-gaps:23 chalk-found-gaps:24 chalk-found-gaps:25
    chalk-found-gaps:28 chalk-found-gaps:29 chalk-found-gaps:30
    chalk-found-gaps:31 chalk-found-gaps:32 chalk-found-gaps:33
    chalk-found-gaps:34 chalk-found-gaps:35 chalk-found-gaps:36
    chalk-found-gaps:37 chalk-found-gaps:38 chalk-found-gaps:39
    chalk-found-gaps:40 chalk-found-gaps:41 chalk-found-gaps:42
    chalk-found-gaps:44 chalk-found-gaps:45 chalk-found-gaps:46
    chalk-found-gaps:47 chalk-found-gaps:48 chalk-found-gaps:49
    chalk-found-gaps:5 chalk-found-gaps:50 chalk-found-gaps:51
    chalk-found-gaps:52 chalk-found-gaps:53 chalk-found-gaps:55
    chalk-found-gaps:56 chalk-found-gaps:57 chalk-found-gaps:58
    chalk-found-gaps:6 chalk-found-gaps:60 chalk-found-gaps:61
    chalk-found-gaps:62 chalk-found-gaps:63 chalk-found-gaps:65
    chalk-found-gaps:66 chalk-found-gaps:68 chalk-found-gaps:69
    chalk-found-gaps:7 chalk-found-gaps:72 chalk-found-gaps:74
    chalk-found-gaps:77 chalk-found-gaps:78 chalk-found-gaps:79
    chalk-found-gaps:8 chalk-found-gaps:80 chalk-found-gaps:81
    chalk-found-gaps:82 chalk-found-gaps:83 chalk-found-gaps:84
    chalk-found-gaps:85 chalk-found-gaps:87 chalk-found-gaps:88 chalk-found-gaps:89
    chalk-found-gaps:9 chalk-found-gaps:90 chalk-found-gaps:91
    chalk-found-gaps:92 chalk-found-gaps:93 chalk-found-gaps:95
    chalk-found-gaps:96 chalk-found-gaps:97 chalk-found-gaps:98
    chalk-found-gaps:99 class-feature:1 class-feature:10 class-feature:11
    class-feature:12 class-feature:2 class-feature:3 class-feature:4
    class-feature:5 class-feature:6 class-feature:7 class-feature:8
    class-feature:9 code-references:1 code-references:2 comparison:1
    comparison:2 comparison:3 comparison:4 comparison:5 comparison:6
    compile-phase:1 compile-phase:2 compile-phase:3 compile-phase:4
    compound-assignment:1 compound-assignment:2 compound-assignment:3
    compound-assignment:4 compound-assignment:5 conditionals:1
    conditionals:2 conditionals:3 conditionals:4 context-from-inside:1
    context-from-inside:2 declarations:1 declarations:2 declarations:3
    dereferencing:1 dereferencing:2 dereferencing:3 dereferencing:4
    dereferencing:5 dereferencing:6 dereferencing:7 dereferencing:8
    dynamic-scope:1 dynamic-scope:2 embedded-code:1 embedded-code:2
    embedded-code:3 eval-replacement:1 formats:1 formats:2 handles:1
    handles:2 handles:3 handles:4 hashes:1 hashes:2 hashes:3 hashes:4
    hashes:5 heredocs:1 heredocs:2 heredocs:3 jumps:1 jumps:3
    list-operators-in-context:1 list-operators-in-context:2
    list-operators-in-context:3 list-operators-in-context:4
    list-operators-in-context:5 loading:1 loading:2 loading:3 loading:4 loading:5 loading:6 loops:1 loops:10
    loops:11 loops:2 loops:3 loops:4 loops:5 loops:6 loops:7 loops:8 loops:9
    named-operators:1 named-operators:2 named-operators:3 named-operators:4
    named-operators:5 named-operators:6 named-operators:7 named-operators:8
    named-operators:9 names:1 names:3 names:4 names:5 names:6 numeric-point:1
    numeric-point:2 numeric-point:3 numeric-point:4 numeric-point:5
    numeric-radix:1 numeric-radix:2 numeric-radix:3 numeric-radix:4
    numeric-radix:5 numeric-radix:6 packages:1 packages:2 packages:3
    pod-and-data:1 pod-and-data:2 pod-and-data:3 pod-and-data:4
    quote-like-terms:2 quote-like-terms:3 quote-like-terms:4
    quote-like-terms:5 quote-like-terms:6 range:1 range:3 read-position:1
    read-position:2 read-position:3 regex-delimiters:1 regex-delimiters:2
    regex-delimiters:3 regex-matching:1 regex-matching:2 regex-matching:3
    regex-matching:4 regex-matching:5 regex-matching:7
    regex-pattern-positions:1 regex-pattern-positions:2 regex-quote-likes:1
    regex-quote-likes:2 strings:1 strings:2 strings:3 subroutines:1
    subroutines:10 subroutines:11 subroutines:2 subroutines:3 subroutines:4
    subroutines:6 subroutines:7 subroutines:8 subroutines:9 symbol-table:2 symbol-table:4
    taking-references:1 taking-references:3 taking-references:4 unary:1
    unary:2 unary:3 unary:4 unary:5 ungated:1 ungated:2 ungated:3 ungated:4
    vstrings:1 vstrings:2 writing:1 writing:2 writing:3 writing:4
);

my %case = map { ( $_->{id} => $_ ) } Chalk::CodeGen::Harness::T2Case::cases();
for my $id (@CASES) {
    my $c = $case{$id} or do { fail("$id: no such case"); next };
    my $r = Chalk::CodeGen::Harness::T2Case::run_case($c);
    is($r->{verdict}, 'SAME', "$id ($c->{cid})") or diag($r->{why} // "got: $r->{got}");
}

done_testing;
