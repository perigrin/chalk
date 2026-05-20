# ABOUTME: Tests for ->@[range] postfix array slice syntax in the Perl grammar.
# ABOUTME: Covers Precedence semiring bracket-reset for the PostfixDeref slice alternative.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_recognizer build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::Precedence;
use Chalk::Bootstrap::Semiring::TypeInference;
use Chalk::Bootstrap::Semiring::Structural;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Desugar;
use Chalk::Grammar::Perl::PrecedenceTable;
use Chalk::Grammar::Perl::KeywordTable;
use Chalk::Grammar::Perl::TypeLibrary;
use Chalk::MOP;

# Build the Perl grammar pipeline once for all tests.
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

unless (defined $ir) {
    plan skip_all => 'Perl grammar failed to parse — cannot run slice tests';
    exit;
}

my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated  = $bnf_target->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::SliceTest/g;
eval $generated;
if ($@) {
    plan skip_all => "Generated grammar code failed: $@";
    exit;
}

my $grammar = Chalk::Grammar::Perl::SliceTest::grammar();

# ---------------------------------------------------------------------------
# Per-stage parser builders
# ---------------------------------------------------------------------------

my sub build_boolean_parser() {
    return build_perl_recognizer($grammar, start => 'Program');
}

my sub build_bp_parser() {
    # Boolean + Precedence
    my $ordered = do {
        my @reordered;
        my $found = false;
        for my $rule ($grammar->@*) {
            if (!$found && $rule->name() eq 'Program') {
                unshift @reordered, $rule;
                $found = true;
            } else {
                push @reordered, $rule;
            }
        }
        \@reordered;
    };
    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar($ordered);
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $comp_sr = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr],
    );
    return Chalk::Bootstrap::Earley->new(grammar => $desugared, semiring => $comp_sr);
}

my sub build_bpt_parser() {
    # Boolean + Precedence + TypeInference
    my $ordered = do {
        my @reordered;
        my $found = false;
        for my $rule ($grammar->@*) {
            if (!$found && $rule->name() eq 'Program') {
                unshift @reordered, $rule;
                $found = true;
            } else {
                push @reordered, $rule;
            }
        }
        \@reordered;
    };
    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar($ordered);
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );
    my $comp_sr = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $type_sr],
    );
    return Chalk::Bootstrap::Earley->new(grammar => $desugared, semiring => $comp_sr);
}

my sub build_bpts_parser() {
    # Boolean + Precedence + TypeInference + Structural
    my $ordered = do {
        my @reordered;
        my $found = false;
        for my $rule ($grammar->@*) {
            if (!$found && $rule->name() eq 'Program') {
                unshift @reordered, $rule;
                $found = true;
            } else {
                push @reordered, $rule;
            }
        }
        \@reordered;
    };
    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar($ordered);
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr   = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $type_sr   = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $comp_sr   = Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $type_sr, $struct_sr],
    );
    return Chalk::Bootstrap::Earley->new(grammar => $desugared, semiring => $comp_sr);
}

my sub build_full_parser() {
    return build_perl_ir_parser($grammar, start => 'Program');
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

my sub parse_ok_with($parser, $src, $label) {
    $parser->semiring->reset_cache() if $parser->semiring->can('reset_cache');
    my $result = $parser->parse_value($src);
    my $ok     = defined($result) && !$result->is_zero();
    ok($ok, $label);
    unless ($ok) {
        diag("  Failed to parse: $src");
    }
    return $ok;
}

my sub rejects_with($parser, $src, $label) {
    $parser->semiring->reset_cache() if $parser->semiring->can('reset_cache');
    my $result = $parser->parse_value($src);
    my $ok     = !defined($result) || $result->is_zero();
    ok($ok, $label);
    unless ($ok) {
        diag("  Should have rejected: $src");
    }
    return $ok;
}

# ---------------------------------------------------------------------------
# Section 1: per-stage discrimination for ->@[range]
#
# Verifies the fix passes each semiring layer independently.
# ---------------------------------------------------------------------------

note 'Section 1: per-stage discrimination for ->@[range]';

{
    my $src = 'my @a = $x->@[0..2];';

    my $bool_parser = build_boolean_parser();
    parse_ok_with($bool_parser, $src, '[B] ->@[0..2] recognized by Boolean');

    my $bp_parser = build_bp_parser();
    parse_ok_with($bp_parser, $src, '[B,P] ->@[0..2] passes Precedence');

    my $bpt_parser = build_bpt_parser();
    parse_ok_with($bpt_parser, $src, '[B,P,T] ->@[0..2] passes TypeInference');

    my $bpts_parser = build_bpts_parser();
    parse_ok_with($bpts_parser, $src, '[B,P,T,S] ->@[0..2] passes Structural');

    my $full_parser = build_full_parser();
    parse_ok_with($full_parser, $src, '[full] ->@[0..2] passes full pipeline');
}

# ---------------------------------------------------------------------------
# Section 2: core slice cases
# ---------------------------------------------------------------------------

note 'Section 2: core slice cases';

{
    my $parser = build_full_parser();

    parse_ok_with($parser, 'my @a = $x->@[0..2];',
        'basic literal range in assignment');

    parse_ok_with($parser, 'my @a = $x->@[$i];',
        'single-index slice');

    parse_ok_with($parser, 'my @a = $x->@[$i .. $j - 1];',
        'variable range with arithmetic in bound');

    parse_ok_with($parser, 'grep { defined $_ } $arr->@[0 .. $#$arr - 1];',
        'slice as builtin LIST argument');
}

# ---------------------------------------------------------------------------
# Section 3: regression guards
# ---------------------------------------------------------------------------

note 'Section 3: regression guards';

{
    my $parser = build_full_parser();

    parse_ok_with($parser, 'my @a = $x->@*;',
        'full array deref ->@* still works');

    parse_ok_with($parser, 'my @a = $x->[0..2];',
        'array constructor subscript still works');

    parse_ok_with($parser, 'my %h = $x->%*;',
        'hash deref ->%* still works');

    parse_ok_with($parser, 'my $n = $x->$*;',
        'scalar deref ->$* still works');

    parse_ok_with($parser, 'my @a = $arr[0..2];',
        'bare subscript still works');

    parse_ok_with($parser, 'my @a = $arr->[0]->[1];',
        'chained subscript still works');
}

done_testing();
