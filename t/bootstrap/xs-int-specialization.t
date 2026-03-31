# ABOUTME: Tests type-directed operator specialization for Int operands.
# ABOUTME: Validates that Int+Int emits SvIV/newSViv instead of SvNV/newSVnv.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::C;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Build IR: a class with a method that does integer arithmetic
# method add_one($self, $n) { return $n + 1; }
my $method = $factory->make('Constructor',
    class  => 'MethodDecl',
    name   => $factory->make('Constant', const_type => 'string', value => 'add_one'),
    params => [
        $factory->make('Constant', const_type => 'string', value => '$self'),
        $factory->make('Constant', const_type => 'string', value => '$n'),
    ],
    body   => [
        $factory->make('Constructor',
            class => 'ReturnStmt',
            value => $factory->make('Constructor',
                class => 'BinaryExpr',
                op    => $factory->make('Constant', const_type => 'string', value => '+'),
                left  => $factory->make('Constant', const_type => 'variable', value => '$n'),
                right => $factory->make('Constant', const_type => 'string', value => '1'),
            ),
        ),
    ],
    return_type => undef,
);

my $class_decl = $factory->make('Constructor',
    class  => 'ClassDecl',
    name   => $factory->make('Constant', const_type => 'string', value => 'Test::IntSpec'),
    parent => undef,
    body   => [$method],
);

my $program = $factory->make('Constructor',
    class      => 'Program',
    statements => [$class_decl],
);

my $target = Chalk::Bootstrap::Perl::Target::C->new(module_name => 'Test::IntSpec');
my $c_result = eval { $target->generate_c_files($program, undef, undef) };
ok(defined $c_result, 'generate_c_files succeeds') or do {
    diag "Error: $@";
    done_testing();
    exit;
};

# Find the .c file and look at the add_one function
my ($c_file) = grep { /\.c$/ } keys $c_result->{files}->%*;
my $c_code = $c_result->{files}{$c_file};

# The binary expression $n + 1 should use SvIV/newSViv when the right
# operand is an integer literal. Currently it uses SvNV/newSVnv.
# After specialization: newSViv(SvIV(n) + 1) instead of newSVnv(SvNV(n) + SvNV(...))

# Test: the + operation in add_one should use integer arithmetic
# when one operand is a known integer literal
like($c_code, qr/newSViv.*\+/, 'Int + literal: uses newSViv for addition result');
unlike($c_code, qr/SvNV.*\+.*SvNV/, 'Int + literal: does not use SvNV for both operands');

# --- Benchmark-style test: specialization count on realistic parse-loop IR ---
#
# Build an IR class with methods that mirror the Earley parse loop's integer
# arithmetic patterns: $pos + 1, $pos - $origin, $i + 1, etc.  Count how
# many newSViv vs newSVnv calls appear in the generated C.  A high ratio of
# newSViv confirms the specialization fires broadly on realistic code, not
# just the trivial toy example above.

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory2 = Chalk::Bootstrap::IR::NodeFactory->instance();

# Helper: make a Constant(variable) node
my sub var($name) {
    return $factory2->make('Constant', const_type => 'variable', value => $name);
}

# Helper: make a Constant(string) node (used for literals and operator names)
my sub lit($val) {
    return $factory2->make('Constant', const_type => 'string', value => $val);
}

# Helper: make a BinaryExpr node
my sub binop($op, $l, $r) {
    return $factory2->make('Constructor',
        class => 'BinaryExpr',
        op    => lit($op),
        left  => $l,
        right => $r,
    );
}

# Helper: make a ReturnStmt node
my sub ret($val) {
    return $factory2->make('Constructor',
        class => 'ReturnStmt',
        value => $val,
    );
}

# Helper: build a method returning a single expression.
# Last element of @params_and_expr is the expression; all others are param names.
my sub method_returning($name, @params_and_expr) {
    my $expr       = pop @params_and_expr;
    my @param_nodes = map { lit($_) } @params_and_expr;
    return $factory2->make('Constructor',
        class       => 'MethodDecl',
        name        => lit($name),
        params      => \@param_nodes,
        body        => [ ret($expr) ],
        return_type => undef,
    );
}

