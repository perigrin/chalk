# ABOUTME: Unit tests for SubDecl emission in Perl::Target::Perl.
# ABOUTME: Validates sub declarations (package, my, our, state) emit correct Perl.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::Perl;

# Reset factory for clean test state
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
my $target  = Chalk::Bootstrap::Perl::Target::Perl->new();

# === Helper: build a SubDecl IR node ===

my sub make_sub_decl(%args) {
    my $name = $factory->make('Constant',
        const_type => 'string', value => $args{name});
    my @param_nodes = map {
        $factory->make('Constant', const_type => 'string', value => $_)
    } ($args{params} // [])->@*;
    my @body_nodes = ($args{body} // [])->@*;
    my $scope = $factory->make('Constant',
        const_type => 'string', value => $args{scope} // 'package');
    return $factory->make('Constructor',
        class  => 'SubDecl',
        name   => $name,
        params => \@param_nodes,
        body   => \@body_nodes,
        scope  => $scope,
    );
}

# Helper: wrap a statement node in a Program to go through generate()
my sub emit_via_program($stmt) {
    my $program = $factory->make('Constructor',
        class      => 'Program',
        statements => [$stmt],
    );
    return $target->generate($program);
}

# === Test 1: Package-scope sub with no params ===
{
    my $sub_node = make_sub_decl(name => 'helper');
    my $code = emit_via_program($sub_node);
    ok(defined $code, 'package sub: emits code');
    like($code, qr/\bsub helper\b/, 'package sub: has sub keyword and name');
    like($code, qr/\(\)/, 'package sub: has empty signature');
    like($code, qr/\{/, 'package sub: has opening brace');
    like($code, qr/\}/, 'package sub: has closing brace');
    unlike($code, qr/\b(?:my|our|state)\s+sub/, 'package sub: no scope prefix');
}

# === Test 2: Package-scope sub with params and body ===
{
    my $return_node = $factory->make('Constructor',
        class => 'ReturnStmt',
        value => $factory->make('Constant',
            const_type => 'string', value => '42'),
    );
    my $sub_node = make_sub_decl(
        name   => 'add',
        params => ['$a', '$b'],
        body   => [$return_node],
    );
    my $code = emit_via_program($sub_node);
    ok(defined $code, 'params sub: emits code');
    like($code, qr/sub add\(\$a, \$b\)/, 'params sub: has name and signature');
    like($code, qr/return/, 'params sub: body contains return');
}

# === Test 3: Lexical (my) sub ===
{
    my $sub_node = make_sub_decl(name => 'private_helper', scope => 'my');
    my $code = emit_via_program($sub_node);
    ok(defined $code, 'my sub: emits code');
    like($code, qr/\bmy sub private_helper\b/, 'my sub: has my prefix');
}

# === Test 4: our sub ===
{
    my $sub_node = make_sub_decl(name => 'public_func', scope => 'our');
    my $code = emit_via_program($sub_node);
    ok(defined $code, 'our sub: emits code');
    like($code, qr/\bour sub public_func\b/, 'our sub: has our prefix');
}

# === Test 5: state sub ===
{
    my $sub_node = make_sub_decl(name => 'cached', scope => 'state');
    my $code = emit_via_program($sub_node);
    ok(defined $code, 'state sub: emits code');
    like($code, qr/\bstate sub cached\b/, 'state sub: has state prefix');
}

done_testing();
