# ABOUTME: A closure or string eval op-assigning a captured lexical, called in an if, an else, a loop or
# ABOUTME: a sub: T2 lowers it as perl answers, and the whole pipeline never emits IR lli rejects.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
require Chalk::CodeGen::Pipeline;
require Chalk::CodeGen::Harness::TapDiff;

# through($src) -> { path, out, exit, why, perl }: the whole pipeline (T2, or its
# refusal) and lli.
sub through ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    my $perl = qx($^X $pl 2>&1);
    my $json = qx($^X -I$SON -MO=-q,SoN,json,not_package=SoN $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = eval { Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1) };
    $err //= $@ if $@;
    my $u = ( $units // [] )->[0];
    return { perl => $perl, why => $err // ( $u ? $u->{err} : 'no unit' ) } unless !$err && $u && $u->{ok};
    my ( $lf, $ll ) = tempfile( SUFFIX => '.ll', UNLINK => 1 );
    binmode $lf, ':utf8'; print $lf $u->{ll}; close $lf;
    my $out = qx(timeout 20 $LLI $ll 2>&1);
    return { perl => $perl, path => $u->{path}, out => $out, exit => $? >> 8 };
}

# THE REGRESSION: once B::SoN wrote `$t += $_[0]` back through the cell, the
# closure's body was `$t = $t + $_[0]` -- which T2 refused where the call is
# in an arm (it placed the cell where it was first used), and the fallback
# lowered by adding a %Slot as a double: lli rejected the module.
for my $src (
    q{my $t = 0; my $add = sub { $t += $_[0] }; if (@ARGV == 0) { $add->(5) } print "$t\n";},
    q{my $t = 0; my $add = sub { $t = $t + $_[0] }; if (@ARGV == 0) { $add->(5) } print "$t\n";},
    q{my $t = 1; my $add = sub { $t *= 2 }; for my $i (1 .. 3) { $add->() } print "$t\n";},
    q{my $t = 1; my $add = sub { $t += $_[0] }; if (@ARGV) { 1 } else { $add->(4) } print "$t\n";},
) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh "$src\n"; close $fh;
    my $r = Chalk::CodeGen::Harness::TapDiff->compare($pl);
    is $r->{verdict}, 'SAME', "T2 lowers it as perl: $src" or diag $r->{why} // explain $r;
}

# WIDER: op= spellings, call sites, closures and string evals -- perl's answer
# through lli, or refused by name; never a module lli rejects, never wrong.
my @ops  = ( '$t += $_[0]', '$t *= 2', '$t -= 1', '$t .= "x"', '$t++', '$t = $t + $_[0]', '$t ||= 9', '$t **= 2' );
my @call = (
    'if (@ARGV == 0) { CALL } print "$t\n";',
    'if (@ARGV) { 1 } else { CALL } print "$t\n";',
    'unless (@ARGV) { CALL; CALL } print "$t\n";',
    'for my $i (1 .. 3) { CALL } print "$t\n";',
    'my $i = 0; while ($i < 2) { CALL; $i++ } print "$t\n";',
    'sub outer { my ($f) = @_; $f->(5) } outer($add); print "$t\n";',
    'CALL if @ARGV == 0; print "$t\n";',
    'CALL; if (@ARGV == 0) { CALL } print "$t\n";',
    'my $r = @ARGV ? 0 : CALL; print "$t\n";',
);
my @src;
for my $op (@ops) {
    for my $c (@call) { ( my $b = $c ) =~ s/CALL/\$add->(5)/g; push @src, "my \$t = 1; my \$add = sub { $op }; $b" }
}
for my $op ( '$t += 2', '$t *= 2', '$t .= "x"', '$t++', '$t = $t + 2', '$t **= 2' ) {
    for my $c ( 'if (@ARGV == 0) { EVAL } print "$t\n";', 'if (@ARGV) { 1 } else { EVAL } print "$t\n";', 'EVAL; print "$t\n";' ) {
        ( my $b = $c ) =~ s/EVAL/eval q{$op; 1}/g;
        push @src, "my \$t = 1; $b";
    }
}
for my $src (@src) {
    my $r = through($src);
    if ( defined $r->{out} ) { is $r->{out}, $r->{perl}, "perl's answer through lli ($r->{path}): $src" or diag explain $r }
    else                     { like $r->{why} // '', qr/GAP/, "refused by name: $src" or diag explain $r }
}

done_testing;
