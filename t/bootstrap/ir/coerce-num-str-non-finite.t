# ABOUTME: Coerce(Num->Str) renders Inf/-Inf/NaN the way perl does, not the way C does.
# ABOUTME: The fixup lived in the deleted return-value epilogue; a real program reaches the Coerce.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';
plan skip_all => "lli not found at $LLI" unless -x $LLI;

# perl and C DISAGREE on how a non-finite double stringifies. Measured on
# perl 5.42.0:
#
#   9**9**9          "Inf"      C's %g gives "inf"
#   -9**9**9         "-Inf"     C gives "-inf"
#   9**9**9 - 9**9**9 "NaN"     C gives "nan"
#
# The return-value type-tag epilogue HAD a fixup for this (LLVM.pm: fcmp uno
# for NaN, fcmp oeq against the +/-Inf bit patterns, selecting perl-spelled
# string constants). Coerce(Num->Str) does not -- it is a bare
# snprintf("%.15g"), so it emits C's spelling.
#
# That was invisible while every observation of a Num went through the
# epilogue. A program that PRINTS a non-finite value reaches the Coerce
# instead, so the epilogue's deletion turns a latent divergence into a live
# wrong answer. The fixup belongs on the Coerce, where a real program meets
# it.

sub run_ll ($ll) {
    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll;
    close $fh;
    my $out  = qx($LLI $tmp 2>&1);
    my $exit = $? >> 8;
    chomp $out;
    return ($out, $exit);
}

# A program that prints one Num, bracketed so an empty result is
# distinguishable from no result at all.
sub print_num ($bits, $label) {
    my $f = Chalk::IR::NodeFactory->new;

    my $c = $f->make('Constant', value => $bits, const_type => 'number');
    $c->set_representation('Num');
    my $s = $f->make('Coerce', inputs => [$c], from_repr => 'Num', to_repr => 'Str');
    $s->set_representation('Str');

    my $lb = $f->make('Constant', value => '[', const_type => 'string');
    $lb->set_representation('Str');
    my $rb = $f->make('Constant', value => ']', const_type => 'string');
    $rb->set_representation('Str');

    my $start = $f->make_cfg('Start');
    my $print = $f->make('Print', inputs => [$lb, $s, $rb]);
    $print->set_control_in($start);

    my $u = $f->make('Constant', value => undef, const_type => 'undef');
    $u->set_representation('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$u]);
    $ret->set_control_in($print);

    my $ll = eval { Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    die "lower failed for $label: $@" unless $ll;
    return run_ll($ll);
}

# The three non-finite spellings, against what perl 5.42.0 actually prints.
# These are LLVM hex double literals: the same bit patterns the epilogue's
# fcmp compared against.
my @cases = (
    [ '0x7FF0000000000000', 'Inf',  '+Inf'  ],
    [ '0xFFF0000000000000', '-Inf', '-Inf'  ],
    [ '0x7FF8000000000000', 'NaN',  'NaN'   ],
);

for my $case (@cases) {
    my ($bits, $want, $label) = $case->@*;
    my ($out, $exit) = print_num($bits, $label);
    is($exit, 0, "$label: exits 0");
    is($out, "[$want]", "$label: prints perl's spelling, not C's");
}

# THE CONTROL. A finite value must be untouched by the fixup -- a branch that
# sent every value down the non-finite path would still pass the three cases
# above. `1e+34` is perl's own rendering (%.15g), so this also pins that the
# finite path is still %.15g and not something the fix rewrote.
{
    my ($out, $exit) = print_num('1.0e+34', 'finite');
    is($exit, 0, 'finite: exits 0');
    is($out, '[1e+34]', 'finite: still renders through %.15g, untouched by the fixup');
}

{
    my ($out, $exit) = print_num('0.1', 'finite small');
    is($out, '[0.1]', 'finite small: 0.1 renders as perl does');
}

done_testing;
