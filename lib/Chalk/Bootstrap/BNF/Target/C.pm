# ABOUTME: C code generation target that reconstructs grammar from BNF IR and builds LR0DFA.
# ABOUTME: Serializes CoreItemIndex, DFA state tables, prediction closures, and nullable set as static C arrays.
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
        $s =~ s/\n/\\n/g;
        $s =~ s/\t/\\t/g;
        $s =~ s/\r/\\r/g;
        $s =~ s/\0/\\0/g;
        $s =~ s/([^\x20-\x7E])/sprintf("\\x%02x", ord($1))/ge;
        return qq("$s");
    }

    # Emit a single static C array declaration with the given type, name, size, and values.
    # Values must already be formatted as C literal strings (e.g. via _c_string, or plain ints).
    my sub _emit_c_array($type, $name, $n, $values) {
        my $init = join(', ', $values->@*);
        return "$type $name\[$n\] = { $init };\n";
    }

    # Return a normalized copy of a Chalk::Grammar::Symbol, stripping /…/ delimiters
    # from terminal values so DFA patterns are bare regexes (e.g. 'a' not '/a/').
    my sub _normalize_symbol($sym) {
        return $sym unless $sym->type() eq 'terminal';
        my $val = $sym->value();
        return $sym unless $val =~ m{^/(.*)/$};
        my %args = (type => 'terminal', value => $1);
        $args{quantifier} = $sym->quantifier() if defined $sym->quantifier();
        return Chalk::Grammar::Symbol->new(%args);
    }

    # Return a normalized copy of a Chalk::Grammar::Rule, with all terminal symbols
    # having their /…/ delimiters stripped from their values.
    my sub _normalize_rule($rule) {
        my @normalized_exprs = map {
            [ map { _normalize_symbol($_) } $_->@* ]
        } $rule->expressions()->@*;
        return Chalk::Grammar::Rule->new(
            name        => $rule->name(),
            expressions => \@normalized_exprs,
        );
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

    # Ordered list of [name, value] pairs collected during _emit_* calls.
    # Populated during generate(); consumed by _emit_header().
    field $_defines = [];

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
        $_defines   = [];

        # IR contains Chalk::Grammar::Rule objects directly.
        # Normalize terminal values: strip /…/ delimiters from terminal symbols so
        # the DFA, CoreItemIndex, and C arrays all use bare regex patterns.
        my @rules = map { _normalize_rule($_) } $ir->@*;
        $last_rule_count = scalar @rules;

        # Collect all terminal patterns for introspection (after normalization)
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

        my $c_arrays = "/* stub */\n";
        if ($core_index) {
            $c_arrays  = $self->_emit_core_item_arrays();
            $c_arrays .= $self->_emit_terminal_maps();
            $c_arrays .= $self->_emit_completion_maps();
            $c_arrays .= $self->_emit_goto_tables();
            $c_arrays .= $self->_emit_prediction_tables();
            $c_arrays .= $self->_emit_nullable_set();
        }

        # The .c file includes chalk.h (which sets up the Perl environment) then
        # dfa_tables.h (which provides defines, typedefs, and extern declarations),
        # followed by the const array definitions with external linkage.
        my $c_body = qq(#include "chalk.h"\n#include "dfa_tables.h"\n\n) . $c_arrays;

        return {
            'dfa_tables.c' => $c_body,
            'dfa_tables.h' => $self->_emit_header(),
        };
    }

    # Emit the 8 CoreItemIndex parallel arrays as C source.
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

        push $_defines->@*, ['NUM_CORE_ITEMS', $n];

        my $out = '';

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

        push $_defines->@*, ['NUM_DFA_STATES',           $num_states];
        push $_defines->@*, ['TOTAL_TMAP_ENTRIES',       $total_entries];
        push $_defines->@*, ['TOTAL_TMAP_SLICES',        $total_slices];
        push $_defines->@*, ['NUM_UNIQUE_TMAP_PATTERNS', $num_patterns];

        my $out = '';

        # tmap_core_ids
        if ($total_entries > 0) {
            $out .= _emit_c_array('const int', 'tmap_core_ids', $total_entries, \@flat_core_ids);
        }
        else {
            $out .= "const int tmap_core_ids[1] = { -1 }; /* empty */\n";
        }

        # tmap_patterns (unique pattern strings)
        my @pat_vals = map { _c_string($_) } @unique_patterns;
        if ($num_patterns > 0) {
            $out .= _emit_c_array('const char *', 'tmap_patterns', $num_patterns, \@pat_vals);
        }
        else {
            $out .= "const char *tmap_patterns[1] = { NULL }; /* empty */\n";
        }

        # tmap_slices: typedef is now in the header; emit array only
        if ($total_slices > 0) {
            my @slice_vals = map { "{$_->{pattern_idx}, $_->{offset}, $_->{count}}" } @all_slices;
            $out .= _emit_c_array('const TMapSlice', 'tmap_slices', $total_slices, \@slice_vals);
        }
        else {
            $out .= "const TMapSlice tmap_slices[1] = { {0, 0, 0} }; /* empty */\n";
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

        push $_defines->@*, ['TOTAL_CMAP_ENTRIES',      $total_entries];
        push $_defines->@*, ['TOTAL_CMAP_SLICES',       $total_slices];
        push $_defines->@*, ['NUM_UNIQUE_CMAP_NONTERMS',$num_nonterms];

        my $out = '';

        if ($total_entries > 0) {
            $out .= _emit_c_array('const int', 'cmap_core_ids', $total_entries, \@flat_core_ids);
        }
        else {
            $out .= "const int cmap_core_ids[1] = { -1 }; /* empty */\n";
        }

        my @nt_vals = map { _c_string($_) } @unique_nonterms;
        if ($num_nonterms > 0) {
            $out .= _emit_c_array('const char *', 'cmap_nonterminals', $num_nonterms, \@nt_vals);
        }
        else {
            $out .= "const char *cmap_nonterminals[1] = { NULL }; /* empty */\n";
        }

        # cmap_slices: typedef is now in the header; emit array only
        if ($total_slices > 0) {
            my @slice_vals = map { "{$_->{nonterm_idx}, $_->{offset}, $_->{count}}" } @all_slices;
            $out .= _emit_c_array('const CMapSlice', 'cmap_slices', $total_slices, \@slice_vals);
        }
        else {
            $out .= "const CMapSlice cmap_slices[1] = { {0, 0, 0} }; /* empty */\n";
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

        push $_defines->@*, ['TOTAL_GOTO_ENTRIES', $total_entries];

        my $out = '';

        # goto_entries: typedef is now in the header; emit array only
        if ($total_entries > 0) {
            my @entry_vals = map { "{" . _c_string($_->{symbol_key}) . ", $_->{target_state}}" } @flat_entries;
            $out .= _emit_c_array('const GotoEntry', 'goto_entries', $total_entries, \@entry_vals);
        }
        else {
            $out .= "const GotoEntry goto_entries[1] = { {NULL, -1} }; /* empty */\n";
        }

        $out .= _emit_c_array('const int', 'goto_state_offset', $num_states, \@so_vals);
        $out .= _emit_c_array('const int', 'goto_state_count',  $num_states, \@sc_vals);
        $out .= "\n";

        return $out;
    }

    # Emit prediction table arrays as static C.
    # For each grammar nonterminal (sorted for determinism): collect prediction items
    # from the LR0DFA, flatten into a single PredictionEntry array, and emit per-nonterminal
    # offset/count arrays for O(1) lookup in the C consumer.
    # skip_count is the number of nullable symbols skipped to reach this prediction item.
    method _emit_prediction_tables() {
        my @rule_names = sort map { $_->name() } $grammar->@*;

        # Only include nonterminals that have prediction items in the DFA
        my @pred_nonterms;
        my @pred_offsets;
        my @pred_counts;
        my @flat_entries;   # { core_id, skip_count }

        for my $name (@rule_names) {
            my $items = $lr0_dfa->prediction_items_for($name);
            next unless defined $items && scalar $items->@*;

            push @pred_offsets, scalar @flat_entries;
            push @pred_counts,  scalar $items->@*;
            push @pred_nonterms, $name;

            for my $item ($items->@*) {
                my ($core_id, $skip_symbols) = $item->@*;
                push @flat_entries, { core_id => $core_id, skip_count => scalar $skip_symbols->@* };
            }
        }

        my $total_entries  = scalar @flat_entries;
        my $num_pred_nts   = scalar @pred_nonterms;

        push $_defines->@*, ['TOTAL_PRED_ENTRIES', $total_entries];
        push $_defines->@*, ['NUM_PRED_NONTERMS',  $num_pred_nts];

        my $out = '';

        # prediction_entries: typedef is now in the header; emit array only
        if ($total_entries > 0) {
            my @entry_vals = map { "{$_->{core_id}, $_->{skip_count}}" } @flat_entries;
            $out .= _emit_c_array('const PredictionEntry', 'prediction_entries', $total_entries, \@entry_vals);
        }
        else {
            $out .= "const PredictionEntry prediction_entries[1] = { {0, 0} }; /* empty */\n";
        }

        my @nt_vals = map { _c_string($_) } @pred_nonterms;
        if ($num_pred_nts > 0) {
            $out .= _emit_c_array('const char *', 'prediction_nonterminals', $num_pred_nts, \@nt_vals);
            $out .= _emit_c_array('const int',    'prediction_offset',       $num_pred_nts, \@pred_offsets);
            $out .= _emit_c_array('const int',    'prediction_count',        $num_pred_nts, \@pred_counts);
        }
        else {
            $out .= "const char *prediction_nonterminals[1] = { NULL }; /* empty */\n";
            $out .= "const int prediction_offset[1] = { 0 }; /* empty */\n";
            $out .= "const int prediction_count[1] = { 0 }; /* empty */\n";
        }

        $out .= "\n";
        return $out;
    }

    # Emit the nullable nonterminal set as a C string array.
    # Iterates all grammar rule names sorted for determinism, checks each against
    # the LR0DFA nullable set, and emits a flat array of quoted names.
    method _emit_nullable_set() {
        my @rule_names = sort map { $_->name() } $grammar->@*;
        my @nullable_names = grep { $lr0_dfa->is_nullable($_) } @rule_names;

        my $num_nullable = scalar @nullable_names;
        push $_defines->@*, ['NUM_NULLABLE', $num_nullable];

        my $out = '';

        if ($num_nullable > 0) {
            my @nt_vals = map { _c_string($_) } @nullable_names;
            $out .= _emit_c_array('const char *', 'nullable_nonterminals', $num_nullable, \@nt_vals);
        }
        else {
            $out .= "const char *nullable_nonterminals[1] = { NULL }; /* empty */\n";
        }

        $out .= "\n";
        return $out;
    }

    # Emit the dfa_tables.h header.
    # Generates #pragma once, includes, all #define constants (collected by the
    # _emit_* methods via $_defines), all struct typedefs, and extern const
    # declarations for every array defined in dfa_tables.c.
    # Must be called after all _emit_* methods have run (so $_defines is populated).
    method _emit_header() {
        my $out = '';

        $out .= "#pragma once\n";
        $out .= "/* Include this header after chalk.h (which provides perl.h) */\n";
        $out .= "\n";

        # All #define constants, in the order they were collected by _emit_* methods.
        $out .= "/* Counts */\n";
        for my $pair ($_defines->@*) {
            $out .= "#define $pair->[0] $pair->[1]\n";
        }
        $out .= "\n";

        # Struct typedefs (must appear before the extern declarations that reference them).
        $out .= "/* Typedefs */\n";
        $out .= "typedef struct { int pattern_idx; int offset; int count; } TMapSlice;\n";
        $out .= "typedef struct { int nonterm_idx; int offset; int count; } CMapSlice;\n";
        $out .= "typedef struct { const char *symbol_key; int target_state; } GotoEntry;\n";
        $out .= "typedef struct { int core_id; int skip_count; } PredictionEntry;\n";
        $out .= "\n";

        # extern const declarations for all arrays defined in dfa_tables.c.
        $out .= "/* CoreItemIndex arrays */\n";
        $out .= "extern const char *ci_rule_names[];\n";
        $out .= "extern const int ci_alt_idxs[];\n";
        $out .= "extern const int ci_dots[];\n";
        $out .= "extern const int ci_is_complete[];\n";
        $out .= "extern const int ci_advance[];\n";
        $out .= "extern const int ci_to_state[];\n";
        $out .= "extern const char *ci_symbol_after_pattern[];\n";
        $out .= "extern const int ci_symbol_after_is_ref[];\n";
        $out .= "\n";

        $out .= "/* Terminal map arrays */\n";
        $out .= "extern const int tmap_core_ids[];\n";
        $out .= "extern const char *tmap_patterns[];\n";
        $out .= "extern const TMapSlice tmap_slices[];\n";
        $out .= "extern const int tmap_state_offset[];\n";
        $out .= "extern const int tmap_state_count[];\n";
        $out .= "\n";

        $out .= "/* Completion map arrays */\n";
        $out .= "extern const int cmap_core_ids[];\n";
        $out .= "extern const char *cmap_nonterminals[];\n";
        $out .= "extern const CMapSlice cmap_slices[];\n";
        $out .= "extern const int cmap_state_offset[];\n";
        $out .= "extern const int cmap_state_count[];\n";
        $out .= "\n";

        $out .= "/* Goto table arrays */\n";
        $out .= "extern const GotoEntry goto_entries[];\n";
        $out .= "extern const int goto_state_offset[];\n";
        $out .= "extern const int goto_state_count[];\n";
        $out .= "\n";

        $out .= "/* Prediction table arrays */\n";
        $out .= "extern const PredictionEntry prediction_entries[];\n";
        $out .= "extern const char *prediction_nonterminals[];\n";
        $out .= "extern const int prediction_offset[];\n";
        $out .= "extern const int prediction_count[];\n";
        $out .= "\n";

        $out .= "/* Nullable set */\n";
        $out .= "extern const char *nullable_nonterminals[];\n";

        return $out;
    }

    # generate_distribution wraps generate() with the standard distribution shape.
    method generate_distribution($ir) {
        return $self->generate($ir);
    }

}
