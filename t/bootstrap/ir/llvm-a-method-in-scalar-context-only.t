# ABOUTME: a method returning a list assignment to a field, called only in scalar
# ABOUTME: context, gives the right side's count -- B::SoN -> chalk -> lli == perl.
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




# A method is one function, so its value has one type. When every call of
# it is scalar, that type is the count (pvm 141: `%h = ()` is 0).
for my $case (
    [ q{use v5.42; use experimental 'class';
        class K { field %h = (a => 1, b => 2); field @l = (1, 2, 3);
          method reset_h { %h = () } method reset_l { @l = (9) } method n { scalar(keys %h) . scalar(@l) } }
        my $k = K->new; my $a = $k->reset_h; my @b = $k->reset_l; print $a, scalar(@b), $k->n, "\n";}, 'pvm 141' ],
    [ q{use v5.42; use experimental 'class';
        class K { field %h; method fill { %h = (a => 1, b => 2, a => 3) } method n { scalar(keys %h) } }
        my $k = K->new; my $c = $k->fill; print "$c ", $k->n, "\n";}, 'the right side counted, not the keys' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

# Perl's answer, or refused by name: called in both contexts.
for my $case (
    [ q{use v5.42; use experimental 'class';
        class K { field %h = (a => 1); method reset_h { %h = (b => 2) } }
        my $k = K->new; my $c = $k->reset_h; my @l = $k->reset_h; print "$c ", scalar(@l), "\n";}, 'both contexts' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (!defined $got && $@ =~ /GAP|LLVM backend/) { pass("$name: refused by name"); next }
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

done_testing;
