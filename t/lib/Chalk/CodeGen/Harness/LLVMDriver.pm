# ABOUTME: L-corner driver: typed SoN Return node -> LLVM IR (via Target::LLVM) -> lli -> BehaviorRecord.
# ABOUTME: Reports runtime-free coverage fraction; never links libperl (Scalar is a GAP, not a fallback).
package Chalk::CodeGen::Harness::LLVMDriver;

use 5.42.0;
use utf8;

use Carp      qw(croak);
use File::Temp qw(tempfile);
use Scalar::Util qw(blessed);

use Chalk::Target::LLVM;
use Chalk::CodeGen::Harness::BehaviorRecord;

# The lli interpreter path.
my $LLI = '/usr/lib/llvm-15/bin/lli';

# run($return_node, \%opts) -> ($L, \%emission_meta)
#
# Takes a typed SoN graph (a Return node) and:
#   1. Counts the number of typed (non-Scalar) values reachable from the Return
#      to compute the runtime-free coverage fraction.
#   2. Lowers the graph to LLVM IR text via Chalk::Target::LLVM->lower().
#   3. If lowering dies (Scalar-GAP or unsupported op), returns a GAP record.
#   4. Writes the .ll to a temp file and runs via lli.
#   5. Captures lli's stdout as the L return value.
#   6. Returns (BehaviorRecord, emission_meta).
#
# emission_meta keys:
#   emitted_for_every_construct   bool  — false if GAP (could not lower)
#   marked_unsupported            bool  — true if GAP (cannot-lower-runtime-free)
#   gap_reason                    str   — 'cannot-lower-runtime-free' on GAP
#   ll_text                       str   — the generated LLVM IR text (for libperl-free assertion)
#   runtime_free_fraction         float — fraction of reachable value-nodes that are non-Scalar
#
# The L corner NEVER links libperl. A Scalar-representation value reaching the
# LLVM backend is a GAP — NOT a libperl fallback. This enforces the self-sufficiency
# premise: the LLVM corner's job is to prove the IR is runtime-free.
sub run {
    my ( $class, $return_node, $opts ) = @_;
    $opts //= {};

    croak "LLVMDriver->run: return_node must be defined"
        unless defined $return_node;

    # ---- Step 1: measure runtime-free coverage ----
    my ( $total, $non_scalar ) = _count_value_nodes($return_node);
    my $runtime_free_fraction =
        ( $total > 0 ) ? ( $non_scalar / $total ) : 1.0;

    # ---- Step 2: attempt lowering ----
    # Class structure reaches the backend as a sealed MOP via $opts->{mop}
    # (019eb42a MOP-direct contract) — never as graph metadata.
    my ( $ll_text, $lower_error );
    eval {
        $ll_text = Chalk::Target::LLVM->lower($return_node,
            (defined $opts->{mop} ? (mop => $opts->{mop}) : ()));
    };
    if ($@) {
        $lower_error = $@;
    }

    # ---- Step 3: GAP when lowering failed ----
    if ( defined $lower_error ) {
        my $L = Chalk::CodeGen::Harness::BehaviorRecord->new(
            return_values     => [],
            wantarray_context => $opts->{context} // 'scalar',
            stdout            => '',
            stderr            => $lower_error,
            exception         => {
                kind    => 'string',
                class   => undef,
                message => "LLVM lowering GAP: $lower_error",
            },
            object_state => {},
        );
        my $emission_meta = {
            emitted_for_every_construct => 0,
            marked_unsupported          => 1,
            gap_reason                  => 'cannot-lower-runtime-free',
            ll_text                     => undef,
            runtime_free_fraction       => $runtime_free_fraction,
            lower_error                 => $lower_error,
        };
        return ( $L, $emission_meta );
    }

    # ---- Step 4: run via lli ----
    my ( $lli_stdout, $lli_exit ) = _run_lli($ll_text);

    # ---- Step 5: build BehaviorRecord ----
    # The L corner captures the lli stdout as the return value.
    # lli prints the result followed by a newline; strip trailing whitespace.
    chomp( my $output = $lli_stdout // '' );

    my $L = Chalk::CodeGen::Harness::BehaviorRecord->new(
        return_values     => [ length($output) ? $output : () ],
        wantarray_context => $opts->{context} // 'scalar',
        stdout            => '',
        stderr            => ( $lli_exit != 0 ? $lli_stdout : '' ),
        exception         => ( $lli_exit != 0
            ? { kind => 'string', class => undef, message => "lli exited $lli_exit: $lli_stdout" }
            : undef ),
        object_state => {},
    );

    my $emission_meta = {
        emitted_for_every_construct => ( $lli_exit == 0 ? 1 : 0 ),
        marked_unsupported          => 0,
        ll_text                     => $ll_text,
        runtime_free_fraction       => $runtime_free_fraction,
        lli_exit                    => $lli_exit,
    };

    return ( $L, $emission_meta );
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

# _run_lli($ll_text) -> ($stdout, $exit_code)
# Writes the LLVM IR to a temp file and executes lli.
sub _run_lli {
    my ($ll_text) = @_;

    my ( $fh, $tmp ) = tempfile( SUFFIX => '.ll', UNLINK => 1 );
    binmode $fh, ':utf8';
    print $fh $ll_text;
    close $fh;

    my $out  = qx($LLI $tmp 2>&1);
    my $exit = $? >> 8;
    return ( $out, $exit );
}

# _count_value_nodes($return_node) -> ($total_count, $non_scalar_count)
#
# Walks the reachable value sub-graph rooted at the Return node's input and
# the control chain (VarDecl/Assign nodes), counting:
#   - total: all nodes that carry a representation field (value-producing nodes)
#   - non_scalar: nodes whose representation is defined and is NOT 'Scalar'
#
# The runtime-free coverage fraction is non_scalar / total (1.0 if total == 0).
# A Constant or operation node with no representation set is treated as potentially
# Scalar (conservative: counts against non_scalar).
sub _count_value_nodes {
    my ($return_node) = @_;

    my %visited;
    my $total      = 0;
    my $non_scalar = 0;

    # Walk the control chain first (VarDecl/Assign/CompoundAssign).
    {
        my $ctrl = $return_node->can('control_in') ? $return_node->control_in : undef;
        while ( defined $ctrl ) {
            _visit_for_coverage( $ctrl, \%visited, \$total, \$non_scalar );
            $ctrl = $ctrl->can('control_in') ? $ctrl->control_in : undef;
        }
    }

    # Walk the value sub-graph from the Return's input.
    my $val = $return_node->inputs->[0];
    _visit_for_coverage( $val, \%visited, \$total, \$non_scalar ) if defined $val;

    return ( $total, $non_scalar );
}

# _visit_for_coverage($node, \%visited, \$total, \$non_scalar)
# Recursive DFS over the data-flow sub-graph rooted at $node.
# Counts nodes with a representation field.
sub _visit_for_coverage {
    my ( $node, $visited, $total_ref, $non_scalar_ref ) = @_;
    return unless defined $node;

    my $id = $node->id;
    return if $visited->{$id}++;

    # Count this node if it is a value-producing node (has a representation field).
    # We check for the set_representation/representation API.
    if ( $node->can('representation') ) {
        $$total_ref++;
        my $repr = $node->representation;
        if ( defined $repr && $repr ne 'Scalar' ) {
            $$non_scalar_ref++;
        }
        # undef representation is conservative (counts as Scalar for coverage purposes)
    }

    # Recurse into inputs.
    if ( $node->can('inputs') ) {
        for my $inp ( $node->inputs->@* ) {
            _visit_for_coverage( $inp, $visited, $total_ref, $non_scalar_ref )
                if defined $inp;
        }
    }
}

1;
