# ABOUTME: Pins that representation decisions in the LLVM backend go through the
# ABOUTME: %_REPR_LLVM_TYPE seam rather than naming a machine type at the emit site.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Target::LLVM;
use Chalk::Target::LLVM::Context;

# ---------------------------------------------------------------------------
# The seam itself. %_REPR_LLVM_TYPE is the declared authority for
# representation -> machine type; these are the functions that read it, so
# that no emit site has to name a type.
#
# T2 is a FUNCTOR between two different categories (perigrin): it maps objects
# (Int, Num -> i64, double) AND arrows (Int <: Num -> sitofp). _repr_to_llvm_type
# answered objects only. The three below answer the rest.
# ---------------------------------------------------------------------------
subtest 'the seam exists and answers for objects, zeros, opcodes and arrows' => sub {
    my $C = 'Chalk::Target::LLVM::Context';

    # Objects: unchanged pre-existing authority.
    is($C->can('_repr_to_llvm_type')->('Int'), 'i64',    'Int -> i64');
    is($C->can('_repr_to_llvm_type')->('Num'), 'double', 'Num -> double (today)');

    # The zero AT that type. A site emitting `0.0` beside a looked-up type is
    # a second authority that drifts the day the type changes.
    is($C->can('_repr_zero')->('Int'), '0',   'Int zero is 0');
    is($C->can('_repr_zero')->('Num'), '0.0', 'Num zero is 0.0 (today)');

    # Opcodes, keyed by the INTEGER mnemonic: the operation's identity is
    # representation-independent, and the representation picks the instruction.
    is($C->can('_repr_opcode')->('add', 'Int'), 'add',  'add at Int -> add');
    is($C->can('_repr_opcode')->('add', 'Num'), 'fadd', 'add at Num -> fadd (today)');
    is($C->can('_repr_opcode')->('icmp','Int'), 'icmp', 'icmp at Int -> icmp');
    is($C->can('_repr_opcode')->('icmp','Num'), 'fcmp', 'icmp at Num -> fcmp (today)');

    # Arrows. `Int <: Num` is a fact about the TYPES; that it costs a sitofp is
    # a fact about the current REPRESENTATION choice.
    is($C->can('_repr_convert_op')->('Int', 'Num'), 'sitofp', 'Int->Num arrow is sitofp (today)');
    is($C->can('_repr_convert_op')->('Num', 'Int'), 'fptosi', 'Num->Int arrow is fptosi (today)');
    is($C->can('_repr_convert_op')->('Boolean', 'Num'), 'uitofp',
        'Boolean->Num is uitofp -- i1 is UNSIGNED, the recorded bug');

    # An arrow between two reprs that SHARE a machine type is the identity, and
    # says so by emitting nothing. Scalar and Slot are the same encoding.
    is($C->can('_repr_convert_op')->('Scalar', 'Slot'), undef,
        'an arrow between reprs sharing a machine type is the identity (undef)');

    # The float predicate is derived, never asserted by name.
    ok( $C->can('_repr_is_float')->('Num'), 'Num is float-typed today');
    ok(!$C->can('_repr_is_float')->('Int'), 'Int is not float-typed');
};

# ---------------------------------------------------------------------------
# The point of the seam: the opcode follows the REPRESENTATION, not the repr's
# NAME. If %_REPR_LLVM_TYPE is changed so Num maps to an integral type, every
# derived answer must move WITH it -- with no edit at any emit site.
#
# This is the acceptance criterion for "the question is askable". It is not a
# proposal to widen Num; it proves the machinery would answer correctly if
# someone did.
# ---------------------------------------------------------------------------
subtest 'remapping Num flips opcodes and arrows with no emit-site edit' => sub {
    my $C = 'Chalk::Target::LLVM::Context';
    my $map  = $C->can('_repr_llvm_type_map')->();
    my $zero = $C->can('_repr_zero_map')->();

    # Since Z is a subset of R, a Num whose values are all integral can be
    # represented by an INTEGER type (perigrin). Nothing about the TYPE Num
    # requires a float REPRESENTATION.
    local $map->{Num}  = 'i64';
    local $zero->{Num} = '0';

    ok(!$C->can('_repr_is_float')->('Num'), 'Num is no longer float-typed');
    is($C->can('_repr_to_llvm_type')->('Num'), 'i64', 'Num now maps to i64');
    is($C->can('_repr_zero')->('Num'), '0', 'and its zero moved with it');

    is($C->can('_repr_opcode')->('add', 'Num'), 'add',
        'add at Num now picks the INTEGER opcode -- the whole point of the seam');
    is($C->can('_repr_opcode')->('icmp', 'Num'), 'icmp',
        'and the comparison picks icmp, so the predicate table choice follows');

    is($C->can('_repr_convert_op')->('Int', 'Num'), undef,
        'Int->Num is now the identity: same machine type, no instruction');
    is($C->can('_repr_convert_op')->('Num', 'Int'), undef,
        'and so is the reverse');
};

# ---------------------------------------------------------------------------
# No emit site may name a machine type it should have asked for.
#
# CODE ONLY: comment lines are stripped FIRST. Prose describing what was
# removed ("the `double` literal that stood here") is documentation, not a
# violation, and a grep that counted it would go red against its own history.
# ---------------------------------------------------------------------------
sub code_lines ($path) {
    open my $fh, '<:encoding(UTF-8)', $path or die "open $path: $!";
    my @out;
    my $lineno = 0;
    my $in_heredoc = 0;
    while (my $line = <$fh>) {
        $lineno++;
        # Heredoc bodies are emitted verbatim (the chalk_str_to_num helper);
        # they are a hand-written C-ABI function, not a lowering site.
        $in_heredoc = 1 if $line =~ /<<'?END_HELPER'?/;
        if ($in_heredoc) {
            $in_heredoc = 0 if $line =~ /^END_HELPER\s*$/;
            next;
        }
        next if $line =~ /^\s*#/;          # whole-line comment
        push @out, [ $lineno, $line ];
    }
    close $fh;
    return \@out;
}

