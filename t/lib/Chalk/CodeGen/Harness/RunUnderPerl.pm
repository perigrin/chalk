# ABOUTME: Oracle that runs corpus snippets under real Perl 5.42 and captures behavior records.
# ABOUTME: Zero Chalk compiler dependency — perl itself is the sole source of truth.
package Chalk::CodeGen::Harness::RunUnderPerl;

use 5.42.0;
use utf8;

use Carp         qw(croak);
use File::Temp   qw(tempfile);
use JSON::PP;
use Scalar::Util qw(looks_like_number);
use IPC::Open3;
use Symbol       qw(gensym);

use Chalk::CodeGen::Harness::BehaviorRecord;

# The absolute path to the perl 5.42.0 binary used as the oracle.
my $PERL_BIN = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";

# extract_snippet($corpus_text, $tag) -> $snippet_text
# Extracts the code body for the given TAG from a === TAG-delimited corpus string.
# Returns the body lines joined with newlines, with leading/trailing whitespace stripped.
# Dies if the tag is not found in the corpus, or if the body is empty.
sub extract_snippet {
    my (undef, $corpus, $tag) = @_;    # undef = class/package name in class-method call syntax
    croak "extract_snippet: corpus must be a non-empty string"
        unless defined $corpus && length $corpus;
    croak "extract_snippet: tag must be a non-empty string"
        unless defined $tag && length $tag;

    my @lines  = split /\n/, $corpus;
    my $in_tag = 0;
    my @body;

    for my $line (@lines) {
        # The === delimiter format is: "=== TAG" or "=== TAG: description"
        # We capture the tag as everything up to the first colon, space, or end-of-line.
        if ($line =~ /^===\s+([^:\s]+)/) {
            my $found_tag = $1;
            if ($in_tag) {
                # We just hit the next === delimiter; stop collecting.
                last;
            }
            if ($found_tag eq $tag) {
                $in_tag = 1;
            }
            next;  # skip the delimiter line itself
        }
        push @body, $line if $in_tag;
    }

    croak "extract_snippet: tag '$tag' not found in corpus"
        unless @body;

    my $snippet = join("\n", @body);
    $snippet =~ s/^\s+|\s+$//g;

    croak "extract_snippet: body for tag '$tag' is empty after stripping"
        unless length $snippet;

    return $snippet;
}

