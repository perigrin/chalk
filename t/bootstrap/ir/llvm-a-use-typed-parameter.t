# ABOUTME: a parameter typed by its use (`$v =~`, `$n + 1`) takes a caller's
# ABOUTME: undef or number as that reading, where every reader agrees.
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

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
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


# The reading the body gives a parameter is not what every caller passes
# (pvm 075 201): refused as "a coercion would not keep the value".
for my $src (
    q{sub f { my ($v) = @_; if (defined $v && $v =~ /^%\$(\w+)$/) { return $1 } return "-" } print f(q{%$abc}), f("x"), f(undef), "\n";},
    q{sub f { my ($v) = @_; return $v =~ /a/ ? "y" : "n" } print f("a"), f(1), "\n";},
    q{sub f { my ($v) = @_; return $v + 1 } print f(1), f(undef), "\n";},
) {
    my $want = qx($^X -e '$src' 2>/dev/null);
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# A sub returning its undef argument returned "defined": the call took the
# callee's Undef value but kept its own Unknown stamp, read "always defined".
for my $src (
    q{sub f { my ($v) = @_; return $v } print defined(f(undef)) ? "d" : "u", defined(f(0)) ? "d" : "u", "\n";},
) {
    is(eval { through_llvm($src) }, qx($^X -e '$src'), "perl's answer for $src") or diag $@;
}

# One that hands the value on would hand on the reading, not the value.
for my $src (
    q{sub c { my ($n) = @_; return 0 unless defined $n; my $s = 0; $s += $_ for 1 .. $n; return $s } print c(3), " ", c(undef), "\n";},
    q{sub f { my ($v) = @_; my $l = length($v // ""); return $v } print defined(f(undef)) ? "d" : "u", "\n";},
    q{sub f { my ($v) = @_; return ($v =~ /x/ ? "x" : "-") . (defined(g($v)) ? "d" : "u") } sub g { return $_[0] } print f(undef), "\n";},
) {
    my $got = eval { through_llvm($src) };
    my $err = $@;
    my $want = qx($^X -e '$src' 2>/dev/null);
    ok(defined $got ? $got eq $want : $err =~ /GAP/, "perl's answer or refused: $src")
        or diag "got: ", $got // $err;
}

done_testing;
