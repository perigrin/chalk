# ABOUTME: C code generation target that reconstructs grammar from BNF IR and builds LR0DFA.
# ABOUTME: Returns stub C file content; serialization of static DFA tables is done in later phases.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Target;
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::CoreItemIndex;
use Chalk::Bootstrap::LR0DFA;

class Chalk::Bootstrap::BNF::Target::C :isa(Chalk::Bootstrap::Target) {

    # Lexical helpers used by _emit_core_item_arrays().
    # Defined as my subs so they are resolved at compile time within the class scope.

    # Escape a Perl string for use as a C string literal and wrap it in double quotes.
    my sub _c_string($s) {
        $s =~ s/\\/\\\\/g;
        $s =~ s/"/\\"/g;
        return qq("$s");
    }

    # Emit a single static C array declaration with the given type, name, size, and values.
    # Values must already be formatted as C literal strings (e.g. via _c_string, or plain ints).
    my sub _emit_c_array($type, $name, $n, $values) {
        my $init = join(', ', $values->@*);
        return "static $type $name\[$n\] = { $init };\n";
    }

    # Stored after the most recent generate() call for introspection by tests
    # and for use by future serialization methods.
    field $last_dfa_state_count :reader = 0;
    field $last_terminal_patterns :reader = [];
    field $last_rule_count :reader = 0;

    # Fields holding the built objects for use by future serialization phases.
    field $core_index;
    field $lr0_dfa;
    field $grammar;

    # Generate stub C output from an arrayref of Constructor:Rule IR nodes.
    # Reconstructs Rule/Symbol objects, builds CoreItemIndex and LR0DFA,
    # stores them for later serialization, and returns stub file content.
    method generate($ir) {
        die "generate() requires an arrayref of IR rules"
            unless defined($ir) && ref($ir) eq 'ARRAY';

        # Reset stored state so each call is independent
        $last_dfa_state_count = 0;
        $last_terminal_patterns = [];
        $last_rule_count = 0;
        $core_index = undef;
        $lr0_dfa    = undef;
        $grammar    = undef;

        # Reconstruct Rule/Symbol objects from the IR
        my @rules = $self->_reconstruct_rules($ir);
        $last_rule_count = scalar @rules;

        # Collect all terminal patterns for introspection
        my @patterns;
        for my $rule (@rules) {
            for my $alt ($rule->expressions()->@*) {
                for my $sym ($alt->@*) {
                    push @patterns, $sym->value()
                        if $sym->type() eq 'terminal';
                }
            }
        }
        $last_terminal_patterns = \@patterns;

        # Build CoreItemIndex and LR0DFA when there are rules to process
        if (@rules) {
            my $index = Chalk::Bootstrap::CoreItemIndex->new();
            $index->build_from_grammar(\@rules);

            my %rule_table = map { $_->name() => $_ } @rules;
            my $dfa = Chalk::Bootstrap::LR0DFA->new(
                grammar    => \@rules,
                core_index => $index,
                rule_table => \%rule_table,
            );
            $dfa->build();

            $core_index           = $index;
            $lr0_dfa              = $dfa;
            $grammar              = \@rules;
            $last_dfa_state_count = $dfa->state_count();
        }

        my $c_body = "/* stub */\n";
        if ($core_index) {
            $c_body  = $self->_emit_core_item_arrays();
            $c_body .= $self->_emit_terminal_maps();
            $c_body .= $self->_emit_completion_maps();
            $c_body .= $self->_emit_goto_tables();
        }

        return {
            'dfa_tables.c' => $c_body,
            'dfa_tables.h' => "/* stub */\n",
        };
    }

