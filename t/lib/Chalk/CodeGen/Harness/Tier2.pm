# ABOUTME: Tier-2 codegen harness — exercises real lib/ modules via hand-authored MOP graphs.
# ABOUTME: S side = real source loaded under perl; P side = hand-authored MOP through Target::Perl.
package Chalk::CodeGen::Harness::Tier2;

use 5.42.0;
use utf8;

use Carp qw(croak);
use Scalar::Util qw(blessed);

use Chalk::CodeGen::Harness::HandGraphs;
use Chalk::CodeGen::Harness::RunUnderPerl;
use Chalk::CodeGen::Harness::PerlDriver;
use Chalk::CodeGen::Harness::Comparator;
use Chalk::CodeGen::Harness::GapMap;

# ---------------------------------------------------------------------------
# Unit registry
#
# Each entry describes one real lib/ unit: the module path (for the S side),
# the class name (for instantiation), and the constructor params that both the
# real module and the hand-authored stub accept.
#
# Optional fields:
#   use_also      — arrayref of extra module names to load in the oracle snippet
#   ctor_raw      — raw Perl argument string for the constructor call, used in
#                   place of encoding ctor_params when complex object construction
#                   is required (e.g., passing nested blessed objects). Must be
#                   valid Perl that evaluates to a list of key => value pairs.
# ---------------------------------------------------------------------------
my %UNIT_REGISTRY = (
    Add => {
        lib_path    => 'lib/Chalk/IR/Node/Add.pm',
        class       => 'Chalk::IR::Node::Add',
        use_module  => 'Chalk::IR::Node::Add',
        ctor_params => { id => 'tier2_test', inputs => [] },
        graph_tag   => 'T2_Add',
        graph_source => 'hand:T2_Add',
    },
    BinOp => {
        lib_path    => 'lib/Chalk/IR/Node/BinOp.pm',
        class       => 'Chalk::IR::Node::BinOp',
        use_module  => 'Chalk::IR::Node::BinOp',
        ctor_params => { id => 'tier2_test', inputs => [], left => 'left_val', right => 'right_val' },
        graph_tag   => 'T2_BinOp',
        graph_source => 'hand:T2_BinOp',
    },
    Symbol => {
        lib_path    => 'lib/Chalk/Grammar/Symbol.pm',
        class       => 'Chalk::Grammar::Symbol',
        use_module  => 'Chalk::Grammar::Symbol',
        ctor_params => { type => 'terminal', value => 'foo' },
        graph_tag   => 'T2_Symbol',
        graph_source => 'hand:T2_Symbol',
    },
    Symbol_ref => {
        lib_path    => 'lib/Chalk/Grammar/Symbol.pm',
        class       => 'Chalk::Grammar::Symbol',
        use_module  => 'Chalk::Grammar::Symbol',
        ctor_params => { type => 'reference', value => 'Bar', quantifier => '*' },
        graph_tag   => 'T2_Symbol',
        graph_source => 'hand:T2_Symbol',
    },
    Rule => {
        lib_path    => 'lib/Chalk/Grammar/Rule.pm',
        class       => 'Chalk::Grammar::Rule',
        use_module  => 'Chalk::Grammar::Rule',
        # One alternative with one terminal symbol — is_terminal_rule() = true.
        use_also  => ['Chalk::Grammar::Symbol'],
        ctor_raw  => q(name => 'TermRule',
            expressions => [[
                Chalk::Grammar::Symbol->new(type => 'terminal', value => 'foo'),
                Chalk::Grammar::Symbol->new(type => 'terminal', value => 'bar'),
            ]]),
        graph_tag   => 'T2_Rule',
        graph_source => 'hand:T2_Rule',
    },
    Rule_mixed => {
        lib_path    => 'lib/Chalk/Grammar/Rule.pm',
        class       => 'Chalk::Grammar::Rule',
        use_module  => 'Chalk::Grammar::Rule',
        # One alternative with a nonterminal symbol — is_terminal_rule() = false.
        use_also  => ['Chalk::Grammar::Symbol'],
        ctor_raw  => q(name => 'MixedRule',
            expressions => [[
                Chalk::Grammar::Symbol->new(type => 'terminal',  value => 'foo'),
                Chalk::Grammar::Symbol->new(type => 'reference', value => 'Bar'),
            ]]),
        graph_tag   => 'T2_Rule_mixed',
        graph_source => 'hand:T2_Rule_mixed',
    },
);

# ---------------------------------------------------------------------------
# run_unit($unit_name) -> { S, P, verdict }
#
# Runs all registered methods for the named unit and returns the aggregate
# result. Croaks if the unit is not registered.
#
# Primarily used to check that the tier-2 path is wired. For per-method
# results use run_unit_method().
# ---------------------------------------------------------------------------
sub run_unit {
    my (undef, $unit_name) = @_;

    my $entry = $UNIT_REGISTRY{$unit_name}
        or croak "Tier2::run_unit: unknown unit '$unit_name'";

    # Run the first registered method as the representative result.
    my $methods = _methods_for($unit_name);
    my $first   = $methods->[0]
        or croak "Tier2::run_unit: no methods registered for '$unit_name'";

    return __PACKAGE__->run_unit_method($unit_name, $first);
}

