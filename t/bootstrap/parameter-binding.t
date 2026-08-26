# ABOUTME: A Parameter node binds to the caller's argument by INDEX, end to end.
# ABOUTME: The declared signature replaces the backend's `shift @_` scan.

use 5.42.0;
use utf8;
use Test2::V0;
use File::Temp qw(tempfile);

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

skip_all "perl5-son not found" unless -f "$SON/B/SoN.pm";
skip_all "lli not found"       unless -x $LLI;
skip_all "perl 5.42 not found" unless -x $PERL;

use lib 'lib', 't/lib';
require Chalk::IR::Serialize::JSON;
require Chalk::Target::LLVM;

# The backend used to recover arity by SCANNING the callee graph for `shift @_`
# reads. With a declared signature there is no `shift` -- there are Parameter
# nodes -- so the scan found zero and GAPped with "callee reads 0 positional
# argument(s) ... but the call passes 2". That scan is precisely the
# recovery-by-scanning the metadata channel exists to retire: a Parameter's
# INDEX already says which argument it is.
sub run_it ($program) {
    my ( $fh, $tmp ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $program;
    close $fh;

    my $want = qx($PERL $tmp 2>&1);
    chomp $want;

    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
    return ( 'err', 'no JSON' ) unless $json =~ /\S/;
    my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
    my $mop = (values %$graphs)[0]->mop;
    my $g = $graphs->{'main::__PROGRAM__'} or return ( 'err', 'no __PROGRAM__' );

    my $ll = eval {
        Chalk::Target::LLVM->lower( $g->returns->[0],
            ( defined $mop ? ( mop => $mop ) : () ) );
    };
    if ($@) { my $e = $@; $e =~ s/\n.*//s; return ( 'gap', $e, $want ) }

    my ( $lfh, $lltmp ) = tempfile( SUFFIX => '.ll', UNLINK => 1 );
    print $lfh $ll;
    close $lfh;
    my $got = qx($LLI $lltmp 2>&1);
    chomp $got;
    $got =~ s/\nUndef:$//;
    return ( 'value', $got, $want );
}

subtest 'a two-parameter signature call binds and runs' => sub {
    my ( $kind, $got, $want )
        = run_it(qq{use 5.42.0;\nsub two(\$a,\$b) { \$a + \$b }\nprint two(1,2), "\\n";\n});
    is $kind, 'value', 'lowered without a GAP' or do { diag $got; return };
    is $got, $want, "chalk matches perl ($want)";
};

subtest 'a one-parameter signature call binds by index' => sub {
    my ( $kind, $got, $want )
        = run_it(qq{use 5.42.0;\nsub dbl(\$x) { \$x * 2 }\nprint dbl(21), "\\n";\n});
    is $kind, 'value', 'lowered without a GAP' or do { diag $got; return };
    is $got, $want, "chalk matches perl ($want)";
};

# Order matters: binding by index must not silently transpose. Subtraction is
# not commutative, so a swapped binding gives a different answer rather than
# the same one -- an addition test cannot discriminate.
subtest 'parameters bind in the right ORDER' => sub {
    my ( $kind, $got, $want )
        = run_it(qq{use 5.42.0;\nsub sub2(\$a,\$b) { \$a - \$b }\nprint sub2(10,3), "\\n";\n});
    is $kind, 'value', 'lowered without a GAP' or do { diag $got; return };
    is $got, $want, "10-3 is $want, not -7";
};

# A parameter read twice hash-conses to ONE node, so the binding must survive
# multiple uses of the same parameter.
subtest 'one parameter used twice' => sub {
    my ( $kind, $got, $want )
        = run_it(qq{use 5.42.0;\nsub sq(\$n) { \$n * \$n }\nprint sq(7), "\\n";\n});
    is $kind, 'value', 'lowered without a GAP' or do { diag $got; return };
    is $got, $want, "7*7 is $want";
};

done_testing;