    # Emit the 7 CoreItemIndex parallel arrays as static C source.
    # All arrays are indexed by core_id (0 to count-1).
    method _emit_core_item_arrays() {
        my $n = $core_index->count();

        # Collect per-id values up front.
        my @rule_names;
        my @alt_idxs;
        my @dots;
        my @is_complete;
        my @advance;
        my @to_state;
        my @sym_patterns;
        my @sym_is_ref;

        for my $id (0 .. $n - 1) {
            push @rule_names,   _c_string($core_index->rule_name_for($id));
            push @alt_idxs,     $core_index->alt_idx_for($id);
            push @dots,         $core_index->dot_for($id);

            my $complete = $core_index->is_complete($id) ? 1 : 0;
            push @is_complete, $complete;

            my $adv = $core_index->advance($id);
            push @advance, defined($adv) ? $adv : -1;

            my $state = $core_index->state_for($id);
            push @to_state, defined($state) ? $state : -1;

            my $sym = $core_index->symbol_after($id);
            if (defined $sym) {
                push @sym_patterns, _c_string($sym->value());
                push @sym_is_ref,   $sym->is_reference() ? 1 : 0;
            }
            else {
                push @sym_patterns, 'NULL';
                push @sym_is_ref,   0;
            }
        }

        my $out = '';

        $out .= "#define NUM_CORE_ITEMS $n\n\n";

        $out .= _emit_c_array('const char *', 'ci_rule_names',          $n, \@rule_names);
        $out .= _emit_c_array('const int',    'ci_alt_idxs',            $n, \@alt_idxs);
        $out .= _emit_c_array('const int',    'ci_dots',                $n, \@dots);
        $out .= _emit_c_array('const int',    'ci_is_complete',         $n, \@is_complete);
        $out .= _emit_c_array('const int',    'ci_advance',             $n, \@advance);
        $out .= _emit_c_array('const int',    'ci_to_state',            $n, \@to_state);
        $out .= _emit_c_array('const char *', 'ci_symbol_after_pattern',$n, \@sym_patterns);
        $out .= _emit_c_array('const int',    'ci_symbol_after_is_ref', $n, \@sym_is_ref);

        return $out;
    }

    # Emit terminal map arrays as static C.
    # For each DFA state: a list of (pattern, [core_ids]) pairs.
    # Patterns are deduplicated into a flat string table.
    # core_ids are flattened into tmap_core_ids with per-slice (pattern, offset, count) records.
    # Per-state offset/count arrays let the C consumer locate each state's slices in O(1).
    method _emit_terminal_maps() {
        my $states = $lr0_dfa->states();
        my $num_states = scalar $states->@*;

        # Deduplicate patterns: pattern string => index in unique-patterns table
        my %pattern_index;
        my @unique_patterns;

        # Collect per-state slice info and flat core_ids as we go.
        # @state_slices[$state_id] = [ {pattern_idx, offset, count}, ... ]
        my @state_slices;
        my @flat_core_ids;

        for my $state ($states->@*) {
            my $sid    = $state->{id};
            my $tmap   = $state->{terminal_map};
            my @slices;

            for my $pattern (sort keys %{$tmap}) {
                # Assign a unique index to this pattern if not seen before
                unless (exists $pattern_index{$pattern}) {
                    $pattern_index{$pattern} = scalar @unique_patterns;
                    push @unique_patterns, $pattern;
                }
                my $pat_idx = $pattern_index{$pattern};
                my $offset  = scalar @flat_core_ids;
                my @ids     = sort { $a <=> $b } $tmap->{$pattern}->@*;
                push @flat_core_ids, @ids;
                push @slices, { pattern_idx => $pat_idx, offset => $offset, count => scalar @ids };
            }

            $state_slices[$sid] = \@slices;
        }

        my $total_entries  = scalar @flat_core_ids;
        my $num_patterns   = scalar @unique_patterns;

        # Build flat slice array and per-state offset/count arrays
        my @all_slices;
        my @so_vals;   # state slice offsets
        my @sc_vals;   # state slice counts
        for my $sid (0 .. $num_states - 1) {
            my $slices = $state_slices[$sid] // [];
            push @so_vals, scalar @all_slices;
            push @sc_vals, scalar $slices->@*;
            push @all_slices, $slices->@*;
        }
        my $total_slices = scalar @all_slices;

        my $out = '';
        $out .= "#define NUM_DFA_STATES $num_states\n";
        $out .= "#define TOTAL_TMAP_ENTRIES $total_entries\n";
        $out .= "#define TOTAL_TMAP_SLICES $total_slices\n";
        $out .= "#define NUM_UNIQUE_TMAP_PATTERNS $num_patterns\n\n";

        # tmap_core_ids
        if ($total_entries > 0) {
            $out .= _emit_c_array('const int', 'tmap_core_ids', $total_entries, \@flat_core_ids);
        }
        else {
            $out .= "static const int tmap_core_ids[1] = { -1 }; /* empty */\n";
        }

        # tmap_patterns (unique pattern strings)
        my @pat_vals = map { _c_string($_) } @unique_patterns;
        if ($num_patterns > 0) {
            $out .= _emit_c_array('const char *', 'tmap_patterns', $num_patterns, \@pat_vals);
        }
        else {
            $out .= "static const char *tmap_patterns[1] = { NULL }; /* empty */\n";
        }

        # TMapSlice typedef + tmap_slices
        $out .= "typedef struct { int pattern_idx; int offset; int count; } TMapSlice;\n";
        if ($total_slices > 0) {
            my @slice_vals = map { "{$_->{pattern_idx}, $_->{offset}, $_->{count}}" } @all_slices;
            $out .= _emit_c_array('const TMapSlice', 'tmap_slices', $total_slices, \@slice_vals);
        }
        else {
            $out .= "static const TMapSlice tmap_slices[1] = { {0, 0, 0} }; /* empty */\n";
        }

        $out .= _emit_c_array('const int', 'tmap_state_offset', $num_states, \@so_vals);
        $out .= _emit_c_array('const int', 'tmap_state_count',  $num_states, \@sc_vals);
        $out .= "\n";

        return $out;
    }

