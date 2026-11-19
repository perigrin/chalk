# ABOUTME: a sub made in a method that reads the method's fields, called directly there, reads them
# ABOUTME: of the object the method was called on; one handed out as a code value is refused by name.
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

for my $case (
    [ q~use v5.42; use experimental 'class';
class C {
    field %m;
    method add ($k) { $m{$k} = 1 }
    method n { my $in = sub ($k) { exists $m{$k} ? 1 : 0 }; return $in->("a") . $in->("b") }
}
my $x = C->new; my $y = C->new;
$x->add("a"); $y->add("b");
print $x->n, $y->n, "\\n";
~, 'a closure in a method reads a hash field, two objects', q~~ ],
    [ q~use v5.42; use experimental 'class';
class P {
    field $name :param;
    method greet ($w) { my $f = sub ($s) { "$s, $name" }; return $f->($w) }
}
print P->new(name => "ann")->greet("hi"), " ", P->new(name => "bo")->greet("yo"), "\\n";
~, 'a closure in a method reads a scalar field', q~~ ],
    [ q~use v5.42; use experimental 'class';
class Q {
    field $v :param;
    method getter { return sub { $v } }
}
my $g = Q->new(v => 3)->getter;
print $g->(), "\\n";
~, 'a closure reading a field handed out as a code value', q~reads a field of its method\'s object, as a code value~ ],
) {
    my ($src, $name, $refuse) = @$case;
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    if (length $refuse) {
        ok(!$err && ( $u->{path} // '' ) ne 't2' && ( $u->{path_why} // '' ) =~ /$refuse/, "$name: refused by name") or diag $err // $u->{path_why} // 'lowered';
        next;
    }
    my $ll = !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef;
    ok(defined $ll, "$name: lowered through T2") or diag $err // $u->{path_why} // $u->{err};
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $lf, ':utf8'; print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

done_testing;
