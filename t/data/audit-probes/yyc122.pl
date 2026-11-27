package C; sub new { bless {v=>1}, shift } sub set { $_[0]{v}=$_[1]; 0 } package main; my $o=C->new; my $n = ($o->{v} = 5) + $o->set(7); print "$n\n";
