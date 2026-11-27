# ABOUTME: map/grep/sort `{` is a BLOCK or an EXPR by the builtin's two signatures --
# ABOUTME: BLOCK LIST (no comma) and EXPR, LIST (a comma) -- one reading, no tie.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;

use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Perl::Target::Perl;

# map, grep and sort take a `{` two ways. As `BLOCK LIST` no comma follows the
# `}`; as `EXPR, LIST` the `{` opens an anonymous hash and a comma is
# required. So the two readings never cover the same tokens, and the parse
# has exactly one -- the filter never sees a tie between them.
#
# Every expectation below was checked against perl 5.42 with
# `perl -MO=Deparse`. perl itself decides by a lookahead GUESS (toke.c) before
# it sees whether a comma follows, so it rejects a few programs whose comma
# settles the question; those are listed separately, pinned as what chalk does
# today, because whether chalk refuses them too is perigrin's decision.

my $ir = perl_pipeline();
die 'Perl grammar failed', "\n" unless defined $ir;
my $generated = Chalk::Bootstrap::BNF::Target::Perl->new->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::MapBlockOrExprTest/g;
eval $generated;
die "Generated grammar failed: $@", "\n" if $@;
my $parser = build_perl_ir_parser(
    Chalk::Grammar::Perl::MapBlockOrExprTest::grammar(), start => 'Program');

local $ENV{CHALK_COUNT_FILTER_TIES} = 1;

