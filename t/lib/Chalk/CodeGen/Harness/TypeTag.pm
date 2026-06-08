# ABOUTME: Canonical type-tag contract for the typed-compare oracle (G2+).
# ABOUTME: Single source of truth for infer_tag, tag_live_value, and LLVM prefix constants.
package Chalk::CodeGen::Harness::TypeTag;

use 5.42.0;
use utf8;

use Scalar::Util qw(looks_like_number);
use builtin      qw(is_bool);
no warnings 'experimental::builtin';

# ---------------------------------------------------------------------------
# infer_tag($string_or_undef) -> $tagged_string
#
# Tags a DECLARED string value from a behavior block (is_bool not available).
# Rules:
#   undef                              -> 'Undef:'
#   already carries a type prefix      -> pass through unchanged
#   empty string                       -> 'Str:'  (not 'Bool:' — cannot distinguish)
#   looks_like_number with decimal     -> sprintf('Num:%g', $val)
#   looks_like_number                  -> "Int:$val"
#   else                               -> "Str:$val"
#
# This is the declared-value oracle: it handles the corpus behavior-block
# 'return:' values that were historically plain untagged strings.
# ---------------------------------------------------------------------------
sub infer_tag {
    my ($val) = @_;
    return 'Undef:' unless defined $val;

    # Already tagged: pass through unchanged.
    return $val if $val =~ /^(?:Bool:|Int:|Num:|Str:|Undef:)/;

    # Empty string declared as "" — could be Str or Bool:false. We cannot
    # distinguish here; treat as Str: so that only properly-tagged Bool: behavior
    # blocks match a Bool:false perl result.
    return 'Str:' if $val eq '';

    if (looks_like_number($val)) {
        # Non-finite: perl stringifies Inf/-Inf/NaN (capitalized). Detect by the
        # canonical face so that declared "Inf" or "NaN" tags correctly as Num:.
        if ($val =~ /^Inf$/i)  { return 'Num:Inf'  }
        if ($val =~ /^-Inf$/i) { return 'Num:-Inf' }
        if ($val =~ /^NaN$/i)  { return 'Num:NaN'  }
        if ($val =~ /\./) {
            return sprintf('Num:%g', $val);
        }
        return "Int:$val";
    }
    return "Str:$val";
}

# ---------------------------------------------------------------------------
# tag_live_value($scalar) -> $tagged_string
#
# Tags a LIVE Perl value (is_bool available). This is the canonical live-value
# oracle rule used by both MdtestCorpus's generated oracle program and
# ReturnNodePerlDriver's print statements.
#
# Rules (checked in order):
#   is_bool true          -> 'Bool:1'
#   is_bool false         -> 'Bool:'
#   undef                 -> 'Undef:'
#   looks_like_number
#     with decimal        -> sprintf('Num:%g', $val)
#     without             -> "Int:$val"
#   else                  -> "Str:$val"
# ---------------------------------------------------------------------------
sub tag_live_value {
    my ($val) = @_;

    if (is_bool($val)) {
        return 'Bool:' . ($val ? '1' : '');
    }
    unless (defined $val) {
        return 'Undef:';
    }
    # Non-finite numerics: perl stringifies these as Inf/-Inf/NaN (capitalized).
    # looks_like_number returns true for Inf/NaN (no decimal point), which would
    # mis-tag them as Int:. Detect and tag as Num: with the perl canonical face.
    if (looks_like_number($val)) {
        my $str = "$val";  # stringify via perl to get the canonical face
        if ($str =~ /^Inf$/i)  { return 'Num:Inf'  }
        if ($str =~ /^-Inf$/i) { return 'Num:-Inf' }
        if ($str =~ /^NaN$/i)  { return 'Num:NaN'  }
        if ($val =~ /\./) {
            return sprintf('Num:%g', $val);
        }
        return "Int:$val";
    }
    return "Str:$val";
}

# ---------------------------------------------------------------------------
# oracle_perl_fragment() -> $perl_source_string
#
# Returns a Perl code fragment (suitable for embedding in a generated .pl
# program) that, given the result in $_ result, prints the canonical type-tag.
# The fragment assumes the result is in a variable named $_result.
#
# The generated program must include:
#   use lib 't/lib';
#   use Chalk::CodeGen::Harness::TypeTag;
# and must be run with -It/lib in @INC so that the module is locatable.
# ---------------------------------------------------------------------------
sub oracle_perl_fragment {
    return <<'END_FRAGMENT';
use Scalar::Util qw(looks_like_number);
use builtin qw(is_bool);
no warnings 'experimental::builtin';
if (is_bool($_result)) {
    print "Bool:" . ($_result ? "1" : "") . "\n";
} elsif (!defined $_result) {
    print "Undef:\n";
} elsif (looks_like_number($_result)) {
    my $_str = "$_result";
    if    ($_str =~ /^Inf$/i)  { print "Num:Inf\n"  }
    elsif ($_str =~ /^-Inf$/i) { print "Num:-Inf\n" }
    elsif ($_str =~ /^NaN$/i)  { print "Num:NaN\n"  }
    elsif ($_result =~ /\./)   { printf "Num:%g\n", $_result }
    else                       { print "Int:$_result\n" }
} else {
    print "Str:$_result\n";
}
END_FRAGMENT
}

# ---------------------------------------------------------------------------
# llvm_prefixes() -> \%prefixes
#
# Returns the canonical tag-prefix table for each supported IR representation.
# The LLVM backend hard-codes these strings into LLVM IR constants; this table
# pins them equal to the perl-oracle prefixes so divergence is caught by test.
#
# Each entry:
#   Int:
#     perl_tag_prefix => 'Int:'
#     llvm_fmt_c      => 'Int:%d\0A\00'   (LLVM c"..." syntax, 8 bytes)
#   Num:
#     perl_tag_prefix => 'Num:'
#     llvm_fmt_c      => 'Num:%g\0A\00'   (8 bytes)
#   Bool:
#     perl_tag_prefix_true  => 'Bool:1'
#     perl_tag_prefix_false => 'Bool:'
#     llvm_true_c           => 'Bool:1\0A\00'   (8 bytes)
#     llvm_false_c          => 'Bool:\0A\00'    (7 bytes)
#   Str:
#     perl_tag_prefix => 'Str:'
#     llvm_fmt_c      => 'Str:%s\0A\00'   (8 bytes)
# ---------------------------------------------------------------------------
sub llvm_prefixes {
    return {
        Int => {
            perl_tag_prefix => 'Int:',
            llvm_fmt_c      => 'Int:%d\0A\00',
        },
        Num => {
            perl_tag_prefix => 'Num:',
            llvm_fmt_c      => 'Num:%g\0A\00',
        },
        Bool => {
            perl_tag_prefix_true  => 'Bool:1',
            perl_tag_prefix_false => 'Bool:',
            llvm_true_c           => 'Bool:1\0A\00',
            llvm_false_c          => 'Bool:\0A\00',
        },
        Str => {
            perl_tag_prefix => 'Str:',
            llvm_fmt_c      => 'Str:%s\0A\00',
        },
        Undef => {
            perl_tag_prefix => 'Undef:',
            llvm_fmt_c      => 'Undef:\0A\00',
        },
    };
}

1;
