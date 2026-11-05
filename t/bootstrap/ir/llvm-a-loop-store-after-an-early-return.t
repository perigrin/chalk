# ABOUTME: An early return in an if, then a loop storing to a hash (pvm 224):
# ABOUTME: the store's key is the loop's, not made before the if.
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
    [ q{my %h; sub f { my (@a) = @_; unless (@a) { return "none" } $h{$_} = 1 for @a; return scalar keys %h } print f(), "|", f(qw(a b)), "\n";}, 'a hash' ],
    [ q{sub f { my ($h, @a) = @_; if (!@a) { return "none" } for (@a) { $h->{$_} = 1 } return scalar keys %$h } print f({}), "|", f({}, qw(a b)), "\n";}, 'a hash reference' ],
    [ q{sub f { my ($h, $n) = @_; unless ($n) { return "none" } $h->{$_} = 1 for 1 .. $n; return join ",", sort keys %$h } print f({}), "|", f({}, 2), "\n";}, 'a range' ],
    [ q{sub f { my ($n) = @_; unless ($n) { return "none" } my @a; $a[$_] = $_ * 2 for 0 .. $n; return "@a" } print f(0), "|", f(2), "\n";}, 'an array' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    else { fail("$name: perl's answer"); diag $@ }
}

done_testing;
