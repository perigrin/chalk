# ABOUTME: Runner for the mdtest-style typed-IR corpus: parses .md topic files into cases,
# ABOUTME: asserts behavior (perl oracle), constructs SoN graphs from ir blocks, and checks L verdict.
package Chalk::CodeGen::Harness::MdtestCorpus;

use 5.42.0;
use utf8;

use Carp         qw(croak);
use File::Temp   qw(tempfile);
use Scalar::Util qw(blessed);
use JSON::PP;

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::Modulo;
use Chalk::IR::Node::Coerce;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::PadAccess;
use Chalk::IR::Node::Return;
use Chalk::IR::Graph::TypedInvariant;
use Chalk::IR::ClassInfo;
use Chalk::IR::MethodInfo;
use Chalk::MOP::Field;

use Chalk::CodeGen::Harness::LLVMDriver;
use Chalk::CodeGen::Harness::BehaviorRecord;
use Chalk::CodeGen::Harness::TypeTag;

# The Perl 5.42.0 binary used as the oracle.
my $PERL_BIN = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";

# ---------------------------------------------------------------------------
# PUBLIC API
# ---------------------------------------------------------------------------

# parse_file($md_path) -> \@cases
#
# Parses a markdown topic file into an ordered list of case hashrefs.
# Each case hashref has:
#   title       => string (the ## heading text)
#   source      => string (content of ```perl block, or undef)
#   behavior    => string (raw content of ```behavior block, or undef)
#   ir          => string (raw content of ```ir block, or undef)
#   source_pos  => [line_start, line_end]  -- for capture-mode rewriting
#   behavior_pos => [line_start, line_end]
#   ir_pos       => [line_start, line_end]
sub parse_file {
    my ($class, $md_path) = @_;
    croak "parse_file: path must be defined" unless defined $md_path;
    croak "parse_file: file not found: $md_path" unless -f $md_path;

    open my $fh, '<:utf8', $md_path
        or croak "parse_file: cannot open '$md_path': $!";
    my @lines = <$fh>;
    close $fh;
    chomp @lines;

    return _split_into_cases(\@lines);
}

# run_case($case, \%opts) -> \%result
#
# Runs a single case through all three checks:
#   1. BEHAVIOR: run source under perl; assert or capture behavior block.
#   2. IR-SHAPE: structural subset match of ir block against the real graph.
#   3. L-VERDICT: run the real graph through LLVMDriver; assert L: line.
#
# opts:
#   graph_for    => coderef($tag) -> $return_node  (required for IR + L checks)
#   capture_mode => bool  (if true: fill empty behavior block from perl oracle)
#   md_path      => str   (required for capture-mode rewrite)
#
# Returns a hashref:
#   title        => string
#   behavior     => { verdict: PASS|CAPTURED|FAIL, actual: $S, declared: $D }
#   ir_shape     => { verdict: PASS|FAIL|SKIP, missing: [...] }   (SKIP if no ir block)
#   l_verdict    => { verdict: PASS|FAIL|SKIP, actual: str, declared: str }
#   overall      => PASS | FAIL | CAPTURED
#   fail_reasons => [...]
sub run_case {
    my ($class, $case, $opts) = @_;
    $opts //= {};

    my @fail_reasons;
    my $overall = 'PASS';

    # ---- Check 1: BEHAVIOR ----
    my $behavior_result = _run_behavior_check($case, $opts, \@fail_reasons);

    # ---- Check 2: IR-SHAPE ----
    my $ir_result = _run_ir_shape_check($case, $opts, \@fail_reasons);

    # ---- Check 3: L-VERDICT ----
    my $l_result = _run_l_verdict_check($case, $opts, \@fail_reasons);

    if (@fail_reasons) {
        $overall = 'FAIL';
    } elsif ($behavior_result->{verdict} eq 'CAPTURED') {
        $overall = 'CAPTURED';
    }

    return {
        title        => $case->{title},
        behavior     => $behavior_result,
        ir_shape     => $ir_result,
        l_verdict    => $l_result,
        overall      => $overall,
        fail_reasons => \@fail_reasons,
    };
}

# run_file($md_path, \%opts) -> \@results
#
# Convenience: parse a .md file and run each case through run_case.
# See run_case for opts.
sub run_file {
    my ($class, $md_path, $opts) = @_;
    $opts //= {};

    my $cases = $class->parse_file($md_path);
    my @results;
    for my $case (@$cases) {
        push @results, $class->run_case($case, { %$opts, md_path => $md_path });
    }
    return \@results;
}

# rewrite_behavior($md_path, $case, $actual_S) -> void
#
# In capture mode: rewrite the .md file to fill in the behavior block for $case
# from the actual BehaviorRecord $actual_S.  The block is replaced in-place.
# Dies if the case has no behavior_pos or if the file cannot be rewritten.
sub rewrite_behavior {
    my ($class, $md_path, $case, $actual_S) = @_;
    croak "rewrite_behavior: md_path required" unless defined $md_path;
    croak "rewrite_behavior: case must have behavior_pos"
        unless defined $case->{behavior_pos};

    open my $fh, '<:utf8', $md_path
        or croak "rewrite_behavior: cannot open '$md_path': $!";
    my @lines = <$fh>;
    close $fh;
    chomp @lines;

    my ($start, $end) = @{ $case->{behavior_pos} };
    # $start is the line index of the ```behavior line
    # $end   is the line index of the closing ``` line
    # We replace the content lines between them (start+1 .. end-1)

    my @new_content = _serialize_behavior($actual_S);
    splice @lines, $start + 1, ($end - $start - 1), @new_content;

    open my $out, '>:utf8', $md_path
        or croak "rewrite_behavior: cannot write '$md_path': $!";
    for my $line (@lines) {
        print $out $line, "\n";
    }
    close $out;
}

