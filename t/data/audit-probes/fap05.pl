package C; sub new { bless {}, shift } sub set { $_[1] = "w" } package main; my $o=C->new; my $v="r"; $o->set($v); print "$v\n";
