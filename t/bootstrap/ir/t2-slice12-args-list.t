# ABOUTME: T2 slice 12 -- a sub reading @_ as a list takes it as one array its caller builds
# ABOUTME: (array arguments flattened); @_, $_[N], shift, scalar(@_) read that array.
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
    [ q{sub f { return "f[" . join("-", @_) . "]" } print f(1, 2, 3), f(), "\n";}, 'join of @_, and no arguments' ],
    [ q{sub f { return "f[@_]" } print f("a", "b"), "\n";}, '"@_"' ],
    [ q{sub f { return $_[0] . "-" . $_[1] . "-" . scalar(@_) } print f(1, 2, 3), "\n";}, '$_[N] and scalar(@_)' ],
    [ q{sub sum { my $t = 0; for my $x (@_) { $t += $x } return $t } my @a = (1, 2, 3); print sum(@a, 4), "\n";}, 'an array argument flattened, a loop over @_' ],
    [ q{sub meth { my $self = shift; return $self . ":" . join(",", @_) } print meth("x", 1, 2), "\n";}, 'shift, then the rest' ],
    [ q{sub f { my ($a, $b) = @_; return "$a$b" . scalar(@_) } print f(1, 2), "\n";}, 'my (...) = @_ and scalar(@_)' ],
) {
    my ($src, $name) = @$case;
    $LAST_LL = '';
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($LAST_LL, qr/^; chalk T2/m, "$name: lowered through T2");
}

# A WRITE TO $_[N] is the caller's variable: perl's answer, or refused.
for my $case (
    [ q{sub bump { $_[0]++ } my $x = 1; bump($x); print $x, "\n";}, '$_[0]++' ],
    [ q{sub f { my $n = shift; return $n . scalar(@_) . (shift // "u") } print f(1, 2), f(1), "\n";}, 'shift twice around scalar(@_)' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    else { like($@, qr/GAP|refused at run time|^lower: /, "$name: refused by name") }
}

done_testing;
