# ABOUTME: The magic string increment's result ends in a NUL: a number read from it
# ABOUTME: (strtod) must stop at its end, not run into whatever bytes follow.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::Target::LLVM;
use Chalk::Target::LLVM::Context;

# `my $a = $ENV{X} // 5; $a++; ...` increments a Str by the magic rule, into
# a fresh buffer of len+1 bytes (one spare for a carry) -- and no NUL. A later
# numeric read goes through strtod, which reads to a NUL: whatever followed
# the buffer joined the number. Measured as a FLAKE: one census run in three
# printed a wrong pvm unary.md case (417), the others perl's answer. Fresh
# heap is usually zeroed, so a program-level test passes by luck; the
# helper's IR is what must hold the terminator.
my $ir = Chalk::Target::LLVM::Context::_emit_slot_inc_helper();
my ($str_inc) = $ir =~ /(define internal %Slot \@chalk_str_inc.*?\n\})/s;
ok(defined $str_inc, '@chalk_str_inc is emitted');
like($str_inc, qr/%n2 = add i64 %len, 2/, 'the buffer has room for a carry AND a terminator');
like($str_inc, qr/store i8 0, i8\* %term/, 'and the result is NUL-terminated');

# AND THE READER RESPECTS THE LENGTH: @chalk_str_to_num takes (ptr, len) and
# handed ptr to strtod, which reads to a NUL. It parses a NUL-terminated copy
# of exactly len bytes, so no Str producer has to be the one that remembered.
my $s2n = Chalk::Target::LLVM::_emit_str_to_num_helper();
like($s2n, qr/store i8 0, i8\* %nul/, 'the number is read from a terminated copy');
unlike($s2n, qr{\@strtod\(i8\* %ptr_after}, 'not from the string in place');

done_testing;