# reading($expr) -> (parsed, ties, the `my @r = ...` line chalk regenerates)
sub reading ($expr) {
    my $src = "class C { method m { my \@x = (1, 2); my \@r = $expr; return \@r; } }";
    $parser->semiring->flush_tie_log;
    $parser->semiring->reset_cache;
    my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
    my $r   = $parser->parse_value($src);
    my $ok  = defined $r && !$r->is_zero;
    my $ties = scalar $parser->semiring->tie_log->@*;
    return ( 0, $ties, '' ) unless $ok;
    my $out = Chalk::Bootstrap::Perl::Target::Perl->new->generate($mop);
    $out = join '', values $out->%* if ref $out eq 'HASH';
    my ($line) = $out =~ /^\s*(my \@r = [^\n]*)/m;
    return ( 1, $ties, $line // '' );
}

# The regenerated call shows the reading: `map {` for BLOCK LIST, `map({`
# for EXPR, LIST (the hash constructor as the first argument).
my %FORM = (
    block => qr/= (?:map|grep|sort) \{/,
    expr  => qr/= (?:map|grep)\(\{/,
);

sub check ($expr, $form, $why) {
    my ( $ok, $ties, $line ) = reading($expr);
    ok $ok, "$expr: parses ($why)" or return;
    is $ties, 0, "$expr: one reading, no tie";
    like $line, $FORM{$form}, "$expr: read as " . ( $form eq 'block' ? 'BLOCK LIST' : 'EXPR, LIST' )
        or diag "regenerated: $line";
}

# PERL ACCEPTS, and the signature rule gives perl's meaning.
check( 'map { $_ => 1 } @x',      'block', 'perl: map({$_, 1;} @x)' );
check( 'map {; $_ => 1 } @x',     'block', 'perl: map({$_, 1;} @x)' );
check( 'map +{ $_ => 1 }, @x',    'expr',  'perl: map({$_, 1}, @x)' );
check( 'map { "\L$_" => 1 }, @x', 'expr',  'perl: map({lc $_, 1}, @x)' );
check( 'map { ($_ => 1) } @x',    'block', 'perl: map({$_, 1;} @x)' );
check( 'map { lc($_) => 1 } @x',  'block', 'perl: map({lc $_, 1;} @x)' );
check( 'map { a => 1 }, @x',      'expr',  q{perl: map({'a', 1}, @x)} );
check( 'map { 1 } @x',            'block', 'perl: map({1;} @x)' );
check( 'map { $_ * 2 } @x',       'block', 'perl: map({$_ * 2;} @x)' );
check( 'grep { $_ } @x',          'block', 'perl: grep({$_;} @x)' );
check( 'sort { $a <=> $b } @x',   'block', 'perl: sort {$a <=> $b} @x' );
# A bare word is never subscripted: `map {` is never the element of a hash
# named by the word map, so a map inside a map's block leaves one reading.
check( 'map { join(q(,), map { $_ } $_) } @x', 'block', q{perl: map({join(',', map({$_;} $_));} @x)} );
# A `{` followed by an operator rather than a comma: as EXPR the anonymous
# hash would be the left operand of `+`; perl guesses BLOCK (its first
# token is no word or string before `,` or `=>`), and so does chalk: of
# two calls over the same tokens, the BLOCK reading is preferred
# (Builder/Containers.pm: `grep { ... } +($b->{own_nodes} // [])->@*`).
check( 'grep { $_ > 1 } +(@x)', 'block', q{perl: grep({$_ > 1;} @x)} );

# PERL REJECTS these: its guess is made before the comma (or its absence) is
# seen, and the guess is wrong. The signatures admit exactly one reading of
# each; chalk takes it. Pinned, not endorsed -- refusing them is a decision.
#   map { "\L$_" => 1 } @x   perl guesses EXPR, then: syntax error near "} @x"
#   map { 1 }, @x            perl guesses BLOCK, then: syntax error near "},"
check( 'map { "\L$_" => 1 } @x', 'block', 'PERL REJECTS: guesses EXPR' );
check( 'map { 1 }, @x',          'expr',  'PERL REJECTS: guesses BLOCK' );

# A builtin with one signature, EXPR LIST, has no BLOCK form: its `{` is an
# anonymous hash, whatever follows the `}`. (Only map, grep and sort have
# two; print and say take a block as their filehandle.)
#   perl -MO=Deparse: bless {%args}, $class  ->  bless({%args}, $class)
{
    my $src = 'class B1 { sub new($class, %args) { return bless {%args}, $class } }';
    $parser->semiring->flush_tie_log;
    $parser->semiring->reset_cache;
    my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
    my $r   = $parser->parse_value($src);
    ok defined $r && !$r->is_zero, 'bless {%args}, $class: parses';
    is scalar $parser->semiring->tie_log->@*, 0, 'bless {%args}, $class: one reading, no tie';
    my $out = Chalk::Bootstrap::Perl::Target::Perl->new->generate($mop);
    $out = join '', values $out->%* if ref $out eq 'HASH';
    like $out, qr/bless\(\{\s*%args\s*\}, \$class\)/, 'bless {%args}, $class: the { is an anonymous hash';
}
{
    my $src = 'class B2 { method m($fh) { print {$fh} "x"; say {$fh} "y"; return 1 } }';
    $parser->semiring->flush_tie_log;
    $parser->semiring->reset_cache;
    my $r = $parser->parse_value($src);
    ok defined $r && !$r->is_zero, 'print {$fh} LIST and say {$fh} LIST still parse';
    # (the block is the filehandle: of the two calls, the block reading)
    is scalar $parser->semiring->tie_log->@*, 0, 'print {$fh} LIST and say {$fh} LIST: no tie';
}

# eval and do have two forms each (perlfunc): `eval BLOCK` / `eval EXPR` and
# `do BLOCK` / `do EXPR`. A `{` after either opens the BLOCK -- perl never
# reads it as an anonymous hash, which as EXPR would be a string to compile
# or a file to run. perl -MO=Deparse: eval {1;}, do {1;}.
for my $case ([ 'eval { 1 }', qr/eval \{/ ], [ 'do { 1 }', qr/do \{/ ]) {
    my ($expr, $want) = $case->@*;
    my $src = "class E1 { sub f(\$s) { my \$v = $expr; my \$w = " . ($expr =~ /^eval/ ? 'eval $s' : 'do $s') . "; return \$v } }";
    $parser->semiring->flush_tie_log;
    $parser->semiring->reset_cache;
    my $r = $parser->parse_value($src);
    ok defined $r && !$r->is_zero, "$expr and its EXPR form parse";
    is scalar $parser->semiring->tie_log->@*, 0, "$expr: one reading, no tie";
}

done_testing;