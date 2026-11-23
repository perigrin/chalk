package C; sub new { bless {n=>0}, shift } sub set { my ($s,$v)=@_; $s->{n}=$v } sub n { $_[0]{n} } package main; my $o=C->new; my $p=$o; $p->set(5); print $o->n,"\n";
