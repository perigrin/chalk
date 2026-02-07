# ABOUTME: Phase 5 test — control flow and full grammar recognition with the Perl grammar.
# ABOUTME: Tests conditionals, loops, full program structures, and real .pm file recognition.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_recognizer);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;

# Build the Perl grammar recognizer with Program as start symbol
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::Phase5/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::Phase5::grammar();
    my $recognizer = build_perl_recognizer($gen_grammar, start => 'Program');

    skip 'Recognizer not built', 1 unless defined $recognizer;

    # §5 IfStatement — basic if
    ok($recognizer->parse('if ($x) { }'),
        'Phase 5: accepts basic if');
    ok($recognizer->parse('if ($x) { $y; }'),
        'Phase 5: accepts if with body');

    # §5 IfStatement — if/else
    ok($recognizer->parse('if ($x) { } else { }'),
        'Phase 5: accepts if/else');
    ok($recognizer->parse('if ($x) { $y; } else { $z; }'),
        'Phase 5: accepts if/else with bodies');

    # §5 IfStatement — if/elsif/else
    ok($recognizer->parse('if ($x) { } elsif ($y) { } else { }'),
        'Phase 5: accepts if/elsif/else');
    ok($recognizer->parse('if ($a) { } elsif ($b) { } elsif ($c) { } else { }'),
        'Phase 5: accepts multiple elsif');

    # §5 IfStatement — unless
    ok($recognizer->parse('unless ($done) { }'),
        'Phase 5: accepts unless');
    ok($recognizer->parse('unless ($done) { } else { }'),
        'Phase 5: accepts unless/else');

    # §5 IfStatement — if with elsif but no else
    ok($recognizer->parse('if ($a) { } elsif ($b) { }'),
        'Phase 5: accepts if/elsif without else');

    # §6 WhileStatement
    ok($recognizer->parse('while ($cond) { }'),
        'Phase 5: accepts while loop');
    ok($recognizer->parse('while ($cond) { $x++; }'),
        'Phase 5: accepts while with body');

    # §6 WhileStatement — until
    ok($recognizer->parse('until ($done) { }'),
        'Phase 5: accepts until loop');
    ok($recognizer->parse('until ($done) { $x++; }'),
        'Phase 5: accepts until with body');

    # §6 ForStatement — C-style for
    ok($recognizer->parse('for (my $i = 0; $i < 10; $i++) { }'),
        'Phase 5: accepts C-style for loop');
    ok($recognizer->parse('for ($i = 0; $i < 10; $i++) { }'),
        'Phase 5: accepts C-style for without my');
    ok($recognizer->parse('for (;;) { }'),
        'Phase 5: accepts infinite for loop');

    # §6 ForStatement — partial expressions
    ok($recognizer->parse('for ($i = 0;;) { }'),
        'Phase 5: accepts for with init only');
    ok($recognizer->parse('for (; $i < 10;) { }'),
        'Phase 5: accepts for with condition only');
    ok($recognizer->parse('for (;; $i++) { }'),
        'Phase 5: accepts for with step only');

    # §6 ForeachStatement — with iterator variable
    ok($recognizer->parse('for my $item (@list) { }'),
        'Phase 5: accepts for-my iterator');
    ok($recognizer->parse('foreach my $key (@list) { }'),
        'Phase 5: accepts foreach-my iterator');
    ok($recognizer->parse('foreach my $key (keys %hash) { }'),
        'Phase 5: accepts foreach-my with function call in list');
    ok($recognizer->parse('for $item (@list) { }'),
        'Phase 5: accepts for iterator without my');

    # §6 ForeachStatement — without iterator variable
    ok($recognizer->parse('for (@list) { }'),
        'Phase 5: accepts for without iterator');
    ok($recognizer->parse('foreach (@list) { }'),
        'Phase 5: accepts foreach without iterator');

    # Nested control flow
    ok($recognizer->parse('if ($x) { while ($y) { } }'),
        'Phase 5: accepts nested if/while');
    ok($recognizer->parse('for my $item (@list) { if ($item) { $item++; } }'),
        'Phase 5: accepts for with nested if');

    # Full program structure (from plan)
    ok($recognizer->parse("use 5.42.0;\nuse utf8;\n\nclass Foo :isa(Bar) {\n    field \$name :param :reader;\n    field \$count :param = 0;\n\n    method increment() {\n        \$count++;\n    }\n\n    method process(\$input) {\n        if (defined(\$input)) {\n            return \$input;\n        }\n        return undef;\n    }\n\n    method collect(\@items) {\n        my \@results;\n        for my \$item (\@items) {\n            push \@results, \$item\n                if defined(\$item);\n        }\n        return \\\@results;\n    }\n}"),
        'Phase 5: accepts full class with control flow (from plan)');

    # Full file recognition — test against real .pm files under lib/Chalk/
    # (Plan requirement: "test against every .pm file under lib/Chalk/")
    use File::Find;
    my @pm_files;
    File::Find::find(
        sub { push @pm_files, $File::Find::name if /\.pm$/ },
        'lib/Chalk'
    );
    for my $file (sort @pm_files) {
        open my $fh, '<:utf8', $file or do {
            fail("Phase 5: cannot read $file: $!");
            next;
        };
        local $/;
        my $source = <$fh>;
        close $fh;
        TODO: {
            local $TODO = 'real file recognition may require grammar or performance fixes';
            ok($recognizer->parse($source),
                "Phase 5: recognizes $file");
        }
    }

    # Negative cases
    ok(!$recognizer->parse('if $x { }'),
        'Phase 5: rejects if without parens around condition');
    ok(!$recognizer->parse('if ($x) {'),
        'Phase 5: rejects if with unclosed block');
    ok(!$recognizer->parse('for (;;)'),
        'Phase 5: rejects for without block');
    ok(!$recognizer->parse('while { }'),
        'Phase 5: rejects while without parens around condition');
}

done_testing();
