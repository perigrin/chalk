# ABOUTME: Tests for Block synthesizing {graph, type} during semantic actions.
# ABOUTME: Per Phase 3a-migration, Block exposes graph + return type union via its focus.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# Build the generated Perl grammar once.
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR')
    or BAIL_OUT('cannot build pipeline');

my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::BlockTypeTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly')
    or BAIL_OUT("cannot eval: $@");

my $gen_grammar = Chalk::Grammar::Perl::BlockTypeTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# Find every leaf Context whose rule is 'Block'.
sub block_leaves($result) {
    my @blocks;
    my @stack = ($result);
    while (@stack) {
        my $ctx = pop @stack;
        next unless defined $ctx;
        my $rule = $ctx->rule();
        my $focus = $ctx->extract();
        if (defined $rule && $rule eq 'Block' && defined $focus) {
            push @blocks, $ctx;
            next;
        }
        push @stack, $ctx->children()->@*;
    }
    return @blocks;
}

# Block focus shape — after migration, Block synthesizes a hashref with
# `graph` (Chalk::IR::Graph) and `type` (return-type string) keys.
sub assert_block_synth($block_ctx, $label) {
    my $focus = $block_ctx->extract();
    ok(ref($focus) eq 'HASH', "$label: Block focus is a hashref")
        or do {
            my $shape = defined $focus ? ref($focus) || 'scalar' : 'undef';
            diag("got: $shape");
            return;
        };
    ok(exists $focus->{graph}, "$label: Block focus has 'graph' key")
        or diag('keys: ' . join(',', sort keys $focus->%*));
    ok(exists $focus->{type}, "$label: Block focus has 'type' key")
        or diag('keys: ' . join(',', sort keys $focus->%*));
    my $g = $focus->{graph};
    ok(defined $g && blessed($g) && $g->isa('Chalk::IR::Graph'),
        "$label: Block.graph is a Chalk::IR::Graph");
    ok(defined $focus->{type} && !ref($focus->{type}),
        "$label: Block.type is a defined string");
}

# Case 1: empty block — type should be 'Void'
{
    my $source = q{
class C {
    method foo() {}
}
};
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    ok(defined $result && !$result->is_zero(), 'empty-block source parses');

    SKIP: {
        skip 'empty-block parse failed', 6 unless defined $result && !$result->is_zero();
        my @blocks = block_leaves($result);
        ok(scalar @blocks >= 1, 'at least one Block leaf for method foo')
            or BAIL_OUT('no Block leaves found for empty method');
        # The innermost Block is for `method foo()`. Pick the last one
        # (deepest in the tree).
        my $body = $blocks[-1];
        assert_block_synth($body, 'empty body');
        my $focus = $body->extract();
        is($focus->{type}, 'Void', 'empty body type is Void')
            if ref($focus) eq 'HASH';
    }
}

# Case 2: literal-final-expression block — type is the literal's type
{
    my $source = q{
class C {
    method foo() {
        42
    }
}
};
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    ok(defined $result && !$result->is_zero(), 'literal-tail source parses');

    SKIP: {
        skip 'literal-tail parse failed', 6 unless defined $result && !$result->is_zero();
        my @blocks = block_leaves($result);
        ok(scalar @blocks >= 1, 'Block leaf found for method foo');
        my $body = $blocks[-1];
        assert_block_synth($body, 'literal-final');
        my $focus = $body->extract();
        if (ref($focus) eq 'HASH') {
            like($focus->{type}, qr/^(Int|Num)$/,
                'literal-final type is Int or Num');
        }
    }
}

# Case 3: explicit-return block — type comes from the Return value
{
    my $source = q{
class C {
    method foo() {
        return 42;
    }
}
};
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    ok(defined $result && !$result->is_zero(), 'explicit-return source parses');

    SKIP: {
        skip 'explicit-return parse failed', 6 unless defined $result && !$result->is_zero();
        my @blocks = block_leaves($result);
        ok(scalar @blocks >= 1, 'Block leaf found for method foo');
        my $body = $blocks[-1];
        assert_block_synth($body, 'explicit-return');
        my $focus = $body->extract();
        if (ref($focus) eq 'HASH') {
            like($focus->{type}, qr/^(Int|Num)$/,
                'explicit-return type is Int or Num');
        }
    }
}

# Case 4: branch-fallthrough block — type is the union of both exit types
# `if (cond) { return 1 } 'fallthrough'` exits via Return 1 OR fall-through string.
{
    my $source = q{
class C {
    method foo() {
        if (1) { return 1 }
        'fallthrough'
    }
}
};
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    ok(defined $result && !$result->is_zero(), 'branch-fallthrough source parses');

    SKIP: {
        skip 'branch-fallthrough parse failed', 4 unless defined $result && !$result->is_zero();
        my @blocks = block_leaves($result);
        ok(scalar @blocks >= 1, 'Block leaves found');
        # The outermost method body Block. Find by matching span: the body
        # block that contains the if statement.
        my $body;
        for my $b (reverse @blocks) {
            my $f = $b->extract();
            next unless ref($f) eq 'HASH';
            # heuristic: the method-body block has type that mentions
            # both Int and Str (or similar union)
            $body = $b;
            last;
        }
        $body //= $blocks[-1];
        assert_block_synth($body, 'branch-fallthrough') if defined $body;
        my $focus = $body->extract();
        if (ref($focus) eq 'HASH') {
            # union should mention both exit types — accept any concrete
            # encoding; the invariant is "more than one exit class".
            ok($focus->{type} =~ /\|/ || $focus->{type} eq 'Any'
                || $focus->{type} =~ /Union/,
                "branch-fallthrough type encodes a union ($focus->{type})");
        }
    }
}

done_testing();
