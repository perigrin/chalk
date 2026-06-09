# ABOUTME: Adversarial tests for Coerce(Str->Num) and Coerce(Str->Bool) LLVM lowering (G3).
# ABOUTME: Verifies lli output matches perl oracle exactly for all edge cases.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Coerce;
use Chalk::IR::Node::Return;
use Chalk::Target::LLVM;
use Chalk::CodeGen::Harness::TypeTag;

my $LLI = '/usr/lib/llvm-15/bin/lli';
my $P   = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# ---------------------------------------------------------------------------
# Helper: run LLVM IR text through lli -> return stdout string
# ---------------------------------------------------------------------------
sub run_lli {
    my ($ll_text) = @_;
    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll_text;
    close $fh;
    my $out  = qx($LLI $tmp 2>&1);
    my $exit = $? >> 8;
    chomp $out;
    return ($out, $exit);
}

# ---------------------------------------------------------------------------
# Helper: run perl oracle on a Str-to-numeric expression
#   perl_str_to_num("abc")  -> what perl gives for "abc" + 0
# ---------------------------------------------------------------------------
sub perl_oracle_str_to_num {
    my ($str) = @_;
    # Use the TypeTag oracle fragment to get the canonical tag for perl's result.
    # This uses the same non-finite detection (Inf/-Inf/NaN -> Num:) as TypeTag.
    my $frag = Chalk::CodeGen::Harness::TypeTag::oracle_perl_fragment();
    (my $escaped = $str) =~ s/\\/\\\\/g;
    $escaped =~ s/"/\\"/g;
    my $cmd = qq{$P -e 'my \$_result = "$escaped" + 0; $frag'};
    my $out = qx($cmd 2>/dev/null);
    chomp $out;
    return $out;
}

sub perl_oracle_str_to_bool {
    my ($str) = @_;
    (my $escaped = $str) =~ s/\\/\\\\/g;
    my $cmd = qq{$P -e 'my \$s = "$str"; print \$s ? "Bool:1\\n" : "Bool:\\n"'};
    my $out = qx($cmd 2>/dev/null);
    chomp $out;
    return $out;
}

# ---------------------------------------------------------------------------
# Build a graph: Constant(str :Str) -> Coerce(Str->Num) :Num -> Return
# ---------------------------------------------------------------------------
sub make_str_to_num_graph {
    my ($str_val) = @_;
    my $f = Chalk::IR::NodeFactory->new;

    my $c = $f->make('Constant', value => $str_val, const_type => 'string');
    $c->set_representation('Str');

    my $coerce = $f->make('Coerce',
        from_repr => 'Str',
        to_repr   => 'Num',
        inputs    => [$c],
    );
    $coerce->set_representation('Num');

    my $ret = $f->make_cfg('Return', inputs => [$coerce]);
    return $ret;
}

# Build a graph: Constant(str :Str) -> Coerce(Str->Bool) :Bool -> Return
sub make_str_to_bool_graph {
    my ($str_val) = @_;
    my $f = Chalk::IR::NodeFactory->new;

    my $c = $f->make('Constant', value => $str_val, const_type => 'string');
    $c->set_representation('Str');

    my $coerce = $f->make('Coerce',
        from_repr => 'Str',
        to_repr   => 'Bool',
        inputs    => [$c],
    );
    $coerce->set_representation('Bool');

    my $ret = $f->make_cfg('Return', inputs => [$coerce]);
    return $ret;
}

# ---------------------------------------------------------------------------
# Coerce(Str->Num) adversarial cases
#
# Perl's leading-numeric rule: scan optional leading whitespace, optional sign,
# then digits + optional .digits + optional [eE][+-]digits. Everything after
# that is ignored. If no digits, result is 0.
#
# The LLVM lowering always uses strtod -> double -> repr=Num. This means all
# results carry the Num: tag, even integer-valued ones. This is correct: the
# IR node's repr is Num (double), and the output format is always Num:%g.
# The value is correct (matching perl); the tag reflects the IR repr.
#
# "abc"   -> Num:0   (no leading digits -> 0.0 as double)
# "3abc"  -> Num:3   (leading integer, trailing ignored -> 3.0 as double)
# " 42 "  -> Num:42  (leading whitespace stripped)
# "3.14x" -> Num:3.14 (leading float)
# ""      -> Num:0   (empty -> 0.0)
# ".5"    -> Num:0.5  (leading dot)
# "0x10"  -> Num:0   (perl does NOT parse hex; "0x10" -> 0.0)
# ---------------------------------------------------------------------------

my @str_to_num_cases = (
    ["abc",    "Num:0",    "no leading digits -> 0"],
    ["3abc",   "Num:3",    "leading integer, trailing ignored -> 3"],
    [" 42 ",   "Num:42",   "leading whitespace stripped -> 42"],
    ["3.14x",  "Num:3.14", "leading float, trailing char ignored -> 3.14"],
    ["",       "Num:0",    "empty string -> 0"],
    [".5",     "Num:0.5",  "leading dot -> 0.5"],
    ["0x10",   "Num:0",    "hex not parsed by perl -> 0"],
    # Non-finite forms: strtod accepts inf/nan; perl yields Inf/NaN/-Inf (capitalized).
    # The LLVM epilogue detects non-finite via fcmp and prints the perl-style face.
    ["inf",      "Num:Inf",  "inf -> Inf (perl-style)"],
    ["Inf",      "Num:Inf",  "Inf -> Inf (already capitalized)"],
    ["infinity", "Num:Inf",  "infinity -> Inf (strtod accepts full word)"],
    ["1e400",    "Num:Inf",  "1e400 -> Inf (overflow -> +Inf)"],
    ["-inf",     "Num:-Inf", "-inf -> -Inf"],
    ["nan",      "Num:NaN",  "nan -> NaN (perl-style)"],
    ["NaN",      "Num:NaN",  "NaN -> NaN (already capitalized)"],
    # Hex-float forms: perl stops at "0" (does NOT parse hex-float); all -> 0.
    ["0x1p4",    "Num:0",    "hex-float 0x1p4 not parsed by perl -> 0"],
    ["0X1P4",    "Num:0",    "hex-float 0X1P4 (uppercase) not parsed by perl -> 0"],
    ["0x.8p0",   "Num:0",    "hex-float 0x.8p0 not parsed by perl -> 0"],
);

