# ABOUTME: Differential harness: a test program under perl vs through B::SoN, T2 and lli,
# ABOUTME: comparing stdout (TAP), stderr (diag) and exit status byte for byte.
package Chalk::CodeGen::Harness::TapDiff;

use 5.42.0;
use utf8;

use File::Temp qw(tempfile);
use Chalk::CodeGen::Pipeline;

# The oracle is perl; the candidate is the T2 path ONLY. A program T2 declines
# and the old Context path lowers is REFUSED here: T2 is the architecture, and
# a pass through Context says nothing about it.
our $PERL = $ENV{TAPDIFF_PERL} // $^X;
our $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
our $LLI  = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';

# compare($path, inc => [dirs]) -> {
#   verdict  SAME | DIFFERS | REFUSED
#   why      on REFUSED, the reason; on DIFFERS, which stream differs
#   perl     { out, err, exit }
#   llvm     { out, err, exit }   (absent on REFUSED)
# }
sub compare ( $class, $path, %opt ) {
    my $inc  = join ' ', map {"-I$_"} @{ $opt{inc} // [] };
    my %perl = _run("$PERL $inc $path");

    my ( undef, $err ) = tempfile( UNLINK => 1 );
    my $json = qx($PERL $inc -I$SON -MO=-q,SoN,json $path 2>$err);
    return _refused( \%perl, 'B::SoN produced no JSON: ' . _first_line( _slurp($err) ) )
        unless $json =~ /\S/;

    my $select = sub ( $graphs, $mop ) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ( [ 'main::__PROGRAM__', $ret ] );
    };
    my ( $units, undef, undef, $load_err ) =
        eval { Chalk::CodeGen::Pipeline->new->run_detail( $json, $select, program_mode => 1 ) };
    $load_err //= $@ || undef;
    return _refused( \%perl, "load: $load_err" ) if $load_err;
    my $u = ( $units // [] )->[0]
        // return _refused( \%perl, 'no entry graph: ' . _first_line( _slurp($err) ) );
    return _refused( \%perl, ( $u->{path_why} // $u->{err} // 'declined' ) =~ s/\A(?!T2: )/T2: /r )
        unless ( $u->{path} // '' ) eq 't2' && $u->{ok};

    my ( $lfh, $ll ) = tempfile( SUFFIX => '.ll', UNLINK => 1 );
    binmode $lfh, ':utf8';
    print $lfh $u->{ll};
    close $lfh;
    my %llvm = _run("$LLI $ll");

    my @diff = grep { $perl{$_} ne $llvm{$_} } qw(out err exit);
    return {
        verdict => @diff ? 'DIFFERS' : 'SAME',
        ( @diff ? ( why => "differs in: @diff" ) : () ),
        perl => \%perl,
        llvm => \%llvm,
    };
}

sub _refused ( $perl, $why ) {
    chomp $why;
    return { verdict => 'REFUSED', why => $why, perl => $perl };
}

# _run($cmd) -> (out => ..., err => ..., exit => ...)
sub _run ($cmd) {
    my ( undef, $err ) = tempfile( UNLINK => 1 );
    my $out = qx($cmd 2>$err);
    my $exit = $? & 127 ? 128 + ( $? & 127 ) : $? >> 8;
    return ( out => $out // '', err => _slurp($err), exit => $exit );
}

sub _slurp ($f) { open my $fh, '<', $f or return ''; local $/; return <$fh> // '' }

sub _first_line ($s) { return ( split /\n/, $s // '' )[0] // '' }

# FROM THE COMMAND LINE: perl t/lib/Chalk/CodeGen/Harness/TapDiff.pm FILE...
# One line per file: SAME|DIFFERS|REFUSED, the path, and why. Exits 0 when
# every file is the same, 1 otherwise.
sub main ( $class, @files ) {
    my $all = 1;
    for my $f (@files) {
        my $r = $class->compare($f);
        $all = 0 unless $r->{verdict} eq 'SAME';
        say join "\t", $r->{verdict}, $f, ( $r->{why} // () );
    }
    return $all ? 0 : 1;
}

exit __PACKAGE__->main(@ARGV) unless caller;

1;
