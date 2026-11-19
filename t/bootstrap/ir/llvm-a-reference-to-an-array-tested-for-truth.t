# ABOUTME: `\@a` is an array reference even where @a is also tested for truth (`!@a`): B::SoN
# ABOUTME: stamps that PadAccess Scalar and its Ref ScalarRef; the loader stamps the Ref by the sigil.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

my $select = sub ($graphs, $mop) {
    my $g = $graphs->{'main::__PROGRAM__'} or return ();
    my $ret = $g->returns->[0] or return ();
    return ([ 'main::__PROGRAM__', $ret ]);
};

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

sub through_llvm ($pl) {
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx(timeout 20 $LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# THE LOADED Ref IS AN ArrayRef / HashRef, by its operand's sigil (Earley.pm's
# `\@held_rows`, read by `!@held_rows` beside it, was ScalarRef).
{
    my $pl = write_pl(q{my @a; my %h; print "e\n" if !@a; my $r = \@a; my $q = \%h; print ref($r), ref($q), "\n";});
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    # The wire's own stamps, before the loader: the case this file is about.
    require JSON::PP;
    my $wire = JSON::PP->new->utf8->decode($json)->{methods}{'main::__PROGRAM__'}{nodes};
    ok( ( grep { $_->{op} eq 'Ref' && ( $_->{stamp} // '' ) eq 'ScalarRef' } @$wire ),
        'the producer stamps the array\'s Ref ScalarRef' );
    require Chalk::IR::Serialize::JSON;
    my $g = Chalk::IR::Serialize::JSON::from_json($json)->{'main::__PROGRAM__'};
    my @refs = grep { $_->operation eq 'Ref' } $g->nodes->@*;
    is( join(' ', sort map { $_->stamp } @refs ), 'ArrayRef HashRef', 'a ref to an array or hash tested for truth is stamped by its sigil' );
}

# ...SO T2 MAKES IT, beside a scalar deref of a reference it makes.
for my $src (
    q{sub f { my ($h, $r) = @_; return scalar(@$h) . $$r }
my @held; my $s = "x";
for my $p (1..3) { if (!@held || $held[-1] != $p) { push @held, $p } }
print f(\@held, \$s), "\n";},
) {
    my $pl = write_pl($src);
    my $got = eval { through_llvm($pl) };
    is($got, scalar qx($^X $pl 2>&1), "perl's answer: $src") or diag $@;
}

done_testing;
