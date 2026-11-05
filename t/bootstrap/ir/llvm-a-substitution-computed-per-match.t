# ABOUTME: s///ge whose replacement is an expression of the captures (pvm 111): made
# ABOUTME: per match from that match's groups; one reading anything else is refused.
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
    [ q{my $s = "a1b2c"; $s =~ s/(\d)/$1*10/ge; print "$s\n";}, 'pvm 111' ],
    [ q{my $s = "x12y345"; $s =~ s/(\d)(\d)/$2 . $1/ge; print "$s\n";}, 'two groups' ],
    [ q{my $s = "a-b"; $s =~ s/(\w)/"<" . $1 . ">"/ge; print "$s\n";}, 'a concatenation' ],
    [ q{my $s = "a-b"; $s =~ s/(\w)/uc($1) x 2/ge; print "$s\n";}, 'a builtin over a capture: perl, or refused' ],
    [ q{my $s = "a0b2"; $s =~ s/(\d)/10 \/ $1/ge; print "$s\n";}, q{a division by zero in the body: refused (perl dies naming the line)} ],
    [ q{my $n = 5; my $s = "a1b2"; $s =~ s/(\d)/$1+$n/ge; print "$s\n";}, 'reading a variable: refused by name' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    elsif ($name =~ /refused/) { like($@, qr/GAP|load|lower: $/, "$name: refused by name") }
    else { fail("$name: perl's answer"); diag $@ }
}

done_testing;