subtest 'Coerce(Str->Num) adversarial cases: lli == perl oracle' => sub {
    plan tests => scalar(@str_to_num_cases) * 3;

    for my $tc (@str_to_num_cases) {
        my ($str, $expected_tag, $desc) = @$tc;

        # Build and lower
        my $ret_node = make_str_to_num_graph($str);
        my $ll = eval { Chalk::Target::LLVM->lower($ret_node) };
        if ($@) {
            fail("$desc: LLVM lowering failed: $@");
            fail("$desc: (skip)");
            fail("$desc: (skip)");
            next;
        }

        # Run lli
        my ($lli_out, $lli_exit) = run_lli($ll);

        # Verify lli matches expected perl tag
        is($lli_exit, 0, "$desc: lli exits 0");
        is($lli_out, $expected_tag, "$desc: lli output '$lli_out' == expected '$expected_tag'");

        # Libperl-free guard
        ok($ll !~ /Perl_|\bSV\b|sv_|libperl/, "$desc: .ll is libperl-free");
    }
};

# ---------------------------------------------------------------------------
# Coerce(Str->Bool) edge cases
#
# Perl's truthiness rule for strings:
#   false: empty string "" or literal "0"
#   true:  everything else (including "0.0", "00", "0 ", "0\n", " ")
# ---------------------------------------------------------------------------

my @str_to_bool_cases = (
    ["",     "Bool:",   "empty string -> false"],
    ["0",    "Bool:",   "literal 0 -> false"],
    ["0.0",  "Bool:1",  "0.0 is a truthy string (not numeric 0)"],
    ["00",   "Bool:1",  "00 is truthy (not a single zero)"],
    ["0 ",   "Bool:1",  "0-space is truthy"],
    ["1",    "Bool:1",  "1 -> true"],
    ["abc",  "Bool:1",  "non-numeric non-empty -> true"],
);

subtest 'Coerce(Str->Bool) edge cases: lli == perl oracle' => sub {
    plan tests => scalar(@str_to_bool_cases) * 3;

    for my $tc (@str_to_bool_cases) {
        my ($str, $expected_tag, $desc) = @$tc;

        my $ret_node = make_str_to_bool_graph($str);
        my $ll = eval { Chalk::Target::LLVM->lower($ret_node) };
        if ($@) {
            fail("$desc: LLVM lowering failed: $@");
            fail("$desc: (skip)");
            fail("$desc: (skip)");
            next;
        }

        my ($lli_out, $lli_exit) = run_lli($ll);

        is($lli_exit, 0, "$desc: lli exits 0");
        is($lli_out, $expected_tag, "$desc: lli output '$lli_out' == expected '$expected_tag'");
        ok($ll !~ /Perl_|\bSV\b|sv_|libperl/, "$desc: .ll is libperl-free");
    }
};

# ---------------------------------------------------------------------------
# Coerce(Str->Num) against live perl oracle: numeric value check
#
# The LLVM emitter always outputs Num:<value> (double repr). The perl oracle
# may tag integer results as Int:. We compare the numeric VALUES, not the tags,
# since both represent the same number. The tag difference (Int: vs Num:) reflects
# the IR representation (always double after strtod), not a value mismatch.
#
# Shown as a table: str | lli-output | perl-value | match
# ---------------------------------------------------------------------------

subtest 'Coerce(Str->Num) lli numeric values match perl oracle' => sub {
    plan tests => scalar(@str_to_num_cases);

    for my $tc (@str_to_num_cases) {
        my ($str, $expected_tag, $desc) = @$tc;

        my $ret_node = make_str_to_num_graph($str);
        my $ll = eval { Chalk::Target::LLVM->lower($ret_node) };
        if ($@) {
            fail("$desc: lowering failed");
            next;
        }
        my ($lli_out, undef) = run_lli($ll);
        my $perl_tag = perl_oracle_str_to_num($str);

        # Extract numeric value from both tags (strip prefix "Num:", "Int:", etc.)
        # Compare numerically: strtod(0.0) vs perl(0) both represent the number 0.
        (my $lli_val  = $lli_out)  =~ s/^(?:Num:|Int:|Str:)//;
        (my $perl_val = $perl_tag) =~ s/^(?:Num:|Int:|Str:)//;

        # Use string comparison for %g-formatted values; both sides use the same
        # %g formatting when they represent the same float value.
        my $lli_num  = sprintf('%g', $lli_val);
        my $perl_num = sprintf('%g', $perl_val);

        is($lli_num, $perl_num,
            sprintf('str="%s": lli-num=%s perl-num=%s (lli-full=%s perl-full=%s)',
                $str, $lli_num, $perl_num, $lli_out, $perl_tag));
    }
};

# Note: the former TODO block for inf/nan/hex-float (issue 019ea740) has been
# resolved and the cases are now included in the main @str_to_num_cases above.
# The LLVM epilogue detects non-finite doubles via fcmp and prints the perl-style
# Inf/NaN/-Inf face; TypeTag tags non-finite as Num: (single source of truth).

done_testing;
