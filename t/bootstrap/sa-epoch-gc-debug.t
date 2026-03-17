# ABOUTME: Regression test for issue #641: SemanticAction semiring kills valid
# ABOUTME: parse paths when epoch GC sweeps boundary items needed by later completions.
use 5.42.0;
use utf8;

use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_recognizer build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# Build Perl grammar pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::EpochGCRegression/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::EpochGCRegression::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# Helper: parse with 5-ary FilterComposite (with SemanticAction)
my sub parse_ir($source, $label) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $ir_parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $ir_result = eval { $ir_parser->parse_value($source) };
    my $ir_err = $@;
    ok(defined $ir_result, $label) or diag("Error: $ir_err");
}

# --- Issue #641: if/elsif/else fails with 5-ary semiring ---
# Root cause: epoch GC triggered by StatementItem completion swept boundary
# items at the sweep_origin position that were still needed by later
# completions (e.g., IfStatement waiting for recursive ElsifChain?).

# Simple if/else: works (no epoch GC conflict)
parse_ir(<<'PERL', '5-ary: simple if/else');
use 5.42.0;
use utf8;
my $x = 1;
if ($x == 1) {
    $x = 2;
} else {
    $x = 3;
}
PERL

# if/elsif without else: works (single ElsifChain, no recursion)
parse_ir(<<'PERL', '5-ary: if/elsif (no else)');
use 5.42.0;
use utf8;
my $x = 1;
if ($x == 1) {
    $x = 2;
} elsif ($x == 3) {
    $x = 4;
}
PERL

# if/elsif/else: THE BUG - epoch GC sweeps IfStatement waiting item
# before the recursive ElsifChain completes
parse_ir(<<'PERL', '5-ary: if/elsif/else');
if (1) {
    2;
} elsif (3) {
    4;
} else {
    5;
}
PERL

# if/elsif/elsif: same bug with multiple elsif recursion
parse_ir(<<'PERL', '5-ary: if/elsif/elsif (no else)');
use 5.42.0;
use utf8;
my $x = 1;
if ($x == 1) {
    $x = 2;
} elsif ($x == 3) {
    $x = 4;
} elsif ($x == 5) {
    $x = 6;
}
PERL

# if/elsif/else with surrounding statements
parse_ir(<<'PERL', '5-ary: if/elsif/else with surrounding stmts');
use 5.42.0;
use utf8;
my $x = 1;
my $y = 2;
if ($x == 1) {
    $y = 10;
} elsif ($x == 2) {
    $y = 20;
} else {
    $y = 30;
}
my $z = $y;
PERL

# Nested if/else: works (no ElsifChain recursion)
parse_ir(<<'PERL', '5-ary: nested if/else');
use 5.42.0;
use utf8;
my $x = 1;
if ($x == 1) {
    if ($x == 2) {
        $x = 3;
    } else {
        $x = 4;
    }
}
PERL

# Actual FilterComposite.pm source (the failing file from the issue)
{
    my $fc_source_path = 'lib/Chalk/Bootstrap/Semiring/FilterComposite.pm';
    open my $fh, '<:utf8', $fc_source_path or die "Cannot open $fc_source_path: $!";
    local $/;
    my $fc_source = readline($fh);
    close $fh;
    ok(defined $fc_source && length($fc_source) > 0, 'FilterComposite.pm source loaded');
    parse_ir($fc_source, '5-ary: FilterComposite.pm parsed');
}

done_testing();
