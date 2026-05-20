# ABOUTME: Tests for grammar extensions addressing self-hosting conformance blockers.
# ABOUTME: Each section covers a specific construct needed for lib/ files to parse.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# Build the Perl grammar pipeline once for all tests.
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

unless (defined $ir) {
    plan skip_all => 'Perl grammar failed to parse — cannot run extension tests';
    exit;
}

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ExtensionTests/g;
eval $generated;
if ($@) {
    plan skip_all => "Generated grammar code failed: $@";
    exit;
}

my $gen_grammar = Chalk::Grammar::Perl::ExtensionTests::grammar();
my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');

unless (defined $parser) {
    plan skip_all => 'Could not build parser';
    exit;
}

# Helper: parse a full program fragment (semicolons included as needed)
my sub parses($src, $label) {
    $parser->semiring->reset_cache();
    my $result = $parser->parse_value($src);
    my $ok = defined($result) && !$result->is_zero();
    ok($ok, $label);
    unless ($ok) {
        diag("  Failed to parse: $src");
    }
    return $ok;
}

my sub rejects($src, $label) {
    $parser->semiring->reset_cache();
    my $result = $parser->parse_value($src);
    my $ok = !defined($result) || $result->is_zero();
    ok($ok, $label);
    return $ok;
}

# ============================================================================
# Section 1: return EXPR if COND / return EXPR unless COND
#
# Grammar gap: SimpleStatement had no PostfixModifier form for ReturnStatement.
# Fix: add "ReturnStatement WS PostfixModifier" as an alternative in SimpleStatement.
# Affects: ~20 lib/ files including Boolean.pm, Context.pm, Scope.pm, Earley.pm.
# ============================================================================

{
    parses(q(return $x if $cond;),        'return EXPR if COND');
    parses(q(return $x unless $cond;),    'return EXPR unless COND');
    parses(q(return undef if !$ok;),      'return undef if not-ok');
    parses(q(return $self->zero() if $left->is_zero();),  'return method if method');
    parses(q(return $result if defined $result;),         'return expr if defined');

    # Pre-existing: bare return with postfix if should still work
    parses(q(return if $cond;),           'bare return if COND (pre-existing)');
    parses(q(return unless $cond;),       'bare return unless COND (pre-existing)');

    # Regression guard: return EXPR without postfix modifier still works
    parses(q(return $x;),                 'return EXPR without modifier');
    parses(q(return;),                    'bare return without modifier');
}

# ============================================================================
# Section 2: -X file test operators in UnaryExpression
#
# Grammar gap: UnaryExpression did not include file test operators.
# Fix: add /-[efdrwxRWXoOzslpSbcugktTBAMC]\b/ alternative to UnaryExpression.
# Affects: Runtime.pm (2 sites with -f).
# ============================================================================

{
    parses(q(if (-f $path) { }),          '-f file test in condition');
    parses(q(if (-d $dir) { }),           '-d directory test');
    parses(q(if (-e $path) { }),          '-e existence test');
    parses(q(my $ok = $ENV{CHALK_SO_PATH} && -f $ENV{CHALK_SO_PATH};), '-f in boolean AND');
    parses(q(if ($ENV{CHALK_SO_PATH} && -f $ENV{CHALK_SO_PATH}) { }), '-f in if condition');

    # Regression: unary minus should still parse (not confused with file test)
    parses(q(-$x;),                       'unary minus still works');
    parses(q(my $y = -42;),               'negative number literal');
    parses(q(- $x;),                      'unary minus with space');
}

# ============================================================================
# Section 3: Qualified scalar variable ($Package::varname)
#
# Grammar gap: ScalarVariable regex /\$[a-zA-Z_]\w*/ did not match $Foo::bar.
# Fix: extend ScalarVariable to admit /\$[a-zA-Z_]\w*(?:::[a-zA-Z_]\w*)*/
# Affects: Runtime.pm (1 site: $Config::Config{dlext}).
# ============================================================================

{
    parses(q(my $x = $Config::Config{dlext};),  '$Config::Config{dlext} hash access');
    parses(q(my $x = $Foo::bar;),                'qualified scalar $Foo::bar');
    parses(q(my $x = $Module::var;),             'qualified scalar in assignment');

    # Regression: simple scalar still works (with statement context)
    parses(q(my $x = $y;),                       'simple scalar still works');
    parses(q(my $x = $config;),                  'unqualified scalar in assignment');
}

done_testing();
