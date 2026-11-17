# ABOUTME: A reference to an element B::SoN takes where it stands (Ref [location, memory]) is
# ABOUTME: T2's: as perl, or where T2 refuses it, refused by T2's reason -- never a wrong answer.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use JSON::PP;

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
require Chalk::CodeGen::Pipeline;

# run($cmd) -> [stdout, stderr, exit code]
sub run ($cmd) {
    my (undef, $ef) = tempfile(UNLINK => 1);
    my $out = qx($cmd 2>$ef);
    my $code = $? >> 8;
    my $err = do { local (@ARGV, $/) = $ef; <> } // '';
    return [ $out, $err, $code ];
}

# lower($src, $edit) -> (the module's text or undef, the path, the reason, the
# .pl): through B::SoN and chalk's whole pipeline (T2), the wire edited by
# $edit first.
sub lower ($src, $edit = undef) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    if ($edit) {
        my $w = JSON::PP->new->decode($json);
        $edit->($_) for map { $_->{nodes}->@* } values $w->{methods}->%*;
        $json = JSON::PP->new->canonical->encode($w);
    }
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    return ( !$err && $u->{ok} ? $u->{ll} : undef, $u->{path} // '', $err // $u->{err} // $u->{path_why}, $pl );
}

# PERL'S ANSWER, through T2: a reference to an element before the start dies
# with perl's message, at a constant index or not; one in range (-1) is the
# element.
for my $case (
    [ qq{my \@a = (1, 2);\nmy \$p = \\\$a[-5];\nprint "x\\n";\n}, 'a constant index before the start' ],
    [ qq{my \@a = (1, 2);\nmy \$i = -5;\n\$i++ if \@ARGV;\nmy \$p = \\\$a[\$i];\nprint "x\\n";\n}, 'an index not a constant before the start' ],
    [ qq{my \@a = (1, 2);\nmy \$p = \\\$a[-1];\n\$\$p = 9;\nprint "\@a \$\$p\\n";\n}, 'a constant index from the end, in range' ],
    [ qq{my \@a = (1, 2);\nmy \$i = -2;\n\$i++ if \@ARGV;\nmy \$p = \\\$a[\$i];\n\$\$p = 9;\nprint "\@a\\n";\n}, 'an index not a constant from the end, in range' ],
) {
    my ($src, $name) = @$case;
    my ($ll, $path, $why, $pl) = lower($src);
    ok(defined $ll, "$name: lowered") or diag $why;
    is($path, 't2', "$name: by T2");
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is_deeply($got, $want, "$name: perl's output, message and exit code");
}

# WHERE T2 REFUSES IT (here: a wire with no site for one that may die, an
# older B::SoN's), it is refused by T2's reason. (The retired fallback once
# printed "x" with exit 0 here, where perl dies.)
for my $case (
    [ qq{my \@a = (1, 2);\nmy \$p = \\\$a[-5];\nprint "x\\n";\n}, 'a constant index before the start, no site' ],
    [ qq{my \@a = (1, 2);\nmy \$i = -5;\n\$i++ if \@ARGV;\nmy \$p = \\\$a[\$i];\nprint "x\\n";\n}, 'an index not a constant, no site' ],
) {
    my ($src, $name) = @$case;
    my ($ll, $path, $why) = lower($src, sub ($n) { delete $n->{fields}{$_} for grep { $n->{op} eq 'Ref' } qw(file line) });
    ok(!defined $ll, "$name: refused");
    like($why // '', qr/\AGAP: T2: out of its slices \(/, "$name: refused by T2's reason") or diag $why;
}

done_testing;
