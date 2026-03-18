# ABOUTME: Tests for Chalk::Bootstrap::DepChaser — IR-driven dependency resolution.
# ABOUTME: Verifies UseDecl extraction from IR and transitive dependency closure.
use 5.42.0;
use utf8;
no warnings 'experimental::class';

use Test::More;
use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::DepChaser;

# === Test 1: extract_use_decls from a hand-built IR ===
subtest 'extract_use_decls from IR tree' => sub {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->new();

    # Build a minimal Program with two UseDecl children
    my $mod_a = $factory->make('Constant', value => 'Chalk::Bootstrap::Context', const_type => 'string');
    my $mod_b = $factory->make('Constant', value => 'Chalk::Grammar::Perl::KeywordTable', const_type => 'string');
    my $use_a = $factory->make('Constructor',
        'class'       => 'UseDecl',
        module_name => $mod_a,
        import_args => undef,
    );
    my $use_b = $factory->make('Constructor',
        'class'       => 'UseDecl',
        module_name => $mod_b,
        import_args => undef,
    );
    my $class_decl = $factory->make('Constructor',
        'class' => 'ClassDecl',
        name    => $factory->make('Constant', value => 'Foo', const_type => 'string'),
        parent  => undef,
        body    => undef,
    );
    my $program = $factory->make('Constructor',
        'class'      => 'Program',
        statements => [$use_a, $use_b, $class_decl],
    );

    my @decls = Chalk::Bootstrap::DepChaser::extract_use_decls($program);
    is(scalar @decls, 2, 'found 2 UseDecl nodes');
    my @names = sort @decls;
    is($names[0], 'Chalk::Bootstrap::Context', 'first module name');
    is($names[1], 'Chalk::Grammar::Perl::KeywordTable', 'second module name');
};

# === Test 2: module_to_path maps Chalk:: modules to lib/ paths ===
subtest 'module_to_path' => sub {
    my $path = Chalk::Bootstrap::DepChaser::module_to_path('Chalk::Bootstrap::Context');
    is($path, 'lib/Chalk/Bootstrap/Context.pm', 'maps module to lib/ path');

    my $path2 = Chalk::Bootstrap::DepChaser::module_to_path('File::Path');
    is($path2, undef, 'non-Chalk module returns undef');
};

# === Test 3: resolve_deps from Earley.pm (single root) ===
subtest 'resolve_deps from Earley.pm' => sub {
    plan skip_all => 'slow integration test, set RUN_SLOW=1'
        unless $ENV{RUN_SLOW};

    my @deps = Chalk::Bootstrap::DepChaser::resolve_deps(
        'lib/Chalk/Bootstrap/Earley.pm',
    );

    # Earley.pm uses Terminal, CoreItemIndex, LR0DFA directly
    my %dep_set = map { $_ => 1 } @deps;
    ok($dep_set{'lib/Chalk/Bootstrap/Terminal.pm'},
        'Terminal.pm in direct deps');
    ok($dep_set{'lib/Chalk/Bootstrap/CoreItemIndex.pm'},
        'CoreItemIndex.pm in direct deps');
    ok($dep_set{'lib/Chalk/Bootstrap/LR0DFA.pm'},
        'LR0DFA.pm in direct deps');

    # Should not include Earley.pm itself
    ok(!$dep_set{'lib/Chalk/Bootstrap/Earley.pm'},
        'root file not in deps list');

    diag "Resolved " . scalar(@deps) . " deps from Earley.pm:";
    diag "  $_" for sort @deps;
};

# === Test 4: resolve_closure from full bootstrap seed set ===
subtest 'resolve_closure for bootstrap' => sub {
    plan skip_all => 'slow integration test, set RUN_SLOW=1'
        unless $ENV{RUN_SLOW};

    my @seeds = (
        'lib/Chalk/Bootstrap/Earley.pm',
        'lib/Chalk/Bootstrap/Semiring/Boolean.pm',
        'lib/Chalk/Bootstrap/Semiring/Precedence.pm',
        'lib/Chalk/Bootstrap/Semiring/Structural.pm',
        'lib/Chalk/Bootstrap/Semiring/TypeInference.pm',
        'lib/Chalk/Bootstrap/Semiring/SemanticAction.pm',
        'lib/Chalk/Bootstrap/Semiring/FilterComposite.pm',
    );

    my @all = Chalk::Bootstrap::DepChaser::resolve_closure(\@seeds);

    my %file_set = map { $_ => 1 } @all;

    # All seeds must be in result
    for my $seed (@seeds) {
        ok($file_set{$seed}, "$seed in closure");
    }

    # Transitive deps discovered via use declarations
    ok($file_set{'lib/Chalk/Bootstrap/Context.pm'},
        'Context.pm discovered transitively (via TypeInference, SemanticAction)');
    ok($file_set{'lib/Chalk/Bootstrap/Scope.pm'},
        'Scope.pm discovered transitively (via SemanticAction)');
    ok($file_set{'lib/Chalk/Bootstrap/IR/NodeFactory.pm'},
        'IR::NodeFactory discovered transitively (via SemanticAction)');
    ok($file_set{'lib/Chalk/Bootstrap/Terminal.pm'},
        'Terminal.pm discovered transitively (via Earley)');
    ok($file_set{'lib/Chalk/Bootstrap/CoreItemIndex.pm'},
        'CoreItemIndex.pm discovered transitively (via Earley)');
    ok($file_set{'lib/Chalk/Bootstrap/LR0DFA.pm'},
        'LR0DFA.pm discovered transitively (via Earley)');
    ok($file_set{'lib/Chalk/Bootstrap/Semiring/TypeInferenceActions.pm'},
        'TypeInferenceActions.pm discovered transitively (via TypeInference)');
    ok($file_set{'lib/Chalk/Grammar/Perl/KeywordTable.pm'},
        'KeywordTable.pm discovered transitively (via TypeInference)');
    ok($file_set{'lib/Chalk/Grammar/Perl/TypeLibrary.pm'},
        'TypeLibrary.pm discovered transitively (via TypeInferenceActions)');

    diag "Full closure (" . scalar(@all) . " files):";
    my $idx = 0;
    for my $file (@all) {
        diag sprintf("  %2d. %s", ++$idx, $file);
    }
};

done_testing;
