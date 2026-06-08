# ABOUTME: P-corner driver for typed SoN Return nodes: lowers to a Perl expression, runs under perl.
# ABOUTME: Parallel to LLVMDriver but targets Perl text emission for the computation slice.
package Chalk::CodeGen::Harness::ReturnNodePerlDriver;

use 5.42.0;
use utf8;

use Carp         qw(croak);
use File::Temp   qw(tempfile);
use Scalar::Util qw(blessed);

use Chalk::CodeGen::Harness::BehaviorRecord;
use Chalk::CodeGen::Harness::TypeTag;

# The path to the perl 5.42.0 binary used as the oracle / P runner.
my $PERL_BIN = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";

# run($return_node, \%opts) -> ($P, \%emission_meta)
#
# Lowers a typed SoN Return node to a Perl expression, wraps it in a minimal
# runnable snippet, and runs under perl 5.42.  Captures stdout as the P return
# value.
#
# This driver covers the computation slice (Int/Num arithmetic, VarDecl/Assign,
# PadAccess, Coerce, TernaryExpr/NumGt) — the same idioms as LLVM corner.
# It does NOT require a Chalk::MOP; it works directly from the Return node.
#
# emission_meta keys:
#   emitted_for_every_construct   bool
#   marked_unsupported            bool
#   perl_snippet                  str   — the generated Perl code (for inspection)
sub run {
    my ( $class, $return_node, $opts ) = @_;
    $opts //= {};

    croak "ReturnNodePerlDriver->run: return_node must be defined"
        unless defined $return_node;

    # ---- Step 1: emit Perl text from the typed Return node ----
    my ( $perl_text, $emit_error );
    eval {
        $perl_text = _emit_return_as_perl($return_node);
    };
    if ($@) {
        $emit_error = $@;
    }

    if ( defined $emit_error ) {
        my $P = Chalk::CodeGen::Harness::BehaviorRecord->new(
            return_values     => [],
            wantarray_context => $opts->{context} // 'scalar',
            stdout            => '',
            stderr            => $emit_error,
            exception         => {
                kind    => 'string',
                class   => undef,
                message => "Perl emission GAP: $emit_error",
            },
            object_state => {},
        );
        my $emission_meta = {
            emitted_for_every_construct => 0,
            marked_unsupported          => 1,
            perl_snippet                => undef,
        };
        return ( $P, $emission_meta );
    }

    # Wrap in a minimal runnable snippet: print the result via printf.
    # Use the same format semantics as LLVM (integer or float).
    my $snippet = "use 5.42.0; use utf8;\n" . $perl_text . "\n";

    # ---- Step 2: run under perl ----
    my ( $stdout, $exit ) = _run_perl($snippet);

    chomp( my $output = $stdout // '' );

    my $P = Chalk::CodeGen::Harness::BehaviorRecord->new(
        return_values     => [ length($output) ? $output : () ],
        wantarray_context => $opts->{context} // 'scalar',
        stdout            => '',
        stderr            => ( $exit != 0 ? $stdout : '' ),
        exception         => ( $exit != 0
            ? { kind => 'string', class => undef, message => "perl exited $exit: $stdout" }
            : undef ),
        object_state => {},
    );

    my $emission_meta = {
        emitted_for_every_construct => ( $exit == 0 ? 1 : 0 ),
        marked_unsupported          => 0,
        perl_snippet                => $snippet,
    };

    return ( $P, $emission_meta );
}

# ---------------------------------------------------------------------------
# Perl emission from typed Return node
# ---------------------------------------------------------------------------

# _emit_return_as_perl($return_node) -> $perl_snippet_string
#
# Emits a Perl script fragment that computes the same value as the Return node
# and prints it (so the script's stdout is the behavior record).
#
# Covers the computation slice: Int/Num constants, Add/Subtract/Multiply/Divide/
# Modulo, Coerce, VarDecl/PadAccess/Assign/CompoundAssign (straight-line only),
# TernaryExpr with Bool condition.
sub _emit_return_as_perl {
    my ($return_node) = @_;

    # Process the control chain first (VarDecl, Assign, CompoundAssign).
    my @ctrl_stmts;
    my %var_table;    # VarDecl id -> Perl variable name
    {
        my @chain;
        my $ctrl = $return_node->can('control_in') ? $return_node->control_in : undef;
        while ( defined $ctrl ) {
            push @chain, $ctrl;
            $ctrl = $ctrl->can('control_in') ? $ctrl->control_in : undef;
        }
        for my $node ( reverse @chain ) {
            my $stmt = _emit_ctrl_stmt( $node, \%var_table );
            push @ctrl_stmts, $stmt if defined $stmt;
        }
    }

    # Emit the value sub-graph.
    my $value_node = $return_node->inputs->[0];
    my $expr       = _emit_expr( $value_node, \%var_table );

    # Emit type-tagged output: both P and L corners emit tags so Bool is
    # distinguishable from its Str coercion in the three-corner Comparator.
    # The tagging logic is the canonical rule from Chalk::CodeGen::Harness::TypeTag.
    my $tag_fragment = Chalk::CodeGen::Harness::TypeTag::oracle_perl_fragment();
    # Wrap: assign the expression to $_result (the variable the fragment expects),
    # then let the fragment print the tag.
    my $print_stmt = "{ my \$_result = $expr;\n$tag_fragment}";

    return join( "\n", @ctrl_stmts ) . ( @ctrl_stmts ? "\n" : '' ) . $print_stmt;
}

# _emit_ctrl_stmt($node, \%var_table) -> $stmt_string or undef
# Emits a Perl statement for a control-chain node (VarDecl/Assign/CompoundAssign).
sub _emit_ctrl_stmt {
    my ( $node, $var_table ) = @_;
    my $op = $node->operation;

    if ( $op eq 'VarDecl' ) {
        # inputs[0] = name Constant, inputs[1] = init value (may be undef)
        my $name_node = $node->inputs->[0];
        my $init_node = $node->inputs->[1];

        # Generate a safe Perl variable name from the node id.
        my $perl_var = '$_v' . $node->id;
        $var_table->{ $node->id } = $perl_var;

        if ( defined $init_node ) {
            my $init_expr = _emit_expr( $init_node, $var_table );
            return "my $perl_var = $init_expr;";
        }
        else {
            return "my $perl_var;";
        }
    }
    elsif ( $op eq 'Assign' || $op eq 'CompoundAssign' ) {
        # inputs[0] = lhs (PadAccess), inputs[1] = rhs
        my $lhs    = $node->inputs->[0];
        my $rhs    = $node->inputs->[1];
        my $lhs_var = _resolve_padaccess( $lhs, $var_table );
        my $rhs_expr = _emit_expr( $rhs, $var_table );

        if ( $op eq 'CompoundAssign' ) {
            my $compound_op = $node->can('op') ? $node->op : '+=';
            return "$lhs_var $compound_op $rhs_expr;";
        }
        else {
            return "$lhs_var = $rhs_expr;";
        }
    }

    return undef;
}

# _emit_expr($node, \%var_table) -> $perl_expression_string
# Recursively emits a Perl expression for a value-producing node.
sub _emit_expr {
    my ( $node, $var_table ) = @_;
    return 'undef' unless defined $node;

    my $op = $node->operation;

    if ( $op eq 'Constant' ) {
        my $val  = $node->value;
        my $repr = $node->can('representation') ? ( $node->representation // '' ) : '';
        # Numeric constants: emit bare.
        return $val if $val =~ /\A-?\d+(?:\.\d+)?\z/;
        # String constants: single-quote them.
        $val =~ s/\\/\\\\/g;
        $val =~ s/'/\\'/g;
        return "'$val'";
    }
    elsif ( $op eq 'Add' ) {
        my $l = _emit_expr( $node->inputs->[0], $var_table );
        my $r = _emit_expr( $node->inputs->[1], $var_table );
        return "($l + $r)";
    }
    elsif ( $op eq 'Subtract' ) {
        my $l = _emit_expr( $node->inputs->[0], $var_table );
        my $r = _emit_expr( $node->inputs->[1], $var_table );
        return "($l - $r)";
    }
    elsif ( $op eq 'Multiply' ) {
        my $l = _emit_expr( $node->inputs->[0], $var_table );
        my $r = _emit_expr( $node->inputs->[1], $var_table );
        return "($l * $r)";
    }
    elsif ( $op eq 'Divide' ) {
        my $l = _emit_expr( $node->inputs->[0], $var_table );
        my $r = _emit_expr( $node->inputs->[1], $var_table );
        return "($l / $r)";
    }
    elsif ( $op eq 'Modulo' ) {
        my $l = _emit_expr( $node->inputs->[0], $var_table );
        my $r = _emit_expr( $node->inputs->[1], $var_table );
        return "($l % $r)";
    }
    elsif ( $op eq 'Coerce' ) {
        # Coerce is transparent for Perl — Perl handles implicit coercions.
        return _emit_expr( $node->inputs->[0], $var_table );
    }
    elsif ( $op eq 'PadAccess' ) {
        return _resolve_padaccess( $node, $var_table );
    }
    elsif ( $op eq 'VarDecl' ) {
        # VarDecl as a value (when referenced directly rather than via PadAccess).
        my $perl_var = $var_table->{ $node->id };
        return $perl_var if defined $perl_var;
        die "ReturnNodePerlDriver: VarDecl id=" . $node->id . " not in var_table";
    }
    elsif ( $op eq 'NumGt' ) {
        my $l = _emit_expr( $node->inputs->[0], $var_table );
        my $r = _emit_expr( $node->inputs->[1], $var_table );
        return "($l > $r)";
    }
    elsif ( $op eq 'NumLt' ) {
        my $l = _emit_expr( $node->inputs->[0], $var_table );
        my $r = _emit_expr( $node->inputs->[1], $var_table );
        return "($l < $r)";
    }
    elsif ( $op eq 'NumGe' ) {
        my $l = _emit_expr( $node->inputs->[0], $var_table );
        my $r = _emit_expr( $node->inputs->[1], $var_table );
        return "($l >= $r)";
    }
    elsif ( $op eq 'NumLe' ) {
        my $l = _emit_expr( $node->inputs->[0], $var_table );
        my $r = _emit_expr( $node->inputs->[1], $var_table );
        return "($l <= $r)";
    }
    elsif ( $op eq 'NumEq' ) {
        my $l = _emit_expr( $node->inputs->[0], $var_table );
        my $r = _emit_expr( $node->inputs->[1], $var_table );
        return "($l == $r)";
    }
    elsif ( $op eq 'NumNe' ) {
        my $l = _emit_expr( $node->inputs->[0], $var_table );
        my $r = _emit_expr( $node->inputs->[1], $var_table );
        return "($l != $r)";
    }
    elsif ( $op eq 'TernaryExpr' ) {
        my $cond  = _emit_expr( $node->inputs->[0], $var_table );
        my $true  = _emit_expr( $node->inputs->[1], $var_table );
        my $false = _emit_expr( $node->inputs->[2], $var_table );
        return "($cond ? $true : $false)";
    }
    else {
        die "ReturnNodePerlDriver: cannot emit op=$op (not in computation slice)";
    }
}

# _resolve_padaccess($node, \%var_table) -> $perl_var_name
# Resolves a PadAccess node to a Perl variable name via its VarDecl input.
sub _resolve_padaccess {
    my ( $node, $var_table ) = @_;

    my $op = $node->can('operation') ? $node->operation : '';

    if ( $op eq 'PadAccess' ) {
        my $vd = $node->inputs->[0];
        die "ReturnNodePerlDriver: PadAccess has no VarDecl input"
            unless defined $vd;
        my $perl_var = $var_table->{ $vd->id };
        die "ReturnNodePerlDriver: VarDecl id=" . $vd->id . " not in var_table"
            unless defined $perl_var;
        return $perl_var;
    }
    elsif ( $op eq 'VarDecl' ) {
        my $perl_var = $var_table->{ $node->id };
        die "ReturnNodePerlDriver: VarDecl id=" . $node->id . " not in var_table"
            unless defined $perl_var;
        return $perl_var;
    }
    else {
        die "ReturnNodePerlDriver: expected PadAccess or VarDecl, got op=$op";
    }
}

# _run_perl($snippet) -> ($stdout, $exit_code)
# Writes the snippet to a temp file and runs under perl 5.42.
sub _run_perl {
    my ($snippet) = @_;

    my ( $fh, $tmp ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    binmode $fh, ':utf8';
    print $fh $snippet;
    close $fh;

    my $out  = qx($PERL_BIN $tmp 2>&1);
    my $exit = $? >> 8;
    return ( $out, $exit );
}

1;
