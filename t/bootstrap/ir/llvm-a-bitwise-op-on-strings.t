# ABOUTME: & | ^ ~ on what may be a string: perl combines bytes when neither operand
# ABOUTME: holds a number, else numbers -- through B::SoN -> chalk -> lli == perl.
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
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return ($out, $pl);
}

sub perl_says ($pl, $env) {
    local @ENV{ keys %$env } = values %$env;
    return scalar qx($^X $pl 2>/dev/null);
}

# Each program runs with %ENV unset (its defaults, mostly numbers) and set
# (strings), and must print what perl prints both ways.
my @envs = ({ X => undef, Y => undef, Z => undef }, { X => '7', Y => '3', Z => 'ab' }, { X => 'ab', Y => undef, Z => 'c' });
my $each_env = sub ($src, $name, $may_refuse) {
    for my $env (@envs) {
        my $shown = join ',', map { "$_=" . ( $env->{$_} // 'unset' ) } sort keys %$env;
        my ($got, $pl) = eval { through_llvm($src, $env) };
        if ($may_refuse && !defined $got && $@ =~ /GAP/) { pass("$name ($shown): refused by name"); next }
        is($got, perl_says($pl, $env), "$name ($shown)") or diag $@;
    }
};

# Lowered: each value that may be a string is read by one bitwise op.
for my $case (
    [ q{my $s1 = $ENV{X} // "12"; my $s2 = $ENV{Y} // "10"; print $s1 & $s2, "\n";}, 'pvm 050: & of two strings' ],
    [ q{my $a = $ENV{X} // 12; print ~$a & 255, "\n";}, 'pvm 049: ~ of a string or a number' ],
    [ q{my $a = $ENV{X} // "ab"; my $b = $ENV{Z} // "c"; print $a | $b, "\n";}, '| of unequal lengths' ],
    [ q{my $a = $ENV{X} // "ab"; print $a ^ "  ", "\n";}, '^ of unequal lengths' ],
    [ q{my $a = $ENV{Z} // "abc"; my $b = $ENV{X} // 5; print $b & $a, "\n";}, '& of unequal lengths, or of a number' ],
    [ q{my $s = $ENV{Z} // "12"; my $t = ~$s; print ~$t, "\n";}, '~ of ~ of a string' ],
) { $each_env->(@$case, 0) }

# Perl's answer, or refused by name: a string a numeric read made a number is
# a number to the op after -- and one node may stand for several variables,
# so which variable the read numified is not known.
for my $case (
    [ q{my $a = $ENV{X} // 6; my $b = $ENV{Y} // 3; my $c = $ENV{Z} // 2;
        print $a | $b & $c, " ", ($a | $b) & $c, "\n";}, 'pvm 047: each variable read by two ops' ],
    [ q{my $s = $ENV{X} // "12"; print $s & 5, " ", $s & "10", "\n";}, 'a string a numeric & read first' ],
    [ q{my $s = $ENV{X} // "12"; my $n = $s + 1; print $s & "10", " $n\n";}, 'a string + also reads' ],
    [ q{my $s = $ENV{X} // "12"; for my $i (1, 2) { print $s & "10" } print "\n";}, 'a string op in a loop' ],
) { $each_env->(@$case, 1) }

done_testing;
