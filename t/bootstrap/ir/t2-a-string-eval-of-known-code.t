# ABOUTME: A string eval whose code B::SoN knew is a block eval calling the body it compiled
# ABOUTME: (a closure over the lexicals the code names): T2 answers as perl, or refuses by its own reason.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
require Chalk::CodeGen::Pipeline;

# run($cmd) -> [stdout, stderr, exit code]
sub run ($cmd) {
    my (undef, $ef) = tempfile(UNLINK => 1);
    my $out = qx($cmd 2>$ef);
    my $code = $? >> 8;
    my $err = do { local (@ARGV, $/) = $ef; <> } // '';
    return [ $out, $err, $code ];
}

# lower($src) -> ($pl, $unit, $err): the program through the pipeline.
sub lower ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json,not_package=SoN $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = eval { Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1) };
    $err //= $@ if $@;
    return ($pl, ($units // [])->[0], $err);
}

# PERL'S ANSWER through T2: its output, its message, its exit code -- and the
# outer variables the eval changed, printed after it.
for my $case (
    [ q{my $i = 0; eval q{$i = 1}; print "i=$i\n";}, 'an eval writing a file lexical (pvm 292)' ],
    [ q{my $s = "abc"; my $c = q{3*4}; $s =~ s/b/$c/ee; print "$s\n";}, 's///ee of a lexical holding a constant (pvm 290)' ],
    [ q{my $x = 2; my $r = eval q{$x * 3}; print "$r [$@]\n";}, 'the value of the last statement, $@ empty' ],
    [ q{my $x = 2; my $r = eval q{ return $x + 1; 9 }; print "$r $x\n";}, 'a return leaves the eval with its value' ],
    [ q{my $i = 0; my $r = eval q{$i = 1; die "no\n"; 5}; print defined $r ? $r : 'u', " $i $@";}, 'a die: $@ set, the eval undef, what the body stored before it stands' ],
    [ q{my $i = 0; $@ = "old"; my $r = eval q{$i + 4}; print "$r [$@]\n";}, 'success clears $@' ],
    [ q{my $i = 0; eval q{$i = 1}; eval q{$i = $i + 10}; print "$i\n";}, 'two evals over one lexical share its cell' ],
    [ q{my $i = 1; { my $j = 5; eval q{$j = 7; $i = $j + 1}; print "$j\n" } print "$i\n";}, 'a lexical of a bare block around the eval' ],
    [ q{my $x = 3; my $r = eval q{my $x = 10; $x + 1}; print "$r $x\n";}, 'a my inside the string is its own' ],
    [ q{my $n = 4; my $r = eval q{ $n > 3 ? "big" : "small" }; print "$r\n";}, 'a choice in the string' ],
    [ q{my $i = 0; eval q{$i = 1; die "stop\n"}; print "i=$i e=$@"; eval q{$i = 2}; print "i=$i e=[$@]\n";}, 'a die then a clean eval' ],
    [ q{my $x = 1; my $r = $x + eval q{$x = 5; 0}; print "$r $x\n";}, 'an operand the eval stores is read after it' ],
    [ q{my $x = 1; my $f = sub { $x = 5; 0 }; my $r = $x + $f->(); print "$r $x\n";}, 'an operand a closure stores is read after its call' ],
    [ q{my $x = 1; my $r = eval { eval q{$x = 2; die "in\n"}; $x + 10 }; print "$r $x [$@]\n";}, 'a string eval in a block eval' ],
    [ q{my $x = 0; my $f = sub { $x + 1 }; eval q{$x = 4}; print $f->(), "\n";}, 'a closure sees what the eval stored' ],
    # AN op= THROUGH THE CELL: B::SoN took the cell itself for the operand and
    # stored nothing, the statement fell out of the body, and these printed
    # 1 and "2 1".
    [ q{my $n = 1; eval q{$n *= 3; 1}; print "$n\n";}, 'an op= in the string stores through the cell' ],
    [ q{my $n = 1; my $r = $n + eval '$n *= 3; 1'; print "$r $n\n";}, 'an operand the eval op-assigns is read after it' ],
    [ q{my $n = 1; my $r = eval q{$n += 4}; print "$r $n\n";}, "an op='s value is the eval's" ],
    [ q{my $n = "a"; eval q{$n x= 3; $n .= "b"; 1}; print "$n\n";}, 'string op=s in the string' ],
    [ q{my $n = 1; my $f = sub { $n *= 3; 1 }; $f->(); $f->(); print "$n\n";}, 'an op= in a closure' ],
    [ q{my $n = 1; my $f = sub { $n }; $n *= 3; $n++; print $f->(), "\n";}, 'op= and ++ in the scope that made the cell' ],
) {
    my ($src, $name) = @$case;
    my ($pl, $u, $err) = lower($src);
    my $ll = !$err && $u && $u->{ok} ? $u->{ll} : undef;
    ok(defined $ll && ( $u->{path} // '' ) eq 't2', "$name: lowered through T2")
        or diag $err // ( $u ? $u->{path_why} // $u->{err} : 'no unit' );
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $lf, ':utf8'; print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

# WHERE T2 REFUSES THE PROGRAM for something else (here a list slice), it is
# refused by T2's own reason -- never lowered some other way.
{
    my ($pl, $u, $err) = lower(q{my $i = 0; eval q{$i = 1}; my @a = (1, 2, 3)[1, 2]; print "@a $i\n";});
    my $why = $err // ( $u && !$u->{ok} ? $u->{err} : undef );
    like($why // 'lowered', qr/\AGAP: T2: out of its slices \(/, "a string eval where T2 refuses the program is refused by T2's reason");
}

# A STRING MADE AT RUN TIME stays refused by name (B::SoN skips the program).
{
    my ($pl, $u, $err) = lower(q{my $n = $ENV{X} // 2; my $r = eval "$n + 1"; print "$r\n";});
    ok(!( $u && $u->{ok} ), 'a string built at run time (pvm 291) is refused');
}

done_testing;
