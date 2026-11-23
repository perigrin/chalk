package C; sub new { bless {n=>0}, shift } sub inc { $_[0]{n}++; $_[0] } sub n { $_[0]{n} } package main; my $o=C->new; $o->inc->inc; print $o->n,"\n";
