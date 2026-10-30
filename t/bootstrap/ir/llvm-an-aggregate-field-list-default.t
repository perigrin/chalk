# ABOUTME: a % or @ field with a list default is a hash or an array of that list:
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

# `field %h = (r => {7 => "V"}, s => [1, 2])`: a Hash field typed by its sigil
# was filled from its default's list as an array, so `$h{s}->@*` counted 0
# and `$h{r}{7}` died "not a Hash reference" (pvm 153).
for my $case (
    [ q{use v5.42; use experimental "class"; class K { field %h = (r => 5); method g { $h{r} } } print K->new->g, "\n";}, "5\n", 'a hash field of a scalar pair' ],
    [ q{use v5.42; use experimental "class"; class K { field %h = (r => { 7 => "V" }); method g { $h{r}{7} } } print K->new->g, "\n";}, "V\n", 'a hash field holding a hash reference' ],
    [ q{use v5.42; use experimental "class"; class K { field %h = (s => [1, 2]); method g { scalar($h{s}->@*) } } print K->new->g, "\n";}, "2\n", 'a hash field holding an array reference' ],
    [ q{use v5.42; use experimental "class"; class K { field @l = (3, [4]); method g { scalar(@l) . $l[1][0] } } print K->new->g, "\n";}, "24\n", 'an array field of a list with a reference' ],
    [ q{use v5.42; use experimental 'class';
        class K { field %items = (r => { 7 => "V" }, s => [1, 2]); method g { $items{r}{7} . scalar($items{s}->@*) . join(",", sort keys %items) } }
        print K->new->g, "\n";}, "V2r,s\n", 'pvm 153' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    if (!defined $got && $@ =~ /GAP/) { pass("$name: refused by name"); diag $@; next }
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
