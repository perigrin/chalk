package P; sub new { bless {l=>[1]}, shift } sub snap { my $s=shift; my @c=@{$s->{l}}; push @{$s->{l}},2; scalar @c } package main; print P->new->snap,"\n";
