# ABOUTME: a method's slurpy @rest takes the arguments past its scalars, passed as an
# ABOUTME: array: through B::SoN -> chalk -> lli == perl, or refused by name.
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




# `method f(@g)` was declared with no parameters -- the loader kept only
# the scalars -- and every call refused ("passes 3 argument(s) but
# 'K'::f declares 0", pvm 231).
for my $case (
    [ q{use v5.42; use experimental "class";
        class K { method f(@g) { return scalar(@g) . "[@g]" } }
        my $k = K->new; print $k->f(), $k->f(7, 8), "\n";}, 'a method of a slurpy alone' ],
    [ q{use v5.42; use experimental "class";
        class K { method f($x, @r) { return "$x:" . join(",", @r) } }
        my $k = K->new; print $k->f(1), " ", $k->f(1, 2, 3), "\n";}, 'a scalar then a slurpy' ],
    [ q{use v5.42; use experimental "class";
        class K { method f($x, @r) { return scalar @r } }
        my $k = K->new; print $k->f(1, 2, 3), "\n";}, 'a slurpy the body counts' ],
    [ q{use v5.42; use experimental "class";
        class K { method isn($x) { $x =~ /a/ }
          method f(@g) { my @r = sort @g; my @n = grep { $self->isn($_) } @r; return "@n" } }
        print K->new->f(qw(ba x aa)), "\n";}, 'pvm 231' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

# Perl's answer, or refused by name: perl dies on too few for the scalars.
{
    my $src = q{use v5.42; use experimental "class"; class K { method f($x, $y, @r) { "$x$y" } } print K->new->f(1), "\n";};
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (!defined $got && $@ =~ /GAP/) { pass('too few for the scalars: refused by name') }
    else { is($got, perl_says($pl // write_pl($src), {}), "too few for the scalars: perl's answer") or diag $@ }
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

done_testing;