# Sites allowed to name a floating machine type, each with the reason it is NOT
# a representation decision. Anything else naming `double` is a finding.
#
# Keyed by a PATTERN matching the line, not by a line number: a line-number
# allow-list goes stale on the next insertion above it, and a stale exemption
# is worse than none -- it hides the real finding it drifts onto.
my @ALLOWED = (
    # The authority itself, and the derived answers that read it.
    [ qr/^\s*Num\s+=> 'double',/          => 'the %_REPR_LLVM_TYPE entry: this IS the authority' ],
    [ qr/\$ty eq 'double' \|\| \$ty eq 'float'/ => '_repr_is_float reads the table to answer float-ness' ],

    # libc and helper ABIs: fixed by the C signature, not by any Chalk type.
    [ qr/declare double \@strtod/          => 'libc signature -- strtod returns a C double' ],
    [ qr/\@snprintf\(/                      => 'snprintf varargs slot must match %.15g -- printf contract' ],
    [ qr/\@chalk_str_to_num\(/              => 'helper ABI (the define at LLVM.pm:129)' ],

    # IEEE-754 Inf/NaN detection. These constants ARE binary64 and cannot be
    # derived from a repr; the fcmp compares against the exact bit patterns.
    #
    # Two exemptions stood beside this one and are GONE with the return-value
    # type-tag epilogue that owned their sites: the `unless $nty eq 'double'`
    # guard, and the `@printf(` varargs slot. This file's own inverse check --
    # "an exemption matching nothing is a hole in the net, left open for a site
    # that no longer exists" -- is what caught them, which is the check working
    # as designed rather than a regression.
    [ qr/fcmp (?:uno|oeq) double/          => 'IEEE-754 binary64 Inf/NaN detection, guarded above' ],

    # `double` as an English word in diagnostic prose, not a type name.
    [ qr/fdiv double\) not i64 sdiv/        => 'diagnostic text in the Int-repr Divide GAP message' ],
    [ qr/double quantifier/                => 'English: a doubled regex quantifier' ],
    [ qr/double-quotish/                   => 'English: double-quotish escapes' ],
);

subtest 'no unguarded machine-type literal at an emit site' => sub {
    my %used;
    for my $file (qw(lib/Chalk/Target/LLVM/Context.pm lib/Chalk/Target/LLVM.pm)) {
        my @found;
        LINE: for my $rec (code_lines($file)->@*) {
            my ($n, $line) = @$rec;
            next unless $line =~ /\bdouble\b/;
            for my $i (0 .. $#ALLOWED) {
                if ($line =~ $ALLOWED[$i][0]) { $used{$i} = 1; next LINE }
            }
            push @found, "$file:$n: $line";
        }
        is(scalar @found, 0, "$file names no unaccounted machine type")
            or diag("Unaccounted `double` at an emit site:\n" . join('', @found)
                  . "\nEither route it through _repr_to_llvm_type, or add it to "
                  . "\@ALLOWED in this test WITH the reason it is structural.");
    }

    # The inverse guard: an exemption matching nothing is a hole in the net,
    # left open for a site that no longer exists.
    for my $i (0 .. $#ALLOWED) {
        ok($used{$i}, "exemption still matches a real line: $ALLOWED[$i][1]")
            or diag("Stale exemption -- nothing matches $ALLOWED[$i][0]. Remove it.");
    }
};

# ---------------------------------------------------------------------------
# The parallel authority. LLVM.pm answered "what machine type" from its own
# literal chain, and had ALREADY DRIFTED once (its own comment at :205-210
# records Context growing a Scalar arm this one never got).
# ---------------------------------------------------------------------------
subtest 'the method return-type authority defers to the type map' => sub {
    my $ret = Chalk::Target::LLVM->can('_method_fn_llvm_ret_type');
    my $map = Chalk::Target::LLVM::Context->can('_repr_to_llvm_type');

    for my $repr (qw(Int Num Boolean Undef Scalar)) {
        is($ret->($repr), $map->($repr),
            "$repr: the return-type answer IS the type map's answer");
    }

    # THE DIVERGENCE IS GONE, which is what this now pins. A Str RETURN used
    # to cross the function boundary as %StrPair (ptr,len) while a Str VALUE
    # was %Str (ptr,len,enc) -- two types for one thing, and the difference was
    # a field nothing ever read.
    #
    # They are one type since the collapse (see
    # docs/plans/2026-09-02-finish-the-str-strpair-migration.md). This asserts
    # the AGREEMENT rather than deleting the check: the return type and the
    # value type must not drift apart again, and Str is the case where they
    # once did.
    is($ret->('Str'), $map->('Str'),
        'Str: the return type and the value type are the SAME type');
    is($map->('Str'), '%Str', 'and that type is %Str');

    # Remapping Num must move the return type too, or the vtable bitcast, the
    # call-site cast and the definition can disagree again.
    my $tmap = Chalk::Target::LLVM::Context->can('_repr_llvm_type_map')->();
    local $tmap->{Num} = 'i64';
    is($ret->('Num'), 'i64', 'a remapped Num moves the method return type with it');
};

done_testing;
