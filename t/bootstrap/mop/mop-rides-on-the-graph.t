# ABOUTME: The MOP is an edge that exists on EVERY load, not only on class programs.
# ABOUTME: Subtest 1 pins the base case -- a class-less program still yields a MOP.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;
plan skip_all => "perl5-son not found at $SON"  unless -f "$SON/B/SoN.pm";

my $dir = tempdir(CLEANUP => 1);

sub load ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -I$SON -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return Chalk::IR::Serialize::JSON::from_json($json);
}

# A program with no classes and no named subs makes the producer emit
# `classes: undef`. The loader used to take that as "there is nothing to build a
# MOP from" and return a one-element list, so a caller asking for the MOP got
# undef -- an edge that exists for some programs and not others. Every program
# has a `main`, so every load has a MOP.
subtest 'a class-less program still yields a MOP' => sub {
    my ($graphs, $mop) = load('my $x = 1 + 2; print $x, "\n";', 'classless');
    ok defined $graphs, 'the graphs came back' or return;
    ok defined $mop, 'and so did the MOP';
    isa_ok $mop, 'Chalk::MOP';
};

done_testing;
