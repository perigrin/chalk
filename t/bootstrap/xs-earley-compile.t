# ABOUTME: Test that Earley.pm XS output compiles without C errors.
# ABOUTME: Catches type mismatches (AV*/SV*) and other C compilation issues.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::Perl::Target::XS;
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);

# Skip if no C compiler
my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
unless ($have_compiler) {
    plan skip_all => 'No C compiler available';
}

eval { require Module::Build; 1 }
    or plan skip_all => 'Module::Build not installed';

# Parse Earley.pm
my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSEarleyCompile') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, 'lib/Chalk/Bootstrap/Earley.pm') };
ok(defined $ir, 'Earley.pm parses to IR') or BAIL_OUT("Parse failed: $@");

# Generate XS distribution
my $xs = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::EarleyCompile');
my $dist = eval { $xs->generate_distribution_with_cfg($ir, $sa, $ctx) };
ok(ref($dist) eq 'HASH', 'XS distribution generated') or BAIL_OUT("XS gen failed: $@");

# Check no fallback stubs remain
my ($xs_file) = grep { /\.xs$/ } sort keys $dist->%*;
my $xs_code = $dist->{$xs_file};
my @fallbacks;
while ($xs_code =~ /eval_pv\("sub [^"]+::(\w+)\s*\{/g) {
    push @fallbacks, $1;
}
is(scalar @fallbacks, 0, 'no eval_pv fallback stubs');

# Check no AV*/SV* type mismatches in var declarations
my @type_issues;
while ($xs_code =~ /^(\s*SV \*\w+_sv = \((?:AV|HV)\*\))/mg) {
    push @type_issues, $1;
}
is(scalar @type_issues, 0, 'no AV*/HV* to SV* type mismatches in var decls')
    or diag("Type mismatches:\n" . join("\n", @type_issues));

# Check no AV* in foreach _list_sv
my @loop_issues;
while ($xs_code =~ /^(\s*SV \*_list_sv = \((?:AV|HV)\*\))/mg) {
    push @loop_issues, $1;
}
is(scalar @loop_issues, 0, 'no AV*/HV* to SV* type mismatches in foreach loops')
    or diag("Loop type mismatches:\n" . join("\n", @loop_issues));

# Try to compile the XS code
use File::Temp qw(tempdir);
my $tmpdir = tempdir(CLEANUP => 1);

# Write files
for my $path (sort keys $dist->%*) {
    my $full = "$tmpdir/$path";
    my $dir = $full;
    $dir =~ s{/[^/]+$}{};
    system("mkdir -p $dir") unless -d $dir;
    open my $fh, '>', $full or die "Can't write $full: $!";
    print $fh $dist->{$path};
    close $fh;
}

# Try building
my $build_ok = eval {
    require Module::Build;
    local $ENV{PERL5LIB} = join(':', 'lib', $ENV{PERL5LIB} // '');
    my $cwd = `pwd`;
    chomp $cwd;
    chdir $tmpdir or die "Can't chdir: $!";
    my $build = Module::Build->new_from_context(quiet => 1);
    $build->dispatch('build');
    chdir $cwd;
    1;
};
my $build_err = $@;

ok($build_ok, 'Earley.pm XS compiles without errors')
    or diag("Build failed: $build_err");

done_testing();
