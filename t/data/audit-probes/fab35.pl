package C; sub new { bless {}, shift } sub set { $_[0]{$_[1]}=$_[2]; $_[0] } package main; my $o=C->new; $o->set(a=>1)->set(b=>2); print join(",",map{"$_$o->{$_}"}sort keys %$o),"\n";
