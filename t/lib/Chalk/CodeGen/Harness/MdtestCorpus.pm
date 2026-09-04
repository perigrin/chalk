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
use Chalk::MOP;

use Chalk::CodeGen::Harness::LLVMDriver;
use Chalk::CodeGen::Harness::BehaviorRecord;
use Chalk::IR::Value;   # for `isa Chalk::IR::Value`
use Chalk::IR::Node;   # stamp reads gate on isa Chalk::IR::Node

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
#   2. IR-SHAPE: constructive self-consistency — build the graph FROM the ir
#      block and TypedInvariant-check it. (Matching a PRODUCER's real graph
#      against the block is shape_subset_check, used by the corpus-wide
#      B::SoN runner; run_case has no real-graph input.)
#   3. L-VERDICT: run the built graph through LLVMDriver; assert L: line.
#
# opts:
#   capture_mode => bool  (if true: fill empty behavior block from perl oracle)
#   md_path      => str   (required for capture-mode rewrite)
#
# Returns a hashref:
#   title        => string
#   behavior     => { verdict: PASS|CAPTURED|FAIL, actual: $S, declared: $D }
#   ir_shape     => { verdict: PASS|FAIL|SKIP|TODO, missing: [...] }
#                  (TODO if no ir block, or a pure-GAP block: both are work we
#                   intend to do, not a check that does not apply. SKIP stays
#                   for genuinely inapplicable cases -- an unbuildable or
#                   unwalkable spec, whose finding another leg reports.)
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
#                                 -> ($return_node, $mop) in list context
#
# Parses a named-SSA ir block and CONSTRUCTS a real SoN graph from it.
# Each node line maps to a NodeFactory->make() call.  The constructed graph
# is then available for TypedInvariant checking and LLVMDriver lowering.
#
# Class structure (019eb42a, MOP-direct): MOP::Class / MOP::Field /
# MOP::Method / MOP::Adjust lines declare onto a per-build Chalk::MOP,
# which is SEALED before return and handed to the backend via
# lower(mop => ...). Call lines name their class via `class: "Name"`
# (the class_name node attribute) — no metadata object rides as an input.
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
    my $build      = { mop => undef };   # per-build MOP, created lazily by MOP::Class lines
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

            my $node = _build_node_from_rhs($factory, \%sym, $name, $rhs, $build);
            unless (defined $node) {
                croak "build_graph_from_ir: could not build node for line: $raw_line";
            }

            # ASK WHETHER IT CAN CARRY A STAMP, NOT WHAT CLASS IT IS.
            #
            # This guard was `$node isa Chalk::IR::Value`, and that is the
            # WRONG QUESTION -- the same one that made commit 0cc04737 a
            # miscompile in the LLVM backend. `stamp` is declared on
            # Chalk::IR::Node (Node.pm:64), the BASE, so every node carries
            # one. But Chalk::IR::Value is a SIBLING of the value-producing
            # control nodes rather than their parent: Print, Proj, VarDecl and
            # ListAssign are each `:isa(Chalk::IR::Node)` DIRECTLY.
            #
            # So a declared `:Repr` on any of those four was silently DROPPED,
            # and the failure surfaced three steps later as "VarDecl reached
            # LLVM backend with NO representation (undef) -- fix TypeInference".
            # It named the wrong pass: TypeInference was fine, the spec block
            # said `:Int`, and this line threw it away. Measured on
            # t/bootstrap/corpus/logical.t, where L3/L3b/L4 all failed this way
            # while being GREEN in the real corpus gate.
            #
            # `isa Chalk::IR::Node` asks the question that actually matters and
            # still excludes the MOP metaobjects this guard was written for: they do
            # not inherit from Chalk::IR::Node at all. Deliberately NOT
            # can(...), which returns false for a method that was never
            # defined AND for one that was deleted -- a guard that degrades
            # silently is what turned 0cc04737 into a miscompile in the first
            # place.
            $node->set_stamp($repr)
                if defined $repr && $node isa Chalk::IR::Node;
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

    # Seal the per-build MOP (when class structure was declared): the
    # backend requires a sealed read surface.
    $build->{mop}->seal if defined $build->{mop};

    return wantarray ? ($ret, $build->{mop}) : $ret;
}

# parse_l_verdict_from_ir($ir_block) -> 'GREEN' | 'GAP' | 'DEVIATES'
#
# Extracts the L: verdict line from a named-SSA ir block.
# Returns 'GREEN' if the L: GREEN line is present, 'GAP' for L: GAP(...),
# 'DEVIATES' for L: DEVIATES(reason) expected=..., or 'GREEN' as the default
# when no L: line is present.
sub parse_l_verdict_from_ir {
    my ($class, $ir_block) = @_;
    return 'GREEN' unless defined $ir_block;

    for my $line (split /\n/, $ir_block) {
        $line =~ s/^\s+|\s+$//g;
        # NOTE: no comment-stripping here. A DEVIATES line's expected= value is
        # verbatim output and may legitimately contain a '#'.
        if ($line =~ /^L:\s*(GREEN|GAP|DEVIATES)/i) {
            return uc($1);
        }
    }
    return 'GREEN';
}

# parse_deviation_from_ir($ir_block) -> { reason, expected } or undef
#
# A DEVIATES case produces output that is LEGAL PERL but not byte-identical to
# what `perl` prints. Its contract is STRICTER than GREEN, not looser: the case
# must still lower and run, and its output must match the DECLARED string
# exactly. The gate stops comparing against `perl` and starts comparing against
# a value a human wrote down and justified.
#
# WHY THE LATITUDE EXISTS. Perl-the-language does not specify IV vs NV, and
# `perl` is not self-consistent about it:
#
#     literal 9007199254740993  ->  9007199254740993
#     2**53 + 1                 ->  9.00719925474099e+15
#     numerically equal?           YES     string equal?  NO
#
# Same value, two outputs, both correct Perl. Byte-identity with `perl` is
# therefore not a well-defined target for that value.
#
# WHY A DECLARED STRING RATHER THAN A NUMERIC COMPARISON. An earlier draft
# proposed asserting the two outputs compare `==` under perl semantics, which
# is stronger where it applies. It does not generalise: `==` is meaningful only
# for IV and NV (perigrin). Hash iteration order, string formatting and list
# output have no numeric comparison at all, and those are exactly the other
# cases a static compiler may legitimately deviate on. The declared string is
# the only mechanism that covers the whole class.
#
# THE RULE THAT DECIDES WHAT MAY USE THIS (perigrin): a deviation is legitimate
# when static compilation CANNOT do what `perl` does, and illegitimate when
# chalk simply HAS NOT YET. Both fields below are mandatory because that
# distinction lives in the reason: a deviation with nothing to check against,
# or with no stated justification, is a defect wearing a legitimising label.
sub parse_deviation_from_ir {
    my ($class, $ir_block) = @_;
    return undef unless defined $ir_block;

    for my $line (split /\n/, $ir_block) {
        $line =~ s/^\s+|\s+$//g;
        next unless $line =~ /^L:\s*DEVIATES/i;

        my ($reason) = $line =~ /^L:\s*DEVIATES\s*\(([^)]*)\)/i;
        die "corpus: L: DEVIATES needs a reason naming the Perl-level "
          . "guarantee that permits the deviation -- got: $line\n"
            unless defined $reason && $reason =~ /\S/;

        my ($expected) = $line =~ /\bexpected=(.*)$/;
        die "corpus: L: DEVIATES needs expected=<output>; without it the case "
          . "would accept ANY output, which is strictly weaker than GREEN "
          . "-- got: $line\n"
            unless defined $expected && $expected =~ /\S/;

        return { reason => $reason, expected => $expected };
    }
    return undef;
}

# ---------------------------------------------------------------------------
# PRIVATE: constructive node builder helpers
# ---------------------------------------------------------------------------

