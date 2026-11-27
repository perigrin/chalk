package O; sub new { bless {}, shift } sub set { my $s = shift; $s->{v} = shift; $s } sub get { $_[0]{v} } package main; my $o = O->new; print $o->set(1)->get, $o->set(2)->get, $o->get, "\n";
