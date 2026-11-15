# ABOUTME: `return @field` (a class's array field) is a list return: in the caller's context its
# ABOUTME: elements, or their count -- as `return @a` of a `my` array is (Chalk::MOP::Class::unloaded).
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
require Chalk::CodeGen::Pipeline;

sub run ($cmd) {
    my (undef, $ef) = tempfile(UNLINK => 1);
    my $out = qx($cmd 2>$ef);
    my $code = $? >> 8;
    my $err = do { local (@ARGV, $/) = $ef; <> } // '';
    return [ $out, $err, $code ];
}

for my $case (
    [ q{use v5.42; use experimental 'class'; class Bag { field @items; method add($x) { push @items, $x; return } method items() { return @items } } my $b = Bag->new; $b->add("a"); $b->add("b"); my @l = $b->items; my $n = $b->items; print scalar(@l), " $n @l\n";},
      'a field array returned: its elements in a list, its count in a scalar' ],
    [ q{use v5.42; use experimental 'class'; class Bag { field @items; method items() { return @items } } my $b = Bag->new; my @l = $b->items; print scalar(@l), " ", scalar($b->items), "\n";},
      'an empty one' ],
) {
    my ($src, $name) = @$case;
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = ( $units // [] )->[0] // {};
    my $ll = !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef;
    ok(defined $ll, "$name: lowered through T2") or diag $err // $u->{path_why} // $u->{err};
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

done_testing;