# _cook_dq_escapes($raw) -> $cooked
#
# Cooks the double-quotish escapes a spec ir-block string Constant may carry so
# its bytes match the producer's cooked graph (perl cooks "hi\n" to hi<LF> in
# op.c; the shape check compares Constant values byte-for-byte). Only the common
# escapes the corpus uses are handled — enough for print/string idioms.
sub _cook_dq_escapes {
    my ($raw) = @_;
    my %map = ( 'n' => "\n", 't' => "\t", 'r' => "\r", '0' => "\0",
                '\\' => "\\", '"' => '"' );
    $raw =~ s/\\([ntr0\\"])/$map{$1}/g;
    return $raw;
}

# _build_node_from_rhs($factory, \%sym, $name, $rhs, $build) -> $node
#
# Parses the RHS of a %name = RHS line and builds the corresponding IR node
# (or declares onto the per-build MOP for MOP::* lines, via $build->{mop}).
# $rhs has already had :Repr stripped.
sub _build_node_from_rhs {
    my ($factory, $sym, $name, $rhs, $build) = @_;

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
        # Double-quoted string: Constant("hi\n") — cook double-quotish escapes so
        # the spec Constant's bytes match the producer's cooked graph (perl cooks
        # "hi\n" to hi<LF> in op.c before B::SoN walks; the shape check compares
        # Constant values byte-for-byte, so an uncooked '\n' would false-FAIL).
        if ($val_raw =~ /^"(.*)"$/) {
            return $factory->make('Constant',
                value => _cook_dq_escapes($1), const_type => 'string');
        }
        # Single-quoted string: Constant('x') — literal, no escape cooking.
        if ($val_raw =~ /^'(.*)'$/) {
            return $factory->make('Constant', value => $1, const_type => 'string');
        }
        # Bare value (integer or negative integer). A ',' or ':' here means the
        # value was mis-parsed — e.g. an unquoted const_type override
        # (Constant(x, const_type: foo)) or a stray delimiter — which would
        # otherwise become a garbage integer Constant. Fail loudly instead.
        croak "build_graph_from_ir: Constant bare value '$val_raw' contains a "
            . "',' or ':' — quote the value or use the "
            . "Constant(\"v\", const_type: \"kind\") form at $name"
            if $val_raw =~ /[,:]/;
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

        my ($inputs_ref, $attrs_ref) = _parse_op_args($op, $args_raw, $sym, $name);
        my @inputs = @$inputs_ref;
        my %attrs  = %$attrs_ref;

        # Call lines name their class via `class: "Name"` — translate to the
        # node's class_name attribute (019eb42a MOP-direct contract).
        if ($op eq 'Call' && exists $attrs{class}) {
            $attrs{class_name} = delete $attrs{class};
        }

        # Phi node: NodeFactory::make('Phi', ...) expects region => $node, values => [...].
        # When built via general N-ary form, we have inputs => [...] and region => $node
        # (already resolved above). Remap to the Phi-specific call shape.
        if ($op eq 'Phi') {
            my $region = delete $attrs{region};

            # predecessors: [%proj0, %proj1] -- WHICH ARM each value arrives
            # from. A list-valued attr, so it needs the bracket form: the
            # general kwarg grammar is one value per key, and a bare
            # `predecessors: %a, %b` silently binds %a and leaves %b to be
            # swallowed as a positional INPUT (measured: it produced a 3-value
            # Phi over a 2-input Region, and predecessors held a lone Proj).
            if (defined(my $preds = $attrs{predecessors})) {
                croak "build_graph_from_ir: Phi predecessors must be a bracketed "
                    . "list, e.g. predecessors: [%proj0, %proj1], at $name"
                    unless ref $preds eq 'ARRAY';
                $attrs{predecessors} = $preds;
            }

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

        return $factory->make($op, inputs => \@inputs, %attrs);
    }

    # MOP::* lines (handled outside the general N-ary block because the op
    # name contains '::'): declare class structure onto the per-build
    # Chalk::MOP via the real declare_* API — the same accumulation the
    # parser performs. The MOP is sealed by build_graph_from_ir before
    # return and handed to the backend via lower(mop => ...).
    if ($rhs =~ /^MOP::(Class|Field|Method|Adjust)\(\s*(.*)\s*\)$/s) {
        my ($kind, $args_raw) = ($1, $2);
        my ($inputs, $attrs) = _parse_op_args("MOP::$kind", $args_raw, $sym, $name);

        # MOP::* lines carry all their data as kwargs (class:, name:, body:, ...).
        # A positional %ref input has no binding here and was silently discarded
        # before — croak so a mis-authored line fails loudly instead of dropping
        # the input.
        croak "build_graph_from_ir: MOP::$kind takes no positional inputs but got "
            . scalar(@$inputs) . " (use kwargs like body: %ref) at $name"
            if @$inputs;

        # MOP::Method reads name/return_repr/body; a 'params:' attr is not
        # consumed and would be silently ignored — croak rather than drop it.
        croak "build_graph_from_ir: MOP::Method 'params:' attr is not supported "
            . "(method params are not modeled by the harness) at $name"
            if $kind eq 'Method' && exists $attrs->{params};

        if ($kind eq 'Class') {
            $build->{mop} //= Chalk::MOP->new;
            my $cname = $attrs->{name} // croak "MOP::Class missing name at $name";
            my %opts;
            $opts{parent_name} = $attrs->{parent}
                if defined $attrs->{parent} && length $attrs->{parent};
            return $build->{mop}->declare_class($cname, %opts);
        }

        my $cls = $attrs->{class}
            // croak "MOP::$kind requires class: %cls at $name";

        if ($kind eq 'Field') {
            my @field_attrs;
            push @field_attrs, ':param'  if ($attrs->{param}  // 'false') eq 'true';
            push @field_attrs, ':reader' if ($attrs->{reader} // 'false') eq 'true';
            my $field = $cls->declare_field(
                ($attrs->{name} // croak "MOP::Field missing name at $name"),
                sigil         => '$',
                has_default   => (($attrs->{has_default} // 'false') eq 'true'),
                default_value => $attrs->{default_value},
                type          => $attrs->{type},
                attributes    => \@field_attrs,
            );
            # An explicit fieldix kwarg is asserted against the index derived
            # from declaration order — drift here would silently shift slots.
            if (defined $attrs->{fieldix} && $field->fieldix != $attrs->{fieldix}) {
                croak "MOP::Field '$attrs->{name}' declared fieldix $attrs->{fieldix} "
                    . "but declaration order derives " . $field->fieldix . " at $name";
            }
            return $field;
        }

        if ($kind eq 'Method') {
            my $repr = $attrs->{return_repr};
            my $m = $cls->declare_method(
                ($attrs->{name} // croak "MOP::Method missing name at $name"),
                (defined $repr ? (return_type => $repr) : ()),
            );
            # The method's lowering root is its graph's Return value.
            if (defined $attrs->{body}) {
                $m->graph->merge(
                    $factory->make_cfg('Return', inputs => [ $attrs->{body} ]));
            }
            return $m;
        }

        # MOP::Adjust: body statements thread control_in in list order so the
        # backend recovers statement order from the control chain.
        my $body = $attrs->{body} // [];
        $body = [$body] unless ref $body eq 'ARRAY';
        my $adj = $cls->declare_adjust();
        my $prev;
        for my $st (@$body) {
            $st->set_control_in($prev) if defined $prev;
            $adj->graph->merge($st);
            $prev = $st;
        }
        return $adj;
    }

    croak "build_graph_from_ir: could not parse RHS '$rhs' for $name";
}

# _parse_op_args($op, $args_raw, \%sym, $name) -> (\@inputs, \%attrs)
#
# Shared argument parser for Op(...) lines: positional %refs become inputs;
# key: "quoted" / key: %ref / key: [%a, %b] / key: bare become attrs.
sub _parse_op_args {
    my ($op, $args_raw, $sym, $name) = @_;

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
    return (\@inputs, \%attrs);
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
    my $is_gap   = __PACKAGE__->parse_l_verdict_from_ir($case->{ir} // '') eq 'GAP';
    my ($match, $reason) = _behavior_matches($actual_val, $declared, $is_gap);
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

# _run_expr_under_perl($source) -> ($stdout, $error_or_undef, $exit)
#
# Runs the case AS A PROGRAM and returns what it printed. A case states its own
# output with say/print; there is no wrapper and no type-tag epilogue.
#
# This used to wrap the source in `my $_result = do { ... }` plus a tagging
# fragment, which gave the snippet a VALUE CONTEXT that a program's top level
# does not have -- perl discards a bare trailing expression in void context --
# so this harness measured a contract no executable has. son-corpus-wide.t was
# flipped first; this is the same flip for the per-topic runners.
#
# STDERR is captured SEPARATELY rather than folded in with 2>&1: perl's warnings
# are not program output, and chalk emits none, so folding made any
# warning-producing case impossible to match.
sub _run_expr_under_perl {
    my ($source) = @_;

    # Strip comment lines from source (# source etc.)
    (my $clean_source = $source) =~ s/^\s*#[^\n]*\n//gm;
    $clean_source =~ s/^\s+|\s+$//g;

    my ($fh, $tmpfile) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $clean_source, "\n";
    close $fh;

    my ($efh, $etmp) = tempfile(SUFFIX => '.err', UNLINK => 1);
    close $efh;
    my $stdout = qx($PERL_BIN $tmpfile 2>$etmp);
    my $exit   = $? >> 8;
    chomp $stdout;

    # A nonzero exit is a RESULT (`exit 4`, `die`), not a harness failure -- the
    # same rule son-corpus-wide.t now uses. It is returned for comparison; only
    # a failure to RUN is an error.
    return ($stdout, undef, $exit);
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
    my ($actual, $declared, $is_gap) = @_;

    # A case is a PROGRAM: what it OUTPUTS is the assertion. The `return:` key
    # is vestigial -- it described a fragment's value, which a program does not
    # have (perl compiles a program's trailing statement in void context, and
    # the last value never reaches the exit status). 183 of the migrated cases
    # declare `return: Bool:1`, which is only "say returned true".
    #
    # So stdout: is authoritative when present. A case with neither key asserts
    # nothing, which _run_behavior_check's caller already treats as a pass.
    if (defined $declared->{stdout}) {
        my $expected = _cook_dq_escapes($declared->{stdout});
        $expected =~ s/\n\z//;   # match _run_expr_under_perl's single chomp
        return $actual eq $expected
            ? (true, '')
            : (false, "stdout mismatch: got '$actual', expected '$expected'");
    }

    # No stdout: declared, but a return: is. That is an UNMIGRATED case: its
    # source still ends in a bare value expression, which a program discards,
    # so it prints nothing and there is nothing to assert against. Say so
    # rather than passing silently -- a quiet fall-through here is the same
    # vacuity trap son-corpus-wide.t's non-vacuity check exists to stop.
    #
    # A GAP-DECLARED case is exempt: the migration transform deliberately skips
    # those (they are never lowered or run, so their source shape does not
    # matter), and demanding output from a case that documents an unsupported
    # construct would be this check inventing work rather than finding it.
    if (defined $declared->{return} && !$is_gap) {
        return (false,
            "unmigrated case: the behavior block declares `return:` but no "
          . "`stdout:`, and a program has no return value -- it printed "
          . "'$actual'. Migrate the source to say/print its value.");
    }

    return (true, '');   # nothing declared, nothing asserted
}

# Capture mode fills an empty behavior block from the oracle. Under the program
# contract the oracle's result IS what the case printed, so it is recorded as
# STDOUT -- recording it as a return value would write back the fragment shape
# this migration removed.
sub _make_behavior_record {
    my ($val) = @_;
    return Chalk::CodeGen::Harness::BehaviorRecord->new(
        return_values     => [],
        wantarray_context => 'scalar',
        stdout            => (defined $val ? $val : ''),
        stderr            => '',
        object_state      => {},
    );
}

sub _serialize_behavior {
    my ($record) = @_;
    my @lines;

    # A case is a PROGRAM: what it PRINTS is the assertion, so capture writes a
    # `stdout:` line. It used to write `return:`, which described a fragment's
    # value -- a program has none -- so a captured block was immediately
    # rejected by _behavior_matches as unmigrated.
    #
    # Escapes are written back in their source form (\n, \t) so the round trip
    # is stable: _cook_dq_escapes reads them on the way in, and a captured
    # block that re-cooked its own literal newline would grow a line each pass.
    my $out = $record->stdout // '';
    $out =~ s/\\/\\\\/g;
    $out =~ s/\n/\\n/g;
    $out =~ s/\t/\\t/g;
    push @lines, "stdout: $out";

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
        return { verdict => 'TODO', missing => [], reason => 'no ir block' };
    }

    # Determine if this is a pure-GAP block (no buildable graph)
    my $declared_verdict = __PACKAGE__->parse_l_verdict_from_ir($ir_text);
    my $is_pure_gap      = _is_pure_gap_block($ir_text);

    if ($is_pure_gap) {
        # Pure-GAP: no nodes to build or validate. That is not a passing shape --
        # it is a spec that has not been written yet, which is WORK WE INTEND TO
        # DO. Reporting it as PASS made an absent spec read as a satisfied one.
        return { verdict => 'TODO', missing => [], reason => 'pure-GAP block; no graph to check' };
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
    my $inv = Chalk::IR::Graph::TypedInvariant->check_nodes(\@all_nodes);
    unless ($inv->{ok}) {
        my $violations_str = join('; ', map { $_->{message} } @{ $inv->{violations} });
        push @$fail_reasons,
            "case '$case->{title}': built graph fails TypedInvariant: $violations_str";
        return { verdict => 'FAIL', missing => [], violations => $inv->{violations} };
    }

    return { verdict => 'PASS', missing => [], built => true };
}

# shape_subset_check($class, $ir_text, $return_node) -> { verdict, missing }
#
# The SHAPE leg of the Phase 4 triple contract: every node signature the
# case's ir block declares must exist in the real graph (loaded from B::SoN
# or any other producer). The spec graph is built from the ir block by the
# constructive builder; both graphs are reduced to node signatures (kind +
# declared repr + Constant value + Coerce from/to) and each spec signature
# must find a match among the real graph's — subset semantics, since a real
# producer graph carries pads, VarDecls, and control shape the hand-authored
# blocks omit.
#
# Verdicts: PASS (all spec signatures found, or nothing to enforce),
# FAIL (missing => [readable signatures]), SKIP (no ir block, or the spec
# block itself is unbuildable — unverifiable, NOT a pass).
# perl's &&, ||, // are operand-RETURNING (`$a && $b` yields $a or $b), so
# their result repr is the operand's — which B::SoN leaves unstamped, letting
# the loader infer it. The corpus spec pins the operand type (:Int). Accept an
# unstamped real And/Or/DefinedOr against the spec's declared repr. Read by
# both the multiset _sig_match and the rooted _pair_match.
my %_OPERAND_RETURNING = (And => 1, Or => 1, DefinedOr => 1);

# spec_invariant_check($ir_text) -> { verdict => PASS|FAIL|SKIP, reason => ... }
#
# Run the IR invariants over the graph the ir BLOCK describes, not the one the
# producer emitted. Those are different graphs and only the producer's was ever
# checked (son-corpus-wide.t runs TypedInvariant on `$g`), so a spec could
# assert a shape the IR forbids and stay green on all three legs.
#
# Measured on D1f: deleting its `predecessors:` line left every leg green, and
# so did SWAPPING it to [%proj1, %proj0] -- an inverted arm pairing, the exact
# defect class of 44d1fa8c and 9ce43cdd. The ir block is the half of a corpus
# case a human reads; a spec that teaches the wrong shape is worse than no spec.
#
# SKIP rather than FAIL when the block cannot be built: unbuildability is the
# shape leg's finding to report, and double-reporting it here would make one
# defect look like two.
sub spec_invariant_check {
    my ($class, $ir_text) = @_;

    return { verdict => 'TODO', reason => 'no ir block' }
        unless defined $ir_text && $ir_text =~ /\S/;

    # A declared-GAP block has no nodes to check. It is not a spec failure, and
    # it is not a passing shape either -- but it is not an inapplicable check
    # either: the spec is simply unwritten. TODO records the intent to write it,
    # where SKIP claimed the check did not apply here.
    return { verdict => 'TODO', reason => 'pure-GAP block; no graph to check' }
        if _is_pure_gap_block($ir_text);

    my $spec_return;
    eval { $spec_return = __PACKAGE__->build_graph_from_ir($ir_text) };
    return { verdict => 'SKIP', reason => 'spec block unbuildable: ' . ($@ || 'builder returned undef') }
        if $@ || !defined $spec_return;

    # Reuse the collector _run_ir_shape_check already uses. That path built the
    # same check years ago but is now reachable only from run_case, which the
    # per-topic suites stopped driving when the corpus gate superseded them --
    # so the check existed and ran on nothing real.
    my @nodes = eval { _collect_all_nodes($spec_return) };
    return { verdict => 'SKIP', reason => "spec graph unwalkable: $@" } if $@;

    my $inv = eval { Chalk::IR::Graph::TypedInvariant->check_nodes(\@nodes) }
        // { ok => 0, violations => [{ message => "died: $@" }] };

    # A SPEC IS A SUBSET, so not every invariant applies to it. The shape leg
    # is a subset match by design -- a case names the nodes it is ABOUT and
    # omits the rest -- and the control-chain invariant reads that omission as
    # a broken effect chain.
    #
    # Measured: 49 of 199 cases with Print/Call nodes leave at least one of
    # them off their `control:` line, across every topic (class-simple,
    # field-basic, method-simple, ...). Applying the chain check to spec blocks
    # failed 36 cases on the FIRST run -- all of them this one message, none of
    # them a real defect. That is the convention, not a backlog.
    #
    # The invariants that DO apply are the ones about a node's own consistency
    # with what the spec wrote down: Phi/Region arity, Phi predecessors,
    # per-position reprs. Those are statements the spec makes, so the spec owns
    # them.
    my @violations = grep { ($_->{message} // '') !~ /broken effect chain/ }
                     ($inv->{violations} // [])->@*;

    return { verdict => 'PASS', reason => '' } unless @violations;
    return {
        verdict => 'FAIL',
        reason  => join('; ', map { $_->{message} } @violations),
    };
}

sub shape_subset_check {
    my ($class, $ir_text, $return_node) = @_;

    return { verdict => 'TODO', missing => [], reason => 'no ir block' }
        unless defined $ir_text && $ir_text =~ /\S/;
    return { verdict => 'SKIP', missing => [], reason => 'no real graph' }
        unless defined $return_node;
    if (_is_pure_gap_block($ir_text)) {
        # Only a declared-GAP block is excused; a node-line-free block claiming
        # L: GREEN is a malformed spec, not a free pass. The excused case is a
        # TODO rather than a PASS: there is no shape to enforce BECAUSE none has
        # been written, and calling that green makes absence look like success.
        return __PACKAGE__->parse_l_verdict_from_ir($ir_text) eq 'GAP'
            ? { verdict => 'TODO', missing => [], reason => 'pure-GAP block; no shape to enforce' }
            : { verdict => 'SKIP', missing => [], reason => 'malformed spec: no node lines but not a declared GAP' };
    }

    my $spec_return;
    eval { $spec_return = __PACKAGE__->build_graph_from_ir($ir_text) };
    if ($@ || !defined $spec_return) {
        my $why = $@ || 'builder returned undef';
        return { verdict => 'SKIP', missing => [], reason => "spec block unbuildable: $why" };
    }

    # Fold-satisfaction (zhi 019f2a50): perl constant-folds literal arithmetic
    # in op.c before B::SoN walks, so `1 + 2` loads as a single Constant(3),
    # not Add(1, 2). The corpus keeps the unfolded operation shape (it names
    # the op under test); a foldable op over all-literal NUMERIC Constants is
    # satisfied by a real Constant of the folded value. The op, and any input
    # (Coerce wrapper / operand Constant) whose every spec consumer is a
    # subsumed fold op, are dropped by id — a literal shared with a non-fold
    # consumer keeps its signature. A producer that does NOT fold (Chalk) still
    # matches the literal shape directly. Rule recorded in
    # docs/plans/2026-06-07-mdtest-corpus-format-draft.md.
    my $folded = _fold_satisfied_ids($spec_return, $return_node);

    # Propagation-satisfaction (zhi 019f2a50): perl's optree copy/const-
    # propagates lexical pads away before B::SoN walks, so `my $x = 1; $x`
    # loads as just Constant(1) — no VarDecl/PadAccess/name-Constant. The
    # corpus keeps the pad-explicit shape (it names the lexical idiom); the
    # pad scaffolding (name-Constant + VarDecl + PadAccess) is subsumed ONLY
    # when the real graph actually propagated it away (has no pad node). The
    # bound VALUE stays required, so a propagated real graph must still carry
    # the right value. A producer that KEEPS the pad (Chalk) is NOT conceded:
    # its pad nodes must match the spec including repr — so a mis-typed kept
    # pad still FAILs.
    my %satisfied = %$folded;
    _mark_pad_scaffolding($spec_return, $return_node, \%satisfied);

    # Assignment + if/else-select propagation (zhi 019f2d47): perl propagates a
    # pure scalar rebind's value to the read site (no Assign survives) and a
    # pure-value branch into a select (no If survives). Subsume that scaffolding
    # only when the real graph actually propagated it away; effectful stores and
    # genuine branches stay required. Rule in the corpus format doc.
    _mark_assign_select_propagation($spec_return, $return_node, \%satisfied);

    # Deref-scaffolding (zhi 019f1bda): perl's aggregate deref ($r->[0]) is an
    # implicit rv2av/rv2hv (an OpMap SKIP), so B::SoN emits Subscript(aggregate,
    # idx) directly with no PostfixDeref. The corpus keeps the explicit
    # PostfixDeref shape; subsume it when the real graph has none. A producer
    # that KEEPS the deref must match it (a real PostfixDeref stays required).
    _mark_deref_scaffolding($spec_return, $return_node, \%satisfied);

    # Coerce-to-Boolean absorption (zhi L4): perl's ! (and other truthiness ops)
    # coerce their operand internally, so B::SoN emits Not(operand) directly
    # with no explicit Coerce(X -> Boolean). The corpus keeps the explicit Coerce;
    # subsume it when its sole consumer is a truthiness op and the real graph
    # carries no such Coerce.
    _mark_coerce_absorption($spec_return, $return_node, \%satisfied);

    my @spec = _collect_node_signatures($spec_return, \%satisfied);
    my @real = _collect_node_signatures($return_node);

    # Match most-constrained spec signatures first so a lax sig (undef
    # fields are unchecked) cannot consume the one real node a stricter
    # same-kind sibling needed — greedy first-fit would false-FAIL there.
    # ponytail: this only bites lax-vs-strict same-kind sibling collisions
    # (e.g. an unstamped Add and an :Int Add contending for one real :Int
    # Add — _sig_match(Add) discriminates on kind+repr only). No current
    # corpus case hits it; the sort is a proven-reachable hedge (verified
    # against greedy order), not mystery defense. Upgrade path if it grows
    # load-bearing: bipartite matching (see 019f2af2 rooted-matching item).
    my @ordered = sort { _sig_specificity($b) <=> _sig_specificity($a) } @spec;
    my @missing = map  { _sig_str($_) }
                  grep { !_sig_match($_, \@real) } @ordered;
    return { verdict => 'FAIL', missing => \@missing }
        if @missing;

    # Rooted-wiring gate (zhi 019f2af2 item 2): the multiset check above proves
    # every declared node EXISTS in the real graph, but is edge-blind — it
    # passes a right-kinds/wrong-WIRING graph (operand swap, dropped store,
    # buried fold constant, root wrapping). AND a rooted walk: the spec Return
    # value must MATCH the real Return value operand-by-position, seeing through
    # the same satisfaction rules as transparent wrappers. If the walk rejects
    # the wiring, FAIL even though the multiset held.
    unless (_rooted_match($spec_return, $return_node, \%satisfied)) {
        return { verdict => 'FAIL', missing => ['<rooted wiring mismatch at return value>'] };
    }

    return { verdict => 'PASS', missing => [] };
}

# ---------------------------------------------------------------------------
# PRIVATE: rooted-wiring match (edge-precise, position-locked)
# ---------------------------------------------------------------------------

# _rooted_match($spec_return, $real_return, \%satisfied) -> bool
#
# The wiring leg of the shape contract. Both arguments are Return nodes; the
# value operand is inputs[0]. The spec's resolved return value must MATCH the
# real's resolved return value at the return position (NO subset-descent into
# real operands there — that is the H3 fix: a real return that WRAPS the spec
# value, e.g. Add(a-b, 100), is rejected). Sub-values are matched positionally,
# seeing through the satisfaction rules (subsumed pad/coerce/deref/fold/store)
# as transparent value-equivalences.
sub _rooted_match {
    my ($spec_return, $real_return, $satisfied) = @_;
    my $spec_val = _return_value($spec_return);
    my $real_val = _return_value($real_return);
    return true unless defined $spec_val;   # nothing to enforce

    # A PROGRAM has no return value: its Return's value operand is the Undef
    # constant (perl compiles a program's trailing statement in void context,
    # and the last value never reaches the exit status). Its observable
    # contract is the EFFECT CHAIN, and the Return's control_in is the last
    # effect — measured, that is the Print for every program shape.
    #
    # Rooting at control_in there is not a relaxation: without it, matching a
    # spec `return %p` against an Undef value operand fails every program case,
    # and simply DROPPING the return line from the ir block is worse — the
    # `return true unless defined $spec_val` above would skip this leg
    # entirely, so 168 cases would go green while checking strictly less. The
    # wiring coverage that the value walk gave a fragment is what the control
    # walk gives a program.
    if (_is_valueless_return($real_val)) {
        my $real_effect = $real_return->can('control_in')
            ? $real_return->control_in : undef;
        return false unless defined $real_effect && blessed($real_effect);
        $real_val = $real_effect;
    }

    return false unless defined $real_val;

    my $ctx = {
        satisfied    => $satisfied,
        pad_multi    => _pad_multi_assigned($spec_return),
        pairing      => {},   # (spec_id\0real_id) pairs in progress — cycle guard
    };
    return _node_match($spec_val, $real_val, $ctx);
}

# _return_value($return_node) -> the value operand (inputs[0]) or undef.
sub _return_value {
    my ($n) = @_;
    return undef unless blessed($n) && $n->can('inputs') && $n->inputs->@*;
    return $n->inputs->[0];
}

# _is_valueless_return($value_node) -> true when the Return carries no value.
#
# The producer gives a PROGRAM's Return the Undef constant it falls back to when
# nothing is on the stack (perl5-son a3f66e9). That is the marker: an Undef
# CONSTANT in the return position means "this unit produced no value", as
# opposed to a computed node that happens to be undef-typed.
sub _is_valueless_return {
    my ($v) = @_;
    return false unless blessed($v) && $v->can('operation');
    return false unless $v->operation eq 'Constant';
    return false unless $v isa Chalk::IR::Value;
    return (($v->stamp // '') eq 'Undef') ? true : false;
}

# _pad_multi_assigned($spec_return) -> { vardecl_id => 1 }
#
# The set of pads (keyed by their VarDecl node id) whose value at a read is a
# BRANCH MERGE the spec cannot name — resolving to {any}. A pad merges when it
# is written by 2+ distinct stores, OR by a single store that is CONDITIONAL
# (control-dependent on a Proj — a postfix-if / one-armed branch, whose read
# merges the store value with the fall-through init). An UNCONDITIONAL single
# store (RMW increment, compound-assign, concat-assign) is NOT a merge: it
# resolves to that store's value. Stores are found by a BIDIRECTIONAL walk
# (inputs + control_in + consumers) because branch stores hang off Proj/Region
# control edges the forward return-walk never reaches.
sub _pad_multi_assigned {
    my ($spec_return) = @_;
    my %store_vd;      # vardecl_id => count of distinct stores
    my %cond_vd;       # vardecl_id => a store is conditional (under a Proj)
    for my $node (_collect_bidirectional($spec_return)) {
        my $k = _node_kind($node);
        next unless $k eq 'Assign' || $k eq 'CompoundAssign';
        my $vd = _store_target_vardecl($node) // next;
        $store_vd{ $vd->id }++;
        $cond_vd{ $vd->id } = 1 if _store_is_conditional($node);
    }
    return {
        map  { $_ => 1 }
        grep { $store_vd{$_} >= 2 || $cond_vd{$_} }
        keys %store_vd
    };
}

# _store_is_conditional($store) -> bool — is this store control-dependent on a
# Proj (i.e. it fires only on one arm of a branch)? Walk the control_in chain
# for a Proj node.
sub _store_is_conditional {
    my ($store) = @_;
    my %seen;
    my $ctrl = $store->can('control_in') ? $store->control_in : undef;
    while (blessed($ctrl) && !$seen{ $ctrl->id }++) {
        return true if _node_kind($ctrl) eq 'Proj';
        $ctrl = $ctrl->can('control_in') ? $ctrl->control_in : undef;
    }
    return false;
}

# _store_target_vardecl($assign) -> the VarDecl bound by the store's lhs
# PadAccess, or undef if the lhs is not a pad rebind.
sub _store_target_vardecl {
    my ($assign) = @_;
    return undef unless $assign->can('inputs') && $assign->inputs->@*;
    my $lhs = $assign->inputs->[0];
    return undef unless blessed($lhs) && _node_kind($lhs) eq 'PadAccess';
    return undef unless $lhs->can('inputs') && $lhs->inputs->@*;
    my $vd = $lhs->inputs->[0];
    return blessed($vd) ? $vd : undef;
}

# _last_pad_store($padaccess, $ctx) -> the single store node to this pad, or ().
# Returns the store (Assign/CompoundAssign) when EXACTLY one exists; a
# multi-store (branch) pad is handled as {any} before this is consulted.
sub _last_pad_store {
    my ($padaccess) = @_;
    return () unless $padaccess->can('inputs') && $padaccess->inputs->@*;
    my $vd = $padaccess->inputs->[0];
    return () unless blessed($vd);
    my @stores;
    for my $node (_collect_bidirectional($padaccess)) {
        my $k = _node_kind($node);
        next unless $k eq 'Assign' || $k eq 'CompoundAssign';
        my $svd = _store_target_vardecl($node);
        push @stores, $node if defined $svd && $svd->id eq $vd->id;
    }
    return @stores == 1 ? ($stores[0]) : ();
}

# _collect_bidirectional($node) -> @nodes reachable via inputs + control_in +
# consumers (the whole connected spec graph, so branch-control stores hanging
# off Proj/Region are visible). Deduped.
sub _collect_bidirectional {
    my ($start) = @_;
    my %seen;
    my @queue = ($start);
    my @out;
    while (my $n = shift @queue) {
        next unless blessed($n);
        next if $seen{ $n->id }++;
        push @out, $n;
        if ($n->can('inputs') && defined $n->inputs) {
            push @queue, grep { blessed($_) } $n->inputs->@*;
        }
        push @queue, $n->control_in
            if $n->can('control_in') && defined $n->control_in;
        push @queue, $n->consumers->@*
            if $n->can('consumers') && defined $n->consumers;
    }
    return @out;
}

# _resolve($node, $ctx) -> ($resolved_node, $any) — see-through the transparent
# satisfaction wrappers to the VALUE a node stands for. Returns ($node, 0)
# normally, or (undef, 1) for {any} (a branch-merged pad the spec can't name).
# Applied on BOTH spec and real nodes so the two resolve to the same shape:
#   Coerce / PostfixDeref            -> inputs[0] (transparent representation
#                                       change / implicit aggregate deref)
#   Assign/CompoundAssign(Subscript) -> the lval Subscript read (an element
#                                       store returns the read-back slot value)
#   Assign/CompoundAssign(PadAccess) -> the store's rhs (a scalar rebind
#                                       returns its assigned value)
#   PadAccess                        -> {any} if branch-merged; else its single
#                                       store's value; else its VarDecl init;
#                                       else uninitialised (unresolvable -> the
#                                       node itself, which cannot match a value)
# Resolution iterates to a fixpoint (a pad may resolve to a store rhs that is
# itself a Coerce, etc.).
sub _resolve {
    my ($node, $ctx, $store_seen) = @_;
    $store_seen //= {};
    my %guard;
    while (blessed($node)) {
        last if $guard{ $node->id }++;    # cycle guard
        my $k = _node_kind($node);

        if (($k eq 'Coerce' || $k eq 'PostfixDeref')
            && $node->can('inputs') && $node->inputs->@*) {
            $node = $node->inputs->[0];
            next;
        }

        if ($k eq 'Assign' || $k eq 'CompoundAssign') {
            next if _advance_store(\$node);
            last;
        }

        if ($k eq 'PadAccess') {
            my ($next, $any) = _resolve_pad($node, $ctx, $store_seen);
            return (undef, 1) if $any;
            last unless defined $next;      # uninitialised — stays the pad
            $node = $next;
            next;
        }

        last;
    }
    return ($node, 0);
}

# _advance_store(\$node) — resolve an Assign/CompoundAssign in place; returns
# true if it advanced $node. An element store (Subscript lval) resolves to the
# lval read; a pad rebind resolves to the store rhs.
sub _advance_store {
    my ($ref) = @_;
    my $node = $$ref;
    return false unless $node->can('inputs') && $node->inputs->@* >= 2;
    my ($lhs, $rhs) = ($node->inputs->[0], $node->inputs->[1]);
    if (blessed($lhs) && _node_kind($lhs) eq 'Subscript') {
        $$ref = $lhs;   # element store returns the read-back slot
        return true;
    }
    $$ref = $rhs;       # scalar rebind returns its rhs
    return true;
}

# _resolve_pad($padaccess, $ctx) -> ($value_node, $any)
# ($node, 1) for a branch-merged pad ({any}); (init_or_store_rhs, 0) for a
# resolvable pad; (undef, 0) for an uninitialised read (no store, no init).
sub _resolve_pad {
    my ($padaccess, $ctx, $store_seen) = @_;
    $store_seen //= {};
    my $vd = $padaccess->can('inputs') && $padaccess->inputs->@*
        ? $padaccess->inputs->[0] : undef;
    return (undef, 0) unless blessed($vd);

    # Branch-merged pad (2+ stores) — the merged value is unnameable: {any}.
    return (undef, 1) if $ctx->{pad_multi}{ $vd->id };

    my $init = ($vd->can('inputs') && $vd->inputs->@* >= 2 && blessed($vd->inputs->[1]))
        ? $vd->inputs->[1] : undef;

    # Single store — the pad reads that store's value. A PRE-store RMW read
    # (the pre-store operand inside the store's own rhs, e.g. $s in $s .= "b" /
    # $i in $i = $i + 1) sees the pad INIT, not the post-store value. The
    # pre-store read may be a DISTINCT node ($i_r vs the $i return read, as
    # B::SoN emits) OR hash-cons to the SAME node as the return read (S4, same
    # varname). Both are handled by tracking the pad's IDENTITY (its VarDecl
    # id): the FIRST resolution of a pad to its store rhs marks the VarDecl;
    # any read of the SAME pad reached while that store rhs is being expanded
    # is a pre-store read and resolves to the init.
    my ($store) = _last_pad_store($padaccess);
    if (defined $store) {
        return ($init, 0) if $store_seen->{ $vd->id };
        $store_seen->{ $vd->id } = 1;
        my $node = $store;
        _advance_store(\$node);
        return ($node, 0);
    }

    # No store — a VarDecl init (inputs[1]) is the pad's value.
    return ($init, 0) if defined $init;

    # No store and no init — uninitialised read.
    return (undef, 0);
}

# _node_match($spec, $real, $ctx) -> bool — positional structural match after
# resolving both sides through the transparent wrappers. Spec operands must
# match real operands at the same index (extra trailing real inputs, e.g. a
# threaded MemStart/store or a read-back store operand, are ignored — the spec
# never names them). NO subset-descent: the resolved real node must BE the
# resolved spec node's counterpart, not sit deeper inside a wrapping real op.
# Commutative ops whose operands may be paired as a bijection rather than
# strictly by index. Operand ORDER does not change the value, so a lax-vs-strict
# same-kind operand reordering (shape-subset-check test 7) is a valid match,
# while for NON-commutative ops a swap changes the result and must be rejected.
my %_COMMUTATIVE = (Add => 1, Multiply => 1, And => 1, Or => 1);

# _deref_sigil_ok($spec, $real) -> bool — when BOTH nodes are PostfixDeref,
# their sigils must agree ('@' array-deref vs '%' hash-deref are behaviorally
# distinct). If either side is not a PostfixDeref the see-through handles it and
# there is no sigil to compare. Returns true unless a spec deref names a sigil
# the real deref does not share.
sub _deref_sigil_ok {
    my ($spec, $real) = @_;
    return true unless blessed($spec) && _node_kind($spec) eq 'PostfixDeref'
                    && blessed($real) && _node_kind($real) eq 'PostfixDeref';
    my $ss = $spec->can('sigil') ? $spec->sigil : undef;
    return true unless defined $ss;      # lax spec — sigil unchecked
    my $rr = $real->can('sigil') ? $real->sigil : undef;
    return defined $rr && $rr eq $ss;
}

sub _node_match {
    my ($spec, $real, $ctx, $store_seen, $in_descent) = @_;
    $store_seen //= {};

    # Sigil gate: _resolve sees THROUGH a PostfixDeref to its inputs[0],
    # dropping the sigil. A spec @-deref and a real %-deref then resolve to the
    # same ref and match — masking an array-vs-hash miscompile. Compare the
    # sigil on the pre-resolution nodes before seeing through.
    return false unless _deref_sigil_ok($spec, $real);

    my ($rs, $any_s) = _resolve($spec, $ctx, $store_seen);
    return true if $any_s;                  # {any} spec pad accepts anything
    my ($rr) = _resolve($real, $ctx, $store_seen);

    return false unless blessed($rs) && blessed($rr);

    # Cycle guard: a loop Phi's backedge input points back into the body,
    # making the operand graph cyclic. Co-inductively assume a pair already
    # being matched holds (bisimulation) — this both terminates and is the
    # correct equivalence for loop-carried values.
    my $pair_key = $rs->id . "\0" . $rr->id;
    return true if $ctx->{pairing}{$pair_key};
    local $ctx->{pairing}{$pair_key} = 1;

    # Structural match first: same pair predicate + operand match. Operands are
    # matched positionally by default; for a COMMUTATIVE op (Add/Multiply/&&/||)
    # a consistent bijection is allowed so a lax spec operand cannot steal the
    # real operand a strict same-kind sibling needs (shape-subset-check test 7).
    # A NON-commutative op (Subtract, DefinedOr, NumLt, Subscript) keeps strict
    # by-index pairing — operand ORDER is load-bearing, so an operand SWAP
    # (T2/H1) stays rejected.
    if (_pair_match($rs, $rr, $in_descent)) {
        my @sin = $rs->can('inputs') && defined $rs->inputs ? $rs->inputs->@* : ();
        my @rin = $rr->can('inputs') && defined $rr->inputs ? $rr->inputs->@* : ();
        # Children are NOT descent — a matched child may itself fold, so reset
        # the descent flag for the operand walk.
        return true
            if _match_operands(\@sin, \@rin, $ctx, $store_seen,
                               $_COMMUTATIVE{ _node_kind($rs) });
    }

    # Fold fallback: perl folds a literal-arithmetic spec op to a Constant that
    # B::SoN loads directly, so a fold-satisfied spec node matches the real node
    # BEING its folded Constant at THIS position (value-anchored, no descent). A
    # folded-away op whose value is merely buried elsewhere in the real graph
    # (T3: real returns TernaryExpr(2,99,2)=99 with a stray Constant(2)) does
    # NOT match here — the real return node must itself be the folded Constant.
    # ANCHORED at the node _node_match was CALLED on: the fold fallback does NOT
    # fire while descending into real inputs (else T3's stray Constant(2), found
    # deeper, would re-open the hole).
    if (!$in_descent && $ctx->{satisfied}{ $rs->id }) {
        my ($fv) = _fold_value($rs);
        ($fv) = _concat_fold_value($rs) unless defined $fv;
        return true if defined $fv
            && _node_kind($rr) eq 'Constant'
            && $rr->can('value') && defined $rr->value && $rr->value eq $fv;
    }

    # Subset-descent (structural only): the spec declares a SUBGRAPH of the real
    # graph, so a real node that WRAPS the spec value (real Multiply(Add,9) for a
    # spec Add) matches by finding the spec subtree deeper. Retry the SPEC node
    # against each real input. Descent runs the structural path ONLY — the
    # value-anchored fold fallback stays anchored above (in_descent=1), so a
    # folded spec op cannot latch onto a stray Constant buried in the real graph.
    for my $ri (_rin_for_descent($rr)) {
        return true if _node_match($rs, $ri, $ctx, $store_seen, 1);
    }

    return false;
}

# _operand_specificity($node) -> how constrained a spec operand is, so the
# commutative bijection matches the pickiest operand first. A defined
# representation is the discriminator the pair-match keys on (a lax undef-repr
# operand matches anything); Constants add their value as a further constraint.
sub _operand_specificity {
    my ($node) = @_;
    return 0 unless blessed($node);
    my $s = 0;
    $s++ if $node isa Chalk::IR::Node && defined $node->stamp;
    $s++ if _node_kind($node) eq 'Constant' && $node->can('value') && defined $node->value;
    return $s;
}

# _rin_for_descent($real) -> the real node's blessed inputs, for subset-descent.
sub _rin_for_descent {
    my ($real) = @_;
    return () unless blessed($real) && $real->can('inputs') && defined $real->inputs;
    return grep { blessed($_) } $real->inputs->@*;
}

# _match_operands(\@sin, \@rin, $ctx, $store_seen, $commutative) -> bool — pair
# each blessed spec operand to a real operand. By INDEX when non-commutative
# (order is load-bearing — an operand SWAP must fail: T2/H1). As a consistent
# BIJECTION (each real operand used once) when commutative — try position
# first, then any other not-yet-consumed real operand — so a lax spec operand
# does not steal the real operand a strict same-kind sibling needs. Children
# reset in_descent (a matched child may itself fold).
sub _match_operands {
    my ($sin, $rin, $ctx, $store_seen, $commutative) = @_;

    # The bijection may only REORDER a commutative op's operands, never DROP a
    # real operand: an extra real operand changes a commutative op's value
    # (Add(3,999,7) != Add(3,7)). So permute only when the blessed-operand
    # counts match; otherwise fall back to strict by-index (a genuine trailing
    # effect on a non-commutative op is still ignored by the index walk).
    my $sn = grep { blessed($_) } @$sin;
    my $rn = grep { blessed($_) } @$rin;
    $commutative &&= ($sn == $rn);

    # Commutative bijection: match the MOST-CONSTRAINED spec operand first, so a
    # lax operand (undef repr, matches anything) does not greedily consume the
    # one real operand a strict same-kind sibling needs (shape-subset-check test
    # 7 — mirrors the constrained-first sort on the multiset leg). Index order is
    # preserved for the non-commutative case.
    my @order = 0 .. $#$sin;
    @order = sort { _operand_specificity($sin->[$b]) <=> _operand_specificity($sin->[$a]) }
        @order if $commutative;

    my %used;   # real index already consumed (bijection)
    SPEC: for my $i (@order) {
        my $s = $sin->[$i];
        next unless blessed($s);            # spec undef/arrayref slot — skip
        # Non-commutative (or mismatched arity): index only. Commutative with
        # equal arity: position first, then any other unused real operand.
        my @cand = $commutative ? ($i, grep { $_ != $i } 0 .. $#$rin) : ($i);
        for my $j (@cand) {
            next if $used{$j};
            next unless defined $rin->[$j] && blessed($rin->[$j]);
            if (_node_match($s, $rin->[$j], $ctx, $store_seen, 0)) {
                $used{$j} = 1;
                next SPEC;
            }
        }
        return false;                       # no real operand matched this spec
    }
    return true;
}

# _concat_fold_value($node) -> ($joined) or () — a Concat of two string
# literals folds to their concatenation (perl folds `"a" . "b"` to a single
# Constant); mirrors the Concat seed in _fold_satisfied_ids.
sub _concat_fold_value {
    my ($node) = @_;
    return () unless blessed($node) && _node_kind($node) eq 'Concat';
    return () unless $node->can('inputs') && $node->inputs->@* == 2;
    my ($l) = _str_literal($node->inputs->[0]);
    my ($r) = _str_literal($node->inputs->[1]);
    return () unless defined $l && defined $r;
    return ($l . $r);
}

# _pair_match($spec, $real) -> bool — the PAIR predicate: same kind, same
# declared repr (operand-returning ops load unstamped — accept undef real
# repr), same Constant value, same Coerce from/to, AND same distinguishing
# LEAF attributes (FieldAccess field_index/field_stash; PadAccess varname).
# The leaf-attr comparison is the H1 fix: a swap of two same-kind NON-literal
# operands (FieldAccess field0 vs field1) is invisible to a kind+repr compare.
sub _pair_match {
    my ($spec, $real, $in_descent) = @_;
    my $sk = _node_kind($spec);
    return false unless $sk eq _node_kind($real);

    # Repr: a spec-declared repr must match the real repr. An UNSTAMPED real
    # node (undef repr) is accepted against any spec repr — B::SoN leaves nested
    # operand-position nodes unstamped for the loader to infer, and the multiset
    # leg already proved the stamped node EXISTS; the rooted leg enforces WIRING,
    # so re-failing on a stamp the loader will fill would false-FAIL a valid
    # lax/strict operand split (shape-subset-check test 7). A real repr that is
    # DEFINED but DIFFERENT still fails (an :Int spec vs a :Num real Divide).
    # `isa Chalk::IR::Node`, NOT Value. `stamp` is on Node, and Value is a
    # SIBLING of Print/Proj/VarDecl/ListAssign rather than their parent -- so a
    # Value test reads undef for four node kinds that carry a stamp. HERE that
    # made the comparison VACUOUS: an undef spec repr against an undef real
    # repr agrees, so a declared `:Repr` on any of those four was never checked
    # at all. The shape leg passed without looking.
    my $srepr = $spec isa Chalk::IR::Node ? $spec->stamp : undef;
    my $rrepr = $real isa Chalk::IR::Node ? $real->stamp : undef;
    if (defined $srepr && defined $rrepr) {
        return false unless $rrepr eq $srepr;
    }

    if ($sk eq 'Constant') {
        my $sv = $spec->can('value') ? $spec->value : undef;
        my $rv = $real->can('value') ? $real->value : undef;
        if (defined $sv) {
            return false unless defined $rv && $rv eq $sv;
        }
    }

    if ($sk eq 'Coerce') {
        return false unless _coerce_shape($spec) eq _coerce_shape($real);
    }

    if ($sk eq 'FieldAccess') {
        return false unless _leaf_eq($spec, $real, 'field_index');
        return false unless _leaf_eq($spec, $real, 'field_stash');
    }

    if ($sk eq 'PadAccess') {
        return false unless _leaf_eq($spec, $real, 'varname');
    }

    # Other leaf-identifying attrs (the H1 leaf-attr-swap class): an EnvRead read
    # the wrong env key, a RegexCapture the wrong group, a EntryDef the wrong
    # stash var. Each must agree when the spec names it (a lax spec leaves it
    # undef, unchecked). These are LEAF nodes with no nested wiring, so the check
    # is unambiguous. A Call's callee (name/dispatch_kind) swap is the same class
    # but the check conflicts with legitimate nested-receiver wiring (method-call
    # threads a void call through the receiver chain) -- filed as a follow-up.
    if ($sk eq 'EnvRead') {
        return false unless _leaf_eq($spec, $real, 'key');
    }
    if ($sk eq 'RegexCapture') {
        return false unless _leaf_eq($spec, $real, 'n');
    }
    if ($sk eq 'EntryDef') {
        return false unless _leaf_eq($spec, $real, 'stash_name');
        return false unless _leaf_eq($spec, $real, 'var_name');
    }

    # A Call's callee (name/dispatch_kind) is a distinguishing leaf attr too: a
    # return-position callee swap (spec name "kind" vs real name "other", or
    # method-vs-sub dispatch) must FAIL the shape leg. But enforcing it at EVERY
    # position breaks legitimate NESTED-receiver wiring: a method-call threads a
    # void call through the receiver chain (new -> inc[void] -> val), so the real
    # val-Call's receiver is a DIFFERENT Call than the spec's straight new-Call
    # receiver. That nested receiver is reached by DESCENT (in_descent=1); only at
    # the RETURN position (in_descent falsey) is the pairing the spec-declared
    # callee, where the swap must be caught. Pin the callee attrs there only
    # (zhi 019f51a0).
    if ($sk eq 'Call' && !$in_descent) {
        return false unless _leaf_eq($spec, $real, 'name');
        return false unless _leaf_eq($spec, $real, 'dispatch_kind');
    }

    return true;
}

# _leaf_eq($a, $b, $attr) -> bool — compare a distinguishing leaf attribute
# when the spec node names it; if the spec leaves it undef the field is
# unchecked (lax spec).
sub _leaf_eq {
    my ($a, $b, $attr) = @_;
    my $av = $a->can($attr) ? $a->$attr : undef;
    return true unless defined $av;
    my $bv = $b->can($attr) ? $b->$attr : undef;
    return defined $bv && $bv eq $av;
}

# Ops the corpus specs use whose all-literal form perl folds in op.c before
# B::SoN walks. The value is computed with perl's own operator (perl-folds-
# perl, so the folded value matches op.c exactly); the result repr is taken
# from the spec op node's declared representation. Comparisons fold to perl's
# boolean (1 / '' — the Constant(1)/Constant() :Boolean B::SoN emits). Str
# comparisons are equally foldable but no corpus case uses them yet. Recursive
# folding IS done (zhi 019f2b61): a TernaryExpr over a folded condition
# collapses to its selected arm (`1 < 2 ? 1 : 0` -> Constant(1), via
# _fold_value), and a Concat of string literals folds to the joined Constant
# (`"a" . "b"` -> Constant("ab")).
my %_FOLD_OP = (
    Add      => sub ($a, $b) { $a + $b },
    Subtract => sub ($a, $b) { $a - $b },
    Multiply => sub ($a, $b) { $a * $b },
    Divide   => sub ($a, $b) { $a / $b },
    Modulo   => sub ($a, $b) { $a % $b },
    NumLt    => sub ($a, $b) { $a <  $b },
    NumGt    => sub ($a, $b) { $a >  $b },
    NumLe    => sub ($a, $b) { $a <= $b },
    NumGe    => sub ($a, $b) { $a >= $b },
    NumEq    => sub ($a, $b) { $a == $b },
    NumNe    => sub ($a, $b) { $a != $b },
);

# _literal_operand($node) -> (defined value) or undef
# A node is a literal operand if it is a Constant, or a Coerce wrapping a
# Constant (the Divide corpus shape coerces its Int operands to Num). Returns
# the Constant's value, or undef if the operand is not literal.
# _literal_operand($node) -> ($value, $repr, $const_node) or ()
# A node is a literal operand if it is a Constant, or a Coerce wrapping a
# Constant (the Divide corpus shape coerces its Int operands to Num). Returns
# the underlying Constant's value + representation + node, or () if the operand
# is not literal. The repr is the fold's numeric-type gate; the node lets the
# caller credit exactly the right operand signature.
sub _literal_operand {
    my ($node) = @_;
    return () unless blessed($node);
    my $kind = _node_kind($node);
    if ($kind eq 'Coerce' && $node->can('inputs') && $node->inputs->@*) {
        $node = $node->inputs->[0];
        return () unless blessed($node);
        $kind = _node_kind($node);
    }
    return () unless $kind eq 'Constant' && $node->can('value');
    my $repr = $node isa Chalk::IR::Node ? $node->stamp : undef;
    return ($node->value, $repr, $node);
}

# Reprs perl's numeric operators fold without coercion warnings. A string
# literal under an arithmetic/Num op would coerce (warning + a spurious value
# that could coincidentally match) — so the fold only fires on numeric operands.
my %_NUMERIC_REPR = (Int => 1, Num => 1);

# _str_literal($node) -> ($value) or ()
# A Str Constant's value, or () if the node is not a string literal. Used by
# the Concat fold (string concatenation of literals).
sub _str_literal {
    my ($node) = @_;
    my ($value, $repr) = _literal_operand($node);
    return () unless defined $value && ($repr // '') eq 'Str';
    return ($value);
}

# _fold_value($node) -> ($value) or ()
# Recursively fold a spec node to its compile-time value, mirroring perl's
# op.c constant folding: a numeric Constant is its value; a foldable binop over
# folded numeric operands is the computed value; a TernaryExpr whose condition
# folds to a definite boolean selects the corresponding arm (itself folded).
# Returns () when the node is not fully foldable (a non-literal operand, a
# non-numeric operand, or a division/modulo by zero) — never a guessed value.
sub _fold_value {
    my ($node) = @_;
    return () unless blessed($node);
    my $kind = _node_kind($node);

    # A literal (Constant, or Coerce over a Constant) folds to its value —
    # but only a NUMERIC one (a string under arithmetic would coerce).
    my ($lit, $lrepr) = _literal_operand($node);
    if (defined $lit) {
        return () unless $_NUMERIC_REPR{ $lrepr // '' };
        return ($lit);
    }

    if (my $fold = $_FOLD_OP{$kind}) {
        return () unless $node->can('inputs') && $node->inputs->@* == 2;
        my ($a) = _fold_value($node->inputs->[0]);
        my ($b) = _fold_value($node->inputs->[1]);
        return () unless defined $a && defined $b;
        my $v = eval { $fold->($a, $b) };
        return defined $v ? ($v) : ();
    }

    if ($kind eq 'TernaryExpr') {
        return () unless $node->can('inputs') && $node->inputs->@* == 3;
        my ($cond, $t, $f) = $node->inputs->@*;
        my ($cv) = _fold_value($cond);
        return () unless defined $cv;
        return _fold_value($cv ? $t : $f);
    }

    return ();
}

# _fold_satisfied_ids($spec_return, $real_return) -> { node_id => 1 }
#
# Finds foldable spec op nodes (arithmetic/Num-comparison over all-literal,
# NUMERIC direct inputs) whose folded Constant is present in the real graph,
# and returns the set of spec node ids subsumed by that fold: the op node and
# any input node (a Coerce wrapper, or an operand Constant) whose EVERY spec
# consumer is a subsumed fold op. The signature collector dedups by id, so this
# is a node-set: a Constant shared with a non-fold consumer (e.g. an
# independent Coerce) is NOT subsumed — its single signature must survive to
# satisfy that consumer. Solving sole-consumer bottom-up is a fixpoint (a
# Coerce becomes subsumable only once its fold op is), so iterate to a stable
# set over the (small) spec graph.
sub _fold_satisfied_ids {
    my ($spec_return, $real_return) = @_;

    # Real Constant values indexed by "value\0repr" for O(1) fold lookup.
    my %real_const;
    for my $sig (_collect_node_signatures($real_return)) {
        next unless $sig->{kind} eq 'Constant' && defined $sig->{value};
        $real_const{ $sig->{value} . "\0" . ($sig->{repr} // '') } = 1;
    }

    my @nodes = _collect_all_nodes($spec_return);

    # Consumer edges over the reachable spec graph: consumers{child_id} = [parent_ids].
    my %consumers;
    for my $node (@nodes) {
        next unless $node->can('inputs') && defined $node->inputs;
        for my $in ($node->inputs->@*) {
            push $consumers{ $in->id }->@*, $node->id if blessed($in);
        }
    }

    # Seed: satisfied fold ops. An op node has no consumers issue — it is the
    # folded-away node itself, always absent from the real graph.
    my %satisfied;
    for my $node (@nodes) {
        my $fold = $_FOLD_OP{ _node_kind($node) } or next;
        next unless $node->can('inputs') && $node->inputs->@* == 2;
        my ($lhs, $rhs) = $node->inputs->@*;
        my ($lv, $lrepr) = _literal_operand($lhs);
        my ($rv, $rrepr) = _literal_operand($rhs);
        next unless defined $lv && defined $rv;
        # Only fold over numeric literals — never coerce a string (warning +
        # spurious value that could coincidentally match a real Constant).
        next unless $_NUMERIC_REPR{ $lrepr // '' } && $_NUMERIC_REPR{ $rrepr // '' };
        my $repr = $node isa Chalk::IR::Node ? $node->stamp : undef;
        my $value = eval { $fold->($lv, $rv) };
        next unless defined $value;   # e.g. modulo/divide by zero — no fold
        # ponytail: the value-key is string-eq. Both sides are perl-default NV
        # stringification (15 sig figs), so 3/4=0.75 matches; a non-terminating
        # fold (1/3) relies on identical stringification on both sides — fine
        # today, revisit if a repeating-decimal fold enters the corpus.
        next unless $real_const{ $value . "\0" . ($repr // '') };
        $satisfied{ $node->id } = 1;
    }

    # Seed: a TernaryExpr over a folded comparison collapses to its selected arm
    # (perl folds `1 < 2 ? 1 : 0` recursively to Constant(1)). Subsume the
    # ternary when its recursive fold value is present in the real graph as a
    # Constant of the ternary's repr; the fixpoint then subsumes its condition
    # subtree and unselected arm.
    for my $node (@nodes) {
        next unless _node_kind($node) eq 'TernaryExpr';
        my ($value) = _fold_value($node);
        next unless defined $value;
        my $repr = $node isa Chalk::IR::Node ? $node->stamp : undef;
        next unless $real_const{ $value . "\0" . ($repr // '') };
        $satisfied{ $node->id } = 1;
    }

    # Seed: a Concat of string literals folds to the joined Constant (perl folds
    # `"a" . "b"` to Constant("ab")). Subsume the Concat when the joined string
    # is present in the real graph as a Str Constant.
    for my $node (@nodes) {
        next unless _node_kind($node) eq 'Concat';
        next unless $node->can('inputs') && $node->inputs->@* == 2;
        my ($l) = _str_literal($node->inputs->[0]);
        my ($r) = _str_literal($node->inputs->[1]);
        next unless defined $l && defined $r;
        next unless $real_const{ ($l . $r) . "\0" . 'Str' };
        $satisfied{ $node->id } = 1;
    }

    # Fixpoint: a non-fold node (a Coerce wrapper, or an operand Constant) is
    # subsumed once ALL its consumers are subsumed — extending the folded-away
    # region inward. A node shared with a non-subsumed consumer stays required.
    my $changed = 1;
    while ($changed) {
        $changed = 0;
        for my $node (@nodes) {
            my $id = $node->id;
            next if $satisfied{$id};
            my $cs = $consumers{$id} or next;   # unconsumed (the Return) stays
            next if grep { !$satisfied{$_} } @$cs;
            $satisfied{$id} = 1;
            $changed = 1;
        }
    }
    return \%satisfied;
}

# _mark_pad_scaffolding($spec_return, $real_return, \%satisfied) — add the ids
# of lexical pad scaffolding (each VarDecl, its name Constant, and every
# PadAccess) to the satisfied set, so they are not required of a producer that
# PROPAGATED the pad away. Subsumption is conceded per-kind ONLY when the real
# graph has NO node of that kind — i.e. propagation actually happened. A
# producer that KEEPS the pad (Chalk) is not conceded: its pad nodes must
# match the spec including repr (a mis-typed kept pad FAILs). The VarDecl's
# INIT value is never subsumed; a name Constant is subsumed only when the
# VarDecl is its sole consumer (a bare Constant used elsewhere survives).
sub _mark_pad_scaffolding {
    my ($spec_return, $real_return, $satisfied) = @_;
    my @nodes = _collect_all_nodes($spec_return);

    # Which pad kinds did the real graph propagate away (emit zero of)?
    my %real_kind;
    $real_kind{ _node_kind($_) } = 1 for _collect_all_nodes($real_return);
    my $pad_propagated  = !$real_kind{PadAccess};
    my $decl_propagated = !$real_kind{VarDecl};

    # Consumer counts so a name-Constant shared beyond its VarDecl survives.
    my %consumers;
    for my $node (@nodes) {
        next unless $node->can('inputs') && defined $node->inputs;
        $consumers{ $_->id }++ for grep { blessed($_) } $node->inputs->@*;
    }

    for my $node (@nodes) {
        my $kind = _node_kind($node);
        if ($kind eq 'PadAccess' && $pad_propagated) {
            $satisfied->{ $node->id } = 1;
        }
        elsif ($kind eq 'VarDecl' && $decl_propagated) {
            $satisfied->{ $node->id } = 1;
            # inputs[0] is the name Constant; subsume it only if this VarDecl
            # is its sole consumer.
            my $name = $node->can('inputs') && $node->inputs->@* ? $node->inputs->[0] : undef;
            if (blessed($name) && _node_kind($name) eq 'Constant'
                && ($consumers{ $name->id } // 0) == 1) {
                $satisfied->{ $name->id } = 1;
            }
        }
    }
    return;
}

# _mark_assign_select_propagation($spec_return, $real_return, \%satisfied) —
# subsume propagated assignment + if/else scaffolding, mirroring the pad rule
# (subsume a spec node kind ONLY when the real graph emitted zero of it, so a
# producer that KEEPS it is not conceded). Two categories:
#   (1) Assign/CompoundAssign: perl propagates a pure scalar/field rebind's
#       stored value to the read site, so no assign node survives. Subsume a
#       spec Assign/CompoundAssign whose lhs (inputs[0]) is a PadAccess or
#       FieldAccess -- a pure rebind. An element/aggregate store (Subscript
#       lhs) is a real effect and stays required.
#   (2) If/Proj/Region: perl propagates a branch whose arms are pure values
#       into a TernaryExpr select. Subsume the spec CFG scaffolding ONLY when
#       the real graph has no If AND carries the equivalent select. A genuine
#       branch (no real select) stays required.
# The bound value nodes are never subsumed here (the value must still match).
sub _mark_assign_select_propagation {
    my ($spec_return, $real_return, $satisfied) = @_;
    my @nodes = _collect_all_nodes($spec_return);

    my (%real_kind, %real_count);
    for my $n (_collect_all_nodes($real_return)) { $real_kind{ _node_kind($n) } = 1; $real_count{ _node_kind($n) }++; }
    my %spec_count;
    $spec_count{ _node_kind($_) }++ for @nodes;

    my $assign_propagated  = !$real_kind{Assign};
    my $caccign_propagated = !$real_kind{CompoundAssign};
    # if/else -> select is conceded only when the real graph replaced the
    # branch with a select: no If survives AND the real graph carries at least
    # as many TernaryExpr selects as the spec has Ifs. The count gate stops one
    # unrelated select from masking a genuinely dropped branch (each propagated
    # If becomes exactly one select).
    my $ifelse_propagated  = !$real_kind{If}
        && ($real_count{TernaryExpr} // 0) >= ($spec_count{If} // 0)
        && ($spec_count{If} // 0) > 0;

    for my $node (@nodes) {
        my $kind = _node_kind($node);
        if (($kind eq 'Assign' && $assign_propagated)
            || ($kind eq 'CompoundAssign' && $caccign_propagated)) {
            # Pure LEXICAL rebind only: lhs (inputs[0]) is a PadAccess. A pad is
            # SSA-like and propagates safely. A FieldAccess store is an
            # object-state mutation of shared heap (the RC4 class) and is NOT a
            # pure rebind — never subsume it, or a dropped field write-back
            # becomes a false green. Element stores (Subscript lhs) likewise
            # stay required.
            my $lhs = $node->can('inputs') && $node->inputs->@*
                ? $node->inputs->[0] : undef;
            my $lk = blessed($lhs) ? _node_kind($lhs) : '';
            $satisfied->{ $node->id } = 1 if $lk eq 'PadAccess';
        }
        elsif (($kind eq 'If' || $kind eq 'Proj' || $kind eq 'Region')
               && $ifelse_propagated) {
            $satisfied->{ $node->id } = 1;
        }
    }
    return;
}

# _mark_deref_scaffolding($spec_return, $real_return, \%satisfied) — subsume a
# spec PostfixDeref (the explicit `@$ref` / `%$ref` deref before a Subscript)
# when the real graph emitted zero PostfixDeref: the producer models the
# aggregate deref implicitly (rv2av/rv2hv is an OpMap SKIP), so its Subscript
# takes the aggregate directly. Existence conceded per-kind, gated on the real
# graph having none — a producer that KEEPS a PostfixDeref must match it.
sub _mark_deref_scaffolding {
    my ($spec_return, $real_return, $satisfied) = @_;

    my %real_kind;
    $real_kind{ _node_kind($_) } = 1 for _collect_all_nodes($real_return);
    return if $real_kind{PostfixDeref};   # producer kept it — require a match

    for my $node (_collect_all_nodes($spec_return)) {
        $satisfied->{ $node->id } = 1 if _node_kind($node) eq 'PostfixDeref';
    }
    return;
}

# Truthiness ops that coerce their operand to a boolean internally, so an
# explicit Coerce(X -> Boolean) feeding one is redundant in the producer's graph.
my %_TRUTHINESS_OP = (Not => 1);

# Numeric arithmetic ops that numify their operands internally (perl's `/`,
# `%`, etc. coerce an Int operand to Num as part of the op itself), so an
# explicit Coerce(X -> Num) feeding one is redundant in the producer's graph.
# Reuses %_FOLD_OP's op set: the same ops that fold over literals are the ones
# that auto-numify when they DON'T fold (e.g. a Divide of two live pad reads).
my %_NUMIFYING_OP = map { $_ => 1 } keys %_FOLD_OP;

# _mark_coerce_absorption($spec_return, $real_return, \%satisfied) — subsume a
# spec Coerce(X -> Boolean) whose SOLE consumer is a truthiness op (Not), or a
# spec Coerce(X -> Num) whose SOLE consumer is a numifying arithmetic op, when
# the real graph carries no such Coerce: the op does its own coercion, so
# B::SoN feeds the operand directly. Only these two absorbed shapes are
# subsumed — a Coerce to any other repr, or feeding a non-absorbing consumer,
# is a real representation change and stays required.
sub _mark_coerce_absorption {
    my ($spec_return, $real_return, $satisfied) = @_;
    my @nodes = _collect_all_nodes($spec_return);

    # Which Coerce (from -> to) shapes does the real graph carry? A real Coerce
    # of the same shape means the producer did NOT absorb it — require a match.
    my %real_coerce;
    for my $node (_collect_all_nodes($real_return)) {
        next unless _node_kind($node) eq 'Coerce';
        $real_coerce{ _coerce_shape($node) } = 1;
    }

    # Consumers of each spec node (by id).
    my %consumers;
    for my $node (@nodes) {
        next unless $node->can('inputs') && defined $node->inputs;
        for my $in ($node->inputs->@*) {
            push $consumers{ $in->id }->@*, $node if blessed($in);
        }
    }

    for my $node (@nodes) {
        next unless _node_kind($node) eq 'Coerce';
        next if $real_coerce{ _coerce_shape($node) };   # producer kept it
        my $to = $node->can('to_repr') ? ($node->to_repr // '') : '';
        my $cs = $consumers{ $node->id } // [];
        next unless @$cs == 1;
        my $sole_kind = _node_kind($cs->[0]);
        next unless ($to eq 'Boolean' && $_TRUTHINESS_OP{$sole_kind})
                 || ($to eq 'Num'  && $_NUMIFYING_OP{$sole_kind});
        $satisfied->{ $node->id } = 1;
    }
    return;
}

# _coerce_shape($node) -> "from->to" for a Coerce node (for real/spec matching).
sub _coerce_shape {
    my ($node) = @_;
    my $from = $node->can('from_repr') ? ($node->from_repr // '') : '';
    my $to   = $node->can('to_repr')   ? ($node->to_repr   // '') : '';
    return "$from->$to";
}

# _sig_match($spec_sig, \@real_sigs) -> bool
# A spec signature matches a real one on kind, declared repr, Constant
# value, and Coerce from/to. Fields the spec leaves undef are unchecked.
# A matched real signature is CONSUMED (multiset subset): two same-kind
# spec nodes need two real nodes. Matching is greedy and edge-blind — it
# compares node multisets, not operand wiring; rooted structural matching
# is the upgrade path if a rewired-but-same-multiset regression ever slips
# through. Operand-returning ops (%_OPERAND_RETURNING, defined above) load
# unstamped; the spec's declared repr is accepted against an undef real repr.
sub _sig_match {
    my ($spec, $real_sigs) = @_;
    for my $i (0 .. $#$real_sigs) {
        my $sig = $real_sigs->[$i];
        next unless $sig->{kind} eq $spec->{kind};
        if (defined $spec->{repr}) {
            # Operand-returning ops load unstamped; accept undef real repr.
            unless ($_OPERAND_RETURNING{ $spec->{kind} } && !defined $sig->{repr}) {
                next unless defined $sig->{repr} && $sig->{repr} eq $spec->{repr};
            }
        }
        if ($spec->{kind} eq 'Constant' && defined $spec->{value}) {
            next unless defined $sig->{value} && $sig->{value} eq $spec->{value};
        }
        if ($spec->{kind} eq 'Coerce') {
            next unless ($sig->{from} // '') eq ($spec->{from} // '');
            next unless ($sig->{to}   // '') eq ($spec->{to}   // '');
        }
        splice @$real_sigs, $i, 1;
        return true;
    }
    return false;
}

# _sig_specificity($sig) -> int — how many constraint fields the sig declares.
sub _sig_specificity {
    my ($sig) = @_;
    return scalar grep { defined $sig->{$_} } qw(repr value from to);
}

# _sig_str($sig) -> str — a readable form for missing-node reporting.
sub _sig_str {
    my ($sig) = @_;
    my $s = $sig->{kind};
    $s .= "(" . $sig->{value} . ")" if $sig->{kind} eq 'Constant' && defined $sig->{value};
    $s .= "(" . ($sig->{from} // '?') . " -> " . ($sig->{to} // '?') . ")"
        if $sig->{kind} eq 'Coerce';
    $s .= " :" . $sig->{repr} if defined $sig->{repr};
    return $s;
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

# _collect_node_signatures($return_node, $skip_ids) -> @signatures
#
# Walks the reachable graph from a Return node and collects a list of
# node-descriptor hashrefs (kind, repr, value, from, to, ...) for matching.
# $skip_ids (optional hashref of node-id => 1) omits fold-satisfied nodes
# from the spec side so they are not re-required by the plain subset match.
sub _collect_node_signatures {
    my ($return_node, $skip_ids) = @_;
    my %visited;
    my @sigs;
    _visit_node($return_node, \%visited, \@sigs, $skip_ids // {});
    return @sigs;
}

sub _visit_node {
    my ($node, $visited, $sigs, $skip_ids) = @_;
    $skip_ids //= {};
    return unless defined $node;
    # Producer graphs may carry arrayref inputs (e.g. Call arg lists) —
    # the same guard Graph::nodes and TypedInvariant carry.
    return unless blessed($node);

    my $id = $node->id;
    return if $visited->{$id}++;

    # A fold-satisfied node (op + its operand Constants/Coerce) is recorded as
    # visited so its inputs are still traversed, but produces no signature —
    # it was already matched by the folded real Constant.
    if ($skip_ids->{$id}) {
        if ($node->can('inputs') && defined $node->inputs) {
            _visit_node($_, $visited, $sigs, $skip_ids) for $node->inputs->@*;
        }
        if ($node->can('control_in') && defined $node->control_in) {
            _visit_node($node->control_in, $visited, $sigs, $skip_ids);
        }
        return;
    }

    # Build the signature for this node
    my $kind = _node_kind($node);
    my $repr = ($node isa Chalk::IR::Node) ? $node->stamp : undef;

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

    push @$sigs, \%sig;

    # Recurse into inputs (data flow)
    if ($node->can('inputs') && defined $node->inputs) {
        for my $inp ($node->inputs->@*) {
            _visit_node($inp, $visited, $sigs, $skip_ids) if defined $inp;
        }
    }

    # Recurse into control_in (control flow)
    if ($node->can('control_in') && defined $node->control_in) {
        _visit_node($node->control_in, $visited, $sigs, $skip_ids);
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

    # Build the graph from the ir block (list context: the per-case MOP,
    # when the block declares class structure, rides along to the backend).
    my ($return_node, $case_mop);
    eval { ($return_node, $case_mop) = __PACKAGE__->build_graph_from_ir($ir_text) };
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

    # Run through LLVMDriver (the case's sealed MOP, when present —
    # LLVMDriver guards undef internally)
    my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node,
        { mop => $case_mop });

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
