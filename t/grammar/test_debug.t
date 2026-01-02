#!/usr/bin/env perl
use 5.42.0;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::ChalkIR;

# Load grammar BNF
my $bnf_file = "$RealBin/../../grammar/chalk.bnf";
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf = do { local $/; <$fh> };
close $fh;

subtest 'State variable with parameter reference' => sub {
    my $grammar = Chalk::Grammar->build_from_bnf($bnf, 'Program', 'Chalk');
    my $source = q{
class Foo {
    sub test($class) {
        state $x = $class;
        return $x;
    }
}
};

    my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
    my $result = $parser->parse_string($source);

    ok($result, 'Parses state variable with parameter reference');
    
    if ($result) {
        my $ir = $result->context->focus;
        print "IR defined: ", (defined($ir) ? "yes" : "no"), "\n";
        print "IR type: ", ref($ir), "\n";
        print "IR has class_defs: ", ($ir->can('class_defs') ? "yes" : "no"), "\n";
        
        if ($ir->can('class_defs')) {
            my $classes = $ir->class_defs;
            print "class_defs defined: ", (defined($classes) ? "yes" : "no"), "\n";
            print "class_defs type: ", ref($classes), "\n";
            print "class_defs count: ", scalar(@$classes), "\n";
        }
    }
};

done_testing();
