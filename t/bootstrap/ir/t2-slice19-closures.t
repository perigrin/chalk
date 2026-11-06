# ABOUTME: T2 slice 19 -- closures: a captured variable is a cell on the heap (the variable's own
# ABOUTME: storage, shared), a code value its function and cells, called directly or through the value.
our $LAST_LL;
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
    $LAST_LL = $units->[0]{ll};
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
for my $case (
    [ q{my $n = 0; my $inc = sub { $n++; return $n }; $inc->(); my $t = $inc->(); print "$t $n\n";}, 'a counter: the closure and its maker share $n' ],
    [ q{sub mk { my ($k) = @_; return sub { return $k * $_[0] } } my $d = mk(2); my $t = mk(10); print $d->(5), " ", $t->(5), "\n";}, 'returned from its maker, its own $k each' ],
    [ q{sub apply { my ($f, $x) = @_; return $f->($x) } my $add = 3; print apply(sub { $_[0] + $add }, 4), "\n";}, 'passed to a sub, called there' ],
    [ q{my $k = 1; my $f = sub { $k }; my $g = $f; print $f ? "t" : "f", " ", ref($f), " ", ($f == $g ? "same" : "diff"), "\n";}, 'a code value is true, its ref CODE' ],
    [ q{my @s = (1, 2, 3); my $sum = 0; my $acc = sub { for my $v (@_) { $sum = $sum + $v } }; $acc->(@s); $acc->(10); print "$sum\n";}, 'arguments as a list, a running total' ],
) {
    my ($src, $name) = @$case;
    $LAST_LL = '';
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($LAST_LL, qr/^; chalk T2/m, "$name: lowered through T2");
}

# A VARIABLE A LOOP RENEWS, captured; an op-assign to a capture (B::SoN
# spells it with no write): perl's answer, or refused.
for my $src (q{my $sum = 0; my $acc = sub { $sum += $_[0] }; $acc->(3); $acc->(4); print "$sum\n";},q{my @f; for my $i (1 .. 3) { my $x = $i * 2; push @f, sub { $x } } print join(",", map { $_->() } @f), "\n";},
             q{my @f; my $x; for my $i (1 .. 3) { $x = $i; push @f, sub { $x } } print join(",", map { $_->() } @f), "\n";}) {
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "a loop's variable captured: perl's answer") }
    else { like($@, qr/GAP|refused at run time|^lower: /, "a loop's variable captured: refused by name") }
}

done_testing;
