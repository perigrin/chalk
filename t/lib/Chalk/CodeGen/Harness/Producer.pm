# ABOUTME: Asks the B::SoN a test runs against what it puts on the control chain, so a test whose
# ABOUTME: right answer depends on a pin asserts the one outcome that producer's wire allows.
use v5.42.0;
use utf8;
use experimental 'class';

# WHY. A division whose divisor may be zero, and a method called by a name
# made at run time, float on the wire of B::SoN before its `placement-pins`:
# chalk then refuses the program by name (the wire is also that of a program
# that dies somewhere else). Once pinned, chalk runs it where it stands and
# the answer is perl's. A test that accepted "perl's answer or the refusal"
# would pass a chalk that refuses everything; these tests ask which wire they
# have and assert its one outcome.
class Chalk::CodeGen::Harness::Producer {
    use File::Temp ();
    use JSON::PP   ();

    my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
    my %answer;

    # wire_option() -> the B::SoN option for the wire version SON_WIRE names
    # (`,wire=2`), or nothing: B::SoN's default. How the gates run on wire 2.
    sub wire_option ($class) { return length( $ENV{SON_WIRE} // '' ) ? ",wire=$ENV{SON_WIRE}" : '' }

    # nodes($src) -> the wire's nodes of the program's own graph.
    sub nodes ($class, $src) {
        my ( $fh, $pl ) = File::Temp::tempfile( SUFFIX => '.pl', UNLINK => 1 );
        print $fh $src;
        close $fh;
        my $wire = eval { JSON::PP::decode_json( scalar qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null) ) } // {};
        return ( $wire->{methods}{'main::__PROGRAM__'}{nodes} // [] )->@*;
    }

    # pins_divisions() -> true where a Divide that may fault is on the control chain.
    sub pins_divisions ($class) {
        return $answer{div} //= ( grep { $_->{op} eq 'Divide' && defined $_->{control_in} }
            $class->nodes(q{my $d = @ARGV; my $q = 1 / $d; print "before\n"; print "$q\n";}) ) ? 1 : 0;
    }

    # pins_dynamic_method_calls() -> true where `$o->$m()` is on the control chain.
    sub pins_dynamic_method_calls ($class) {
        return $answer{dyn} //= ( grep { $_->{op} eq 'Call' && ( $_->{fields}{dispatch_kind} // '' ) eq 'dynamic_method' && defined $_->{control_in} }
            $class->nodes(qq{package C; sub new { bless {}, shift } sub m { 1 }\npackage main; my \$o = C->new; my \$m = "m"; \$o->\$m(); print "x\\n";}) ) ? 1 : 0;
    }
}

1;
