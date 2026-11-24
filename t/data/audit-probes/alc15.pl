package C; sub new { bless {v=>1}, shift } sub nx { $_[0] = C->new; 1 } package main; my $o=C->new; $o->{v}=5; $o->nx; print $o->{v},"\n";