    # Emit completion map arrays as static C.
    # Identical encoding to terminal maps but keyed by nonterminal name.
    method _emit_completion_maps() {
        my $states     = $lr0_dfa->states();
        my $num_states = scalar $states->@*;

        my %nonterm_index;
        my @unique_nonterms;
        my @state_slices;
        my @flat_core_ids;

        for my $state ($states->@*) {
            my $sid    = $state->{id};
            my $cmap   = $state->{completion_map};
            my @slices;

            for my $nt (sort keys %{$cmap}) {
                unless (exists $nonterm_index{$nt}) {
                    $nonterm_index{$nt} = scalar @unique_nonterms;
                    push @unique_nonterms, $nt;
                }
                my $nt_idx = $nonterm_index{$nt};
                my $offset = scalar @flat_core_ids;
                my @ids    = sort { $a <=> $b } $cmap->{$nt}->@*;
                push @flat_core_ids, @ids;
                push @slices, { nonterm_idx => $nt_idx, offset => $offset, count => scalar @ids };
            }

            $state_slices[$sid] = \@slices;
        }

        my $total_entries  = scalar @flat_core_ids;
        my $num_nonterms   = scalar @unique_nonterms;

        my @all_slices;
        my @so_vals;
        my @sc_vals;
        for my $sid (0 .. $num_states - 1) {
            my $slices = $state_slices[$sid] // [];
            push @so_vals, scalar @all_slices;
            push @sc_vals, scalar $slices->@*;
            push @all_slices, $slices->@*;
        }
        my $total_slices = scalar @all_slices;

        my $out = '';
        $out .= "#define TOTAL_CMAP_ENTRIES $total_entries\n";
        $out .= "#define TOTAL_CMAP_SLICES $total_slices\n";
        $out .= "#define NUM_UNIQUE_CMAP_NONTERMS $num_nonterms\n\n";

        if ($total_entries > 0) {
            $out .= _emit_c_array('const int', 'cmap_core_ids', $total_entries, \@flat_core_ids);
        }
        else {
            $out .= "static const int cmap_core_ids[1] = { -1 }; /* empty */\n";
        }

        my @nt_vals = map { _c_string($_) } @unique_nonterms;
        if ($num_nonterms > 0) {
            $out .= _emit_c_array('const char *', 'cmap_nonterminals', $num_nonterms, \@nt_vals);
        }
        else {
            $out .= "static const char *cmap_nonterminals[1] = { NULL }; /* empty */\n";
        }

        $out .= "typedef struct { int nonterm_idx; int offset; int count; } CMapSlice;\n";
        if ($total_slices > 0) {
            my @slice_vals = map { "{$_->{nonterm_idx}, $_->{offset}, $_->{count}}" } @all_slices;
            $out .= _emit_c_array('const CMapSlice', 'cmap_slices', $total_slices, \@slice_vals);
        }
        else {
            $out .= "static const CMapSlice cmap_slices[1] = { {0, 0, 0} }; /* empty */\n";
        }

        $out .= _emit_c_array('const int', 'cmap_state_offset', $num_states, \@so_vals);
        $out .= _emit_c_array('const int', 'cmap_state_count',  $num_states, \@sc_vals);
        $out .= "\n";

        return $out;
    }

