our $x = 1; sub f { $main::{x} and ${$main::{x}} = 5; $_[0] } print f($x), "\n";