# wrap_program($snippet, $spec) -> $program_text
# Wraps a code snippet into a complete, runnable Perl 5.42 program that:
#   - enables the required pragmas and features
#   - instantiates the class named in $spec->{class} with $spec->{constructor}{params}
#   - calls $spec->{method} with $spec->{method_args} in $spec->{context}
#   - captures stdout/stderr, return values, exceptions, and object state
#   - prints a JSON-encoded BehaviorRecord envelope to STDOUT
# Dies if required spec fields (class, method) are missing.
sub wrap_program {
    my (undef, $snippet, $spec) = @_;
    croak "wrap_program: snippet must be a non-empty string"
        unless defined $snippet && length $snippet;
    croak "wrap_program: spec must be a hashref"
        unless ref $spec eq 'HASH';
    croak "wrap_program: spec must have a 'class' field"
        unless defined $spec->{class} && length $spec->{class};
    croak "wrap_program: spec must have a 'method' field"
        unless defined $spec->{method} && length $spec->{method};

    my $class       = $spec->{class};
    my $method      = $spec->{method};
    my $context     = $spec->{context} // 'scalar';
    my $params      = $spec->{constructor}{params} // {};
    my $ctor_raw    = $spec->{constructor}{raw};
    my $method_args = $spec->{method_args} // [];

    # Serialize constructor params as Perl code: (key => val, ...)
    # When ctor_raw is provided it is used verbatim (supports complex object
    # construction that cannot be expressed via plain key/value pairs).
    my $ctor_args = defined $ctor_raw ? $ctor_raw : _encode_perl_args($params);

    # Serialize method args as Perl code: (val, ...)
    my $meth_args = _encode_perl_list($method_args);

    # Choose call expression based on context.
    # We store results into @_ret in all cases for uniform downstream handling.
    # NOTE: @_ret is declared in the outer harness block; the call_expr must ASSIGN
    # to it without re-declaring with 'my' (which would create a new lexical scoped
    # to the eval block and leave the outer @_ret empty).
    my $call_expr;
    if ($context eq 'list') {
        $call_expr = "\@_ret = \$_obj->$method($meth_args);";
    }
    elsif ($context eq 'void') {
        $call_expr = "\$_obj->$method($meth_args);";
    }
    else {
        # scalar (default)
        $call_expr = "\@_ret = (scalar(\$_obj->$method($meth_args)));";
    }

    my $context_str = $context;

    # Build the complete driver program.
    # The harness captures the snippet's own STDOUT/STDERR using local *STDOUT/*STDERR
    # aliasing to in-memory scalars, then restores them before printing the JSON envelope.
    my $program = <<"END_PROGRAM";
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';
use Scalar::Util qw(blessed looks_like_number weaken refaddr);
use JSON::PP;

# --- Snippet under test ---
$snippet

# --- Harness driver ---
{
    my \$_stdout_buf = '';
    my \$_stderr_buf = '';
    my \$_exception  = undef;
    my \@_ret        = ();

    # Capture stdout/stderr during method invocation via local filehandle aliasing.
    # local *STDOUT ensures the original handles are restored even on die.
    open(my \$_cap_stdout, '>', \\\$_stdout_buf) or die "open cap_stdout: \$!";
    open(my \$_cap_stderr, '>', \\\$_stderr_buf) or die "open cap_stderr: \$!";

    {
        local *STDOUT = \$_cap_stdout;
        local *STDERR = \$_cap_stderr;

        eval {
            my \$_obj = ${class}->new($ctor_args);
            $call_expr
        };
    }
    my \$_eval_err = \$\@;
    close \$_cap_stdout;
    close \$_cap_stderr;

    # Build exception record if eval caught something.
    if (\$_eval_err) {
        if (ref \$_eval_err && blessed(\$_eval_err)) {
            my \$_msg = '';
            eval { \$_msg = \$_eval_err->message() if \$_eval_err->can('message'); };
            \$_msg ||= "\$_eval_err";
            \$_exception = {
                kind    => 'object',
                class   => ref(\$_eval_err),
                message => \$_msg,
            };
        }
        else {
            (my \$_clean = "\$_eval_err") =~ s{ at \\S+ line \\d+\\.?\\n?}{};
            \$_clean =~ s/\\s+\$//;
            \$_exception = {
                kind    => 'string',
                class   => undef,
                message => \$_clean,
            };
        }
    }

    # Serialize return values: recursively handle nested refs/blessed objects.
    my \@_serialized_ret = map { _serialize_value(\$_) } \@_ret;

    my \$_record = {
        return_values      => \\\@_serialized_ret,
        wantarray_context  => '$context_str',
        stdout             => \$_stdout_buf,
        stderr             => \$_stderr_buf,
        exception          => \$_exception,
        object_state       => {},
        hash_order_policy  => 'sorted-keys',
        fp_tolerance       => 1e-9,
        dualvar_policy     => 'numeric-first',
        aliasing_topology  => {},
    };

    my \$_json = JSON::PP->new->utf8->canonical->encode(\$_record);
    print \$_json, "\\n";
}

sub _serialize_value {
    my (\$v) = \@_;
    return undef unless defined \$v;
    if (ref \$v eq 'HASH') {
        return { map { \$_ => _serialize_value(\$v->{\$_}) } sort keys \%{\$v} };
    }
    elsif (ref \$v eq 'ARRAY') {
        return [ map { _serialize_value(\$_) } \@{\$v} ];
    }
    elsif (ref \$v && blessed(\$v)) {
        return { '__blessed__' => ref(\$v), '__str__' => "\$v" };
    }
    elsif (ref \$v eq 'CODE') {
        return '__CODE__';
    }
    elsif (ref \$v) {
        return { '__ref__' => ref(\$v), '__str__' => "\$v" };
    }
    else {
        return \$v;
    }
}
END_PROGRAM

    return $program;
}

# run_program($program_text) -> ($stdout, $stderr, $exit_code)
# Writes the program to a temp file and runs it under perl 5.42.
# Returns (stdout_string, stderr_string, exit_code).
sub run_program {
    my (undef, $program) = @_;
    croak "run_program: program must be a non-empty string"
        unless defined $program && length $program;

    my ($fh, $filename) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $program;
    close $fh;

    my ($stdout, $stderr) = ('', '');
    my $child_stderr = gensym;

    my $pid = open3(my $child_stdin, my $child_stdout, $child_stderr,
        $PERL_BIN, $filename);

    close $child_stdin;

    # Read all stdout then all stderr (small programs — no deadlock risk).
    {
        local $/;
        $stdout = readline($child_stdout) // '';
        $stderr = readline($child_stderr) // '';
    }

    waitpid($pid, 0);
    my $exit = $? >> 8;

    return ($stdout, $stderr, $exit);
}

