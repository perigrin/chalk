# ABOUTME: End-to-end validation: parse Phase 2 inputs, compare ConciseTree against B::Concise oracle.
# ABOUTME: Tests optimizer-stable cases (full comparison) and compile-time only cases.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_concise_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::ConciseTree;
use Chalk::Bootstrap::ConciseTree::Oracle;
use Chalk::Bootstrap::ConciseTree::Comparator;

# Check B::Concise is available
my $concise_check = `perl -MO=Concise,-exec -e '1' 2>&1`;
my $has_concise = ($concise_check =~ /enter/);

# Build the Perl grammar pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ConciseValidation/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::ConciseValidation::grammar();
    my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
    skip 'Concise parser not built', 1 unless defined $parser;

    my $oracle = Chalk::Bootstrap::ConciseTree::Oracle->new();
    my $comparator = Chalk::Bootstrap::ConciseTree::Comparator->new();

    # Helper to parse and extract ConciseTree from our parser
    my sub our_tree($source) {
        my $result = $parser->parse_value($source);
        return undef unless defined $result;
        my ($bool_val, $sem_val) = $result->@*;
        return undef unless $bool_val;
        return $sem_val->extract();
    }

    # Helper to get op names from a tree
    my sub op_names($tree) {
        return map { $_->name() } $tree->ops()->@*;
    }

    # ========================================================================
    # Optimizer-stable cases: full structural comparison against B::Concise
    # ========================================================================

    # Test sources omit `use 5.42.0;` to avoid version literal ambiguity.
    # B::Concise handles `use` at compile time (no runtime ops), but our
    # grammar can ambiguously parse the version as a numeric literal in
    # expression context. The oracle runs with -e which doesn't need `use`.
    my @stable_cases = (
        {
            name   => 'scalar int assignment',
            source => 'my $x = 42;',
        },
        {
            name   => 'scalar string assignment',
            source => 'my $x = "hello";',
        },
        {
            name   => 'scalar float assignment',
            source => 'my $x = 3.14;',
        },
        {
            name   => 'two scalar assignments',
            source => 'my $x = "hello"; my $y = 3.14;',
        },
        {
            name   => 'array assignment',
            source => 'my @arr = (1, 2);',
        },
        {
            name   => 'bare scalar declaration',
            source => 'my $x;',
        },
    );

    for my $case (@stable_cases) {
        my $ours = our_tree($case->{source});
        ok(defined $ours, "$case->{name}: our parser produces tree");

        SKIP: {
            skip "perl with B::Concise not available", 2 unless $has_concise;
            skip "our parse failed for $case->{name}", 2 unless defined $ours;

            my $theirs = $oracle->concise_for($case->{source});
            ok(defined $theirs, "$case->{name}: oracle produces tree");

            my $result = $comparator->compare($ours, $theirs);
            ok($result->{match}, "$case->{name}: structural match")
                or diag(
                    "Differences:\n",
                    join("\n", $result->{differences}->@*),
                    "\n\nOurs:\n", $ours->to_exec_string(),
                    "\n\nTheirs:\n", $theirs->to_exec_string(),
                );
        }
    }

    # ========================================================================
    # Compile-time only: verify minimal ops
    # ========================================================================

    # Test sources omit `use 5.42.0;` — version literal is ambiguously parsed
    # as numeric expressions by our grammar. `use utf8;` alone is compile-time.
    {
        my $ours = our_tree('use utf8;');
        ok(defined $ours, 'compile-time only: our parser produces tree');

        my @names = op_names($ours);
        is_deeply(\@names, [qw(enter stub leave)],
            'compile-time only: enter stub leave');

        SKIP: {
            skip "perl with B::Concise not available", 1 unless $has_concise;

            my $theirs = $oracle->concise_for('use utf8;');
            my $result = $comparator->compare($ours, $theirs);
            ok($result->{match}, 'compile-time only: structural match')
                or diag(
                    "Differences:\n",
                    join("\n", $result->{differences}->@*),
                    "\n\nOurs:\n", $ours->to_exec_string(),
                    "\n\nTheirs:\n", $theirs->to_exec_string(),
                );
        }
    }

    # ========================================================================
    # Optimizer-volatile: test generation only, skip oracle comparison
    # (Perl's optimizer removes const in void context)
    # ========================================================================

    {
        my $ours = our_tree('42;');
        ok(defined $ours, 'volatile: bare integer parses');
        ok((grep { $_->name() eq 'const' } $ours->ops()->@*),
            'volatile: bare integer has const (pre-optimization)');
    }

    {
        my $ours = our_tree('"hello";');
        ok(defined $ours, 'volatile: bare string parses');
        ok((grep { $_->name() eq 'const' } $ours->ops()->@*),
            'volatile: bare string has const (pre-optimization)');
    }
}

done_testing;
