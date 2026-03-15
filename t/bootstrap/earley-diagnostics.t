# ABOUTME: Tests for Earley parser diagnostic output on parse failure.
# ABOUTME: Verifies Rust-style error messages with line:col, source context, and expected tokens.
use 5.42.0;
use utf8;
use lib 'lib';
use lib 't/bootstrap/lib';

use Test::More;

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Semiring::Boolean;

# Set up grammar once for all tests
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
eval "$generated; 1" or die "Grammar eval failed: $@";
no strict 'refs';
my $grammar = "Chalk::Grammar::BNF::Generated"->can('grammar')->();
die "Grammar not defined" unless defined $grammar;

sub make_parser() {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($grammar, start => 'Program');
    $parser->semiring->reset_cache();
    return $parser;
}

# Test 1: Successful parse emits no warning
{
    my $parser = make_parser();
    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= $_[0] };
    my $result = $parser->parse_value("use 5.42.0;\n");
    ok(defined $result, 'valid input parses successfully');
    is($warnings, '', 'no warnings emitted on successful parse');
}

# Test 2: Failed parse emits diagnostic warning
{
    my $parser = make_parser();
    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= $_[0] };
    my $result = $parser->parse_value("@@@ not valid perl @@@\n");
    ok(!defined $result, 'invalid input returns undef');
    like($warnings, qr/error: parse failed/, 'diagnostic warning emitted on failure');
}

# Test 3: Diagnostic contains line and column
{
    my $parser = make_parser();
    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= $_[0] };
    # Line 1 is valid, line 2 is not
    my $result = $parser->parse_value("use 5.42.0;\n@@@ bad @@@\n");
    ok(!defined $result, 'partial input returns undef');
    like($warnings, qr/line \d+, column \d+/, 'diagnostic contains line and column');
}

# Test 4: Diagnostic contains expected tokens
{
    my $parser = make_parser();
    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= $_[0] };
    $parser->parse_value("@@@ bad @@@\n");
    like($warnings, qr/expected:/, 'diagnostic lists expected tokens');
}

# Test 5: Diagnostic contains source context lines
{
    my $parser = make_parser();
    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= $_[0] };
    $parser->parse_value("use 5.42.0;\nuse utf8;\n@@@ bad @@@\nmy \$x = 1;\n");
    # Should show numbered source lines around the failure
    like($warnings, qr/\d+ \|/, 'diagnostic contains numbered source lines');
}

# Test 6: File parameter appears in diagnostic
{
    my $parser = make_parser();
    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= $_[0] };
    $parser->parse_value("@@@ bad @@@\n", 'test/example.pm');
    like($warnings, qr{test/example\.pm}, 'file path appears in diagnostic');
}

# Test 7: Default <input> when no file parameter
{
    my $parser = make_parser();
    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= $_[0] };
    $parser->parse_value("@@@ bad @@@\n");
    like($warnings, qr{<input>}, 'default <input> shown when no file given');
}

# Test 8: Diagnostic shows progress (bytes parsed of total)
{
    my $parser = make_parser();
    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= $_[0] };
    $parser->parse_value("@@@ bad @@@\n");
    like($warnings, qr/\d+ of \d+ bytes/, 'diagnostic shows progress in bytes');
}

done_testing();
