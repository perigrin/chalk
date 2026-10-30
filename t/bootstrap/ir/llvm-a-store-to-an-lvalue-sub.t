# ABOUTME: a store to an :lvalue sub's call is a store to the variable it returns:
# ABOUTME: through B::SoN -> chalk -> lli == perl, or refused by name.
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




# `slot() = 42` is an Assign whose lhs is the Call; refused as "Assign lhs
# must be a PadAccess(VarDecl), VarDecl, or Subscript(lvalue); got Call".
for my $case (
    [ q{my $slot = 0; sub slot :lvalue { $slot } slot() = 42; print slot(), " $slot\n";}, 'a sub returning a file lexical' ],
    [ q{my $slot = 0; sub slot :lvalue { $slot } slot() = 42;
        print slot(), "\n"; my $anon = sub :prototype($) { $_[0] * 2 }; print $anon->(21), "\n";}, 'pvm 398' ],
    [ q{my $n = "a"; sub n :lvalue { $n } n() = "b"; my $t = n() . "c"; n() = $t; print "$n\n";}, 'a store read back through the call' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

# Perl's answer, or refused by name: an :lvalue sub whose body is more than
# the variable it returns.
{
    my $src = q{my @a = (1, 2); sub el :lvalue { $a[1] } el() = 9; print "@a\n";};
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (!defined $got && $@ =~ /GAP/) { pass('an element an :lvalue sub returns: refused by name') }
    else { is($got, perl_says($pl // write_pl($src), {}), "an element an :lvalue sub returns: perl's answer") or diag $@ }
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

done_testing;
