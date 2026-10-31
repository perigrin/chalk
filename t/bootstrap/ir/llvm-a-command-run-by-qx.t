# ABOUTME: qx and readpipe run a command through libc popen and return what it printed:
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





# qx was refused as a host effect; libc is chalk's syscall layer already
# (print is printf), so the command runs through popen.
for my $case (
    [ q{my $out = qx{echo hi}; print $out;}, 'pvm 365' ],
    [ q{my $cmd = $ENV{NOPE_XYZ} // "echo hi"; my $out = readpipe $cmd; print "got $out";}, 'readpipe of a computed command' ],
    [ q{print "a"; my $o = qx{echo b}; print $o, "c\n";}, 'output before the command keeps its order' ],
    [ q{my $o = qx{printf 'x\ny\n'}; print length($o), "\n";}, 'more than one line, counted' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
}

# Perl's answer, or refused by name: $? after the command.
{
    my $src = q{my $o = qx{false}; print $? >> 8, "\n";};
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (!defined $got && $@ =~ /GAP/) { pass('$? after qx: refused by name') }
    else { is($got, perl_says($pl // write_pl($src), {}), "\$? after qx: perl's answer") or diag $@ }
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}

done_testing;
