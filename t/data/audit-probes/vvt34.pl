package O; sub new { bless {}, shift } sub f { $_[1] .= "x" } package main; my @a = (1,2,3); my $o = O->new; for my $x (@a) { $o->f($x) } print "@a\n";
