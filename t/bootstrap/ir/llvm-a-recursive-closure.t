# ABOUTME: a closure that calls itself through the variable it is stored in is a real
# ABOUTME: function: its cells passed by pointer, called from its maker and from itself.
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

# INLINED, a closure that calls itself would never stop: it is a define,
# taking the variables it captured as %Slot* (pvm 134, 135).
for my $case (
    [ 'my $w; $w = sub { return $_[0] ? $w->(0) : 5 }; print $w->(1), "\n";',
      'at the top level' ],
    [ 'sub f { my $w; $w = sub { my $n = shift; return $n <= 0 ? 0 : $n + $w->($n - 1) }; return $w->(3) } print f(), "\n";',
      'inside a sub, summing (pvm 134)' ],
    # (A bare `return` makes its value a list: refused by name for now.)
    [ 'my $t = 0; my $w; $w = sub { my $n = shift; return 0 if $n <= 0; $t = $t + $n; $w->($n - 1) }; $w->(4); print "$t\n";',
      'writing another capture as it recurses' ],
    # A signature binds its parameter as a shift does.
    [ 'use v5.38; my $w; $w = sub ($n) { return $n <= 0 ? 0 : $n + $w->($n - 1) }; print $w->(3), "\n";',
      'with a signature' ],
    # Called only in void context, its value (a loop's) is never made (pvm 135).
    [ q{use v5.38; sub collect ($tree, $dv) { my $walk; $walk = sub ($node) { return unless ref $node; $dv->{$node->{name}} //= 1 if exists $node->{name}; for my $k ($node->{kids}->@*) { $walk->($k) } }; $walk->($tree); return join ",", sort keys %$dv } print collect({ kids => [{ name => 'a', kids => [] }, { name => 'b', kids => [{ name => 'a', kids => [] }] }] }, { z => 0 }), "\n";},
      'called only in void context (pvm 135)' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

# Perl dies on a call of another arity than the signature: refused by name.
{
    my $src = 'use v5.38; my $w; $w = sub ($n) { return $n <= 0 ? 0 : $w->($n - 1, 1) }; print $w->(3), "\n";';
    eval { through_llvm($src, {}) };
    like($@, qr/GAP: .*signature/, 'a call of another arity than the signature: refused');
}

done_testing;