# Build methods that mirror Earley parse-loop integer arithmetic patterns.
# Each method returns an integer arithmetic expression.  At least one operand
# in each of patterns 1, 3, 4, 5, 7 is a known-integer literal so the
# specialiser should pick newSViv/SvIV for those.  Patterns 2 and 6 have no
# literal operand and should remain generic (newSVnv), giving a baseline.

# Pattern 1: $pos + 1  (position advance — literal RHS)
my $m1 = method_returning('advance_pos', '$self', '$pos',
    binop('+', var('$pos'), lit('1')),
);

# Pattern 2: $pos - $origin  (relative distance — no literal, expect newSVnv)
my $m2 = method_returning('relative_dist', '$self', '$pos', '$origin',
    binop('-', var('$pos'), var('$origin')),
);

# Pattern 3: $i + 1  (loop counter advance — literal RHS)
my $m3 = method_returning('next_index', '$self', '$i',
    binop('+', var('$i'), lit('1')),
);

# Pattern 4: $count - 1  (loop counter decrement — literal RHS)
my $m4 = method_returning('prev_count', '$self', '$count',
    binop('-', var('$count'), lit('1')),
);

# Pattern 5: $n * 2  (scaling by a literal)
my $m5 = method_returning('double_n', '$self', '$n',
    binop('*', var('$n'), lit('2')),
);

# Pattern 6: $pos + $offset  (both variables, no literal — expect newSVnv)
my $m6 = method_returning('offset_pos', '$self', '$pos', '$offset',
    binop('+', var('$pos'), var('$offset')),
);

# Pattern 7: ($pos + 1) - $origin  (chained: inner result is a newSViv
# sub-expression; codegen merges both into one newSViv wrapping the whole expr)
my $m7 = method_returning('chart_index', '$self', '$pos', '$origin',
    binop('-',
        binop('+', var('$pos'), lit('1')),
        var('$origin'),
    ),
);

my $class2 = $factory2->make('Constructor',
    class  => 'ClassDecl',
    name   => lit('Test::ParseLoop'),
    parent => undef,
    body   => [ $m1, $m2, $m3, $m4, $m5, $m6, $m7 ],
);

my $program2 = $factory2->make('Constructor',
    class      => 'Program',
    statements => [$class2],
);

my $target2  = Chalk::Bootstrap::Perl::Target::C->new(module_name => 'Test::ParseLoop');
my $result2  = eval { $target2->generate_c_files($program2, undef, undef) };
ok(defined $result2, 'parse-loop IR: generate_c_files succeeds') or do {
    diag "Error: $@";
    done_testing();
    exit;
};

my ($c_file2) = grep { /\.c$/ } keys $result2->{files}->%*;
my $c_code2   = $result2->{files}{$c_file2};

# Count specialised (newSViv) and generic (newSVnv) arithmetic calls.
# In return position Target::C emits bare newSViv(...)/newSVnv(...); as
# sub-expressions it emits sv_2mortal(newSViv(...)).  Both patterns count.
my @specialised = ($c_code2 =~ /\bnewSViv\b/g);
my @generic     = ($c_code2 =~ /\bnewSVnv\b/g);

my $spec_count    = scalar @specialised;
my $generic_count = scalar @generic;
my $total         = $spec_count + $generic_count;

diag "Integer-specialised newSViv calls : $spec_count";
diag "Generic              newSVnv calls : $generic_count";
diag "Total arithmetic calls            : $total";

# Patterns 1, 3, 4, 5, 7 each contribute a newSViv call (5 total).  Pattern 7
# chains two integer expressions but the codegen merges them into one newSViv
# wrapping the combined arithmetic, so the count stays at 5 — not 6.  Require
# exactly the count we can prove statically (≥ 5).
cmp_ok($spec_count, '>=', 5,
    'at least 5 arithmetic ops use integer specialisation (newSViv) on parse-loop patterns');

# Most parse-loop arithmetic involves literals or chains from literals, so
# specialised ops should outnumber the generic fallback.
cmp_ok($spec_count, '>', $generic_count,
    'integer-specialised ops outnumber generic newSVnv ops');

# Patterns 2 and 6 (both-variable, no literal) must remain generic, confirming
# the specialiser does not over-promote unknown-typed operands.
like($c_code2, qr/\bnewSVnv\b/,
    'non-literal-operand arithmetic correctly falls back to newSVnv');

done_testing();
