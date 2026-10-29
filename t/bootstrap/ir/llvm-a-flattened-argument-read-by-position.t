# ABOUTME: an array or list argument fills as many positions of @_ as it has elements,
# ABOUTME: read by position: through B::SoN -> chalk -> lli == perl, or refused by name.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

sub through_llvm ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# `my ($c, $a, $b) = @_` of f(@x) read undef past the first argument, so the
# call was refused (pvm 174, "an argument stamped Array flattens into @_").
for my $case (
    [ q{sub f { my ($c, $a, $b) = @_; return "$c/$a/" . ($b // 'u') } my @x = (1, "P", 3); print f(@x), "\n";}, "1/P/3\n", 'f(@x), my (...) = @_' ],
    [ q{sub f { my ($c, $a, $b) = @_; return "$c/$a/" . ($b // 'u') } my @x = ("P"); print f(1, @x), "\n";}, "1/P/u\n", 'f(1, @x), short' ],
    [ q{sub f { my $c = shift; my $a = shift; return "$c/$a" } my @x = (7, 8, 9); print f(@x), "\n";}, "7/8\n", 'f(@x), two shifts' ],
    [ q{sub f { return $_[0] + $_[2] } my @x = (1, 2, 3); print f(@x), "\n";}, "4\n", 'f(@x), $_[0] and $_[2]' ],
    [ q{sub g { (5, 6) } sub f { my ($a, $b) = @_; return $a * $b } print f(g()), "\n";}, "30\n", 'f(g()), a list a call returns' ],
    # NOT FLATTENED, the same read: `$b // 'u'` of an argument not passed was a
    # %Slot that the concatenation took for a %Str (lli rejected the module).
    [ q{sub f { my ($c, $a, $b) = @_; return "$c/$a/" . ($b // 'u') } print f(1, "P"), "\n";}, "1/P/u\n", 'f(1, "P"), an argument not passed, // into a string' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# A WRITE THROUGH @_ into a flattened argument stores into the caller's
# element: refused by name.
{
    my $got = eval { through_llvm(q{sub g { $_[1] = 42 } my @x = (1, 2); g(@x); print "@x\n";}) };
    ok(!defined $got && $@ =~ /GAP/, 'a write through @_ into an array argument: refused by name') or diag $got // $@;
}

done_testing;
