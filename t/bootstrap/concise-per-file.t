# ABOUTME: Per-file oracle validation: parse real .pm files, compare ConciseTree against B::Concise.
# ABOUTME: Tests that the full pipeline produces correct ops for actual source files, tiered by complexity.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_concise_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::ConciseTree;
use Chalk::Bootstrap::ConciseTree::Oracle;
use Chalk::Bootstrap::ConciseTree::Comparator;
use OracleCache qw(get_or_generate);

# ========================================================================
# File list: [file_path, label] pairs.
# Sorted by tier (A-D), matching the original validate_file() ordering.
# ========================================================================
my @FILES = (
    # Tier A: Simplest files (11-15 lines)
    # Pure data classes with use declarations, feature class, simple methods
    # returning string constants. All constructs already have action methods.
    ['lib/Chalk/Bootstrap/IR/Node/Start.pm',              'Tier A: IR::Node::Start'],
    ['lib/Chalk/Bootstrap/IR/Node/Return.pm',             'Tier A: IR::Node::Return'],
    ['lib/Chalk/Bootstrap/Target.pm',                     'Tier A: Target'],
    ['lib/Chalk/Bootstrap/Optimizer/Pass.pm',             'Tier A: Optimizer::Pass'],

    # Tier B: Classes with field declarations (17-22 lines)
    # Same as Tier A but with field declarations, which cause B::Concise to
    # emit nextstate instead of stub inside the class body.
    ['lib/Chalk/Bootstrap/IR/Node/Constant.pm',           'Tier B: IR::Node::Constant'],
    ['lib/Chalk/Bootstrap/Target/XS/AST/Node.pm',        'Tier B: XS::AST::Node'],
    ['lib/Chalk/Bootstrap/Target/XS/AST/Statement.pm',   'Tier B: XS::AST::Statement'],
    ['lib/Chalk/Bootstrap/Target/XS/AST/Module.pm',      'Tier B: XS::AST::Module'],
    ['lib/Chalk/Bootstrap/IR/Node/Constructor.pm',        'Tier B: IR::Node::Constructor'],

    # Tier C: Classes with methods containing runtime logic (25-45 lines)
    # Methods use string interpolation, conditionals, regex, join, push,
    # etc. B::Concise sees compile-time class envelope only for main program.
    ['lib/Chalk/Bootstrap/ConciseOp.pm',                  'Tier C: ConciseOp'],
    ['lib/Chalk/Bootstrap/ConciseTree.pm',                'Tier C: ConciseTree'],
    ['lib/Chalk/Bootstrap/ConciseTree/Comparator.pm',     'Tier C: ConciseTree::Comparator'],
    ['lib/Chalk/Bootstrap/ConciseTree/Oracle.pm',         'Tier C: ConciseTree::Oracle'],
    ['lib/Chalk/Bootstrap/Context.pm',                    'Tier C: Context'],

    # Tier D: All remaining oracle-matching files
    # Includes classes with diverse method bodies, standalone modules with
    # subs, and large files. B::Concise main-program optree matches ours.
    ['lib/Chalk/Bootstrap/Target/XS/AST/CompositeNode.pm','Tier D: XS::AST::CompositeNode'],
    ['lib/Chalk/Bootstrap/Target/XS/AST/VarDecl.pm',     'Tier D: XS::AST::VarDecl'],
    ['lib/Chalk/Grammar/Symbol.pm',                       'Tier D: Symbol'],
    ['lib/Chalk/Bootstrap/Target/XS/AST/Preamble.pm',    'Tier D: XS::AST::Preamble'],
    ['lib/Chalk/Bootstrap/Terminal.pm',                   'Tier D: Terminal'],
    ['lib/Chalk/Grammar/Rule.pm',                         'Tier D: Rule'],
    ['lib/Chalk/Bootstrap/IR/Node.pm',                    'Tier D: IR::Node'],
    ['lib/Chalk/Bootstrap/Optimizer.pm',                  'Tier D: Optimizer'],
    ['lib/Chalk/Bootstrap/Semiring/Composite.pm',         'Tier D: Semiring::Composite'],
    ['lib/Chalk/Bootstrap/Semiring/SemanticAction.pm',    'Tier D: Semiring::SemanticAction'],
    ['lib/Chalk/Grammar/Perl/KeywordTable.pm',            'Tier D: KeywordTable'],
    ['lib/Chalk/Bootstrap/Target/XS/AST/XSUB.pm',        'Tier D: XS::AST::XSUB'],
    ['lib/Chalk/Bootstrap/Optimizer/DCE.pm',              'Tier D: Optimizer::DCE'],
    ['lib/Chalk/Bootstrap/Target/Perl.pm',                'Tier D: Target::Perl'],
    ['lib/Chalk/Grammar/BNF/Generated.pm',                'Tier D: BNF::Generated'],
    ['lib/Chalk/Bootstrap/Desugar.pm',                    'Tier D: Desugar'],
    ['lib/Chalk/Grammar/BNF.pm',                          'Tier D: Grammar::BNF'],
    ['lib/Chalk/Bootstrap/Semiring/Structural.pm',        'Tier D: Semiring::Structural'],
    ['lib/Chalk/Bootstrap/Semiring/TypeInference.pm',     'Tier D: Semiring::TypeInference'],
    ['lib/Chalk/Bootstrap/Earley.pm',                     'Tier D: Earley'],
    ['lib/Chalk/Bootstrap/Target/XS.pm',                  'Tier D: Target::XS'],
    ['lib/Chalk/Grammar/Perl/PrecedenceTable.pm',         'Tier D: PrecedenceTable'],
    ['lib/Chalk/Bootstrap/Semiring/Boolean.pm',           'Tier D: Semiring::Boolean'],
    ['lib/Chalk/Bootstrap/Perl/Actions.pm',              'Tier D: Perl::Actions'],
    ['lib/Chalk/Bootstrap/Perl/Target/Perl.pm',          'Tier D: Perl::Target::Perl'],
    ['lib/Chalk/Bootstrap/Perl/Target/XS.pm',            'Tier D: Perl::Target::XS'],
);

