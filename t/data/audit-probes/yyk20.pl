package P; sub new { bless {}, shift } sub m { "m@_[1..$#_]" } package main; my $o = P->new; my $m = "m"; my $c = "P"; print $o->$m(1), $c->new->m(2), P->can("m")->($o, 3), "P"->new->$m, "\n";
