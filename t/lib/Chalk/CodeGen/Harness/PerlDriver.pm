# ABOUTME: Perl code-gen driver: hand graph -> Target::Perl->generate -> run under perl 5.42.
# ABOUTME: Returns a BehaviorRecord P and emission_meta so the Comparator can classify the verdict.
package Chalk::CodeGen::Harness::PerlDriver;

use 5.42.0;
use utf8;

use Carp qw(croak);
use Scalar::Util qw(blessed);

use Chalk::Bootstrap::Perl::Target::Perl;
use Chalk::CodeGen::Harness::RunUnderPerl;
use Chalk::CodeGen::Harness::BehaviorRecord;

# run($graph, $spec) -> ($P, \%emission_meta)
#
# Takes a hand graph (a Chalk::MOP as returned by HandGraphs->graph_for) and an
# exercise spec hashref. Calls Target::Perl->generate($graph) to produce Perl
# source, prepends the required pragmas, runs the result under perl 5.42 via
# RunUnderPerl, and captures a BehaviorRecord P.
#
# The SAME graph object is passed directly to generate() — no re-derivation.
#
# Returns a two-element list: ($P, \%emission_meta).
#   $P            — a Chalk::CodeGen::Harness::BehaviorRecord
#   $emission_meta — { emitted_for_every_construct => bool, marked_unsupported => bool }
#
# This sub never dies on runtime errors from the generated code; those are
# captured as exception fields in the returned BehaviorRecord.
sub run {
    my (undef, $graph, $spec) = @_;    # undef = class name
    croak "PerlDriver->run: graph must be a Chalk::MOP"
        unless defined $graph && blessed($graph) && $graph->isa('Chalk::MOP');
    croak "PerlDriver->run: spec must be a hashref"
        unless ref $spec eq 'HASH';

    # ---- Emission step: generate Perl source from the graph ----
    my $target = Chalk::Bootstrap::Perl::Target::Perl->new;
    my ($generated, $emit_error) = _safe_generate($target, $graph);

    if (defined $emit_error) {
        # generate() itself died — treat as GAP (could not emit)
        my $emission_meta = {
            emitted_for_every_construct => 0,
            marked_unsupported          => 1,
            emit_error                  => $emit_error,
        };
        my $P = Chalk::CodeGen::Harness::BehaviorRecord->new(
            return_values    => [],
            wantarray_context => $spec->{context} // 'scalar',
            stdout           => '',
            stderr           => $emit_error,
            exception        => {
                kind    => 'string',
                class   => undef,
                message => "generate() died: $emit_error",
            },
            object_state     => {},
        );
        return ($P, $emission_meta);
    }

    # ---- Classify the emission ----
    # A degenerate/empty emission is a GAP.
    my $snippet = _flatten_generated($generated);

    if (!defined $snippet || !length($snippet) || $snippet !~ /\S/) {
        my $emission_meta = {
            emitted_for_every_construct => 0,
            marked_unsupported          => 0,
        };
        my $P = Chalk::CodeGen::Harness::BehaviorRecord->new(
            return_values    => [],
            wantarray_context => $spec->{context} // 'scalar',
            stdout           => '',
            stderr           => '',
            exception        => undef,
            object_state     => {},
        );
        return ($P, $emission_meta);
    }

    # ---- Prepend required pragmas ----
    # The generated code is a class body — it needs pragmas to be runnable.
    # When the spec has use_also modules (e.g. for complex constructor args
    # that reference types from other modules), load them from lib/ first.
    my $full_snippet = _add_pragmas($snippet, $spec->{use_also});

    # ---- Run under perl 5.42 via RunUnderPerl ----
    # For sub-name specs (non-class top-level subs), use capture_sub; otherwise
    # use the standard class/method capture.
    my $P = eval {
        exists $spec->{sub_name}
            ? Chalk::CodeGen::Harness::RunUnderPerl->capture_sub($full_snippet, $spec)
            : Chalk::CodeGen::Harness::RunUnderPerl->capture($full_snippet, $spec);
    };
    if ($@) {
        # The harness itself failed (e.g. driver produced no JSON output).
        # Build a synthetic BehaviorRecord reflecting the rig failure.
        my $err = $@;
        $P = Chalk::CodeGen::Harness::BehaviorRecord->new(
            return_values    => [],
            wantarray_context => $spec->{context} // 'scalar',
            stdout           => '',
            stderr           => $err,
            exception        => {
                kind    => 'string',
                class   => undef,
                message => "harness failure: $err",
            },
            object_state     => {},
        );
    }

    # ---- Build emission_meta ----
    # For the Perl driver: if generate returned non-empty code for the graph,
    # we treat it as a complete emission attempt (emitted_for_every_construct=1).
    # The Comparator then decides PASS vs MISCOMPILE based on behavior divergence.
    my $emission_meta = {
        emitted_for_every_construct => 1,
        marked_unsupported          => 0,
        graph_source                => 'hand',
    };

    return ($P, $emission_meta);
}

# --- Internal helpers ---

# _safe_generate($target, $graph) -> ($generated, $error)
# Calls $target->generate($graph) inside an eval. Returns ($result, undef) on success
# or (undef, $error_string) on failure.
sub _safe_generate {
    my ($target, $graph) = @_;
    my $result = eval { $target->generate($graph) };
    if ($@) {
        return (undef, "$@");
    }
    return ($result, undef);
}

# _flatten_generated($generated) -> $snippet_string
# Accepts either a plain string or a HashRef[Str] (the two return shapes of generate).
# For a HashRef, joins all values sorted by key with newlines.
sub _flatten_generated {
    my ($generated) = @_;
    return undef unless defined $generated;
    return $generated unless ref $generated eq 'HASH';
    return join("\n", map { $generated->{$_} } sort keys %$generated);
}

# _add_pragmas($snippet, \@use_also) -> $full_snippet
# Prepends the Perl 5.42 pragmas required to make a bare class declaration
# runnable. When use_also is given, those modules are loaded from lib/ before
# the snippet (needed when complex ctor_raw args reference external types).
sub _add_pragmas {
    my ($snippet, $use_also) = @_;
    my @lines = (
        'use 5.42.0;',
        'use utf8;',
        "use feature 'class';",
        "no warnings 'experimental::class';",
    );
    if (defined $use_also && ref $use_also eq 'ARRAY' && @$use_also) {
        push @lines, "use lib 'lib';";
        push @lines, "use $_;" for @$use_also;
    }
    push @lines, $snippet;
    return join("\n", @lines);
}

1;
