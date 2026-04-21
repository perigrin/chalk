# ABOUTME: Tests for Context unified coordination fields (error, mop).
# ABOUTME: Verifies default values, extend passthrough, and opts override for each field.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Context;
use Chalk::MOP;

# error field — default undef
{
    my $ctx = Chalk::Bootstrap::Context->new(focus => 'x');
    ok(!defined $ctx->error, 'error defaults to undef');
}

# error field — set via constructor
{
    my $ctx = Chalk::Bootstrap::Context->new(focus => 'x', error => 'boom');
    is($ctx->error, 'boom', 'error set via constructor');
}

# error field — passes through extend
{
    my $ctx = Chalk::Bootstrap::Context->new(focus => 'x', error => 'kept');
    my $new = $ctx->extend(sub { 'y' });
    is($new->error, 'kept', 'error passes through extend');
}

# error field — override in extend opts
{
    my $ctx = Chalk::Bootstrap::Context->new(focus => 'x', error => 'old');
    my $new = $ctx->extend(sub { 'y' }, error => 'new');
    is($new->error, 'new', 'error overridden in extend opts');
    is($ctx->error, 'old', 'original error unchanged');
}

# mop field — default undef
{
    my $ctx = Chalk::Bootstrap::Context->new(focus => 'x');
    ok(!defined $ctx->mop, 'mop defaults to undef');
}

# mop field — set via constructor
{
    my $mop = Chalk::MOP->new;
    my $ctx = Chalk::Bootstrap::Context->new(focus => 'x', mop => $mop);
    is(refaddr($ctx->mop), refaddr($mop), 'mop set via constructor');
}

# mop field — passes through extend
{
    my $mop = Chalk::MOP->new;
    my $ctx = Chalk::Bootstrap::Context->new(focus => 'x', mop => $mop);
    my $new = $ctx->extend(sub { 'y' });
    is(refaddr($new->mop), refaddr($mop), 'mop passes through extend');
}

# mop field — override in extend opts
{
    my $mop1 = Chalk::MOP->new;
    my $mop2 = Chalk::MOP->new;
    my $ctx = Chalk::Bootstrap::Context->new(focus => 'x', mop => $mop1);
    my $new = $ctx->extend(sub { 'y' }, mop => $mop2);
    is(refaddr($new->mop), refaddr($mop2), 'mop overridden in extend opts');
    is(refaddr($ctx->mop), refaddr($mop1), 'original mop unchanged');
}

# mop field — set to undef via extend opts
{
    my $mop = Chalk::MOP->new;
    my $ctx = Chalk::Bootstrap::Context->new(focus => 'x', mop => $mop);
    my $new = $ctx->extend(sub { 'y' }, mop => undef);
    ok(!defined $new->mop, 'mop can be set to undef via opts');
}

# mop and error independent — setting one doesn't affect the other
{
    my $mop = Chalk::MOP->new;
    my $ctx = Chalk::Bootstrap::Context->new(focus => 'x', mop => $mop, error => 'err');
    my $new = $ctx->extend(sub { 'y' }, error => 'new_err');
    is(refaddr($new->mop), refaddr($mop), 'mop preserved when only error overridden');
    is($new->error, 'new_err', 'error overridden independently');
}

done_testing();
