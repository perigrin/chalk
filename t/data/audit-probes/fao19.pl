package V; sub new { my $c=shift; bless [@_], $c } sub add { my ($a,$b)=@_; V->new(map { $a->[$_]+$b->[$_] } 0..$#$a) } package main; my $x=V->new(1,2); my $y=$x->add($x); $x->[0]=9; print "@$y\n";
