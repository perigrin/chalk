package O; sub new { bless [1,2], shift } sub f { $_[0][-2] = 5; $_[1] } package main; my $o = O->new; print $o->f($o->[0]), "\n";
