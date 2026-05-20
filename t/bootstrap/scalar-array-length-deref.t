# ABOUTME: Tests for $#{EXPR} array-length-of-deref syntax in the Perl grammar.
# ABOUTME: Covers Precedence semiring brace-reset for the ScalarVariable block form.
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
    plan skip_all => 'Perl grammar failed to parse — cannot run $#{EXPR} tests';
    exit;
}

my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated  = $bnf_target->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ArrayLengthDerefTest/g;
eval $generated;
if ($@) {
    plan skip_all => "Generated grammar code failed: $@";
    exit;
}

my $grammar = Chalk::Grammar::Perl::ArrayLengthDerefTest::grammar();

# ---------------------------------------------------------------------------
# Per-stage parser builders (mirrors postfix-array-slice.t structure)
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
# Section 1: per-stage discrimination for $#{EXPR}
#
# Verifies the fix passes each semiring layer independently.
# ---------------------------------------------------------------------------

note 'Section 1: per-stage discrimination for $#{EXPR}';

{
    my $src = 'my $n = $#{$arr};';

    my $bool_parser = build_boolean_parser();
    parse_ok_with($bool_parser, $src, '[B] $#{$arr} recognized by Boolean');

    my $bp_parser = build_bp_parser();
    parse_ok_with($bp_parser, $src, '[B,P] $#{$arr} passes Precedence');

    my $bpt_parser = build_bpt_parser();
    parse_ok_with($bpt_parser, $src, '[B,P,T] $#{$arr} passes TypeInference');

    my $bpts_parser = build_bpts_parser();
    parse_ok_with($bpts_parser, $src, '[B,P,T,S] $#{$arr} passes Structural');

    my $full_parser = build_full_parser();
    parse_ok_with($full_parser, $src, '[full] $#{$arr} passes full pipeline');
}

# ---------------------------------------------------------------------------
# Section 2: core $#{EXPR} cases
# ---------------------------------------------------------------------------

note 'Section 2: core $#{EXPR} cases';

{
    my $parser = build_full_parser();

    parse_ok_with($parser, 'my $n = $#{$arr};',
        'basic: scalar variable inside braces');

    parse_ok_with($parser, 'my $n = $#{ $arr };',
        'whitespace tolerance: spaces around inner expression');

    parse_ok_with($parser, 'for my $i (0 .. $#{$arr}) { my $x = $arr->[$i]; }',
        'in for-loop range bound');

    parse_ok_with($parser, 'my @rest = $arr->@[1 .. $#{$arr}];',
        'combined with Fix A postfix slice: ->@[1 .. $#{$arr}]');

    parse_ok_with($parser, 'my $n = $#{$obj->method()};',
        'non-scalar inner expression: method call inside braces');
}

# ---------------------------------------------------------------------------
# Section 3: precedence boundary probe
#
# $a + $#{ $b - 1 } — inner `-` must NOT steal the outer `+` context.
# Without a brace-boundary reset in Precedence, the inner `-` level would
# be compared against the outer `+` level and could cause mis-parse or reject.
# ---------------------------------------------------------------------------

note 'Section 3: precedence boundary probe';

{
    my $parser = build_full_parser();

    parse_ok_with($parser, 'my $n = $a + $#{ $b - 1 };',
        'precedence boundary: inner - does not steal outer + context');

    parse_ok_with($parser, 'my $n = $a * $#{ $b + $c };',
        'precedence boundary: inner + inside * context');

    parse_ok_with($parser, 'my $n = $#{ $arr } - 1;',
        'precedence boundary: $#{EXPR} as left operand of binary op');
}

# ---------------------------------------------------------------------------
# Section 4: regression guards
# ---------------------------------------------------------------------------

note 'Section 4: regression guards';

{
    my $parser = build_full_parser();

    parse_ok_with($parser, 'my $n = $#$arr;',
        'regression: existing $#$name form still works');

    parse_ok_with($parser, 'my $n = $#arr;',
        'regression: existing $#name form still works');

    parse_ok_with($parser, 'my $h = { foo => 1 };',
        'regression: HashConstructor not confused with $#{...}');

    parse_ok_with($parser, 'my $h = { count => $#{$arr} };',
        'regression: HashConstructor and $#{EXPR} in same expression');

    parse_ok_with($parser, 'my @a = $x->@[1 .. $#$x];',
        'regression: postfix slice with $#$name (Fix A) still works');
}

done_testing();