# Check B::Concise is available
my $concise_check = `perl -MO=Concise,-exec -e '1' 2>&1`;
my $has_concise = ($concise_check =~ /enter/);

# Build the Perl grammar pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::PerFileValidation/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::PerFileValidation::grammar();
    my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
    skip 'Concise parser not built', 1 unless defined $parser;

    my $oracle = Chalk::Bootstrap::ConciseTree::Oracle->new();
    my $comparator = Chalk::Bootstrap::ConciseTree::Comparator->new();

    # Parse a .pm file and return our ConciseTree
    my sub our_tree_for_file($file) {
        my $source = do {
            open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
            local $/;
            <$fh>;
        };
        my $result = $parser->parse_value($source);
        return undef unless defined $result;
        return undef unless $result->[0]; # Boolean
        return $result->[4]->extract();   # SemanticAction result
    }

    # Get B::Concise oracle tree for a .pm file (using cache)
    my sub oracle_tree_for_file($file) {
        return undef unless $has_concise;
        my $output = get_or_generate($file);
        return $oracle->parse_concise_output($output);
    }

    # Run per-file comparison for a single file, returns result hash
    my sub run_validation($file, $label) {
        my %result = (file => $file, label => $label);

        my $ours = our_tree_for_file($file);
        $result{parse_ok} = defined $ours ? 1 : 0;

        if (defined $ours) {
            my $theirs = oracle_tree_for_file($file);
            if (defined $theirs) {
                my $cmp = $comparator->compare($ours, $theirs);
                $result{match} = $cmp->{match} ? 1 : 0;
                unless ($cmp->{match}) {
                    $result{diag} = join("\n",
                        "File: $file",
                        "Differences:",
                        (map { "  $_" } $cmp->{differences}->@*),
                        "Ours: " . join(", ", map { $_->structural_key() } $ours->ops()->@*),
                        "Theirs: " . join(", ", map { $_->structural_key() } $theirs->ops()->@*),
                    );
                }
            } else {
                $result{oracle_skip} = 1;
            }
        }

        return \%result;
    }

    # Files with known oracle mismatches or parse failures.
    # Parse failures: ambiguity patterns not yet resolved by semiring disambiguation.
    # Oracle mismatch: ConciseTree ops differ from B::Concise (introcv/clonecv for my sub).
    my %TODO_FILES = (
        # Parse failures — remaining ambiguities
        'lib/Chalk/Bootstrap/Perl/Actions.pm'      => 'Complex my sub + regex constructs exceed grammar capacity',
        'lib/Chalk/Bootstrap/Earley.pm'             => 'Pre-existing phase5 Earley parse failure',
        'lib/Chalk/Bootstrap/Perl/Target/XS.pm'     => 'Remaining parse ambiguity in complex patterns',
        # Oracle mismatch — my sub introcv/clonecv not modeled
        'lib/Chalk/Bootstrap/Semiring/SemanticAction.pm' => 'Oracle mismatch: my sub introcv/clonecv ops',
    );

    # Emit TAP for a single file result
    my sub emit_tap_for_result($r) {
        my $todo_reason = $TODO_FILES{$r->{file}};
        subtest $r->{label} => sub {
            local $TODO = $todo_reason if $todo_reason;

            ok($r->{parse_ok}, "$r->{label}: parses successfully")
                or diag("Parse returned undef for $r->{file}");

            SKIP: {
                skip "$r->{label} did not parse", 1 unless $r->{parse_ok};
                skip "B::Concise oracle failed for $r->{file}", 1 if $r->{oracle_skip};

                ok($r->{match}, "$r->{label}: matches B::Concise oracle")
                    or diag($r->{diag} // "unknown error");
            }
        };
    }

    my $serial = $ENV{CONCISE_SERIAL};
    my $num_workers = $ENV{CONCISE_WORKERS} // 4;

    if ($serial) {
        # Serial mode: run everything in the parent process sequentially
        for my $entry (@FILES) {
            my ($file, $label) = $entry->@*;
            my $result;
            eval { $result = run_validation($file, $label); };
            if ($@ || !defined $result) {
                my $err = $@ // 'unknown error';
                $err =~ s/\n.*//s;  # keep first line only
                $result = { file => $file, label => $label, parse_ok => 0, diag => "Parse died: $err" };
            }
            emit_tap_for_result($result);
        }
    } else {
        # Parallel mode: fork N workers, distribute files round-robin by size desc

        # Sort indices by file size descending for load balancing
        my @sorted_indices = sort {
            (-s $FILES[$b][0] // 0) <=> (-s $FILES[$a][0] // 0)
        } 0 .. $#FILES;

        # Distribute files to workers round-robin
        my @worker_files;
        for my $i (0 .. $#sorted_indices) {
            my $worker = $i % $num_workers;
            $worker_files[$worker] //= [];
            push $worker_files[$worker]->@*, $sorted_indices[$i];
        }

        # Fork workers, each writes results to its pipe
        my @pipes;
        my @pids;

        for my $w (0 .. $#worker_files) {
            pipe(my $reader, my $writer) or die "pipe: $!";
            my $pid = fork();
            die "fork: $!" unless defined $pid;

            if ($pid == 0) {
                # Child worker
                close $reader;
                $writer->autoflush(1);

                for my $idx ($worker_files[$w]->@*) {
                    my ($file, $label) = $FILES[$idx]->@*;
                    my $result;
                    eval { $result = run_validation($file, $label); };
                    if ($@ || !defined $result) {
                        my $err = $@ // 'unknown error';
                        $err =~ s/\n.*//s;  # keep first line only
                        $result = { file => $file, label => $label, parse_ok => 0, diag => "Parse died: $err" };
                    }

                    # Write tab-delimited result line
                    my $parse_ok = $result->{parse_ok} // 0;
                    my $match = $result->{match} // 0;
                    my $oracle_skip = $result->{oracle_skip} // 0;
                    # Encode diag: replace newlines and tabs for safe transport
                    my $diag = $result->{diag} // '';
                    $diag =~ s/\t/\\t/g;
                    $diag =~ s/\n/\\n/g;

                    print $writer join("\t",
                        $idx, $file, $label, $parse_ok, $match, $oracle_skip, $diag
                    ) . "\n";
                }

                close $writer;
                exit 0;
            }

            # Parent
            close $writer;
            push @pipes, $reader;
            push @pids, $pid;
        }

        # Parent: collect results from all workers
        my %results;
        for my $reader (@pipes) {
            while (my $line = <$reader>) {
                chomp $line;
                my ($idx, $file, $label, $parse_ok, $match, $oracle_skip, $diag) = split /\t/, $line, 7;
                # Decode diag
                $diag =~ s/\\n/\n/g;
                $diag =~ s/\\t/\t/g;

                $results{$idx} = {
                    file        => $file,
                    label       => $label,
                    parse_ok    => $parse_ok,
                    match       => $match,
                    oracle_skip => $oracle_skip,
                    diag        => $diag,
                };
            }
            close $reader;
        }

        # Wait for all children
        for my $pid (@pids) {
            waitpid($pid, 0);
        }

        # Emit TAP in original file order
        for my $i (0 .. $#FILES) {
            if (exists $results{$i}) {
                emit_tap_for_result($results{$i});
            } else {
                # Should not happen, but handle gracefully
                fail("$FILES[$i][1]: worker did not return result");
            }
        }
    }
}

done_testing;
