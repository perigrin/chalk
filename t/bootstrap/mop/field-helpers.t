# ABOUTME: Tests for MOP::Field attribute helper methods.
# ABOUTME: Verifies has_attribute, is_param, has_reader semantics.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::MOP::Class;
use Chalk::MOP::Field;

# A bare class scaffold for declare_field.
my $mop = Chalk::MOP->new;
my $cls = $mop->declare_class('Test::Field::Helpers');

# 1. Field with no attributes: all helpers return false.
my $f1 = $cls->declare_field('$plain', sigil => '$');
ok(!$f1->has_attribute('param'),  'plain field: has_attribute(param) is false');
ok(!$f1->has_attribute('reader'), 'plain field: has_attribute(reader) is false');
ok(!$f1->is_param,                'plain field: is_param is false');
ok(!$f1->has_reader,              'plain field: has_reader is false');

# 2. Field with :param: is_param true, has_reader false.
my $f2 = $cls->declare_field('$p', sigil => '$', attributes => [':param']);
ok($f2->is_param,                 'param field: is_param is true');
ok($f2->has_attribute('param'),   'param field: has_attribute(param) is true');
ok(!$f2->has_reader,              'param field: has_reader is false');

# 3. Field with :reader: has_reader true, is_param false.
my $f3 = $cls->declare_field('$r', sigil => '$', attributes => [':reader']);
ok($f3->has_reader,               'reader field: has_reader is true');
ok($f3->has_attribute('reader'),  'reader field: has_attribute(reader) is true');
ok(!$f3->is_param,                'reader field: is_param is false');

# 4. Field with both :param and :reader.
my $f4 = $cls->declare_field('$pr', sigil => '$', attributes => [':param', ':reader']);
ok($f4->is_param,                 'pr field: is_param is true');
ok($f4->has_reader,               'pr field: has_reader is true');

# 5. has_attribute is case-sensitive and does not match partial names.
my $f5 = $cls->declare_field('$x', sigil => '$', attributes => [':reader']);
ok(!$f5->has_attribute('read'),   'has_attribute(read) is false (no partial match)');
ok(!$f5->has_attribute('Reader'), 'has_attribute(Reader) is false (case-sensitive)');

done_testing();
