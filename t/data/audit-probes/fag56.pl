package P; sub new { bless {l=>[1]}, shift } sub items { @{$_[0]{l}} } sub add { push @{$_[0]{l}}, $_[1] } package main; my $p=P->new; my @c=$p->items; $p->add(2); print scalar(@c),"\n";
