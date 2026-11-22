use parent -norequire; package B2; sub new { bless {}, shift } sub DESTROY { print "d\n" } package main; B2->new; print "e\n";
