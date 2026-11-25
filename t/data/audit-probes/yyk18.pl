package P; sub new { bless {n=>0}, shift } sub inc { $_[0]{n}++; $_[0] } sub n { $_[0]{n} } package main; my $o = P->new; print $o->inc->inc->inc->n, P->new->inc->n, "\n";