# build_graph_from_ir($ir_block) -> $return_node_or_undef
#
# Parses a named-SSA ir block and CONSTRUCTS a real SoN graph from it.
# Each node line maps to a NodeFactory->make() call.  The constructed graph
# is then available for TypedInvariant checking and LLVMDriver lowering.
#
# Grammar handled:
#   %name = Constant(value) :Repr
#   %name = Op(%a, %b) :Repr          -- binary/unary data ops
#   %name = Coerce(%x : From -> To) :Repr
#   %name = VarDecl(%nameconst, %init) :Repr
#   %name = PadAccess(%vd, "$varname") :Repr
#   return %name
#   control: %a -> %b                  -- control_in chain
#   L: GREEN | L: GAP(reason)         -- verdict (not a node; parsed separately)
#
# A pure-GAP block (only an L: GAP(...) line, no node lines) returns undef.
sub build_graph_from_ir {
    my ($class, $ir_block) = @_;
    croak "build_graph_from_ir: ir_block must be defined" unless defined $ir_block;

    my $factory    = Chalk::IR::NodeFactory->new;
    my %sym;              # %name -> node object
    my $return_name;      # the %name handed to 'return'
    my @control_seq;      # ordered list of %names from 'control:' line
    my @branch_edges;     # [ [$from_name, $to_name], ... ] from branch_control: lines
    my @loop_backedges;   # [ [$phi_name, $val_name], ... ] from loop_backedge: lines
    my $has_nodes   = false;

    for my $raw_line (split /\n/, $ir_block) {
        # Strip trailing inline comments and whitespace
        (my $line = $raw_line) =~ s/\s*#.*$//;
        $line =~ s/^\s+|\s+$//g;
        next unless length $line;

        # Skip L: verdict lines (handled by parse_l_verdict_from_ir)
        next if $line =~ /^L:/;

        # 'return %name'
        if ($line =~ /^return\s+(%\w+)\s*$/) {
            $return_name = $1;
            next;
        }

        # 'control: %a -> %b -> ...'
        if ($line =~ /^control:\s+(.+)$/) {
            my @parts = split /\s*->\s*/, $1;
            @control_seq = map { s/^\s+|\s+$//gr } @parts;
            next;
        }

        # 'branch_control: %from -> %to'
        # Sets $to->set_control_in($from), wiring $to as a consumer of $from.
        # Use for branching control edges (if-branch bodies, loop bodies) that
        # cannot be expressed as a flat sequential chain.
        if ($line =~ /^branch_control:\s+(%\w+)\s*->\s*(%\w+)\s*$/) {
            push @branch_edges, [$1, $2];
            next;
        }

        # 'loop_backedge: %phi -> %body_val'
        # Sets the backedge (inputs[1]) of a loop Phi node after the body
        # computation is defined, resolving the circular reference inherent
        # in SSA loop phis. Calls phi->set_backedge($body_val).
        if ($line =~ /^loop_backedge:\s+(%\w+)\s*->\s*(%\w+)\s*$/) {
            push @loop_backedges, [$1, $2];
            next;
        }

        # '%name = ...' binding lines
        if ($line =~ /^(%\w+)\s*=\s*(.+)$/) {
            my ($name, $rhs) = ($1, $2);
            $has_nodes = true;

            # Parse optional :Repr at end of rhs
            my $repr;
            if ($rhs =~ s/\s*:(\w+)\s*$//) {
                $repr = $1;
            }

            my $node = _build_node_from_rhs($factory, \%sym, $name, $rhs);
            unless (defined $node) {
                croak "build_graph_from_ir: could not build node for line: $raw_line";
            }

            # Only call set_representation on IR nodes (ClassInfo/MethodInfo/MOP::Field
            # are metadata objects that do not have this method).
            $node->set_representation($repr)
                if defined $repr && $node->can('set_representation');
            $sym{$name} = $node;
            next;
        }

        # Unrecognized line (not a comment, not empty, not a known form)
        croak "build_graph_from_ir: unrecognized ir line: $raw_line";
    }

    # Pure-GAP: no node lines were found
    return undef unless $has_nodes;

    # Build the Return node
    croak "build_graph_from_ir: no 'return %name' line found"
        unless defined $return_name;
    croak "build_graph_from_ir: 'return $return_name' but '$return_name' not defined"
        unless exists $sym{$return_name};

    my $ret = $factory->make_cfg('Return', inputs => [ $sym{$return_name} ]);

    # Wire control_in chain: the control: line lists nodes in dependency order.
    # The last node in the chain is the control predecessor of Return.
    # Each node's control_in is set to the previous node in the sequence.
    if (@control_seq) {
        # Set Return's control_in to the last listed control node
        my $prev_ctrl = undef;
        for my $ctrl_name (@control_seq) {
            croak "build_graph_from_ir: control: references undefined '$ctrl_name'"
                unless exists $sym{$ctrl_name};
            my $ctrl_node = $sym{$ctrl_name};
            $ctrl_node->set_control_in($prev_ctrl) if defined $prev_ctrl;
            $prev_ctrl = $ctrl_node;
        }
        $ret->set_control_in($sym{ $control_seq[-1] });
    }

    # Wire branch_control edges: set_control_in for branching control paths.
    for my $edge (@branch_edges) {
        my ($from_name, $to_name) = @$edge;
        croak "build_graph_from_ir: branch_control: from '$from_name' undefined"
            unless exists $sym{$from_name};
        croak "build_graph_from_ir: branch_control: to '$to_name' undefined"
            unless exists $sym{$to_name};
        $sym{$to_name}->set_control_in($sym{$from_name});
    }

    # Wire loop_backedge edges: set inputs[1] on Phi nodes for loop-carried values.
    for my $edge (@loop_backedges) {
        my ($phi_name, $val_name) = @$edge;
        croak "build_graph_from_ir: loop_backedge: phi '$phi_name' undefined"
            unless exists $sym{$phi_name};
        croak "build_graph_from_ir: loop_backedge: value '$val_name' undefined"
            unless exists $sym{$val_name};
        my $phi_node = $sym{$phi_name};
        my $val_node = $sym{$val_name};
        croak "build_graph_from_ir: loop_backedge: '$phi_name' is not a Phi node"
            unless $phi_node->can('operation') && $phi_node->operation eq 'Phi';
        $phi_node->set_backedge($val_node);
    }

    # Post-build pass: wire Region->head back-pointers.
    # For each Region node in the symbol table, look at its Proj inputs to
    # find the If or Loop node that produced those Projs. Call set_region on
    # that If/Loop so the LLVM backend can traverse the structure.
    for my $sym_name (keys %sym) {
        my $node = $sym{$sym_name};
        next unless $node->can('operation') && $node->operation eq 'Region';
        my $inputs = $node->inputs // [];
        for my $inp (@$inputs) {
            next unless defined $inp && $inp->can('operation');
            next unless $inp->operation eq 'Proj';
            # The Proj's inputs[0] is the If or Loop node.
            my $proj_inputs = $inp->inputs // [];
            my $parent = $proj_inputs->[0];
            next unless defined $parent && $parent->can('set_region');
            $parent->set_region($node);
            last;    # One set_region call per Region is enough.
        }
    }

    return $ret;
}

# parse_l_verdict_from_ir($ir_block) -> 'GREEN' | 'GAP'
#
# Extracts the L: verdict line from a named-SSA ir block.
# Returns 'GREEN' if the L: GREEN line is present, 'GAP' for L: GAP(...),
# or 'GREEN' as the default when no L: line is present.
sub parse_l_verdict_from_ir {
    my ($class, $ir_block) = @_;
    return 'GREEN' unless defined $ir_block;

    for my $line (split /\n/, $ir_block) {
        $line =~ s/\s*#.*$//;
        $line =~ s/^\s+|\s+$//g;
        if ($line =~ /^L:\s*(GREEN|GAP)/i) {
            return uc($1);
        }
    }
    return 'GREEN';
}

# ---------------------------------------------------------------------------
# PRIVATE: constructive node builder helpers
# ---------------------------------------------------------------------------

# _build_node_from_rhs($factory, \%sym, $name, $rhs) -> $node
#
# Parses the RHS of a %name = RHS line and builds the corresponding IR node.
# $rhs has already had :Repr stripped.
sub _build_node_from_rhs {
    my ($factory, $sym, $name, $rhs) = @_;

    # Coerce(%x : From -> To)
    if ($rhs =~ /^Coerce\(\s*(%\w+)\s*:\s*(\w+)\s*->\s*(\w+)\s*\)/) {
        my ($input_name, $from, $to) = ($1, $2, $3);
        croak "build_graph_from_ir: Coerce references undefined '$input_name' at $name"
            unless exists $sym->{$input_name};
        return $factory->make('Coerce',
            inputs    => [ $sym->{$input_name} ],
            from_repr => $from,
            to_repr   => $to,
        );
    }

    # Constant(undef) — the undef literal (must be checked before the general Constant case)
    if ($rhs =~ /^Constant\(\s*undef\s*\)$/) {
        return $factory->make('Constant', value => undef, const_type => 'undef');
    }

    # Constant("value", const_type: "kind") — explicit const_type override
    # (e.g. a qr// literal: Constant("foo", const_type: "regex") :Regex).
    if ($rhs =~ /^Constant\(\s*"(.*)"\s*,\s*const_type:\s*"(\w+)"\s*\)$/) {
        return $factory->make('Constant', value => $1, const_type => $2);
    }

    # Constant(value)  — value may be a number, negative number, or quoted string
    if ($rhs =~ /^Constant\(\s*(.*?)\s*\)$/) {
        my $val_raw = $1;
        # Quoted string: Constant("$x") or Constant('x')
        if ($val_raw =~ /^"(.*)"$/ || $val_raw =~ /^'(.*)'$/) {
            my $str_val = $1;
            return $factory->make('Constant', value => $str_val, const_type => 'string');
        }
        # Bare value (integer or negative integer)
        return $factory->make('Constant', value => $val_raw, const_type => 'integer');
    }

    # VarDecl(%nameconst, %init)
    if ($rhs =~ /^VarDecl\(\s*(%\w+)\s*,\s*(%\w+)\s*\)$/) {
        my ($nc_name, $init_name) = ($1, $2);
        croak "build_graph_from_ir: VarDecl name ref '$nc_name' undefined at $name"
            unless exists $sym->{$nc_name};
        croak "build_graph_from_ir: VarDecl init ref '$init_name' undefined at $name"
            unless exists $sym->{$init_name};
        return $factory->make('VarDecl',
            inputs => [ $sym->{$nc_name}, $sym->{$init_name} ]);
    }

    # PadAccess(%vd, "$varname")
    if ($rhs =~ /^PadAccess\(\s*(%\w+)\s*,\s*"([^"]*)"\s*\)$/) {
        my ($vd_name, $varname) = ($1, $2);
        croak "build_graph_from_ir: PadAccess VarDecl '$vd_name' undefined at $name"
            unless exists $sym->{$vd_name};
        return $factory->make('PadAccess',
            targ    => 0,
            varname => $varname,
            inputs  => [ $sym->{$vd_name} ]);
    }

    # General N-ary ops with optional keyword args:
    #   Op(%a, %b, %c)                    — N input references, no attrs
    #   Op(%a, %b, key: value)            — inputs + keyword attrs
    #   Op(%a, key: "quoted", key2: bare) — mixed inputs and attrs
    #
    # Grammar: Op(arg, arg, ...) where each arg is either:
    #   %name        — an input reference (resolved from symbol table)
    #   key: value   — a keyword attr (passed to make() as a named pair)
    # Values may be a quoted string "..." or a bare token.
    if ($rhs =~ /^(\w+)\(\s*(.*)\s*\)$/s) {
        my ($op, $args_raw) = ($1, $2);

        # Split on commas, respecting double-quoted strings (don't split inside "...").
        # e.g. param_names: "left,right" must not be split at the comma inside quotes.
        my @raw_args = _split_args_respecting_quotes($args_raw);

        my @inputs;
        my %attrs;

        for my $arg (@raw_args) {
            $arg =~ s/^\s+|\s+$//g;
            next unless length $arg;

            if ($arg =~ /^(%\w+)$/) {
                # Input reference
                my $ref = $1;
                croak "build_graph_from_ir: $op input '$ref' undefined at $name"
                    unless exists $sym->{$ref};
                push @inputs, $sym->{$ref};
            } elsif ($arg =~ /^(\w+)\s*:\s*"(.*)"$/s) {
                # Keyword attr: key: "quoted string"
                $attrs{$1} = $2;
            } elsif ($arg =~ /^(\w+)\s*:\s*\[([^\]]*)\]$/) {
                # Keyword attr: key: [%a, %b, %c] — list of node refs
                my ($key, $list_raw) = ($1, $2);
                my @refs;
                for my $item (split /\s*,\s*/, $list_raw) {
                    $item =~ s/^\s+|\s+$//g;
                    next unless length $item;
                    croak "build_graph_from_ir: $op list-attr '$key' item '$item' is not a %ref at $name"
                        unless $item =~ /^%\w+$/;
                    croak "build_graph_from_ir: $op list-attr '$key' item '$item' undefined at $name"
                        unless exists $sym->{$item};
                    push @refs, $sym->{$item};
                }
                $attrs{$key} = \@refs;
            } elsif ($arg =~ /^(\w+)\s*:\s*(%\w+)$/) {
                # Keyword attr: key: %node_ref — resolve to node object
                my ($key, $ref) = ($1, $2);
                croak "build_graph_from_ir: $op kwarg '$key: $ref' references undefined '$ref' at $name"
                    unless exists $sym->{$ref};
                $attrs{$key} = $sym->{$ref};
            } elsif ($arg =~ /^(\w+)\s*:\s*(\S+)$/) {
                # Keyword attr: key: bare_token
                $attrs{$1} = $2;
            } else {
                croak "build_graph_from_ir: $op cannot parse arg '$arg' at $name";
            }
        }

        # Phi node: NodeFactory::make('Phi', ...) expects region => $node, values => [...].
        # When built via general N-ary form, we have inputs => [...] and region => $node
        # (already resolved above). Remap to the Phi-specific call shape.
        if ($op eq 'Phi') {
            my $region = delete $attrs{region};
            return $factory->make('Phi', region => $region, values => \@inputs, %attrs);
        }

        # Call(name='new'): param_names attr is a comma-separated string -> arrayref.
        # e.g. param_names: "name" -> ['name']; param_names: "" -> []
        # (The pre-convergence New/FieldDef special-cases are gone — those node
        # types were deleted in R3; the factory croaks on them.)
        if ($op eq 'Call' && ($attrs{name} // '') eq 'new') {
            if (exists $attrs{param_names}) {
                my $pn = $attrs{param_names};
                if (!defined $pn || $pn eq '') {
                    $attrs{param_names} = [];
                }
                else {
                    $attrs{param_names} = [ split /\s*,\s*/, $pn ];
                }
            }
            else {
                $attrs{param_names} = [];
            }
        }

        # MethodInfo: construct a Chalk::IR::MethodInfo (not a hash-consed IR node).
        # Stored in %sym so ClassInfo can reference it. Not passed to $factory->make().
        if ($op eq 'MethodInfo') {
            my $mi_name     = $attrs{name}        // croak "MethodInfo missing name at $name";
            my $body_node   = $attrs{body_node};   # may be undef (resolved node or raw)
            my $return_repr = $attrs{return_repr}; # may be undef
            return Chalk::IR::MethodInfo->new(
                name        => $mi_name,
                body        => [],
                return_type => $return_repr,
                body_node   => $body_node,
                return_repr => $return_repr,
            );
        }

        # ClassInfo: construct Chalk::IR::ClassInfo directly.
        if ($op eq 'ClassInfo') {
            my $ci_name   = $attrs{name}    // croak "ClassInfo missing name at $name";
            my $ci_parent = $attrs{parent};
            # parent: "" -> undef, else string value
            $ci_parent = undef if defined $ci_parent && $ci_parent eq '';
            my $ci_methods   = $attrs{methods}   // [];
            my $ci_fields    = $attrs{fields}    // [];
            my $ci_parent_ci = $attrs{parent_ci};  # optional ClassInfo object reference
            # adjusts: each node ref in the list is the body node for one ADJUST block.
            # Wrap each as a single-element arrayref for registry's body_nodes shape.
            my $ci_adj_nodes = $attrs{adjusts} // [];
            my $ci_adjusts   = [ map { [$_] } @$ci_adj_nodes ];
            return Chalk::IR::ClassInfo->new(
                name      => $ci_name,
                parent    => $ci_parent,
                parent_ci => $ci_parent_ci,
                methods   => (ref $ci_methods eq 'ARRAY' ? $ci_methods : [$ci_methods]),
                fields    => (ref $ci_fields  eq 'ARRAY' ? $ci_fields  : [$ci_fields]),
                adjusts   => $ci_adjusts,
            );
        }

        return $factory->make($op, inputs => \@inputs, %attrs);
    }

    # MOP::Field: construct a Chalk::MOP::Field (not a hash-consed IR node).
    # Handled outside the general N-ary block because the op name contains '::'.
    if ($rhs =~ /^MOP::Field\(\s*(.*)\s*\)$/s) {
        my $args_raw = $1;
        my @raw_args = _split_args_respecting_quotes($args_raw);
        my %attrs;
        for my $arg (@raw_args) {
            $arg =~ s/^\s+|\s+$//g;
            next unless length $arg;
            if ($arg =~ /^(\w+)\s*:\s*"(.*)"$/) {
                $attrs{$1} = $2;
            } elsif ($arg =~ /^(\w+)\s*:\s*(%\w+)$/) {
                my ($key, $ref) = ($1, $2);
                croak "MOP::Field kwarg '$key: $ref' references undefined '$ref' at $name"
                    unless exists $sym->{$ref};
                $attrs{$key} = $sym->{$ref};
            } elsif ($arg =~ /^(\w+)\s*:\s*(\S+)$/) {
                $attrs{$1} = $2;
            } else {
                croak "MOP::Field cannot parse arg '$arg' at $name";
            }
        }
        # Translate param/reader booleans to attributes list
        my @field_attrs;
        push @field_attrs, ':param'   if ($attrs{param}   // 'false') eq 'true';
        push @field_attrs, ':reader'  if ($attrs{reader}  // 'false') eq 'true';
        my $has_default   = ($attrs{has_default}   // 'false') eq 'true';
        my $default_value = $attrs{default_value};
        return Chalk::MOP::Field->new(
            name          => ($attrs{name}    // croak "MOP::Field missing name at $name"),
            sigil         => '$',
            class         => undef,
            fieldix       => (defined $attrs{fieldix} ? $attrs{fieldix} + 0 : 0),
            has_default   => $has_default,
            default_value => $default_value,
            type          => $attrs{type},
            attributes    => \@field_attrs,
        );
    }

    croak "build_graph_from_ir: could not parse RHS '$rhs' for $name";
}

# _split_args_respecting_quotes($args_raw) -> @args
#
# Splits a comma-separated argument list but does NOT split inside double-quoted
# strings or square bracket lists. This handles cases like param_names: "left,right"
# where the comma inside the quotes is part of the value, and methods: [%m1, %m2]
# where the comma inside the brackets is part of the list.
sub _split_args_respecting_quotes {
    my ($str) = @_;
    my @parts;
    my $current   = '';
    my $in_quote  = 0;
    my $bracket_depth = 0;
    for my $i (0 .. length($str) - 1) {
        my $ch = substr($str, $i, 1);
        if ($ch eq '"' && !$in_quote) {
            $in_quote = 1;
            $current .= $ch;
        }
        elsif ($ch eq '"' && $in_quote) {
            $in_quote = 0;
            $current .= $ch;
        }
        elsif ($ch eq '[' && !$in_quote) {
            $bracket_depth++;
            $current .= $ch;
        }
        elsif ($ch eq ']' && !$in_quote) {
            $bracket_depth--;
            $current .= $ch;
        }
        elsif ($ch eq ',' && !$in_quote && $bracket_depth == 0) {
            push @parts, $current;
            $current = '';
        }
        else {
            $current .= $ch;
        }
    }
    push @parts, $current if length($current) || @parts;
    return @parts;
}

# ---------------------------------------------------------------------------
# PRIVATE: markdown parsing
# ---------------------------------------------------------------------------

sub _split_into_cases {
    my ($lines) = @_;

    my @cases;
    my $current_case;
    my $in_fence    = 0;
    my $fence_lang  = '';
    my $fence_start = -1;
    my @fence_body;

    for my $i (0 .. $#$lines) {
        my $line = $lines->[$i];

        if (!$in_fence) {
            # Start a new case on ## headings
            if ($line =~ /^##\s+(.+)$/) {
                # Save any in-progress case
                push @cases, $current_case if defined $current_case;
                $current_case = {
                    title        => $1,
                    source       => undef,
                    behavior     => undef,
                    ir           => undef,
                    source_pos   => undef,
                    behavior_pos => undef,
                    ir_pos       => undef,
                };
                next;
            }

            # Opening fence: ```lang
            if ($line =~ /^```(\w*)$/) {
                $fence_lang  = $1;
                $fence_start = $i;
                @fence_body  = ();
                $in_fence    = 1;
                next;
            }
        } else {
            # Closing fence
            if ($line =~ /^```$/) {
                $in_fence = 0;
                if (defined $current_case) {
                    my $content = join("\n", @fence_body);
                    my $pos     = [$fence_start, $i];
                    if ($fence_lang eq 'perl' || $fence_lang eq 'chalk') {
                        $current_case->{source}     = $content;
                        $current_case->{source_pos} = $pos;
                    } elsif ($fence_lang eq 'behavior') {
                        $current_case->{behavior}     = $content;
                        $current_case->{behavior_pos} = $pos;
                    } elsif ($fence_lang eq 'ir') {
                        $current_case->{ir}     = $content;
                        $current_case->{ir_pos} = $pos;
                    }
                }
                $fence_lang = '';
                next;
            }
            push @fence_body, $line;
        }
    }

    # Save the last in-progress case
    push @cases, $current_case if defined $current_case;

    return \@cases;
}

# ---------------------------------------------------------------------------
# PRIVATE: behavior check
# ---------------------------------------------------------------------------

sub _run_behavior_check {
    my ($case, $opts, $fail_reasons) = @_;

    my $source = $case->{source};
    unless (defined $source && $source =~ /\S/) {
        push @$fail_reasons, "case '$case->{title}': no source block";
        return { verdict => 'FAIL', actual => undef, declared => undef };
    }

    # Run source under perl to capture actual behavior; stash value for L-verdict check
    my ($actual_val, $run_error) = _run_expr_under_perl($source);
    if (defined $run_error) {
        push @$fail_reasons, "case '$case->{title}': perl oracle failed: $run_error";
        return { verdict => 'FAIL', actual => undef, declared => undef,
                 error => $run_error };
    }
    # Stash so _run_l_verdict_check can compare lli output against perl without
    # re-running perl or requiring a separate perl_oracle_for callback.
    $case->{_perl_actual} = $actual_val;

    my $behavior_text = $case->{behavior} // '';
    my $is_empty = ($behavior_text !~ /\S/ || $behavior_text =~ /^\s*#\s*capture\s*$/m);

    if ($is_empty && $opts->{capture_mode}) {
        # Capture mode: fill in the behavior block from perl oracle
        if (defined $opts->{md_path}) {
            __PACKAGE__->rewrite_behavior($opts->{md_path}, $case,
                _make_behavior_record($actual_val));
        }
        return { verdict => 'CAPTURED', actual => $actual_val, declared => undef };
    }

    if ($is_empty) {
        # Empty behavior block but not in capture mode: treat as PASS (no assertion)
        return { verdict => 'PASS', actual => $actual_val, declared => undef };
    }

    # Non-empty: parse and assert
    my $declared = _parse_behavior_block($behavior_text);
    my ($match, $reason) = _behavior_matches($actual_val, $declared);
    if ($match) {
        return { verdict => 'PASS', actual => $actual_val, declared => $declared };
    } else {
        push @$fail_reasons,
            "case '$case->{title}': behavior mismatch: $reason "
            . "(perl says '$actual_val', declared '" . ($declared->{return} // '?') . "')";
        return { verdict => 'FAIL', actual => $actual_val, declared => $declared,
                 reason => $reason };
    }
}

# _run_expr_under_perl($source) -> ($value_string, $error_or_undef)
#
# Wraps the source snippet in a minimal program that evaluates it in scalar
# context and prints the result.  Returns (result_string, undef) on success,
# or (undef, error_message) on failure.
sub _run_expr_under_perl {
    my ($source) = @_;

    # Strip comment lines from source (# source etc.)
    (my $clean_source = $source) =~ s/^\s*#[^\n]*\n//gm;
    $clean_source =~ s/^\s+|\s+$//g;

    # The oracle emits a TYPE-TAGGED canonical string so Bool is distinguishable
    # from its Str coercion (is_bool discriminates). Tags: Bool:1/Bool: Int:N
    # Num:%g Str:<val> Undef: -- lli must print the same tag from its known repr.
    # The tagging logic is the canonical rule from Chalk::CodeGen::Harness::TypeTag.
    my $tag_fragment = Chalk::CodeGen::Harness::TypeTag::oracle_perl_fragment();
    my $program = <<"END_PROGRAM";
use 5.42.0;
use utf8;

my \$_result = do { $clean_source };

$tag_fragment
END_PROGRAM

    my ($fh, $tmpfile) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $program;
    close $fh;

    my $stdout = qx($PERL_BIN $tmpfile 2>&1);
    my $exit   = $? >> 8;

    if ($exit != 0) {
        chomp $stdout;
        return (undef, "exit $exit: $stdout");
    }

    chomp $stdout;
    return ($stdout, undef);
}

# _parse_behavior_block($text) -> \%declared
# Parses lines like "return: 3", "context: scalar", "stdout: ..." into a hashref.
sub _parse_behavior_block {
    my ($text) = @_;
    my %d;
    for my $line (split /\n/, $text) {
        next if $line =~ /^\s*#/;  # skip comment lines
        next unless $line =~ /\S/;
        if ($line =~ /^\s*(\w+(?:-\w+)*)\s*:\s*(.*)$/) {
            my ($key, $val) = ($1, $2);
            $val =~ s/\s+$//;
            $d{$key} = $val;
        }
    }
    return \%d;
}

# _behavior_matches($actual_tagged, \%declared) -> ($bool, $reason)
#
# Both sides are type-tagged (e.g. "Int:5", "Bool:", "Str:hello").
# The perl oracle ($actual_tagged) always emits a tag via _run_expr_under_perl.
# The declared return value may be:
#   - Already tagged (e.g. "Bool:", "Int:5") — compare as-is.
#   - A plain untagged value (e.g. "5", "hello") — infer a tag using the same
#     heuristic as the oracle (without is_bool, so plain numbers become Int:/Num:,
#     and plain strings become Str:). This keeps existing behavior blocks green.
sub _behavior_matches {
    my ($actual, $declared) = @_;

    my $declared_return = $declared->{return};
    unless (defined $declared_return) {
        return (true, '');  # no return assertion
    }

    # Compute a tag for the declared return value if it is not already tagged.
    my $decl_tagged = _infer_tag($declared_return);

    # Compare tags exactly.
    if ($actual eq $decl_tagged) {
        return (true, '');
    }
    return (false, "tag mismatch: got '$actual', expected '$decl_tagged' (declared: '$declared_return')");
}

# _infer_tag($declared_str) -> tagged string
#
# Delegates to Chalk::CodeGen::Harness::TypeTag::infer_tag — the single
# source of truth for the declared-value tag rule. See TypeTag for the full
# rule specification.
sub _infer_tag {
    my ($val) = @_;
    return Chalk::CodeGen::Harness::TypeTag::infer_tag($val);
}

sub _make_behavior_record {
    my ($val) = @_;
    return Chalk::CodeGen::Harness::BehaviorRecord->new(
        return_values     => [defined $val ? $val : ()],
        wantarray_context => 'scalar',
        stdout            => '',
        stderr            => '',
        object_state      => {},
    );
}

sub _serialize_behavior {
    my ($record) = @_;
    my @lines;
    my $vals = $record->return_values;
    if (@$vals) {
        push @lines, "return: $vals->[0]";
    } else {
        push @lines, "return: undef";
    }
    push @lines, "context: " . ($record->wantarray_context // 'scalar');
    return @lines;
}

# ---------------------------------------------------------------------------
# PRIVATE: IR-shape check (constructive: builds graph from ir block)
# ---------------------------------------------------------------------------

sub _run_ir_shape_check {
    my ($case, $opts, $fail_reasons) = @_;

    my $ir_text = $case->{ir};
    unless (defined $ir_text && $ir_text =~ /\S/) {
        return { verdict => 'SKIP', missing => [], reason => 'no ir block' };
    }

    # Determine if this is a pure-GAP block (no buildable graph)
    my $declared_verdict = __PACKAGE__->parse_l_verdict_from_ir($ir_text);
    my $is_pure_gap      = _is_pure_gap_block($ir_text);

    if ($is_pure_gap) {
        # Pure-GAP: no nodes to build or validate — structural check passes trivially.
        return { verdict => 'PASS', missing => [], reason => 'pure-GAP block; no graph to check' };
    }

    # Build the graph from the ir block
    my $return_node;
    eval { $return_node = __PACKAGE__->build_graph_from_ir($ir_text) };
    if ($@) {
        my $err = $@;
        push @$fail_reasons,
            "case '$case->{title}': ir block failed to build graph: $err";
        return { verdict => 'FAIL', missing => [], error => $err };
    }
    unless (defined $return_node) {
        return { verdict => 'SKIP', missing => [], reason => 'build_graph_from_ir returned undef' };
    }

    # Run the TypedInvariant on the built graph to catch ill-typed blocks
    my @all_nodes = _collect_all_nodes($return_node);
    my $inv = Chalk::IR::Graph::TypedInvariant->check(\@all_nodes);
    unless ($inv->{ok}) {
        my $violations_str = join('; ', map { $_->{message} } @{ $inv->{violations} });
        push @$fail_reasons,
            "case '$case->{title}': built graph fails TypedInvariant: $violations_str";
        return { verdict => 'FAIL', missing => [], violations => $inv->{violations} };
    }

    return { verdict => 'PASS', missing => [], built => true };
}

# _is_pure_gap_block($ir_text) -> bool
# A pure-GAP block has an L: GAP(...) line and NO %name = ... node lines.
sub _is_pure_gap_block {
    my ($ir_text) = @_;
    my $has_node_lines = false;
    for my $line (split /\n/, $ir_text) {
        $line =~ s/\s*#.*$//;
        $line =~ s/^\s+|\s+$//g;
        next unless length $line;
        next if $line =~ /^L:/;
        next if $line =~ /^return\s/;
        next if $line =~ /^control:/;
        if ($line =~ /^%\w+\s*=/) {
            $has_node_lines = true;
            last;
        }
    }
    return !$has_node_lines;
}

# _collect_all_nodes($return_node) -> @nodes
# Collects all reachable nodes from a Return node (data + control), deduped.
sub _collect_all_nodes {
    my ($return_node) = @_;
    my %visited;
    my @nodes;
    _collect_nodes_recursive($return_node, \%visited, \@nodes);
    return @nodes;
}

sub _collect_nodes_recursive {
    my ($node, $visited, $nodes) = @_;
    return unless defined $node;
    my $id = $node->id;
    return if $visited->{$id}++;
    push @$nodes, $node;
    if ($node->can('inputs') && defined $node->inputs) {
        _collect_nodes_recursive($_, $visited, $nodes) for $node->inputs->@*;
    }
    if ($node->can('control_in') && defined $node->control_in) {
        _collect_nodes_recursive($node->control_in, $visited, $nodes);
    }
}

# _parse_ir_block($text) -> { nodes => [...], l_verdict => str }
#
# Parses node-by-role lines:
#   Constant(1) :Int        -> { kind=>'Constant', value=>'1', repr=>'Int' }
#   Constant(-7) :Int       -> { kind=>'Constant', value=>'-7', repr=>'Int' }
#   Coerce(Int -> Num)      -> { kind=>'Coerce', from=>'Int', to=>'Num' }
#   Add(Int, Int) :Int      -> { kind=>'Add', arg_reprs=>['Int','Int'], repr=>'Int' }
#   Return(Add)             -> { kind=>'Return', input_kind=>'Add' }
#   L: GREEN                -> l_verdict = 'GREEN'
#   L: GAP(reason)          -> l_verdict = 'GAP', gap_reason = 'reason'
sub _parse_ir_block {
    my ($text) = @_;

    my @nodes;
    my $l_verdict;
    my $gap_reason;

    for my $line (split /\n/, $text) {
        # Strip inline comments
        $line =~ s/\s*#.*$//;
        next unless $line =~ /\S/;

        # L: verdict line
        if ($line =~ /^\s*L:\s*(GREEN|GAP(?:\(([^)]*)\))?)\s*$/) {
            my $verdict = $1;
            $gap_reason = $2 if defined $2;
            $l_verdict  = ($verdict =~ /^GAP/) ? 'GAP' : 'GREEN';
            next;
        }

        # Coerce(From -> To)
        if ($line =~ /^\s*Coerce\(\s*(\w+)\s*->\s*(\w+)\s*\)/) {
            push @nodes, {
                kind  => 'Coerce',
                from  => $1,
                to    => $2,
                raw   => "Coerce($1 -> $2)",
            };
            next;
        }

        # NodeKind(args) :Repr  or  NodeKind(args)
        if ($line =~ /^\s*(\w+)\(([^)]*)\)(?:\s*:(\w+))?/) {
            my ($kind, $args_raw, $repr) = ($1, $2, $3);
            my @args = map { s/^\s+|\s+$//gr } split /,/, $args_raw;
            push @nodes, {
                kind      => $kind,
                args      => \@args,
                repr      => $repr,
                raw       => "$kind($args_raw)" . (defined $repr ? " :$repr" : ''),
            };
            next;
        }
    }

    return {
        nodes     => \@nodes,
        l_verdict => $l_verdict // 'GREEN',
        gap_reason => $gap_reason,
    };
}

# _collect_node_signatures($return_node) -> @signatures
#
# Walks the reachable graph from a Return node and collects a list of
# node-descriptor hashrefs (kind, repr, value, from, to, ...) for matching.
sub _collect_node_signatures {
    my ($return_node) = @_;
    my %visited;
    my @sigs;
    _visit_node($return_node, \%visited, \@sigs);
    return @sigs;
}

sub _visit_node {
    my ($node, $visited, $sigs) = @_;
    return unless defined $node;

    my $id = $node->id;
    return if $visited->{$id}++;

    # Build the signature for this node
    my $kind = _node_kind($node);
    my $repr = ($node->can('representation')) ? $node->representation : undef;

    my %sig = (kind => $kind, repr => $repr);

    # For Constant nodes, capture the value
    if ($kind eq 'Constant' && $node->can('value')) {
        $sig{value} = $node->value;
    }

    # For Coerce nodes, capture from_repr and to_repr
    if ($kind eq 'Coerce') {
        $sig{from} = $node->can('from_repr') ? $node->from_repr : undef;
        $sig{to}   = $node->can('to_repr')   ? $node->to_repr   : undef;
    }

    # For arithmetic op nodes, capture input representations
    if ($node->can('inputs') && defined $node->inputs) {
        my @input_reprs = map {
            defined $_ && $_->can('representation') ? $_->representation : undef
        } $node->inputs->@*;
        $sig{input_reprs} = \@input_reprs;
    }

    push @$sigs, \%sig;

    # Recurse into inputs (data flow)
    if ($node->can('inputs') && defined $node->inputs) {
        for my $inp ($node->inputs->@*) {
            _visit_node($inp, $visited, $sigs) if defined $inp;
        }
    }

    # Recurse into control_in (control flow)
    if ($node->can('control_in') && defined $node->control_in) {
        _visit_node($node->control_in, $visited, $sigs);
    }
}

# _node_kind($node) -> string
# Returns the class's short name (last component after ::).
sub _node_kind {
    my ($node) = @_;
    my $class = ref($node) || blessed($node) || "$node";
    $class =~ s/.*:://;
    return $class;
}

# _find_node($req, \@real_nodes) -> bool
# Returns true if the real graph contains a node matching $req.
sub _find_node {
    my ($req, $real_nodes) = @_;

    for my $sig (@$real_nodes) {
        next unless $sig->{kind} eq $req->{kind};

        if ($req->{kind} eq 'Coerce') {
            next unless (defined $sig->{from} && $sig->{from} eq ($req->{from} // ''));
            next unless (defined $sig->{to}   && $sig->{to}   eq ($req->{to}   // ''));
            return true;
        }

        if ($req->{kind} eq 'Constant') {
            # Check value if provided in args
            if (defined $req->{args} && @{ $req->{args} }) {
                my $expected_val = $req->{args}[0];
                # Strip quotes if present
                $expected_val =~ s/^['"]|['"]$//g;
                next unless defined $sig->{value} && $sig->{value} eq $expected_val;
            }
        }

        if ($req->{kind} eq 'Return') {
            # Return node — check input kind if specified
            if (defined $req->{args} && @{ $req->{args} } && $req->{args}[0] ne '') {
                # Declared as Return(Add) — we just check a Return exists (relaxed subset match)
                # The input kind check would require extra traversal; just verify Return is present.
            }
        }

        # Check representation if declared
        if (defined $req->{repr}) {
            next unless defined $sig->{repr} && $sig->{repr} eq $req->{repr};
        }

        # Check input representations for arithmetic ops
        # e.g. Add(Int, Int) :Int requires inputs with Int repr
        if (defined $req->{args} && @{ $req->{args} }
            && $req->{kind} !~ /^(Constant|Return|Coerce)$/)
        {
            my @req_arg_reprs = grep { $_ =~ /^(Int|Num|Str|Bool|Scalar)$/ } @{ $req->{args} };
            if (@req_arg_reprs) {
                my @actual_reprs = grep { defined $_ } @{ $sig->{input_reprs} // [] };
                my $match = true;
                for my $i (0 .. $#req_arg_reprs) {
                    unless (defined $actual_reprs[$i] && $actual_reprs[$i] eq $req_arg_reprs[$i]) {
                        $match = false;
                        last;
                    }
                }
                next unless $match;
            }
        }

        return true;
    }
    return false;
}

# ---------------------------------------------------------------------------
# PRIVATE: L-verdict check (constructive: builds graph from ir block)
# ---------------------------------------------------------------------------

sub _run_l_verdict_check {
    my ($case, $opts, $fail_reasons) = @_;

    my $ir_text = $case->{ir};
    unless (defined $ir_text && $ir_text =~ /\S/) {
        return { verdict => 'SKIP', reason => 'no ir block' };
    }

    # Parse the declared L: verdict from the block
    my $decl        = __PACKAGE__->parse_l_verdict_from_ir($ir_text);
    my $is_pure_gap = _is_pure_gap_block($ir_text);

    # Pure-GAP block: no graph to lower; verify declared verdict is also GAP
    if ($is_pure_gap) {
        if ($decl eq 'GAP') {
            return { verdict => 'PASS', actual => 'GAP', declared => 'GAP',
                     note => 'pure-GAP block with declared GAP — consistent' };
        } else {
            push @$fail_reasons,
                "case '$case->{title}': L verdict mismatch — "
                . "pure-GAP block (no nodes) but declared '$decl'";
            return { verdict => 'FAIL', actual => 'GAP', declared => $decl };
        }
    }

    # Build the graph from the ir block
    my $return_node;
    eval { $return_node = __PACKAGE__->build_graph_from_ir($ir_text) };
    if ($@) {
        my $err = $@;
        push @$fail_reasons,
            "case '$case->{title}': L check: ir block failed to build graph: $err";
        return { verdict => 'FAIL', error => $err };
    }
    unless (defined $return_node) {
        # build_graph_from_ir returned undef (pure-GAP) — check declared is GAP
        if ($decl eq 'GAP') {
            return { verdict => 'PASS', actual => 'GAP', declared => 'GAP',
                     note => 'build_graph_from_ir returned undef, declared GAP matches' };
        }
        push @$fail_reasons,
            "case '$case->{title}': L verdict mismatch — "
            . "graph builds to undef (GAP) but declared '$decl'";
        return { verdict => 'FAIL', actual => 'GAP', declared => $decl };
    }

    # Run through LLVMDriver
    my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);

    # Classify the LLVMDriver result using the three-way distinction:
    #   GAP        = lowering DIED (marked_unsupported=1; no .ll was produced)
    #   MISCOMPILE = .ll was produced (ll_text defined) but lli rejected it (lli_exit != 0)
    #   GREEN      = .ll produced AND lli exited 0 AND emitted_for_every_construct=1
    #
    # The old single-branch !emitted_for_every_construct => GAP was wrong: it
    # conflated lowering-failure (GAP) with lowering-succeeded-but-lli-rejected
    # (MISCOMPILE), laundering real miscompiles as passing GAPs (F3).
    my $actual_verdict;
    if ($meta->{marked_unsupported}) {
        # Lowering threw — no .ll was produced at all.
        $actual_verdict = 'GAP';
    } elsif (defined $meta->{ll_text} && ($meta->{lli_exit} // 0) != 0) {
        # .ll was produced but lli rejected it — this is a MISCOMPILE, not a GAP.
        $actual_verdict = 'MISCOMPILE';
    } elsif ($meta->{emitted_for_every_construct}) {
        $actual_verdict = 'GREEN';
    } else {
        # Fallback: lowering did not mark unsupported but also did not
        # emit for every construct (partial lowering) — treat as GAP.
        $actual_verdict = 'GAP';
    }

    if ($actual_verdict ne $decl) {
        push @$fail_reasons,
            "case '$case->{title}': L verdict mismatch — "
            . "actual '$actual_verdict' but declared '$decl' "
            . ($actual_verdict eq 'GAP'
                ? "(gap_reason: " . ($meta->{gap_reason} // 'unknown') . ")"
                : ($actual_verdict eq 'MISCOMPILE'
                    ? "(lli_exit: " . ($meta->{lli_exit} // '?') . ")"
                    : ''));
        return { verdict => 'FAIL', actual => $actual_verdict, declared => $decl,
                 meta => $meta };
    }

    # For GREEN: verify lli output agrees with perl behavior oracle (from behavior check).
    # Both sides are type-tagged (e.g. "Int:5", "Bool:", "Num:3.14").
    # The perl oracle always emits a tag. The lli output must print the same tag.
    # Exact string comparison — no numeric tolerance needed (the tag encodes the type).
    if ($actual_verdict eq 'GREEN') {
        my $lli_out  = $L->return_values->[0] // '';
        my $expected = $opts->{perl_oracle_value} // $case->{_perl_actual};

        if (defined $expected && length $expected) {
            if ($lli_out ne $expected) {
                push @$fail_reasons,
                    "case '$case->{title}': L corner output '$lli_out' "
                    . "does not match perl oracle '$expected' (type-tagged compare)";
                return { verdict => 'FAIL', actual => $actual_verdict, declared => $decl,
                         lli_out => $lli_out, expected => $expected, meta => $meta };
            }
        }

        # Central mechanical libperl-free guard (G.2/F4):
        # A GREEN verdict certifies runtime-free — no libperl symbols allowed in the .ll.
        # This guard fires on EVERY GREEN regardless of which .t file invokes the harness,
        # replacing the absent/inconsistent per-.t unlike() calls (5/12 corpus files had none).
        #
        # Pattern covers: Perl_ (API functions), SV/AV/HV (type names),
        # sv_/av_/hv_ (API prefixes), PL_ (globals), newSV (constructor), libperl (link ref).
        #
        # H2 fix: apply the guard only to instruction/declaration lines, NOT to string-constant
        # payload lines.  A global constant like `@str_const_0 = ... c"an SV in a HV\00"`
        # legitimately contains "SV"/"HV" as English words inside the payload but is
        # not a libperl reference.  Strip lines that match the LLVM string-constant
        # global pattern before grepping so those payloads cannot false-match.
        my $ll_text = $meta->{ll_text} // '';
        # Remove the c"..." payload substring from string-constant global definitions.
        # CG2: strip ONLY the c"..." content (not the whole line) so a libperl symbol
        # in the global name or type annotation outside the payload is still visible.
        # Before: s/^[^\n]*\bconstant\b[^\n]*\bc"[^\n]*$//mg  (whole-line strip)
        # After:  s/\bc"[^"]*"//mg  (payload-only strip — preserves name, type, annotations)
        (my $ll_stripped = $ll_text) =~ s/\bc"[^"]*"//mg;
        if ($ll_stripped =~ /Perl_|\bSV\b|sv_|\bAV\b|\bHV\b|\bPL_|newSV|libperl/) {
            push @$fail_reasons,
                "case '$case->{title}': GREEN .ll contains a libperl symbol "
                . "(violates runtime-free contract) — check emitter for Perl C-API leak";
            return { verdict => 'FAIL', actual => $actual_verdict, declared => $decl,
                     meta => $meta, libperl_leak => 1 };
        }
    }

    return { verdict => 'PASS', actual => $actual_verdict, declared => $decl,
             meta => $meta };
}

1;
