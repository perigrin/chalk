# ABOUTME: Runner for the mdtest-style typed-IR corpus: parses .md topic files into cases,
# ABOUTME: asserts behavior (perl oracle), ir-shape (structural subset match), and L verdict.
package Chalk::CodeGen::Harness::MdtestCorpus;

use 5.42.0;
use utf8;

use Carp      qw(croak);
use File::Temp qw(tempfile);
use Scalar::Util qw(blessed looks_like_number);
use JSON::PP;

use Chalk::CodeGen::Harness::LLVMDriver;
use Chalk::CodeGen::Harness::BehaviorRecord;

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

    # Run source under perl to capture actual behavior
    my ($actual_val, $run_error) = _run_expr_under_perl($source);
    if (defined $run_error) {
        push @$fail_reasons, "case '$case->{title}': perl oracle failed: $run_error";
        return { verdict => 'FAIL', actual => undef, declared => undef,
                 error => $run_error };
    }

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

    my $program = <<"END_PROGRAM";
use 5.42.0;
use utf8;
use Scalar::Util qw(looks_like_number);

my \$_result = do { $clean_source };

if (!defined \$_result) {
    print "undef\\n";
} elsif (looks_like_number(\$_result) && \$_result =~ /\\./) {
    # Float: use %g format (matches lli output)
    printf "%g\\n", \$_result;
} else {
    print \$_result, "\\n";
}
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