# ---------------------------------------------------------------------------
# run_unit_method($unit_name, $method_name, $spec_overrides?) -> { S, P, verdict }
#
# Runs one method of a tier-2 unit end-to-end:
#   S = RunUnderPerl->capture(real lib/ module snippet, spec)
#   P = PerlDriver->run(HandGraphs->graph_for(T2_$unit), spec)
#   verdict = Comparator->verdict(S, P, emission_meta)
#
# $spec_overrides is an optional hashref merged into the spec. If it contains
# an 'expected_output' key, the call croaks — expected values must be
# perl-derived (not hand-specified).
# ---------------------------------------------------------------------------
sub run_unit_method {
    my (undef, $unit_name, $method_name, $spec_overrides) = @_;

    my $entry = $UNIT_REGISTRY{$unit_name}
        or croak "Tier2::run_unit_method: unknown unit '$unit_name'";

    # Guard: reject manual expected_output in spec overrides.
    if (defined $spec_overrides && ref $spec_overrides eq 'HASH') {
        croak "Tier2::run_unit_method: 'expected_output' in spec is rejected — "
            . "expected values must be perl-derived (run under the oracle), never hand-specified"
            if exists $spec_overrides->{expected_output};
    }

    my $class        = $entry->{class};
    my $ctor_params  = $entry->{ctor_params};
    my $ctor_raw     = $entry->{ctor_raw};
    my $graph_tag    = $entry->{graph_tag};
    my $graph_source = $entry->{graph_source};

    my $spec = {
        class       => $class,
        constructor => { params => $ctor_params, raw => $ctor_raw },
        method      => $method_name,
        method_args => [],
        context     => 'scalar',
        use_also    => $entry->{use_also},
    };

    # ---- S side: oracle via real lib/ module ----
    my $snippet = _build_oracle_snippet($entry);
    my $S = Chalk::CodeGen::Harness::RunUnderPerl->capture($snippet, $spec);

    # ---- P side: generated via hand-authored MOP ----
    my $mop = Chalk::CodeGen::Harness::HandGraphs->graph_for($graph_tag);
    croak "Tier2::run_unit_method: no hand graph for tag '$graph_tag'"
        unless defined $mop;

    my ($P, $emission_meta) = Chalk::CodeGen::Harness::PerlDriver->run($mop, $spec);
    $emission_meta->{graph_source} = $graph_source;

    # ---- Verdict ----
    my $verdict = Chalk::CodeGen::Harness::Comparator->verdict($S, $P, $emission_meta);

    return {
        S       => $S,
        P       => $P,
        verdict => $verdict,
    };
}

# ---------------------------------------------------------------------------
# check_spec_completeness($unit_name, $snippet, $spec) -> reason_or_undef
#
# Delegates to GapMap::check_spec_completeness so tier-2 units apply the
# same under-spec guard as tier-1.
# ---------------------------------------------------------------------------
sub check_spec_completeness {
    my (undef, $unit_name, $snippet, $spec) = @_;
    return Chalk::CodeGen::Harness::GapMap->check_spec_completeness(
        $unit_name, $snippet, $spec
    );
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

# _build_oracle_snippet($entry) -> $snippet_text
#
# Builds the Perl snippet for the S side: loads the real lib/ module via
# 'use lib 'lib'' then loads the module with use. When the entry has a
# use_also list, those modules are loaded as well (needed when ctor_raw
# constructs objects whose types come from other modules).
sub _build_oracle_snippet {
    my ($entry) = @_;
    my $module   = $entry->{use_module};
    my @also     = $entry->{use_also} ? $entry->{use_also}->@* : ();
    my $snippet  = "use lib 'lib';\nuse $module;";
    for my $also (@also) {
        $snippet .= "\nuse $also;";
    }
    return $snippet;
}

# _methods_for($unit_name) -> \@method_names
#
# Returns the list of methods to exercise for a given unit, in declaration
# order. Introspects the hand-authored MOP to find methods on the target class.
sub _methods_for {
    my ($unit_name) = @_;

    my $entry = $UNIT_REGISTRY{$unit_name}
        or croak "_methods_for: unknown unit '$unit_name'";

    my $mop = Chalk::CodeGen::Harness::HandGraphs->graph_for($entry->{graph_tag});
    return [] unless defined $mop;

    my $target_class = $entry->{class};
    my $cls = $mop->for_class($target_class);
    return [] unless defined $cls;

    return [ map { $_->name } $cls->methods() ];
}

1;
