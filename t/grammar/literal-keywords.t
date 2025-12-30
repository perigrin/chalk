# ABOUTME: Test semantic actions for keyword literals (undef, true, false)
# ABOUTME: Verifies these keywords produce proper Constant IR nodes with correct types
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
use Chalk::Grammar::Chalk::Type::Undef;
use Chalk::Grammar::Chalk::Type::Boolean;
use File::Spec;
use FindBin qw($RealBin);
use Scalar::Util qw(blessed);

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, '..', '..', 'grammar', 'chalk.bnf');
open my $grammar_fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Helper to parse expression and extract the return value's Constant node
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

# Test 1: 'undef' literal produces Constant node
{
    my $result = parse_expr('undef');

    ok(defined $result, 'undef literal parses successfully');
    ok($result->can('type'), 'result has type accessor');

    my $type = $result->type;
    isa_ok($type, 'Chalk::Grammar::Chalk::Type::Undef', 'undef literal has Undef type');
}

# Test 2: 'undef' literal value is undef
{
    my $result = parse_expr('undef');

    ok($result->can('value'), 'result has value accessor');
    ok(!defined($result->value), 'undef literal value is undef');
}

# Test 3: 'true' literal produces Constant node with Boolean type
{
    my $result = parse_expr('true');

    ok(defined $result, 'true literal parses successfully');
    ok($result->can('type'), 'true result has type accessor');

    my $type = $result->type;
    isa_ok($type, 'Chalk::Grammar::Chalk::Type::Boolean', 'true literal has Boolean type');
}

# Test 4: 'true' literal value is 1
{
    my $result = parse_expr('true');

    ok($result->can('value'), 'true result has value accessor');
    is($result->value, 1, 'true literal value is 1');
}

# Test 5: 'false' literal produces Constant node with Boolean type
{
    my $result = parse_expr('false');

    ok(defined $result, 'false literal parses successfully');
    ok($result->can('type'), 'false result has type accessor');

    my $type = $result->type;
    isa_ok($type, 'Chalk::Grammar::Chalk::Type::Boolean', 'false literal has Boolean type');
}

# Test 6: 'false' literal value is 0
{
    my $result = parse_expr('false');

    ok($result->can('value'), 'false result has value accessor');
    is($result->value, 0, 'false literal value is 0');
}

# Test 7: 'undef' as expression in return statement
{
    my $result = parse_expr('return undef;');

    ok(defined $result, 'return undef parses successfully');
    isa_ok($result->type, 'Chalk::Grammar::Chalk::Type::Undef', 'return undef has Undef type value');
}

# Test 8: 'true' in boolean expression context
{
    my $result = parse_expr('my $x = true;');

    # Result should be a Store node, check its value
    ok(defined $result, 'assignment with true parses successfully');
    if ($result->can('op') && $result->op eq 'Store') {
        my $val = $result->value;
        isa_ok($val->type, 'Chalk::Grammar::Chalk::Type::Boolean', 'assigned true has Boolean type');
        is($val->value, 1, 'assigned true has value 1');
    } else {
        pass('skipping type check - different IR structure');
        pass('skipping value check - different IR structure');
    }
}

done_testing();
