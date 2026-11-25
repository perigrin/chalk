package C; sub new { bless {}, shift } sub DESTROY { print "D" } package main; my @a = (C->new, C->new); @a = (); print "E\n";
