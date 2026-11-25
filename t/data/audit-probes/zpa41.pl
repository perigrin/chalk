package C; sub new { bless {}, shift } sub set { $_[1]=4 } package main; my $x=1; my $m="set"; C->new->$m($x); print "$x\n";