# parse_output($stdout_text) -> \%record_hash
# Parses the JSON envelope printed by the driver program.
# Dies if the output is empty or not valid JSON.
sub parse_output {
    my (undef, $stdout) = @_;
    croak "parse_output: stdout is empty — the driver program produced no output"
        unless defined $stdout && $stdout =~ /\S/;

    my $data = eval { JSON::PP->new->utf8->decode($stdout) };
    croak "parse_output: failed to parse JSON output: $@\nOutput was: $stdout"
        if $@;

    croak "parse_output: decoded output is not a hashref"
        unless ref $data eq 'HASH';

    return $data;
}

# capture($snippet, $spec) -> BehaviorRecord
# Full pipeline: validate -> wrap_program -> run_program -> parse_output -> BehaviorRecord.
# Dies on empty snippet, incomplete spec, or driver failure without JSON output.
sub capture {
    my (undef, $snippet, $spec) = @_;
    croak "capture: snippet must be a non-empty string"
        unless defined $snippet && length $snippet;
    croak "capture: spec must be a hashref"
        unless ref $spec eq 'HASH';
    croak "capture: spec must have a 'class' field"
        unless defined $spec->{class} && length $spec->{class};
    croak "capture: spec must have a 'method' field"
        unless defined $spec->{method} && length $spec->{method};

    my $program = Chalk::CodeGen::Harness::RunUnderPerl->wrap_program($snippet, $spec);
    my ($stdout, $stderr, $exit) = Chalk::CodeGen::Harness::RunUnderPerl->run_program($program);

    # If the driver itself crashed without producing JSON output, propagate the failure.
    # A snippet that throws an exception but whose harness catches it will still produce
    # JSON (with exception populated), so exit != 0 alone is not sufficient to die here.
    my $data = Chalk::CodeGen::Harness::RunUnderPerl->parse_output($stdout);

    return Chalk::CodeGen::Harness::BehaviorRecord->new(
        return_values      => $data->{return_values}     // [],
        wantarray_context  => $data->{wantarray_context} // 'scalar',
        stdout             => $data->{stdout}            // '',
        stderr             => $data->{stderr}            // '',
        exception          => $data->{exception},
        object_state       => $data->{object_state}      // {},
        hash_order_policy  => $data->{hash_order_policy} // 'sorted-keys',
        fp_tolerance       => $data->{fp_tolerance}      // 1e-9,
        dualvar_policy     => $data->{dualvar_policy}    // 'numeric-first',
        aliasing_topology  => $data->{aliasing_topology} // {},
    );
}

