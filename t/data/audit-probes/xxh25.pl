package O; sub new { bless {n=>1}, shift } sub m { $_[1] = 9 } package main; my $o = O->new; $o->m($o->{n}); my $x = 1; O->m($x); print $o->{n}, $x, "\n";
