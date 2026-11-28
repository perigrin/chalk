package O; sub new { bless [1,2], shift } sub f { my $s = shift; $s->[-2] = 5; $_[0] } package main; my $o = O->new; print $o->f($o->[0]), "\n";
