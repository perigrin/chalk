sub f { my ($p) = @_; $x2::v = 5; $p } package x2; our $v = 1; package main; print f($x2::v), $x2::v, "\n";