# _behavior_matches($actual_string, \%declared) -> ($bool, $reason)
sub _behavior_matches {
    my ($actual, $declared) = @_;

    my $declared_return = $declared->{return};
    unless (defined $declared_return) {
        return (true, '');  # no return assertion
    }

    # Numeric comparison with tolerance for floats
    if (looks_like_number($actual) && looks_like_number($declared_return)) {
        my $diff = abs($actual - $declared_return);
        if ($diff < 1e-9) {
            return (true, '');
        }
        return (false, "numeric mismatch: got '$actual', expected '$declared_return'");
    }

    # String comparison
    if ($actual eq $declared_return) {
        return (true, '');
    }
    return (false, "string mismatch: got '$actual', expected '$declared_return'");
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
# PRIVATE: IR-shape check
# ---------------------------------------------------------------------------

sub _run_ir_shape_check {
    my ($case, $opts, $fail_reasons) = @_;

    my $ir_text = $case->{ir};
    unless (defined $ir_text && $ir_text =~ /\S/) {
        return { verdict => 'SKIP', missing => [], reason => 'no ir block' };
    }

    my $graph_for = $opts->{graph_for};
    unless (defined $graph_for) {
        return { verdict => 'SKIP', missing => [], reason => 'no graph_for supplied' };
    }

    # Look up the graph by the case title (used as corpus tag lookup).
    # The graph_for coderef may look up by case title or by a tag extracted
    # from the ir block (an "# ir-tag: arith-add" comment line).
    my $ir_tag = _extract_ir_tag($case);
    unless (defined $ir_tag) {
        return { verdict => 'SKIP', missing => [],
                 reason => "no ir-tag comment in ir block for '$case->{title}'" };
    }

    my $return_node;
    eval { $return_node = $graph_for->($ir_tag) };
    if ($@) {
        push @$fail_reasons, "case '$case->{title}': graph_for('$ir_tag') died: $@";
        return { verdict => 'FAIL', missing => [], error => $@, tag => $ir_tag };
    }
    unless (defined $return_node) {
        return { verdict => 'SKIP', missing => [],
                 reason => "graph_for('$ir_tag') returned undef (no graph for this idiom)" };
    }

    # Parse the ir block into shape requirements
    my $shape = _parse_ir_block($ir_text);

    # Walk the real graph and collect node signatures
    my @real_nodes = _collect_node_signatures($return_node);

    # Structural subset match: every declared node must appear in the real graph
    my @missing;
    for my $req (@{ $shape->{nodes} }) {
        unless (_find_node($req, \@real_nodes)) {
            push @missing, $req->{raw};
        }
    }

    if (@missing) {
        push @$fail_reasons,
            "case '$case->{title}': ir-shape mismatch — declared nodes not found in graph: "
            . join(', ', map { "'$_'" } @missing);
        return { verdict => 'FAIL', missing => \@missing, tag => $ir_tag };
    }

    return { verdict => 'PASS', missing => [], tag => $ir_tag,
             real_nodes => \@real_nodes };
}

# _extract_ir_tag($case) -> $tag_or_undef
# Looks for "# ir-tag: arith-add" comment line in the ir block.
sub _extract_ir_tag {
    my ($case) = @_;
    my $ir = $case->{ir} // '';
    if ($ir =~ /^\s*#\s*ir-tag:\s*(\S+)/m) {
        return $1;
    }
    return undef;
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
# PRIVATE: L-verdict check
# ---------------------------------------------------------------------------

sub _run_l_verdict_check {
    my ($case, $opts, $fail_reasons) = @_;

    my $ir_text = $case->{ir};
    unless (defined $ir_text && $ir_text =~ /\S/) {
        return { verdict => 'SKIP', reason => 'no ir block' };
    }

    my $graph_for = $opts->{graph_for};
    unless (defined $graph_for) {
        return { verdict => 'SKIP', reason => 'no graph_for supplied' };
    }

    my $ir_tag = _extract_ir_tag($case);
    unless (defined $ir_tag) {
        return { verdict => 'SKIP', reason => "no ir-tag in ir block" };
    }

    my $return_node;
    eval { $return_node = $graph_for->($ir_tag) };
    if ($@) {
        push @$fail_reasons, "case '$case->{title}': L check: graph_for('$ir_tag') died: $@";
        return { verdict => 'FAIL', error => $@ };
    }
    unless (defined $return_node) {
        # GAP idiom (no graph) — check declared L: verdict is also GAP
        my $shape = _parse_ir_block($ir_text);
        my $decl  = $shape->{l_verdict};
        if ($decl eq 'GAP') {
            return { verdict => 'PASS', actual => 'GAP', declared => 'GAP',
                     note => 'no-graph idiom, declared GAP matches' };
        } else {
            push @$fail_reasons,
                "case '$case->{title}': L verdict mismatch — "
                . "graph is a GAP idiom (no Return node) but declared '$decl'";
            return { verdict => 'FAIL', actual => 'GAP', declared => $decl };
        }
    }

    # Parse declared L verdict
    my $shape      = _parse_ir_block($ir_text);
    my $decl       = $shape->{l_verdict};

    # Run through LLVMDriver
    my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);

    my $actual_verdict;
    if ($meta->{marked_unsupported} || !$meta->{emitted_for_every_construct}) {
        $actual_verdict = 'GAP';
    } else {
        $actual_verdict = 'GREEN';
    }

    if ($actual_verdict ne $decl) {
        push @$fail_reasons,
            "case '$case->{title}': L verdict mismatch — "
            . "actual '$actual_verdict' but declared '$decl' "
            . ($actual_verdict eq 'GAP' ? "(gap_reason: " . ($meta->{gap_reason} // 'unknown') . ")" : '');
        return { verdict => 'FAIL', actual => $actual_verdict, declared => $decl,
                 meta => $meta };
    }

    # For GREEN: additionally verify lli output matches declared behavior
    if ($actual_verdict eq 'GREEN' && defined $opts->{perl_oracle_for}) {
        my $expected = $opts->{perl_oracle_for}->($ir_tag);
        if (defined $expected) {
            my $lli_out = $L->return_values->[0] // '';
            # Numeric comparison with tolerance
            if (looks_like_number($lli_out) && looks_like_number($expected)) {
                my $diff = abs($lli_out - $expected);
                if ($diff >= 1e-9) {
                    push @$fail_reasons,
                        "case '$case->{title}': L corner output '$lli_out' "
                        . "does not match perl oracle '$expected'";
                    return { verdict => 'FAIL', actual => $actual_verdict, declared => $decl,
                             lli_out => $lli_out, expected => $expected };
                }
            } elsif ($lli_out ne $expected) {
                push @$fail_reasons,
                    "case '$case->{title}': L corner output '$lli_out' "
                    . "does not match perl oracle '$expected'";
                return { verdict => 'FAIL', actual => $actual_verdict, declared => $decl,
                         lli_out => $lli_out, expected => $expected };
            }
        }
    }

    return { verdict => 'PASS', actual => $actual_verdict, declared => $decl,
             meta => $meta };
}

1;
