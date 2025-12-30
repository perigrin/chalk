# ABOUTME: Test semantic action for RegexSubstitution (s///)
# ABOUTME: Verifies s/// patterns produce proper Constant IR nodes
use 5.42.0;
use Test::More;

# Set lib path at compile time using abs_path on $0 for worktree compatibility
BEGIN {
    use Cwd qw(abs_path);
    use File::Spec;
    my $test_file = abs_path($0);
    my ($vol, $dir, $file) = File::Spec->splitpath($test_file);
    my $lib_dir = abs_path(File::Spec->catdir($vol, $dir, '..', '..', 'lib'));
    unshift @INC, $lib_dir;
}

use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::ChalkIR;
use File::Spec;
use FindBin qw($RealBin);
use Scalar::Util qw(blessed);

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, '..', '..', 'grammar', 'chalk.bnf');
open my $grammar_fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Helper to parse expression and extract the return value's node
sub parse_expr {
    my ($code) = @_;
    my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $chalk_grammar);
    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        semiring => $semiring,
    );
    my $result = $parser->parse_string($code);

    return undef unless $result;

    # Extract the Stop node from the parse result
    my $stop;
    if ($result->can('context')) {
        my $ctx = $result->context;
        if ($ctx && $ctx->can('focus')) {
            $stop = $ctx->focus;
        }
    }

    return undef unless $stop && $stop->can('returns');

    # Get the return value from the first Return node
    my $returns = $stop->returns;
    return undef unless $returns && @$returns;

    my $ret = $returns->[0];
    return undef unless $ret && $ret->can('value');

    return $ret->value;
}

# Test 1: Simple s/// produces Constant node
{
    my $result = parse_expr('s/foo/bar/');

    ok(defined $result, 's/foo/bar/ parses successfully');
    isa_ok($result, 'Chalk::IR::Node::Constant', 's/// produces Constant node');
}

# Test 2: s/// with pattern and replacement
{
    my $result = parse_expr('s/hello/world/');

    ok($result->can('value'), 'result has value accessor');
    like($result->value, qr/s\/hello\/world\//, 's/// value contains pattern and replacement');
}

# Test 3: s/// with flags
{
    my $result = parse_expr('s/foo/bar/gi');

    ok(defined $result, 's/// with flags parses successfully');
    like($result->value, qr/gi$/, 's/// value contains flags');
}

# Test 4: s/// type is Regex
{
    my $result = parse_expr('s/a/b/');

    isa_ok($result->type, 'Chalk::Grammar::Chalk::Type::Regex', 's/// has Regex type');
}

# Test 5: s/// with empty replacement
{
    my $result = parse_expr('s/remove//');

    ok(defined $result, 's/// with empty replacement parses successfully');
    like($result->value, qr/s\/remove\/\//, 's/// value has empty replacement');
}

done_testing();
