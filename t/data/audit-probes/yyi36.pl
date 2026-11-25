sub sw { @_[0,1] = @_[1,0] } my ($x,$y)=(1,2); sw($x,$y); my @a=(3,4); sw(@a); my %h=(a=>5,b=>6); sw(@h{qw(a b)}); print "$x$y@a$h{a}$h{b}\n";
