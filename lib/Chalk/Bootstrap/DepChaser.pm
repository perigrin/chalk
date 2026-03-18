# ABOUTME: IR-driven dependency resolver for XS bootstrap compilation.
# ABOUTME: Extracts UseDecl module names from IR and resolves transitive closure.
use 5.42.0;
use utf8;

package Chalk::Bootstrap::DepChaser;

use Exporter 'import';
our @EXPORT_OK = qw(extract_use_decls module_to_path resolve_deps);

use Chalk::Bootstrap::IR::Node::Constructor;
use Chalk::Bootstrap::IR::Node::Constant;

# Extract module names from UseDecl Constructor nodes in a Program IR.
# Walks top-level statements looking for Constructor:UseDecl nodes.
# Returns a list of module name strings.
sub extract_use_decls($ir) {
    return unless defined $ir;
    return unless $ir isa Chalk::Bootstrap::IR::Node::Constructor;
    return unless $ir->class() eq 'Program';

    # Program's inputs()->[0] is the statements arrayref
    my $statements = $ir->inputs()->[0];
    return unless defined $statements && ref($statements) eq 'ARRAY';

    my @modules;
    for my $stmt ($statements->@*) {
        next unless $stmt isa Chalk::Bootstrap::IR::Node::Constructor;
        next unless $stmt->class() eq 'UseDecl';
        my $name_node = $stmt->inputs()->[0];
        next unless defined $name_node;
        next unless $name_node isa Chalk::Bootstrap::IR::Node::Constant;
        push @modules, $name_node->value();
    }
    return @modules;
}

# Map a module name to a lib/ relative path, only for Chalk:: modules.
# Returns undef for non-Chalk modules (core, CPAN, etc.)
sub module_to_path($module_name) {
    return unless $module_name =~ /^Chalk::/;
    my $path = $module_name;
    $path =~ s{::}{/}g;
    return "lib/$path.pm";
}

# Resolve the full transitive dependency closure starting from a root file.
# Parses each file through the Chalk pipeline, extracts UseDecls, and recurses.
# Returns list of file paths (excluding the root itself).
sub resolve_deps($root_file, %opts) {
    my $grammar = $opts{grammar};

    # Lazy-load pipeline if no grammar provided
    if (!defined $grammar) {
        require TestPipeline;
        require Chalk::Bootstrap::BNF::Target::Perl;
        require Chalk::Bootstrap::IR::NodeFactory;
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        my $raw_ir = TestPipeline::perl_pipeline();
        die "perl_pipeline returned undef" unless defined $raw_ir;
        my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
        my $generated = $bnf_target->generate($raw_ir);
        $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::DepChaser/g;
        eval "$generated; 1" or die "Grammar eval failed: $@";
        no strict 'refs';
        $grammar = "Chalk::Grammar::Perl::DepChaser::grammar"->();
    }

    my %seen;       # file path => 1
    my @result;     # ordered dep list
    my @queue = ($root_file);

    while (@queue) {
        my $file = shift @queue;
        next if $seen{$file}++;
        next unless -f $file;

        # Parse file to IR
        require Chalk::Bootstrap::IR::NodeFactory;
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        require TestPipeline;
        my $parser = TestPipeline::build_perl_ir_parser($grammar, start => 'Program');
        my $semiring = $parser->semiring();
        $semiring->reset_cache();

        open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
        local $/;
        my $source = <$fh>;
        close $fh;

        my $parse_result = $parser->parse_value($source);
        next unless defined $parse_result;

        my $sa = $semiring->semirings()->[4];
        my $sem_ctx = $parse_result->[4];
        next unless defined $sem_ctx;
        my $ir = $sem_ctx->extract();
        next unless defined $ir;

        my @modules = extract_use_decls($ir);
        for my $mod (@modules) {
            my $path = module_to_path($mod);
            next unless defined $path;
            next unless -f $path;
            next if $seen{$path};
            push @queue, $path;
        }

        # Add to result (but not the root file)
        push @result, $file unless $file eq $root_file;
    }

    return @result;
}
