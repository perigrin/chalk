package K; sub new { bless {v => 1}, shift } sub set { $_[0]{v} = $_[1]; $_[0] } sub v { $_[0]{v} } package main; my $o = K->new; my $s = $o->v . $o->set(2)->v . $o->v; print "$s\n";
