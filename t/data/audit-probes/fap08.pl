package C; sub new { bless {}, shift } sub ch { my $m="set"; $_[0]->$m($_[1]) } sub set { $_[1]="w" } package main; my $v="r"; C->new->ch($v); print "$v\n";