    # Emit goto table arrays as static C.
    # goto_entries is a flat array of { symbol_key, target_state } structs.
    # goto_state_offset/goto_state_count provide O(1) per-state access.
    method _emit_goto_tables() {
        my $states     = $lr0_dfa->states();
        my $num_states = scalar $states->@*;

        my @flat_entries;    # { symbol_key, target_state }
        my @so_vals;
        my @sc_vals;

        for my $sid (0 .. $num_states - 1) {
            my $state      = $states->[$sid];
            my $goto_table = $state->{goto_table};
            push @so_vals, scalar @flat_entries;
            my @syms = sort keys %{$goto_table};
            push @sc_vals, scalar @syms;
            for my $sym_key (@syms) {
                push @flat_entries, { symbol_key => $sym_key, target_state => $goto_table->{$sym_key} };
            }
        }

        my $total_entries = scalar @flat_entries;

        my $out = '';
        $out .= "#define TOTAL_GOTO_ENTRIES $total_entries\n\n";
        $out .= "typedef struct { const char *symbol_key; int target_state; } GotoEntry;\n";

        if ($total_entries > 0) {
            my @entry_vals = map { "{" . _c_string($_->{symbol_key}) . ", $_->{target_state}}" } @flat_entries;
            $out .= _emit_c_array('const GotoEntry', 'goto_entries', $total_entries, \@entry_vals);
        }
        else {
            $out .= "static const GotoEntry goto_entries[1] = { {NULL, -1} }; /* empty */\n";
        }

        $out .= _emit_c_array('const int', 'goto_state_offset', $num_states, \@so_vals);
        $out .= _emit_c_array('const int', 'goto_state_count',  $num_states, \@sc_vals);
        $out .= "\n";

        return $out;
    }

    # generate_distribution wraps generate() with the standard distribution shape.
    method generate_distribution($ir) {
        return $self->generate($ir);
    }

    # Reconstruct Chalk::Grammar::Rule and Chalk::Grammar::Symbol objects
    # from an arrayref of Constructor:Rule IR nodes.
    method _reconstruct_rules($ir) {
        my @rules;
        for my $rule_node ($ir->@*) {
            push @rules, $self->_reconstruct_rule($rule_node);
        }
        return @rules;
    }

    # Reconstruct a single Chalk::Grammar::Rule from a Constructor:Rule IR node.
    # IR layout: inputs()->[0] = Constant(name), inputs()->[1] = arrayref of Expression nodes
    method _reconstruct_rule($rule_node) {
        my $inputs      = $rule_node->inputs();
        my $name        = $inputs->[0]->value();
        my $expr_nodes  = $inputs->[1];

        my @expressions;
        for my $expr_node ($expr_nodes->@*) {
            push @expressions, $self->_reconstruct_expression($expr_node);
        }

        return Chalk::Grammar::Rule->new(
            name        => $name,
            expressions => \@expressions,
        );
    }

    # Reconstruct a single alternative (arrayref of Symbol objects)
    # from a Constructor:Expression IR node.
    # IR layout: inputs()->[0] = arrayref of Symbol Constructor nodes
    method _reconstruct_expression($expr_node) {
        my $symbol_nodes = $expr_node->inputs()->[0];
        my @symbols;
        for my $sym_node ($symbol_nodes->@*) {
            push @symbols, $self->_reconstruct_symbol($sym_node);
        }
        return \@symbols;
    }

    # Reconstruct a single Chalk::Grammar::Symbol from a Constructor:Symbol IR node.
    # IR layout: inputs()->[0] = Constant(type), inputs()->[1] = Constant(value),
    #            inputs()->[2] = Constant(quantifier) or undef
    method _reconstruct_symbol($sym_node) {
        my $inputs     = $sym_node->inputs();
        my $type_str   = $inputs->[0]->value();
        my $raw_value  = $inputs->[1]->value();
        my $quant_node = $inputs->[2];
        my $quant_str  = defined($quant_node) ? $quant_node->value() : undef;

        # Strip /…/ delimiters from terminal values (same logic as Target::Perl)
        my $value = $raw_value;
        if ($type_str eq 'terminal' && $value =~ m{^/(.*)/$}s) {
            $value = $1;
        }

        my %args = (type => $type_str, value => $value);
        $args{quantifier} = $quant_str if defined $quant_str;

        return Chalk::Grammar::Symbol->new(%args);
    }
}
