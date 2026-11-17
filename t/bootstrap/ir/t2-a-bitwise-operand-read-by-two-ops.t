# ABOUTME: A value that may be a string read by two bitwise ops (a shift too): one done on
# ABOUTME: numbers makes it a number to the next, as perl's; a node of two variables refused.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
require Chalk::CodeGen::Pipeline;

# t2($src) -> (the module T2 alone made, or undef; the program's path; T2's reason)
sub t2 ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    my $ll = !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef;
    return ($ll, $pl, $err // $u->{path_why} // $u->{err});
}

# run($cmd, \%env) -> [stdout, stderr]
sub run ($cmd, $env) {
    local @ENV{ keys %$env } = values %$env;
    delete @ENV{ grep { !defined $env->{$_} } keys %$env };
    my (undef, $ef) = tempfile(UNLINK => 1);
    my $out = qx($cmd 2>$ef);
    my $err = do { local (@ARGV, $/) = $ef; <> } // '';
    return [ $out, $err ];
}

my @envs = ({ X => undef, Y => undef, Z => undef }, { X => '7', Y => '3', Z => 'ab' }, { X => 'ab', Y => undef, Z => 'c' }, { X => 'ab', Y => 'cd', Z => 'e' });

# (each: the program, its name, and whether T2 refuses it, by name)
for my $case (
    [ q{my $a = $ENV{X} // 6; my $b = $ENV{Y} // 3; my $c = $ENV{Z} // 2; print $a | $b & $c, " ", ($a | $b) & $c, "\n";},
      'pvm 047: each variable read by two ops' ],
    [ q{my $a = $ENV{X} // "6"; my $b = $ENV{Y} // "3"; print $a & $b, " ", $a | $b, "\n";}, 'two string ops' ],
    [ q{my $a = $ENV{X} // 6; my $s = $a << 1; my $c = ~$a & 255; print "$s $c\n";}, 'a shift, then ~' ],
    # A STRING A SHIFT MADE A NUMBER, then & with another string: perl's & is on
    # numbers. A COPY made before is another variable: B::SoN's one node for
    # both leaves its op floating, refused.
    [ q{my $a = $ENV{X} // "ab"; my $s = $a << 1; print $s, " ", $a & ( $ENV{Y} // "cd" ), "\n";}, 'a shift, then & of strings' ],
    [ q{my $a = $ENV{X} // "ab"; my $b = $a; my $s = $a << 1; my $r = $b & "a1"; print "$s $r\n";}, 'a copy before the shift (another variable)', 'refused' ],
    # AN %ENV VALUE OR AN @ARGV ELEMENT READ AS A NUMBER ELSEWHERE is a number
    # when a `//` copies it: refused (it printed "a " for perl's "0").
    [ q{my $n = $ENV{X} + 0; my $a = $ENV{X} // "ab"; print $a & "a1", " $n\n";}, 'an %ENV value read as a number before', 'refused' ],
    [ q{my $n = $ARGV[0] + 0; my $a = $ARGV[0] // "ab"; print $a & "a1", " $n\n";}, 'an @ARGV element read as a number before', 'refused' ],
    [ q{my $n = $ARGV[1] + 0; my $a = $ARGV[0] // "ab"; print $a & "a1", " $n\n";}, 'another @ARGV element read as a number' ],
    [ q{my $a = $ENV{X} // "ab"; my $n = $a & 5; print $n, " ", $a & 3, "\n";}, '& with numbers twice' ],
    [ q{my $a = $ENV{X} // "12"; my $n = $a & 5; print $n, " ", $a | "  ", "\n";}, '& with a number, then | with a string' ],
) {
    my ($src, $name, $refused) = @$case;
    my ($ll, $pl, $why) = t2("$src\n");
    if ($refused) { ok(!defined $ll, "$name: not T2's"); like($why // '', qr/\AT2: out of its slices \(/, "$name: refused by name"); next }
    ok(defined $ll, "$name: T2's") or do { diag $why; next };
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    for my $i (0 .. $#envs) {
        my $env = $envs[$i];
        my $shown = join ',', map { "$_=" . ( $env->{$_} // 'unset' ) } sort keys %$env;
        my $got = run("timeout 20 $LLI $llp", $env);
        is($got->[0], run("$^X $pl", $env)->[0], "$name ($shown): perl's") or diag $got->[1];
    }
}

done_testing;
