package O; sub new { bless {v=>1}, shift } sub set { $_[0]{v} = 5 } sub f { $_[0]->set; $_[1] } package main; my $o = O->new; print $o->f($o->{v}), "\n";
