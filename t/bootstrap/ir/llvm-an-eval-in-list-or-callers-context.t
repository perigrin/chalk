# ABOUTME: a block eval in list context, or in its caller's context, that can die:
# ABOUTME: the empty list in a list, undef in a scalar -- B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

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
    [ q{sub w { return eval { die "x\n" if $_[0]; 5 } } my $s = w(1); my $t = w(0);
        print defined $s ? "d" : "u", " $t\n";}, "the caller's context is a scalar" ],
    # A list-context call runs its sub's list copy (Serialize::JSON
    # CONTEXT_COPY), whose eval's value is a list: empty on a die.
    [ q{sub w { return eval { die "x\n" if $_[0]; 5 } } my @r = w(1); my $s = w(1);
        print scalar(@r), " ", defined $s ? "d" : "u", " ", w(0), "\n";}, 'pvm 091' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

# Perl's answer, or refused by name: a list-context eval that can die needs
# its value typed as a list for that call's context (per-context typing).
for my $case (
    [ q{my @r = eval { die "boom\n" if @ARGV == 0; 7 }; print scalar(@r), " $@";}, 'a list eval that dies' ],
    [ q{my @r = eval { die "boom\n" if @ARGV; 7 }; print scalar(@r), " [@r]\n";}, 'a list eval that does not die' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (!defined $got && $@ =~ /GAP/) { pass("$name: refused by name"); next }
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

# Perl's answer, or refused by name: a body that leaves several values (the
# producer merges only the last).
for my $case (
    [ q{my @r = eval { die "boom\n" if @ARGV; (1, 2) }; print scalar(@r), " [@r]\n";}, 'a list body' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (!defined $got && $@ =~ /GAP|lower: \n/) { pass("$name: refused"); next }
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

# A LIST EVAL WHOSE BODY ALWAYS DIES gives the empty list. Its value had no
# Phi at the join (B::SoN pushed undef alone), and T2 assigned (undef): 1 for
# perl's 0 -- a silent wrong answer until the eval profile (wire v2 stage 8)
# put the value at its join, where the context is read. Perl's, or refused.
for my $src ( q{my @r = eval { die "x\n" }; print scalar(@r), "\n";}, q{my @r = eval { die "x\n"; (1) }; print scalar(@r), "\n";} ) {
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if ( !defined $got ) { like( $@, qr/GAP: T2: out of its slices \(an eval in list context whose value is typed a scalar/, 'a list eval that always dies: refused by name' ); next }
    is( $got, "0\n", "a list eval that always dies: perl's 0" );
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

done_testing;
