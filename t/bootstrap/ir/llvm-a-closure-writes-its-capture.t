# ABOUTME: a closure that writes what it captured stores through the cell -- the
# ABOUTME: variable's own location -- and a frame writing its own cell is not a capture.
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

sub through_llvm ($src, $env) {
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
    local @ENV{ keys %$env } = values %$env;
    my $out = qx(timeout 20 $LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return ($out, $pl);
}

sub perl_says ($pl, $env) {
    local @ENV{ keys %$env } = values %$env;
    return scalar qx($^X $pl 2>/dev/null);
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

# A capture is the variable itself (perl: `my $x = 1; my $c = sub { $x =
# $x + 1 }; $c->()` leaves $x at 2). chalk keeps it in the frame that made it,
# so a closure's write is a store through that location.
for my $case (
    [ 'my $x = 1; my $c = sub { $x = $x + 1; return $x }; $c->(); print $c->(), " $x\n";',
      'a closure writes its capture' ],
    [ 'sub f { my $x = 1; my $c = sub { $x = $x + 1; return $x }; $c->(); return $c->() . " $x" } print f(), "\n";',
      'inside a sub' ],
    # f makes a cell for $w and writes it -- its own variable, not a capture.
    [ 'sub f { my $w; $w = sub { return 5 }; return $w->() + 1 } print f(), "\n";',
      'a frame writes its own cell' ],
    # A READ BEFORE A STORE is the value before it: `$k++` returns the old $k.
    [ 'my $k = 1; my $f = sub { return $k++ }; my $a = $f->(); my $b = $f->(); print "$a $b $k\n";',
      'a post-increment of a capture returns the old value' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

done_testing;
