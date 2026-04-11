#!/usr/bin/env perl
# ABOUTME: Quick scanner to identify which .pm files Chalk can parse and extract graphs from.
# ABOUTME: Used during Phase A to select comparison targets.

use 5.42.0;
use utf8;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# Build grammar once
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ScanTest/g;
eval $generated;
die $@ if $@;
my $grammar = Chalk::Grammar::Perl::ScanTest::grammar();

my @dirs = @ARGV ? @ARGV : ('lib/Chalk/IR');
my @files;
for my $dir (@dirs) {
    push @files, glob("$dir/*.pm");
}

for my $file (sort @files) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $file or next;
    local $/;
    my $source = <$fh>;
    close $fh;

    my $parser = build_perl_ir_parser($grammar, start => 'Program');
    my $result = eval { $parser->parse_value($source) };
    my $ok = (defined $result && defined $result->[4]) ? 'OK' : 'FAIL';

    my $graphs = 0;
    my @method_names;
    if ($ok eq 'OK') {
        my $prog = eval { $result->[4]->extract() };
        if (defined $prog && $prog isa Chalk::IR::Program) {
            for my $c ($prog->classes()->@*) {
                my $cn = $c->name();
                for my $m ($c->methods()->@*) {
                    if (defined $m->graph()) {
                        $graphs++;
                        push @method_names, "${cn}::" . $m->name();
                    }
                }
                for my $s ($c->subs()->@*) {
                    if (defined $s->graph()) {
                        $graphs++;
                        push @method_names, "${cn}::" . $s->name();
                    }
                }
            }
            for my $s ($prog->top_level_subs()->@*) {
                if (defined $s->graph()) {
                    $graphs++;
                    push @method_names, $s->name();
                }
            }
        }
    }
    say "$ok ($graphs graphs) $file";
    if ($graphs > 0 && $ENV{VERBOSE}) {
        say "  $_" for @method_names;
    }
}
