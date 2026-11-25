package P; sub new { bless {l=>[1,2]}, shift } sub l { @{$_[0]{l}} } sub add { push @{$_[0]{l}},3 } package main; my $o=P->new; my @c=$o->l; $o->add; print scalar(@c), scalar(my @d=$o->l), "\n";