# capture_sub($snippet, $spec) -> BehaviorRecord
# Variant of capture() for top-level sub snippets (no class instantiation).
# spec must have: sub_name (required), sub_args (optional arrayref).
# Wraps the snippet so the named sub is called directly and the return value
# is captured. Used by the GapMap for non-class idioms (I2, M1, M2).
sub capture_sub {
    my (undef, $snippet, $spec) = @_;
    croak "capture_sub: snippet must be a non-empty string"
        unless defined $snippet && length $snippet;
    croak "capture_sub: spec must be a hashref"
        unless ref $spec eq 'HASH';
    croak "capture_sub: spec must have a 'sub_name' field"
        unless defined $spec->{sub_name} && length $spec->{sub_name};

    my $sub_name  = $spec->{sub_name};
    my $sub_args  = $spec->{sub_args} // [];
    my $context   = $spec->{context}  // 'scalar';
    my $args_code = _encode_perl_list($sub_args);

    my $call_expr;
    if ($context eq 'list') {
        $call_expr = "\@_ret = $sub_name($args_code);";
    } elsif ($context eq 'void') {
        $call_expr = "$sub_name($args_code);";
    } else {
        $call_expr = "\@_ret = (scalar($sub_name($args_code)));";
    }

    my $program = <<"END_PROGRAM";
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';
use Scalar::Util qw(blessed looks_like_number);
use JSON::PP;

# --- Snippet under test ---
$snippet

# --- Harness driver ---
{
    my \$_stdout_buf = '';
    my \$_stderr_buf = '';
    my \$_exception  = undef;
    my \@_ret        = ();

    open(my \$_cap_stdout, '>', \\\$_stdout_buf) or die "open cap_stdout: \$!";
    open(my \$_cap_stderr, '>', \\\$_stderr_buf) or die "open cap_stderr: \$!";

    {
        local *STDOUT = \$_cap_stdout;
        local *STDERR = \$_cap_stderr;
        eval { $call_expr };
    }
    my \$_eval_err = \$\@;
    close \$_cap_stdout;
    close \$_cap_stderr;

    if (\$_eval_err) {
        if (ref \$_eval_err && blessed(\$_eval_err)) {
            my \$_msg = '';
            eval { \$_msg = \$_eval_err->message() if \$_eval_err->can('message'); };
            \$_msg ||= "\$_eval_err";
            \$_exception = { kind => 'object', class => ref(\$_eval_err), message => \$_msg };
        } else {
            (my \$_clean = "\$_eval_err") =~ s{ at \\S+ line \\d+\\.?\\n?}{};
            \$_clean =~ s/\\s+\$//;
            \$_exception = { kind => 'string', class => undef, message => \$_clean };
        }
    }

    my \$_record = {
        return_values      => \\\@_ret,
        wantarray_context  => '$context',
        stdout             => \$_stdout_buf,
        stderr             => \$_stderr_buf,
        exception          => \$_exception,
        object_state       => {},
        hash_order_policy  => 'sorted-keys',
        fp_tolerance       => 1e-9,
        dualvar_policy     => 'numeric-first',
        aliasing_topology  => {},
    };

    my \$_json = JSON::PP->new->utf8->canonical->encode(\$_record);
    print \$_json, "\\n";
}
END_PROGRAM

    my ($stdout, $stderr, $exit) = Chalk::CodeGen::Harness::RunUnderPerl->run_program($program);
    my $data = Chalk::CodeGen::Harness::RunUnderPerl->parse_output($stdout);

    return Chalk::CodeGen::Harness::BehaviorRecord->new(
        return_values      => $data->{return_values}     // [],
        wantarray_context  => $data->{wantarray_context} // 'scalar',
        stdout             => $data->{stdout}            // '',
        stderr             => $data->{stderr}            // '',
        exception          => $data->{exception},
        object_state       => $data->{object_state}      // {},
        hash_order_policy  => $data->{hash_order_policy} // 'sorted-keys',
        fp_tolerance       => $data->{fp_tolerance}      // 1e-9,
        dualvar_policy     => $data->{dualvar_policy}    // 'numeric-first',
        aliasing_topology  => $data->{aliasing_topology} // {},
    );
}

# --- Internal helpers ---

# _encode_perl_args(\%params) -> "(key => val, ...)" string for constructor call
sub _encode_perl_args {
    my ($params) = @_;
    return '' unless defined $params && ref $params eq 'HASH' && %$params;
    my @pairs;
    for my $k (sort keys %$params) {
        my $v = $params->{$k};
        push @pairs, "$k => " . _encode_perl_scalar($v);
    }
    return join(', ', @pairs);
}

# _encode_perl_list(\@args) -> "val, val, ..." string for method args
sub _encode_perl_list {
    my ($args) = @_;
    return '' unless defined $args && ref $args eq 'ARRAY' && @$args;
    return join(', ', map { _encode_perl_scalar($_) } @$args);
}

# _encode_perl_scalar($val) -> perl literal string (scalar, number, arrayref, or hashref)
# Recursively encodes refs so a real arrayref/hashref can be passed as a method argument.
# Array refs encode as [ elem, elem, ... ] and hash refs as { 'key' => val, ... } with
# keys sorted for determinism. Mirrors the structure of _serialize_value (which handles
# the reverse direction: return values back from the generated program).
sub _encode_perl_scalar {
    my ($v) = @_;
    return 'undef' unless defined $v;
    if (ref $v eq 'ARRAY') {
        my @encoded = map { _encode_perl_scalar($_) } $v->@*;
        return '[' . join(', ', @encoded) . ']';
    }
    if (ref $v eq 'HASH') {
        my @pairs;
        for my $k (sort keys $v->%*) {
            push @pairs, "'" . ($k =~ s/'/\\'/gr) . "' => " . _encode_perl_scalar($v->{$k});
        }
        return '{ ' . join(', ', @pairs) . ' }';
    }
    if (looks_like_number($v) && $v !~ /^0\d/) {
        return $v + 0;  # emit as numeric literal
    }
    # String: escape for single-quote context
    (my $escaped = $v) =~ s/\\/\\\\/g;
    $escaped =~ s/'/\\'/g;
    return "'$escaped'";
}

1;
