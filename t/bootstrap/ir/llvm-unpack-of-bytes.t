# ABOUTME: unpack with a constant C template (C, Cn, C*) in a list: the bytes as
# ABOUTME: numbers, through B::SoN -> chalk -> lli == perl; other templates refused by name.
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




for my $case (
    [ q{my $s = $ENV{X} // "ABC"; my @c = unpack("C3", $s); print "@c\n";}, 'pvm 368' ],
    [ q{my @c = unpack("C*", "hi!"); print scalar(@c), " @c\n";}, 'C*' ],
    [ q{my @c = unpack("C5", "ab"); print scalar(@c), " @c\n";}, 'a count past the end' ],
    [ q{my @c = unpack("C", "Zq"); print "@c\n";}, 'C alone is one' ],
    [ q{my $t = 0; $t += $_ for unpack("C*", "\x01\x02\x03"); print "$t\n";}, 'summed in a loop' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

# Perl's answer, or refused by name.
for my $case (
    [ q{my @c = unpack("A2 A1", "xyz"); print "@c\n";}, 'another template' ],
    [ q{my $c = unpack("C", "A"); print "$c\n";}, 'scalar context' ],
    # The producer stamps the elements Unknown, as it does glob's.
    [ q{my @c = unpack("C*", "hi!"); print "$c[0] $c[2]\n";}, 'an element read' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (!defined $got && $@ =~ /GAP/) { pass("$name: refused by name"); next }
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

done_testing;
