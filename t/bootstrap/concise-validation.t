# ABOUTME: End-to-end validation: parse Perl inputs, compare ConciseTree against B::Concise oracle.
# ABOUTME: Tests Phase 2-5 (declarations, class/sub/method, expressions, control flow) stable + structural cases.
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
    # Result tuple: [0]=Boolean, [1]=Precedence, [2]=TypeInference, [3]=Structural, [4]=SemanticAction
    my sub our_tree($source) {
        my $result = $parser->parse_value($source);
        return undef unless defined $result;
        my $bool_val = $result->[0];
        my $sem_val = $result->[4];
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
        {
            name   => 'regex match assignment',
            source => 'my $x = /foo/;',
        },
        {
            name   => 'hash with fat comma',
            source => 'my %h = (a => 1, b => 2);',
        },
        # Phase 4: Expressions
        # Binary arithmetic with variable operands (avoids constant folding + unary ambiguity)
        {
            name   => 'multiplication',
            source => 'my $a = 1; my $b = 2; my $c = $a * $b;',
        },
        {
            name   => 'exponentiation',
            source => 'my $a = 1; my $b = 2; my $c = $a ** $b;',
        },
        {
            name   => 'modulus',
            source => 'my $a = 1; my $b = 2; my $c = $a % $b;',
        },
        # Comparison
        {
            name   => 'numeric equality',
            source => 'my $a = 1; my $b = 2; my $c = $a == $b;',
        },
        {
            name   => 'string equality',
            source => 'my $a = "x"; my $b = "y"; my $c = $a eq $b;',
        },
        # Unary
        {
            name   => 'negation',
            source => 'my $a = 1; my $b = -$a;',
        },
        {
            name   => 'logical not',
            source => 'my $a = 1; my $b = not $a;',
        },
        # PostfixIncDec (value context — void context optimizes to preinc)
        {
            name   => 'postfix increment',
            source => 'my $a = 1; my $b = $a++;',
        },
        # Chained binary expressions (Precedence semiring disambiguates)
        {
            name   => 'chained pow+modulo',
            source => 'my $a = 2; my $b = 3; my $c = 5; my $d = $a ** $b % $c;',
        },
        # Compound assignment
        {
            name   => 'compound add-assign',
            source => 'my $a = 1; $a += 2;',
        },
        # Previously ambiguous operators (resolved by TypeInference)
        {
            name   => 'binary addition',
            source => 'my $a = 1; my $b = 2; my $c = $a + $b;',
        },
        {
            name   => 'binary subtraction',
            source => 'my $a = 1; my $b = 2; my $c = $a - $b;',
        },
        {
            name   => 'chained add-subtract',
            source => 'my $a = 1; my $b = 2; my $c = $a + $b - 1;',
        },
        # Note: defined-or (//) not oracle-stable because branching ops
        # (dor, and, or, ||, &&) have different exec order in B::Concise
        # (branch-between-operands) vs our tree (flat left-right-op).

        # Phase 5: Control flow — oracle-stable cases
        {
            name   => 'simple if',
            source => 'my $x = 1; if ($x) { my $y = 2; }',
        },
        {
            name   => 'unless',
            source => 'my $x = 1; unless ($x) { my $y = 2; }',
        },
        {
            name   => 'if-else',
            source => 'my $x = 1; if ($x) { my $y = 2; } else { my $z = 3; }',
        },
        {
            name   => 'if-elsif-else',
            source => 'my $x = 1; if ($x > 0) { my $y = 1; } elsif ($x < 0) { my $y = 2; } else { my $y = 3; }',
        },
        {
            name   => 'while loop',
            source => 'my $x = 1; while ($x > 0) { my $y = 2; }',
        },
        {
            name   => 'until loop',
            source => 'my $x = 1; until ($x > 0) { my $y = 1; }',
        },
        {
            name   => 'foreach loop',
            source => 'my @a = (1, 2); for my $i (@a) { my $x = $i; }',
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

    # ========================================================================
    # Phase 3: Class definitions, subroutines, methods
    # ========================================================================

    # --- Named sub: compile-time only (oracle-stable) ---
    # B::Concise produces: enter, stub, leave
    # Our parser should produce the same when SubroutineDefinition parse wins.
    {
        my $ours = our_tree('sub foo { }');
        ok(defined $ours, 'named sub: our parser produces tree');

        my @names = op_names($ours);
        is_deeply(\@names, [qw(enter stub leave)],
            'named sub: enter stub leave');

        SKIP: {
            skip "perl with B::Concise not available", 2 unless $has_concise;

            my $theirs = $oracle->concise_for('sub foo { }');
            ok(defined $theirs, 'named sub: oracle produces tree');

            my $result = $comparator->compare($ours, $theirs);
            ok($result->{match}, 'named sub: structural match')
                or diag(
                    "Differences:\n",
                    join("\n", $result->{differences}->@*),
                    "\n\nOurs:\n", $ours->to_exec_string(),
                    "\n\nTheirs:\n", $theirs->to_exec_string(),
                );
        }
    }

    # --- Named sub with return value: compile-time only (oracle-stable) ---
    # TypeInference rejects 'sub' as Identifier, so SubroutineDefinition
    # always wins. B::Concise: enter, stub, leave (body in sub's own optree).
    {
        my $ours = our_tree('sub foo { return 42; }');
        ok(defined $ours, 'named sub with body: our parser produces tree');

        my @names = op_names($ours);
        is_deeply(\@names, [qw(enter stub leave)],
            'named sub with body: enter stub leave');

        SKIP: {
            skip "perl with B::Concise not available", 2 unless $has_concise;

            my $theirs = $oracle->concise_for('sub foo { return 42; }');
            ok(defined $theirs, 'named sub with body: oracle produces tree');

            my $result = $comparator->compare($ours, $theirs);
            ok($result->{match}, 'named sub with body: structural match')
                or diag(
                    "Ours:\n", $ours->to_exec_string(),
                    "\n\nTheirs:\n", $theirs->to_exec_string(),
                );
        }
    }

    # --- Named sub with signature: compile-time only (oracle-stable) ---
    {
        my $ours = our_tree('sub foo($x, $y) { return $x + $y; }');
        ok(defined $ours, 'named sub with sig: our parser produces tree');

        my @names = op_names($ours);
        is_deeply(\@names, [qw(enter stub leave)],
            'named sub with sig: enter stub leave');

        SKIP: {
            skip "perl with B::Concise not available", 2 unless $has_concise;

            my $theirs = $oracle->concise_for('sub foo($x, $y) { return $x + $y; }');
            ok(defined $theirs, 'named sub with sig: oracle produces tree');

            my $result = $comparator->compare($ours, $theirs);
            ok($result->{match}, 'named sub with sig: structural match')
                or diag(
                    "Ours:\n", $ours->to_exec_string(),
                    "\n\nTheirs:\n", $theirs->to_exec_string(),
                );
        }
    }

    # --- Anonymous sub: oracle-stable ---
    # TypeInference rejects 'sub' as Identifier, so AnonymousSub action
    # always fires. B::Concise: enter, nextstate, anoncode, padsv_store, leave.
    {
        my $ours = our_tree('my $x = sub { return 42; };');
        ok(defined $ours, 'anonymous sub: our parser produces tree');

        my @names = op_names($ours);
        is_deeply(\@names, [qw(enter nextstate anoncode padsv_store leave)],
            'anonymous sub: correct op sequence');

        SKIP: {
            skip "perl with B::Concise not available", 2 unless $has_concise;

            my $theirs = $oracle->concise_for('my $x = sub { return 42; };');
            ok(defined $theirs, 'anonymous sub: oracle produces tree');

            my $result = $comparator->compare($ours, $theirs);
            ok($result->{match}, 'anonymous sub: structural match')
                or diag(
                    "Ours:\n", $ours->to_exec_string(),
                    "\n\nTheirs:\n", $theirs->to_exec_string(),
                );
        }
    }

    # --- Multiple subs: compile-time only ---
    {
        my $ours = our_tree('sub foo { } sub bar { }');
        ok(defined $ours, 'multiple subs: our parser produces tree');

        my @names = op_names($ours);
        is_deeply(\@names, [qw(enter stub leave)],
            'multiple subs: enter stub leave');
    }

    # --- Sub then variable declaration ---
    {
        my $ours = our_tree('sub foo { } my $x = 1;');
        ok(defined $ours, 'sub + var decl: our parser produces tree');

        my @names = op_names($ours);
        # The sub is compile-time, the var decl produces runtime ops
        ok((grep { $_ =~ /^padsv/ } @names),
            'sub + var decl: variable declaration produces padsv op');
    }

    # --- Bare block with contents ---
    {
        my $ours = our_tree('{ my $x = 42; }');
        ok(defined $ours, 'bare block: our parser produces tree');

        my @names = op_names($ours);
        # Block contents should pass through to program level
        ok((grep { $_ =~ /^padsv/ } @names),
            'bare block: child ops pass through');
    }

    # ========================================================================
    # Phase 5: Control flow — structural ordering verification
    # Oracle comparison is done via the stable_cases array above (7 cases).
    # Additional ordering verification below uses index-based checks for
    # cases that exercise specific op-ordering patterns.
    # ========================================================================

    # Helper to find first index of an op by name, optionally starting from offset
    my sub first_op_index($name, $ops_ref, $from = 0) {
        for my $i ($from .. $#$ops_ref) {
            return $i if $ops_ref->[$i]->name() eq $name;
        }
        return -1;
    }

    # --- Simple if: condition → and → body ---
    {
        my $ours = our_tree('my $x = 1; if ($x == 1) { my $y = 2; }');
        ok(defined $ours, 'if ordering: our parser produces tree');

        my @ops = $ours->ops()->@*;
        my $eq_idx = first_op_index('eq', \@ops);
        my $and_idx = first_op_index('and', \@ops);
        ok($eq_idx >= 0 && $and_idx >= 0, 'if ordering: has eq and and ops');
        ok($eq_idx < $and_idx, 'if ordering: condition eq before branch and')
            or diag("Ours:\n", $ours->to_exec_string());
    }

    # --- Unless: condition → or → body ---
    {
        my $ours = our_tree('my $x = 0; unless ($x == 0) { my $y = 1; }');
        ok(defined $ours, 'unless ordering: our parser produces tree');

        my @ops = $ours->ops()->@*;
        my $eq_idx = first_op_index('eq', \@ops);
        my $or_idx = first_op_index('or', \@ops);
        ok($eq_idx >= 0 && $or_idx >= 0, 'unless ordering: has eq and or ops');
        ok($eq_idx < $or_idx, 'unless ordering: condition eq before branch or')
            or diag("Ours:\n", $ours->to_exec_string());
    }

    # --- If-else: condition → cond_expr → true body / else body ---
    {
        my $ours = our_tree('my $x = 1; my $y = 2; my $z = 3; if ($x == 1) { $y; } else { $z; }');
        ok(defined $ours, 'if-else ordering: our parser produces tree');

        my @ops = $ours->ops()->@*;
        my $eq_idx = first_op_index('eq', \@ops);
        my $cond_idx = first_op_index('cond_expr', \@ops);
        ok($eq_idx >= 0 && $cond_idx >= 0, 'if-else ordering: has eq and cond_expr');
        ok($eq_idx < $cond_idx, 'if-else ordering: condition eq before cond_expr')
            or diag("Ours:\n", $ours->to_exec_string());
    }

    # --- If-elsif-else: two cond_expr ops in correct order ---
    {
        my $ours = our_tree('my $a = 1; my $b = 2; my $c = 3; if ($a == 1) { $b; } elsif ($b == 2) { $c; } else { $a; }');
        ok(defined $ours, 'if-elsif-else ordering: our parser produces tree');

        my @ops = $ours->ops()->@*;
        my @cond_exprs;
        for my $i (0 .. $#ops) {
            push @cond_exprs, $i if $ops[$i]->name() eq 'cond_expr';
        }
        ok(scalar @cond_exprs >= 2, 'if-elsif-else ordering: has at least 2 cond_expr ops')
            or diag("cond_expr count: ", scalar @cond_exprs,
                    "\nOurs:\n", $ours->to_exec_string());

        SKIP: {
            skip 'need 2 cond_exprs for order check', 1 unless scalar @cond_exprs >= 2;
            # Each condition's eq should precede its cond_expr
            my $eq1_idx = first_op_index('eq', \@ops);
            ok($eq1_idx >= 0 && $eq1_idx < $cond_exprs[0],
                'if-elsif-else ordering: first condition before first cond_expr')
                or diag("eq=$eq1_idx, cond_expr=$cond_exprs[0]");
        }
    }

    # --- While: enterloop → condition → and → body → unstack → leaveloop ---
    {
        my $ours = our_tree('my $x = 1; while ($x > 0) { my $y = 2; }');
        ok(defined $ours, 'while ordering: our parser produces tree');

        my @ops = $ours->ops()->@*;
        my $enter_idx = first_op_index('enterloop', \@ops);
        my $gt_idx = first_op_index('gt', \@ops);
        my $and_idx = first_op_index('and', \@ops);
        my $unstack_idx = first_op_index('unstack', \@ops);
        my $leave_idx = first_op_index('leaveloop', \@ops);

        ok($enter_idx >= 0, 'while ordering: has enterloop');
        ok($enter_idx < $gt_idx, 'while ordering: enterloop before condition gt')
            or diag("Ours:\n", $ours->to_exec_string());
        ok($gt_idx < $and_idx, 'while ordering: condition gt before branch and')
            or diag("Ours:\n", $ours->to_exec_string());
        ok($and_idx < $unstack_idx, 'while ordering: branch and before unstack')
            or diag("Ours:\n", $ours->to_exec_string());
        ok($unstack_idx < $leave_idx, 'while ordering: unstack before leaveloop')
            or diag("Ours:\n", $ours->to_exec_string());
    }

    # --- Until: enterloop → condition → or → body → unstack → leaveloop ---
    {
        my $ours = our_tree('my $x = 0; until ($x > 0) { my $y = 1; }');
        ok(defined $ours, 'until ordering: our parser produces tree');

        my @ops = $ours->ops()->@*;
        my $enter_idx = first_op_index('enterloop', \@ops);
        my $gt_idx = first_op_index('gt', \@ops);
        my $or_idx = first_op_index('or', \@ops);

        ok($enter_idx >= 0 && $gt_idx >= 0 && $or_idx >= 0,
            'until ordering: has enterloop, gt, and or');
        ok($enter_idx < $gt_idx, 'until ordering: enterloop before condition gt')
            or diag("Ours:\n", $ours->to_exec_string());
        ok($gt_idx < $or_idx, 'until ordering: condition gt before branch or')
            or diag("Ours:\n", $ours->to_exec_string());
    }

    # --- Foreach: list → enteriter → iter → and → body → unstack → leaveloop ---
    {
        my $ours = our_tree('my @list = (1, 2, 3); for my $i (@list) { $i; }');
        ok(defined $ours, 'foreach ordering: our parser produces tree');

        my @ops = $ours->ops()->@*;
        # Find the second padav (list ref, not declaration)
        my $first_padav = first_op_index('padav', \@ops);
        my $list_padav = first_op_index('padav', \@ops, $first_padav + 1);
        my $enteriter_idx = first_op_index('enteriter', \@ops);
        my $iter_idx = first_op_index('iter', \@ops);
        my $and_idx = first_op_index('and', \@ops);
        my $unstack_idx = first_op_index('unstack', \@ops);
        my $leaveloop_idx = first_op_index('leaveloop', \@ops);

        ok($list_padav >= 0, 'foreach ordering: has list padav');
        ok($list_padav < $enteriter_idx, 'foreach ordering: list before enteriter')
            or diag("Ours:\n", $ours->to_exec_string());
        ok($enteriter_idx < $iter_idx, 'foreach ordering: enteriter before iter')
            or diag("Ours:\n", $ours->to_exec_string());
        ok($iter_idx < $and_idx, 'foreach ordering: iter before and')
            or diag("Ours:\n", $ours->to_exec_string());
        ok($and_idx < $unstack_idx, 'foreach ordering: and before unstack')
            or diag("Ours:\n", $ours->to_exec_string());
        ok($unstack_idx < $leaveloop_idx, 'foreach ordering: unstack before leaveloop')
            or diag("Ours:\n", $ours->to_exec_string());
    }
}

done_testing;
