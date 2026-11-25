package C; sub new { bless {}, shift } sub set { $_[1]=4 } package main; my $x=1; C->new->set($x); print "$x\n";
