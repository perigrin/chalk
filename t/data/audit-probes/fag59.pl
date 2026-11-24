package P; sub new { bless {h=>{a=>1}}, shift } sub snap { my $s=shift; my %c=%{$s->{h}}; $s->{h}{b}=2; scalar keys %c } package main; print P->new->snap,"\n";
