package O; sub new { bless {v=>1}, shift } sub f { my $s = shift; $s->{v} = 5; $_[0] } package main; my $o = O->new; print $o->f($o->{v}), "\n";
