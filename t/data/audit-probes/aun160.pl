package D; sub new { bless {}, shift } package E; our @ISA=("D"); sub DESTROY { print "d\n" } package main; { my $x = E->new; } print "e\n";
